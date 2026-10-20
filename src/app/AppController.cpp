#include "app/AppController.h"
#include "data/DbSchema.h"
#include "common/AppLogger.h"

#include "common/AgcUtils.h"
#include "ingest/ImageIngest.h"
#include "data/ArchiveMaintenance.h"
#include "data/StatsService.h"
#include "data/SearchService.h"
#include "data/SettingsStore.h"
#include "ingest/IngestCoordinator.h"
#include <iostream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QHostAddress>
#include <QCoreApplication>
#include <QDirIterator>

#include <algorithm>
#include <utility>
#include <limits>

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QSettings>
#include <QTime>
#include <QStandardItemModel>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QClipboard>
#include <QUrl>
#include <QWindow>
#include <QImageReader>
#include <QStandardPaths>
#include <QUuid>
#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QtConcurrent/QtConcurrentRun>
#include <QThread>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {

static QSqlDatabase getThreadDatabase()
{
    const QString connName = QStringLiteral("worker_db_%1").arg(reinterpret_cast<quintptr>(QThread::currentThread()), 0, 16);
    if (QSqlDatabase::contains(connName)) {
        QSqlDatabase db = QSqlDatabase::database(connName);
        if (db.isOpen()) return db;
    }
    QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connName);
    db.setDatabaseName(DBSchema::defaultDatabasePath());
    if (!db.open()) {
        LOG_ERROR("后台线程数据库打开失败: {}", db.lastError().text().toStdString());
    } else {
        QSqlQuery pragma(db);
        pragma.exec("PRAGMA journal_mode = WAL;");
        pragma.exec("PRAGMA busy_timeout = 5000;");
        pragma.exec("PRAGMA synchronous = NORMAL;");
    }
    return db;
}

constexpr int kMaxPageSize = 200;

bool isSafeArchiveRoot(const QString &path)
{
    const QFileInfo info(path);
    const QString clean = QDir::cleanPath(info.absoluteFilePath());
    if (clean.isEmpty() || info.isSymbolicLink()) return false;
    const QString root = QDir::cleanPath(QDir(clean).rootPath());
    const QString home = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
    const QString appDir = QDir::cleanPath(QCoreApplication::applicationDirPath());
    if (clean == root || clean == home || clean == appDir) return false;
    return QFileInfo(QDir(clean).filePath(QStringLiteral(".carriervision-images"))).isFile()
        || QFileInfo(QDir(clean).filePath(QStringLiteral(".carriervision-archive"))).isFile();
}

} // namespace

using SearchService::RecordFilter;
using SearchService::buildRecordFilter;
using SearchService::parseResultFilter;
using SearchService::queryRecordPage;
using SearchService::resolveImagePath;

void AppController::triggerCleanup()
{
    if (m_cleanupRunning) {
        LOG_INFO("历史数据清理任务正在执行，忽略重复触发");
        return;
    }
    int keepDays = 90;
    int logKeepDays = 30;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        keepDays = qBound(1, DBSchema::getConfigInt(db, "cleanup/keepDays", 90), 3650);
        logKeepDays = qBound(1, DBSchema::getConfigInt(db, "cleanup/logKeepDays", 30), 3650);
    }

    LOG_INFO("执行历史数据清理任务: 图像保留天数={} 天, 日志保留天数={} 天", keepDays, logKeepDays);
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-keepDays);

    const QString archiveRoot = m_archiveDirectory.isEmpty()
        ? (QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("images"))
        : m_archiveDirectory;
    if (!isSafeArchiveRoot(archiveRoot)) {
        setStatusMessage(QStringLiteral("已拒绝清理未标记或危险的图像目录: %1").arg(archiveRoot));
        return;
    }

    // Restore legacy directory staging conservatively; never recursively delete it.
    QDir archive(archiveRoot);
    const auto staged = QDir(archive.filePath(".cleanup_staging")).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks);
    for (const auto &entry : staged) {
        const QString name = entry.fileName();
        if (name.size() <= 37 || name.at(name.size() - 37) != u'_') continue;
        const QString original = archive.filePath(name.left(name.size() - 37));
        if (QFileInfo::exists(original) || !QDir().rename(entry.absoluteFilePath(), original)) {
            setStatusMessage(QStringLiteral("清理中止：旧隔离目录需要恢复: %1").arg(entry.absoluteFilePath()));
            return;
        }
    }
    // 数据库与文件删除在维护线程用独立连接执行，避免阻塞界面与上传处理
    m_cleanupRunning = true;
    const QStringList managedRoots{archiveRoot, m_ftpRoot};
    (void)QtConcurrent::run(&m_maintenancePool, [this, archiveRoot, managedRoots, cutoff, logKeepDays]() {
        int removed = 0;
        bool more = false;
        QString error;
        const bool removeOk = ArchiveMaintenance::cleanup(getThreadDatabase(), archiveRoot,
            managedRoots, cutoff, removed, more, error);
        // 清理超期运行日志文件 (超过 logKeepDays 天的日志自动删除)
        if (removeOk) AppLogger::cleanupLogsOlderThanDays(logKeepDays);

        QMetaObject::invokeMethod(this, [this, removeOk, more, error, logKeepDays]() {
            finishCleanup(removeOk, more, error, logKeepDays);
        }, Qt::QueuedConnection);
    });
}

void AppController::finishCleanup(bool removeOk, bool more, const QString &error, int logKeepDays)
{
    m_cleanupRunning = false;
    if (!removeOk) {
        setStatusMessage(QStringLiteral("清理未完成: %1").arg(error));
        return;
    }
    if (more) QTimer::singleShot(50, this, &AppController::triggerCleanup);

    // FTP 轮转日志与主线程日志写入共用文件，留在主线程处理
    if (!m_ftpLogPath.isEmpty()) {
        const QString rotatedLog = m_ftpLogPath + QStringLiteral(".1");
        QFileInfo fi(rotatedLog);
        if (fi.exists() && fi.lastModified() < QDateTime::currentDateTime().addDays(-logKeepDays)) {
            QFile::remove(rotatedLog);
            LOG_INFO("已自动删除超期 FTP 轮转日志: {}", rotatedLog.toStdString());
        }
    }

    setStatusMessage(QStringLiteral("历史图像与日志数据清理完成"));
}

int AppController::cleanupKeepDays() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return DBSchema::getConfigInt(db, "cleanup/keepDays", 90);
}

int AppController::cleanupLogKeepDays() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return DBSchema::getConfigInt(db, "cleanup/logKeepDays", 30);
}

int AppController::cleanupRunHour() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return DBSchema::getConfigInt(db, "cleanup/runHour", 1);
}

QString AppController::homepageDescription() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return DBSchema::getConfig(
        db,
        "homepage/description",
        QStringLiteral("欢迎使用 AGC ImageViewer。系统用于接收、浏览和查询 AGC 检测图片，并提供批次监控、数据统计及参数设置等功能。"));
}

bool AppController::isDarkMode() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return DBSchema::getConfigBool(db, "ui/isDark", false);
}

void AppController::setDarkMode(bool dark)
{
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        if (DBSchema::getConfigBool(db, "ui/isDark", false) == dark) {
            return;
        }
        DBSchema::setConfig(db, "ui/isDark", dark ? QStringLiteral("true") : QStringLiteral("false"));
    }
    LOG_INFO("持久化保存颜色主题配置: {}", dark ? "深色模式 (Dark)" : "浅色模式 (Light)");
    emit darkModeChanged(dark);
}

void AppController::setCleanupKeepDays(int days)
{
    days = qBound(1, days, 3650);
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        DBSchema::setConfig(db, "cleanup/keepDays", QString::number(days));
    }
    LOG_DEBUG("设置图像清理保留天数: {} 天", days);
}

void AppController::setCleanupLogKeepDays(int days)
{
    days = qBound(1, days, 3650);
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        DBSchema::setConfig(db, "cleanup/logKeepDays", QString::number(days));
    }
    LOG_DEBUG("设置日志清理保留天数: {} 天", days);
}

void AppController::setCleanupRunHour(int hour)
{
    hour = qBound(0, hour, 23);
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        DBSchema::setConfig(db, "cleanup/runHour", QString::number(hour));
    }
    scheduleCleanup();
    LOG_DEBUG("设置清理执行时间点: 每天 {} 时", hour);
}

void AppController::scheduleCleanup()
{
    const int runHour = qBound(0, cleanupRunHour(), 23);
    const QDateTime now = QDateTime::currentDateTime();
    QDateTime nextRun(now.date(), QTime(runHour, 0));
    if (nextRun <= now) nextRun = nextRun.addDays(1);
    m_cleanupTimer.setSingleShot(true);
    m_cleanupTimer.start(static_cast<int>(qMax<qint64>(1, now.msecsTo(nextRun))));
}

bool AppController::saveHomepageDescription(const QString &description)
{
    const QString trimmedDescription = description.trimmed();
    if (trimmedDescription.isEmpty()) {
        return false;
    }

    bool success = false;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        success = DBSchema::setConfig(db, "homepage/description", trimmedDescription);
    }
    if (!success) {
        return false;
    }

    emit homepageDescriptionChanged();
    return true;
}

bool AppController::verifySettingsPassword(const QString &password) const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::verifySettingsPassword(db, password);
}

void AppController::activateEnglishInputMethod()
{
#ifdef Q_OS_WIN
    // 使用系统英文（美国）键盘布局，避免密码输入框仍保留中文输入法状态。
    const HKL layout = LoadKeyboardLayoutW(L"00000409",
                                           KLF_ACTIVATE | KLF_SUBSTITUTE_OK);
    if (!layout) {
        return;
    }

    ActivateKeyboardLayout(layout, 0);

    if (QWindow *window = QGuiApplication::focusWindow()) {
        SendMessageW(reinterpret_cast<HWND>(window->winId()),
                     WM_INPUTLANGCHANGEREQUEST,
                     0,
                     reinterpret_cast<LPARAM>(layout));
    }
#endif
}

bool AppController::changeSettingsPassword(const QString &currentPassword,
                                           const QString &newPassword)
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::changeSettingsPassword(db, currentPassword, newPassword);
}

bool AppController::resetSettingsPassword()
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::resetSettingsPassword(db);
}

bool AppController::resetSettingsPasswordAuthorized(const QString &password)
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::resetSettingsPasswordAuthorized(db, password);
}

bool AppController::hasMaintenancePassword() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::hasMaintenancePassword(db);
}

bool AppController::setMaintenancePassword(const QString &currentSettingsPassword, const QString &newPassword)
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::setMaintenancePassword(db, currentSettingsPassword, newPassword);
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_ftpService = new FtpIngestService;
    m_ftpService->moveToThread(&m_ftpThread);
    connect(&m_ftpThread, &QThread::finished, m_ftpService, &QObject::deleteLater);
    m_ftpThread.setObjectName(QStringLiteral("FtpIngest"));
    m_ftpThread.start();

    m_logPool.setMaxThreadCount(1);
    m_searchPool.setMaxThreadCount(2);
    m_statsPool.setMaxThreadCount(2);
    // 工作线程持有按线程命名的数据库连接，线程不能回收，否则新线程可能复用旧地址拿到不属于自己的连接
    m_searchPool.setExpiryTimeout(-1);
    m_statsPool.setExpiryTimeout(-1);
    m_maintenancePool.setMaxThreadCount(1);
    m_maintenancePool.setExpiryTimeout(-1);
    connect(&m_logWatcher, &QFutureWatcher<QVariantMap>::finished, this, [this]() {
        m_logBusy = false;
        if (m_activeLogRequest == m_logGeneration) emit logQueryFinished(m_activeLogRequest, m_logWatcher.result());
        else startLogQuery();
    });
    m_ftpLogThrottleTimer.setSingleShot(true);
    m_ftpLogThrottleTimer.setInterval(150);
    connect(&m_ftpLogThrottleTimer, &QTimer::timeout, this, &AppController::ftpLogChanged);

    const QDateTime now = QDateTime::currentDateTime();
    m_defaultSearchStart = AgcUtils::formatDateTime(now.addDays(-1));
    m_defaultSearchEnd = AgcUtils::formatDateTime(now);
    m_searchSummary = QStringLiteral("请输入时间范围和序列号后开始搜索");

    // 默认槽位映射：来源 1..12，目标默认 1..12（可映射到 1..14）。随后 loadSettings() 会从配置覆盖。
    m_slotMapping.resize(12);
    for (int i = 0; i < 12; ++i) {
        m_slotMapping[i] = i + 1;
    }

    // Ensure the current images model starts with 12 placeholder entries so UI slots map correctly
    {
        QVector<ImageItem> initItems;
        initItems.resize(12);
        m_currentImagesModel.setItems(initItems);
        // notify UI of initial slots so delegates can refresh once loaded
        for (int i = 0; i < initItems.size(); ++i) {
            emit slotUpdated(i);
        }
    }

    loadSettings();
    ensureDirectories();
    connect(&m_cleanupTimer, &QTimer::timeout, this, [this]() {
        triggerCleanup();
        scheduleCleanup();
    });
    scheduleCleanup();

    // prepare ftp log path
    m_ftpLogPath = QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("ftp.log");
    // try loading existing ftp log file
    loadFtpLogs();

    AppLogger::setLogCallback([this](const QString &/*level*/, const QString &/*message*/, const QString &/*time*/) {
        QMetaObject::invokeMethod(this, [this]() {
            emit latestWarnOrErrorChanged();
        }, Qt::QueuedConnection);
    });

    connect(m_ftpService, &FtpIngestService::runningChanged, this, [this](bool running) {
        m_ftpRunning = running;
        emit ftpServerStateChanged();
    });
    connect(m_ftpService, &FtpIngestService::clientCountChanged, this, [this](int count) {
        m_ftpClientCount = count;
        emit ftpServerStateChanged();
    });
    connect(m_ftpService, &FtpIngestService::imageStored, this, &AppController::onFtpImageStored);
    connect(m_ftpService, &FtpIngestService::ingestFailed, this, &AppController::setStatusMessage);
    connect(m_ftpService, &FtpIngestService::logMessage, this, [this](const QString &message) {
        const QString boundedMessage = message.left(2048);

        // 去除 FtpServer 内部前缀中重复的时间戳与 [FTP] 标识，使系统日志格式保持工整统一
        QString cleanMessage = boundedMessage;
        static const QRegularExpression prefixRx(QStringLiteral(R"(^\d{4}-\d{2}-\d{2}T[^\s]+\s+\[FTP\]\s+)"));
        cleanMessage.remove(prefixRx);

        const bool isCritical = cleanMessage.contains(QStringLiteral("异常")) ||
                               cleanMessage.contains(QStringLiteral("失败")) ||
                               cleanMessage.contains(QStringLiteral("failed")) ||
                               cleanMessage.contains(QStringLiteral("error"));

        if (isCritical) {
            LOG_WARN("[FTP] {}", cleanMessage.toStdString());
            setStatusMessage(cleanMessage);
        } else {
            // 详细协议交互（如 CMD/RSP、服务内部状态、目录与文件事件等）记录为 DEBUG，避免与应用层关键里程碑日志重复
            LOG_DEBUG("[FTP] {}", cleanMessage.toStdString());
        }

        const QString entry = QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + boundedMessage;
        m_ftpLogLines.append(entry);
        if (m_ftpLogLines.size() > 2000) {
            m_ftpLogLines.removeFirst();
            int idx = m_ftpLogBuffer.indexOf(QLatin1Char('\n'));
            if (idx >= 0) m_ftpLogBuffer.remove(0, idx + 1);
        }
        if (!m_ftpLogBuffer.isEmpty()) m_ftpLogBuffer.append(QLatin1Char('\n'));
        m_ftpLogBuffer.append(entry);

        QFile f(m_ftpLogPath);
        if (f.exists() && f.size() >= 5 * 1024 * 1024) {
            const QString oldPath = m_ftpLogPath + QStringLiteral(".1");
            QFile::remove(oldPath);
            QFile::rename(m_ftpLogPath, oldPath);
        }
        if (f.open(QIODevice::Append | QIODevice::Text)) {
            QTextStream ts(&f);
            ts << entry << "\n";
            f.close();
        }

        if (!m_ftpLogThrottleTimer.isActive()) {
            m_ftpLogThrottleTimer.start();
        }
    });
    // 上传校验、提交与未决上传恢复均在 FTP 线程执行
    ftpPushRoot();

    // start integrated FTP server
    startFtpServer();
    LOG_DEBUG("内置 FTP 服务初始化检测: ftpRunning={}", ftpRunning());
    if (!ftpRunning() && !m_ftpUsers.isEmpty()) {
        const QString failMsg = QStringLiteral("无法启动内置 FTP 服务（端口可能被占用），继续运行但部分功能不可用");
        LOG_WARN("内置 FTP 服务未能启动: 端口={}, 账户数={}", m_ftpPort, m_ftpUsers.size());
        setStatusMessage(failMsg);
    }

    // start integrated TCP data receiver
    connect(&m_tcpReceiver, &TcpDataReceiver::runningChanged, this, [this](bool) {
        emit tcpServerStateChanged();
    });
    connect(&m_tcpReceiver, &TcpDataReceiver::clientCountChanged, this, [this](int) {
        emit tcpServerStateChanged();
    });
    connect(&m_tcpReceiver, &TcpDataReceiver::logMessage, this, [this](const QString &msg) {
        LOG_INFO("{}", msg.toStdString());
    });
    m_tcpReceiver.batchHandler = [this](const QJsonObject &data, QString &error) {
        return processTcpBatch(data, error);
    };

    startTcpServer();

    setStatusMessage(
        QStringLiteral("源目录 %1，归档目录 %2")
            .arg(m_sourceDirectory, m_archiveDirectory));
}

QString AppController::ftpLog() const
{
    return m_ftpLogBuffer;
}

QVariantList AppController::weeklyReports()
{
    QVariantList out;
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return out;
    QSqlQuery q(db);
    if (!q.exec("SELECT createtime, drivers_filename, deformed_filename FROM weekly_reports ORDER BY createtime DESC")) return out;
    while (q.next()){
        QVariantMap m;
        m[QStringLiteral("createtime")] = q.value(0).toString();
        m[QStringLiteral("drivers_filename")] = q.value(1).toString();
        m[QStringLiteral("deformed_filename")] = q.value(2).toString();
        out.append(m);
    }
    return out;
}

QVariantList AppController::driveWheelRackStats(const QString &startDate, const QString &endDate)
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::wheelGroupRackStats(QSqlDatabase::database(), startDate, endDate, 1, 8);
}

QVariantList AppController::walkingWheelRackStats(const QString &startDate, const QString &endDate)
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::wheelGroupRackStats(QSqlDatabase::database(), startDate, endDate, 9, 16);
}

QVariantList AppController::rackWheelMonitorStatus() const
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::rackWheelMonitorStatus(QSqlDatabase::database());
}

QVariantList AppController::rackPhotoCounts() const
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::rackPhotoCounts(QSqlDatabase::database());
}

int AppController::currentRackHint() const
{
    return m_currentCarrierId >= 1 && m_currentCarrierId <= 50 ? m_currentCarrierId : 0;
}

QVariantMap AppController::homepageCurrentDetection() const
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::homepageCurrentDetection(QSqlDatabase::database(), currentRackHint());
}

int AppController::requestStats(const QString &kind, const QVariantList &args)
{
    const int requestId = ++m_statsRequestSeq;
    // 首页概览依赖主线程状态，在投递前取出
    const QVariantList effectiveArgs = kind == QLatin1String("homepageCurrentDetection")
        ? QVariantList{currentRackHint()} : args;

    (void)QtConcurrent::run(&m_statsPool, [this, requestId, kind, effectiveArgs]() {
        bool known = false;
        const QVariant result = StatsService::run(getThreadDatabase(), kind, effectiveArgs, &known);
        if (!known) LOG_WARN("未知统计请求或参数不足: {}", kind.toStdString());
        QMetaObject::invokeMethod(this, [this, requestId, kind, result]() {
            emit statsReady(requestId, kind, result);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

QVariantMap AppController::latestRackWheelMonitorImage(int rackNumber, int wheelNumber) const
{
    QVariantMap image;
    if (rackNumber < 1 || rackNumber > 50 || wheelNumber < 1 || wheelNumber > 16) {
        return image;
    }

    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return image;
    }

    QSqlQuery query(db);
    const QString sql = QStringLiteral(
        "SELECT imagename, createtime, result FROM record "
        "WHERE carrier_id = :rack AND wheel_id = :wheel "
        "ORDER BY createtime DESC, rowid DESC LIMIT 1");

    query.prepare(sql);
    query.bindValue(QStringLiteral(":rack"), rackNumber);
    query.bindValue(QStringLiteral(":wheel"), wheelNumber);
    if (!query.exec() || !query.next()) {
        return image;
    }

    const QString imageName = query.value(0).toString().trimmed();
    QString imagePath = resolveImagePath(imageName, m_archiveDirectory, m_sourceDirectory);
    if (imagePath.isEmpty()) imagePath = imageName;

    image.insert(QStringLiteral("filePath"), imagePath);
    image.insert(QStringLiteral("fileName"), QFileInfo(imagePath).fileName());
    image.insert(QStringLiteral("time"), query.value(1).toString());
    image.insert(QStringLiteral("result"), query.value(2).toInt());
    return image;
}

QVariantList AppController::wheelRackResultStats(const QString &startDate, const QString &endDate,
                                                  int wheelNumber, const QString &resultType)
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::wheelRackResultStats(QSqlDatabase::database(), startDate, endDate,
                                              wheelNumber, resultType);
}

QVariantList AppController::rackWheelResultStats(const QString &startDate, const QString &endDate,
                                                  int rackNumber, const QString &resultType,
                                                  int wheelType) const
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::rackWheelResultStats(QSqlDatabase::database(), startDate, endDate,
                                              rackNumber, resultType, wheelType);
}

void AppController::openReportFile(const QString &fileName)
{
    if (fileName.isEmpty() || QFileInfo(fileName).fileName() != fileName
        || fileName.contains(u'/') || fileName.contains(u'\\')) return;
    const QString path = QDir(QCoreApplication::applicationDirPath() + QDir::separator() + "data")
                             .filePath(fileName);
    QFileInfo fi(path);
    if (!fi.exists()) {
        LOG_WARN("打开报表文件失败，目标文件不存在: {}", path.toStdString());
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void AppController::loadFtpLogs()
{
    m_ftpLogLines.clear();
    QFile f(m_ftpLogPath);
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        constexpr qint64 maxLogRead = 5 * 1024 * 1024;
        if (f.size() > maxLogRead) {
            f.seek(f.size() - maxLogRead);
            f.readLine(); // 丢弃被截断的首行。
        }
        QTextStream ts(&f);
        while (!ts.atEnd()) {
            QString line = ts.readLine();
            if (!line.isEmpty()) {
                m_ftpLogLines.append(line);
                while (m_ftpLogLines.size() > 2000) m_ftpLogLines.removeFirst();
            }
        }
        f.close();
    }
    {
        QStringList sl;
        for (const QVariant &v : m_ftpLogLines) sl.append(v.toString());
        m_ftpLogBuffer = sl.join('\n');
    }
    LOG_DEBUG("loadFtpLogs: 已加载 {} 行 FTP 日志", m_ftpLogLines.size());
    emit ftpLogChanged();
}

void AppController::clearFtpLogs()
{
    m_ftpLogLines.clear();
    m_ftpLogBuffer.clear();
    QFile f(m_ftpLogPath);
    if (f.exists()) f.remove();
    emit ftpLogChanged();
}

void AppController::debugLog(const QString &text)
{
    LOG_DEBUG("QML调试信息: {}", text.toStdString());
}

QVariantList AppController::ftpLogLines() const
{
    return m_ftpLogLines;
}


AppController::~AppController()
{
    stopFtpServer();
    FtpIngestService *service = m_ftpService;
    QMetaObject::invokeMethod(service, [service]() { service->shutdown(); }, Qt::BlockingQueuedConnection);
    m_ftpThread.quit();
    m_ftpThread.wait(); // finished 时 deleteLater 回收 m_ftpService
    m_ftpService = nullptr;
    stopTcpServer();
    ++m_searchGeneration;
    ++m_alertSearchGeneration;
    m_searchPool.clear();
    m_searchPool.waitForDone();
    m_statsPool.clear();
    m_statsPool.waitForDone();
    m_maintenancePool.waitForDone();
    m_logPool.waitForDone();
    AppLogger::setLogCallback(nullptr);
}

QVariantMap AppController::latestWarnOrError() const
{
    return AppLogger::latestWarningOrError();
}

void AppController::clearLatestWarnOrError()
{
    AppLogger::clearLatestWarningOrError();
    emit latestWarnOrErrorChanged();
}

QString AppController::sourceDirectory() const
{
    return m_sourceDirectory;
}

QString AppController::archiveDirectory() const
{
    return m_archiveDirectory;
}

QString AppController::statusMessage() const
{
    return m_statusMessage;
}

QString AppController::currentSerialsRaw() const
{
    return m_currentSerialsRaw;
}

QString AppController::currentReceivedAtText() const
{
    return m_currentReceivedAtText;
}

int AppController::currentRoundNumber() const
{
    return m_currentRoundNumber;
}

int AppController::currentCopiedCount() const
{
    return m_currentCopiedCount;
}

int AppController::currentExpectedCount() const
{
    return m_currentExpectedCount;
}

// pendingBatchCount removed

QString AppController::searchSummary() const
{
    return m_searchSummary;
}

QString AppController::defaultSearchStart() const
{
    return m_defaultSearchStart;
}

QString AppController::defaultSearchEnd() const
{
    return m_defaultSearchEnd;
}

ImageListModel *AppController::currentImagesModel()
{
    return &m_currentImagesModel;
}

ImageListModel *AppController::searchImagesModel()
{
    return &m_searchImagesModel;
}

int AppController::latestRackWheelImageRack() const
{
    const QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return 0;
    }

    QSqlQuery query(db);
    // 两步查询走时间索引，见 StatsService::homepageCurrentDetection 中的说明
    if (!query.exec(QStringLiteral(R"(
        SELECT carrier_id
        FROM record
        WHERE createtime = (
            SELECT createtime FROM record
            WHERE +result = 1 AND +distance > 0 AND +wheel_id BETWEEN 1 AND 16
            ORDER BY createtime DESC LIMIT 1)
          AND result = 1
          AND distance > 0
          AND wheel_id BETWEEN 1 AND 16
        ORDER BY rowid DESC
        LIMIT 1
    )")) || !query.next()) {
        return 0;
    }

    const int rackNumber = query.value(0).toInt();
    return rackNumber > 0 ? rackNumber : 0;
}

int AppController::latestRackWheelTotalPages(int rackNumber) const
{
    if (rackNumber < 1) return 0;
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return 0;
    QSqlQuery q(db);
    const QString sql = QStringLiteral(R"(
        SELECT MAX(cnt) FROM (
            SELECT wheel_id AS w, COUNT(*) AS cnt
            FROM record
            WHERE carrier_id = :rack AND result = 1 AND distance > 0
              AND wheel_id BETWEEN 1 AND 16
            GROUP BY wheel_id
        )
    )");
    if (!q.prepare(sql)) return 0;
    q.bindValue(QStringLiteral(":rack"), rackNumber);
    if (!q.exec()) return 0;
    if (q.next()) {
        return static_cast<int>(qMin<qint64>(q.value(0).toLongLong(), std::numeric_limits<int>::max()));
    }
    return 0;
}

void AppController::loadLatestRackWheelImages(int rackNumber)
{
    // default to first page (latest per wheel)
    loadLatestRackWheelImagesPage(rackNumber, 1);
}

void AppController::loadLatestRackWheelImagesPage(int rackNumber, int page)
{
    QVector<ImageItem> items;
    if (rackNumber < 1) {
        m_searchImagesModel.clear();
        m_searchSummary = QStringLiteral("取得 0 条记录");
        emit searchSummaryChanged();
        return;
    }

    if (page < 1) page = 1;

    QSqlDatabase db = QSqlDatabase::database();
    QString queryError;
    if (db.isValid() && db.isOpen()) {
        QSqlQuery q(db);
        const QString sql = QStringLiteral(R"(
            SELECT rowid, createtime, carrier_id, wheel_id, camera_id, result, imagename, distance, dist_norm, lower_tolerance
            FROM record
            WHERE carrier_id = :rack AND result = 1 AND distance > 0
              AND wheel_id = :wheel
            ORDER BY createtime DESC, rowid DESC
            LIMIT 1 OFFSET %1
        )").arg((page - 1));

        if (!q.prepare(sql)) {
            queryError = q.lastError().text();
            LOG_ERROR("loadLatestRackWheelImagesPage 预处理 SQL 失败: {}", queryError.toStdString());
        } else {
            for (int slot = 1; slot <= 16; ++slot) {
                const int wheel = slot;
                q.bindValue(QStringLiteral(":rack"), rackNumber);
                q.bindValue(QStringLiteral(":wheel"), wheel);
                if (!q.exec()) {
                    queryError = q.lastError().text();
                    LOG_ERROR("loadLatestRackWheelImagesPage 查询执行失败: {}", queryError.toStdString());
                    break;
                }
                if (q.next()) {
                    ImageItem item;
                    item.receivedAt = QDateTime::fromString(q.value(1).toString(), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
                    if (!item.receivedAt.isValid()) item.receivedAt = QDateTime::fromString(q.value(1).toString(), Qt::ISODate);
                    item.carrierId = q.value(2).toInt();
                    item.rack = item.carrierId;
                    item.wheelId = slot;
                    item.slot = slot;
                    item.cameraId = q.value(4).toInt();
                    item.result = q.value(5).toInt();
                    item.fileName = QFileInfo(q.value(6).toString().trimmed()).fileName();
                    item.distance = q.value(7).toDouble();
                    item.dist_norm = q.value(8).toDouble();
                    item.lower_tolerance = q.value(9).toDouble();

                    const QString rawName = q.value(6).toString().trimmed();
                    item.filePath = resolveImagePath(rawName, m_archiveDirectory, m_sourceDirectory);
                    if (!item.filePath.isEmpty()) item.fileUrl = QUrl::fromLocalFile(item.filePath).toString();
                    items.append(item);
                }
                q.finish();
            }
        }
    } else {
        queryError = QStringLiteral("无法打开数据库");
        LOG_ERROR("架轮间距分页查询失败: {}", queryError.toStdString());
    }

    const QString dbPath = QSqlDatabase::database().databaseName();
    QMetaObject::invokeMethod(&m_searchImagesModel, [this, items, dbPath, rackNumber, queryError]() mutable {
        m_searchImagesModel.setItems(items);
        if (!queryError.isEmpty()) {
            m_searchSummary = QStringLiteral("读取架号 %1 失败：%2").arg(rackNumber).arg(queryError);
        } else {
            const QString dbFile = QFileInfo(dbPath).fileName();
            m_searchSummary = QStringLiteral("取得 %1 条记录（DB: %2）").arg(items.size()).arg(dbFile);
        }
        emit searchSummaryChanged();
        emit latestRackLoadFinished(items.size(), dbPath);
    }, Qt::QueuedConnection);
}

void AppController::searchPaged(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter, int page, int pageSize)
{
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const int gen = ++m_searchGeneration;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;

    (void)QtConcurrent::run(&m_searchPool, [this, gen, startText, endText, serialKeyword, rackNumber, wheelNo, resultFilter, page, pageSize, archiveDir, sourceDir]() {
        RecordFilter filter = buildRecordFilter(startText, endText, rackNumber, wheelNo);
        const QString serialToken = serialKeyword.trimmed();
        if (!serialToken.isEmpty()) {
            filter.where << QStringLiteral("imagename LIKE :filename");
            filter.binds.append({QStringLiteral(":filename"),
                                 serialToken.contains('%') ? serialToken : QStringLiteral("%") + serialToken + QStringLiteral("%")});
        }
        int parsedResult = 0;
        if (parseResultFilter(resultFilter, parsedResult)) {
            filter.where << QStringLiteral("result = :res");
            filter.binds.append({QStringLiteral(":res"), parsedResult});
        }

        QSqlDatabase db = getThreadDatabase();
        if (!db.isValid() || !db.isOpen()) {
            LOG_ERROR("分页搜索失败，后台数据库无法打开");
            return;
        }

        int totalCount = 0;
        QVector<ImageItem> items;
        if (!queryRecordPage(db, QStringLiteral("record"), filter, page, pageSize, archiveDir, sourceDir, totalCount, items))
            return;
        for (const ImageItem &item : std::as_const(items)) {
            if (item.filePath.isEmpty())
                LOG_WARN("分页搜索结果中图片文件缺失: {}", item.fileName.toStdString());
        }

        LOG_DEBUG("searchPaged: start={} end={} serial={} rack={} wheel={} res={} page={} pageSize={} count={}",
                  startText.toStdString(), endText.toStdString(), serialToken.toStdString(),
                  rackNumber, wheelNo.toStdString(), resultFilter.toStdString(), page, pageSize, totalCount);

        if (m_searchGeneration.load() != gen) return;
        QMetaObject::invokeMethod(this, [this, gen, items, totalCount]() {
            if (m_searchGeneration.load() != gen) return;
            m_searchImagesModel.clear();
            m_searchImagesModel.setItems(items);
            m_searchSummary = QStringLiteral("取得 %1 条记录").arg(totalCount);
            emit searchSummaryChanged();
            emit searchPagedResult(totalCount);
        }, Qt::QueuedConnection);
    });
}

void AppController::alertSearchPaged(const QString &startText, const QString &endText,
                                     int rackNumber, const QString &wheelNo,
                                     int page, int pageSize)
{
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const int gen = ++m_alertSearchGeneration;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;

    (void)QtConcurrent::run(&m_searchPool, [this, gen, startText, endText, rackNumber, wheelNo, page, pageSize, archiveDir, sourceDir]() {
        const RecordFilter filter = buildRecordFilter(startText, endText, rackNumber, wheelNo);

        QSqlDatabase db = getThreadDatabase();
        if (!db.isValid() || !db.isOpen()) return;

        int totalCount = 0;
        QVector<ImageItem> items;
        if (!queryRecordPage(db, QStringLiteral("alertrecord"), filter, page, pageSize, archiveDir, sourceDir, totalCount, items))
            return;

        if (m_alertSearchGeneration.load() != gen) return;
        QMetaObject::invokeMethod(this, [this, gen, items, totalCount]() {
            if (m_alertSearchGeneration.load() != gen) return;
            m_searchImagesModel.clear();
            m_searchImagesModel.setItems(items);
            m_searchSummary = QStringLiteral("取得 %1 条报警记录").arg(totalCount);
            emit searchSummaryChanged();
            emit searchPagedResult(totalCount);
        }, Qt::QueuedConnection);
    });
}

void AppController::loadFtpSettingsFromFile()
{
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        if (!db.isOpen()) return;
        const SettingsStore::FtpSettings settings = SettingsStore::loadFtpSettings(db, m_ftpPort);
        m_ftpUsers = settings.users;
        m_ftpRoot = settings.root;
        m_ftpPort = settings.port;
        m_slotMapping = settings.slotMapping;
    }
    m_ftpAllowAnonymous = false; // 内置服务不允许匿名上传。
    if (!m_ftpUsers.isEmpty()) m_ftpUser = m_ftpUsers.firstKey();
    emit ftpSettingsChanged();
    LOG_DEBUG("loadFtpSettings: 有效端口={}, 用户={}", m_ftpPort, m_ftpUser.toStdString());
}

bool AppController::saveFtpSettingsToFile()
{
    const SettingsStore::FtpSettings settings{m_ftpUsers, m_ftpRoot, m_ftpPort, m_slotMapping};
    QString error;
    bool saved = false;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        saved = SettingsStore::saveFtpSettings(db, settings, error);
    }
    if (!saved) setStatusMessage(error);
    return saved;
}

QVariantList AppController::slotMapping() const
{
    QVariantList list;
    for (int v : m_slotMapping) list.append(v);
    return list;
}

void AppController::setSlotMapping(int sourceOneBased, int targetValue)
{
    if (sourceOneBased < 1 || sourceOneBased > 12) return;
    if (targetValue < 1) targetValue = 1; if (targetValue > 14) targetValue = 14; // allow 1..14
    int idx = sourceOneBased - 1;
    if (m_slotMapping[idx] == targetValue) return;
    const int previous = m_slotMapping[idx];
    m_slotMapping[idx] = targetValue;
    if (!saveFtpSettingsToFile()) { m_slotMapping[idx] = previous; return; }
    LOG_INFO("更新槽位通道映射关系: 槽位 {} -> 逻辑通道 {}", sourceOneBased, targetValue);
    emit mappingChanged();
}

QVariantList AppController::rackWheelDistances(int rackNumber) const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::rackWheelDistances(db, rackNumber);
}

bool AppController::saveRackWheelDistances(int rackNumber, const QVariantList &distances)
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::saveRackWheelDistances(db, rackNumber, distances);
}

QVariantList AppController::gearSumResult() const {
    return m_gearSumResult;
}

void AppController::gearSumQuery(const QString &startDate, const QString &endDate, const QString &rackno, const QVariant &selectedTurns) {
    // Build date bounds
    QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    const QString rackTrimmed = rackno.trimmed();
    bool rackOk = false;
    const int rackValue = rackTrimmed.toInt(&rackOk);
    const bool filterByRack = !rackTrimmed.isEmpty() && (!rackOk || rackValue > 0);

    // prepare wheel filter
    QStringList wheelList;
    if (selectedTurns.isValid()) {
        QVariantList arr = selectedTurns.toList();
        for (const QVariant &v : arr) {
            const int wheel = v.toInt();
            if (wheel >= 1 && wheel <= 16) wheelList << QString::number(wheel);
        }
    }

    // default counts map
    QMap<int,QPair<int,int>> counts; // wheel -> (ok,ng)
    int outputRangeStart = 1;
    int outputRangeEnd = 8;
    // If user provided an explicit contiguous eight-wheel list, adapt the output range.
    if (!wheelList.isEmpty()) {
        QList<int> wheels;
        for (const QString &s : wheelList) wheels.append(s.toInt());
        std::sort(wheels.begin(), wheels.end());
        int minw = wheels.first();
        int maxw = wheels.last();
        if (wheels.size() == 8 && maxw - minw == 7) {
            outputRangeStart = minw;
            outputRangeEnd = maxw;
        }
    }
    for (int i=outputRangeStart;i<=outputRangeEnd;i++) counts[i] = qMakePair(0,0);

    QSqlDatabase db = QSqlDatabase::database();
    if (db.isValid() && db.isOpen()) {
        QSqlQuery q(db);
        QString sql = QStringLiteral("SELECT wheel_id, result, COUNT(*) as c FROM record");
        QStringList where{QStringLiteral("wheel_id BETWEEN 1 AND 16")};
        if (startTime.isValid()) where << "createtime >= :start";
        if (endTime.isValid()) where << "createtime <= :end";
        if (filterByRack) where << "carrier_id = :rack";
        if (!wheelList.isEmpty()) where << QStringLiteral("wheel_id IN (%1)").arg(wheelList.join(","));
        if (!where.isEmpty()) sql += " WHERE " + where.join(" AND ");
        sql += " GROUP BY wheel_id, result";

        if (!q.prepare(sql)) {
            LOG_ERROR("gearSum SQL 预处理失败: {}", q.lastError().text().toStdString());
        } else {
            if (startTime.isValid()) q.bindValue(":start", AgcUtils::formatDateTime(startTime));
            if (endTime.isValid()) q.bindValue(":end", AgcUtils::formatDateTime(endTime));
            if (filterByRack) q.bindValue(":rack", rackValue);

            // Log final SQL and parameters for debugging
            QString debugSql = sql;
            LOG_DEBUG("gearSum SQL: {}", debugSql.toStdString());
            QStringList paramLog;
            if (startTime.isValid()) paramLog << QStringLiteral(":start=%1").arg(AgcUtils::formatDateTime(startTime));
            if (endTime.isValid()) paramLog << QStringLiteral(":end=%1").arg(AgcUtils::formatDateTime(endTime));
            if (filterByRack) paramLog << QStringLiteral(":rack=%1").arg(rackValue);
            else paramLog << QStringLiteral(":rack=ALL");
            if (!wheelList.isEmpty()) paramLog << QStringLiteral("wheels=%1").arg(wheelList.join(","));
            LOG_DEBUG("gearSum 参数: {}", paramLog.join(" ").toStdString());

            if (q.exec()) {
                while (q.next()) {
                    int wheel = q.value(0).toInt();
                    int res = q.value(1).toInt();
                    int c = q.value(2).toInt();
                    LOG_DEBUG("gearSum 行数据: wheel={} res={} count={}", wheel, res, c);
                    if (wheel >= outputRangeStart && wheel <= outputRangeEnd) {
                        if (res == 1) counts[wheel].first += c; else counts[wheel].second += c;
                    }
                }
            } else {
                LOG_ERROR("gearSum 数据库查询失败: {}", q.lastError().text().toStdString());
            }
        }
    } else {
        LOG_ERROR("gearSum 无法执行查询，数据库未连接");
    }

    QVariantList out;
    for (int i = outputRangeStart; i <= outputRangeEnd; ++i) {
        QVariantMap mapItem;
        mapItem.insert(QStringLiteral("wheel"), i);
        mapItem.insert(QStringLiteral("ok"), counts[i].first);
        mapItem.insert(QStringLiteral("ng"), counts[i].second);
        out.append(mapItem);
    }

    m_gearSumResult = out;
    LOG_DEBUG("gearSum 汇总统计计算完成，已触发更新");
    emit gearSumResultChanged();
}

void AppController::openGenericSearch(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType)
{
    emit genericSearchRequested(startDate, endDate, wheelNumber, resultType);
}

void AppController::startFtpServer()
{
    if (m_ftpRunning) return;
    if (m_ftpUsers.isEmpty()) {
        setStatusMessage(QStringLiteral("请先创建 FTP 账户，服务未启动"));
        return;
    }
    // ensure root directory exists (use archive instead of incoming)
    if (m_ftpRoot.isEmpty()) m_ftpRoot = m_archiveDirectory;
    QTemporaryFile probe(QDir(m_ftpRoot).filePath(".cv-write-test-XXXXXX"));
    if (!QSqlDatabase::database().isOpen() || !QDir().mkpath(m_ftpRoot) || !probe.open()) {
        setStatusMessage(QStringLiteral("FTP 未启动：数据库或上传目录不可用")); return;
    }
    if (ftpListen(m_ftpPort, m_ftpRoot)) {
        const QString msg = QStringLiteral("FTP 服务器已启动：端口 %1，目录 %2").arg(m_ftpPort).arg(m_ftpRoot);
        setStatusMessage(msg);
        LOG_INFO("FTP 服务器已成功启动: 监听端口={}, 根目录={}, 用户数={}", m_ftpPort, m_ftpRoot.toStdString(), m_ftpUsers.size());
        // write accounts to ftp log for visibility
        QStringList accs;
        for (auto it = m_ftpUsers.constBegin(); it != m_ftpUsers.constEnd(); ++it) accs << it.key();
        const QString acctLine = QStringLiteral("FTP ACCOUNTS: %1").arg(accs.join(","));
        QFile af(m_ftpLogPath);
        if (af.open(QIODevice::Append | QIODevice::Text)) {
            QTextStream ts(&af);
            ts << QDateTime::currentDateTime().toString(Qt::ISODateWithMs) << " " << acctLine << "\n";
            af.close();
        }
        // Also append to in-memory ftp log lines so UI shows it immediately
        const QString acctEntry = QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + acctLine;
        m_ftpLogLines.append(acctEntry);
        while (m_ftpLogLines.size() > 2000) m_ftpLogLines.removeFirst();
        emit ftpLogChanged();
        LOG_DEBUG("startFtpServer: 追加账户记录, 当前条数={}", m_ftpLogLines.size());
        // Append startup info to ftp log buffer so UI can show current root and files
        const QString header = QStringLiteral("FTP START: %1").arg(QDateTime::currentDateTime().toString(Qt::ISODateWithMs));
        m_ftpLogBuffer.append(header + "\n");
        m_ftpLogBuffer.append(QStringLiteral("根目录: %1\n").arg(m_ftpRoot));
        QDir d(m_ftpRoot);
        QFileInfoList files = d.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
        if (files.isEmpty()) {
            m_ftpLogBuffer.append(QStringLiteral("(目录为空)\n"));
        } else {
            const int shown = qMin(200, files.size());
            for (int i = 0; i < shown; ++i) {
                m_ftpLogBuffer.append(files.at(i).fileName() + "\n");
            }
            if (files.size() > shown) m_ftpLogBuffer.append(QStringLiteral("... 共 %1 个文件\n").arg(files.size()));
        }
        emit ftpLogChanged();
    } else {
        const QString msg = QStringLiteral("无法启动 FTP 服务器（端口可能被占用）：%1").arg(m_ftpPort);
        setStatusMessage(msg);
        LOG_ERROR("无法启动内置 FTP 服务器，端口可能被占用: {}", m_ftpPort);
    }
    emit ftpServerStateChanged();
}

bool AppController::saveCsv(const QString &filePath, const QString &content)
{
    if (filePath.isEmpty() || QFileInfo(filePath).isAbsolute()
        || QFileInfo(filePath).fileName() != filePath || filePath.contains(u'/')
        || filePath.contains(u'\\') || content.size() > 50 * 1024 * 1024) return false;
    const QString path = QDir(QCoreApplication::applicationDirPath()).filePath(filePath);
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        LOG_ERROR("导出CSV失败，无法打开目标文件: {}", filePath.toStdString());
        return false;
    }
    QTextStream ts(&f);
    ts << content;
    if (!f.commit()) {
        LOG_ERROR("导出CSV失败，无法提交写入: {}", filePath.toStdString());
        return false;
    }
    LOG_INFO("成功导出CSV报表: 文件={}, 大小={}字节", filePath.toStdString(), content.size());
    return true;
}

bool AppController::ftpListen(int port, const QString &root)
{
    FtpIngestService *service = m_ftpService;
    const auto users = m_ftpUsers;
    const bool allowAnonymous = m_ftpAllowAnonymous;
    bool ok = false;
    QMetaObject::invokeMethod(service, [service, port, root, users, allowAnonymous]() {
        service->setRoot(root);
        return service->start(static_cast<quint16>(port), root, users, allowAnonymous);
    }, Qt::BlockingQueuedConnection, &ok);
    m_ftpRunning = ok;
    return ok;
}

void AppController::ftpStop()
{
    FtpIngestService *service = m_ftpService;
    QMetaObject::invokeMethod(service, [service]() { service->stop(); }, Qt::BlockingQueuedConnection);
    m_ftpRunning = false;
    m_ftpClientCount = 0;
}

void AppController::ftpPushUsers()
{
    FtpIngestService *service = m_ftpService;
    const auto users = m_ftpUsers;
    const bool allowAnonymous = m_ftpAllowAnonymous;
    QMetaObject::invokeMethod(service, [service, users, allowAnonymous]() {
        service->setUsers(users, allowAnonymous);
    }, Qt::QueuedConnection);
}

void AppController::ftpPushRoot()
{
    FtpIngestService *service = m_ftpService;
    const QString root = m_ftpRoot.isEmpty() ? m_archiveDirectory : m_ftpRoot;
    QMetaObject::invokeMethod(service, [service, root]() { service->setRoot(root); }, Qt::QueuedConnection);
}

void AppController::stopFtpServer()
{
    ftpStop();
    setStatusMessage(QStringLiteral("FTP 服务器已停止"));
    LOG_INFO("FTP 服务器已停止运行");
    emit ftpServerStateChanged();
}

void AppController::startTcpServer()
{
    if (m_tcpReceiver.isRunning()) return;
    QSqlDatabase db = QSqlDatabase::database();
    if (db.isOpen()) {
        m_tcpPort = DBSchema::getConfigInt(db, QStringLiteral("tcp/port"), 9000);
    }
    m_tcpReceiver.listen(QHostAddress::Any, static_cast<quint16>(m_tcpPort));
    emit tcpServerStateChanged();
}

void AppController::stopTcpServer()
{
    m_tcpReceiver.stop();
    emit tcpServerStateChanged();
}

bool AppController::tcpRunning() const
{
    return m_tcpReceiver.isRunning();
}

int AppController::tcpPort() const
{
    return m_tcpPort;
}

int AppController::tcpClientCount() const
{
    return m_tcpReceiver.clientCount();
}

void AppController::setTcpPort(int port)
{
    if (port <= 0 || port > 65535 || m_tcpPort == port) return;
    m_tcpPort = port;
    QSqlDatabase db = QSqlDatabase::database();
    if (db.isOpen()) {
        DBSchema::setConfig(db, QStringLiteral("tcp/port"), QString::number(port));
    }
    if (m_tcpReceiver.isRunning()) {
        m_tcpReceiver.stop();
        m_tcpReceiver.listen(QHostAddress::Any, static_cast<quint16>(m_tcpPort));
    }
    emit tcpServerStateChanged();
}

bool AppController::processTcpBatch(const QJsonObject &batchData, QString &error)
{
    ImageIngest::BatchData batch;
    if (!ImageIngest::parseBatchJson(batchData, batch, error)) {
        LOG_ERROR("[TCP] 批次数据解析失败: {}", error.toStdString());
        setStatusMessage(QStringLiteral("TCP 报文解析失败: %1").arg(error));
        return false;
    }

    {
        QMutexLocker lock(&m_dbMutex);
        if (!ImageIngest::recordBatch(QSqlDatabase::database(), batch, error)) {
            LOG_ERROR("[TCP] 数据原子入库失败: {}", error.toStdString());
            setStatusMessage(QStringLiteral("数据入库失败: %1").arg(error));
            return false;
        }
    }

    m_currentCarrierId = batch.carrierId;
    m_currentRoundNumber = 0;
    m_currentReceivedAtText = AgcUtils::formatDateTime(batch.timestamp);
    m_currentSerialsRaw = QStringLiteral("载具 #%1 (轮数=%2)").arg(batch.carrierId).arg(batch.wheels.size());
    m_currentCopiedCount = batch.wheels.size();
    emit currentBatchChanged();

    // FTP 图像可能先于本批次到达：按发送方声明的 imageName 精确匹配缓存，否则到归档目录查找
    QStringList consumed;
    const QVector<ImageItem> cards = IngestCoordinator::buildStationCards(batch, [&](const QString &imageName) {
        const QString cached = m_pendingImages.find(imageName);
        if (!cached.isEmpty()) {
            consumed << imageName;
            return cached;
        }
        return resolveImagePath(imageName, m_archiveDirectory, m_sourceDirectory);
    });
    for (const QString &imageName : std::as_const(consumed)) m_pendingImages.remove(imageName);
    m_currentImagesModel.setItems(cards);
    LOG_INFO("[TCP] 载具 #{} 数据已成功入库并刷新 12 宫格卡片", batch.carrierId);
    setStatusMessage(QStringLiteral("载具 #%1 测量数据已接收，共 %2 轮").arg(batch.carrierId).arg(batch.wheels.size()));
    return true;
}

void AppController::onFtpImageStored(const QString &filePath)
{
    const QFileInfo file(filePath);
    if (!file.isFile() || file.isSymbolicLink()) return;
    const QString fileName = file.fileName();
    const QString resolvedUrl = QUrl::fromLocalFile(file.absoluteFilePath()).toString();

    const QString imageKey = IngestCoordinator::imageKey(fileName);
    bool matched = false;
    for (int i = 0; i < m_currentImagesModel.count(); ++i) {
        ImageItem item = m_currentImagesModel.itemAt(i);
        if (IngestCoordinator::imageKey(item.fileName) == imageKey && !imageKey.isEmpty()) {
            item.filePath = file.absoluteFilePath();
            item.fileUrl = resolvedUrl;
            item.fileName = fileName;
            m_currentImagesModel.updateSlotItem(i, item);
            matched = true;
        }
    }

    if (!matched) {
        const QDateTime now = QDateTime::currentDateTime();
        m_pendingImages.add(file.absoluteFilePath(), now);
        m_pendingImages.prune(now);
    }

    LOG_INFO("[FTP] 图像文件入库归档: {}, 关联卡片={}, 待关联缓存={}",
             fileName.toStdString(), matched, m_pendingImages.size());
}

QString AppController::ftpUser() const
{
    return m_ftpUser;
}



QString AppController::ftpRoot() const
{
    return m_ftpRoot;
}

QString AppController::ftpAccountsDebug() const
{
    QStringList parts;
    for (auto it = m_ftpUsers.constBegin(); it != m_ftpUsers.constEnd(); ++it) {
        parts << it.key();
    }
    return parts.join("; ");
}

int AppController::ftpPort() const
{
    return m_ftpPort;
}

bool AppController::ftpRunning() const
{
    return m_ftpRunning;
}

int AppController::ftpClientCount() const
{
    return m_ftpClientCount;
}

void AppController::setFtpUser(const QString &user)
{
    // update the single-legency displayed ftpUser and also update users map
    if (m_ftpUsers.contains(user) && m_ftpUsers.value(user) == m_ftpPass) return;
    // if user exists keep its password, otherwise create default pass
    if (user.trimmed().isEmpty() || user.size() > 64 || !m_ftpUsers.contains(user)) return;
    m_ftpUser = user;
    emit ftpSettingsChanged();
    ftpPushUsers();
    saveFtpSettingsToFile();
}

void AppController::setFtpPass(const QString &pass)
{
    if (m_ftpUser.isEmpty() || pass.isEmpty() || pass.size() > 256) return;
    const auto previous = m_ftpUsers;
    m_ftpUsers.insert(m_ftpUser, AgcUtils::encodePassword(pass));
    if (!saveFtpSettingsToFile()) { m_ftpUsers = previous; return; }
    m_ftpPass.clear();
    emit ftpSettingsChanged();
    ftpPushUsers();
}

bool AppController::applyFtpConfiguration(const QString &root, int port)
{
    const QString normalized = AgcUtils::normalizedPath(root);
    if (normalized.isEmpty() || normalized == QDir::rootPath() || normalized == QDir::homePath()
        || normalized == QCoreApplication::applicationDirPath() || QFileInfo(normalized).isSymbolicLink()
        || port < 1 || port > 65535) {
        setStatusMessage(QStringLiteral("FTP 根目录或端口无效")); return false;
    }
    if (!QDir().mkpath(normalized)) {
        setStatusMessage(QStringLiteral("无法创建 FTP 根目录: %1").arg(normalized)); return false;
    }
    QTemporaryFile probe(QDir(normalized).filePath(".cv-write-test-XXXXXX"));
    if (!probe.open()) { setStatusMessage(QStringLiteral("FTP 根目录不可写")); return false; }
    const QString previousRoot = m_ftpRoot;
    const int previousPort = m_ftpPort;
    const bool running = m_ftpRunning;
    if (running) ftpStop();
    m_ftpRoot = normalized; m_ftpPort = port;
    bool success = !running || ftpListen(port, normalized);
    if (success) success = saveFtpSettingsToFile();
    if (!success) {
        if (m_ftpRunning) ftpStop();
        m_ftpRoot = previousRoot; m_ftpPort = previousPort;
        const bool restored = !running || ftpListen(previousPort, previousRoot);
        ftpPushRoot();
        setStatusMessage(restored ? QStringLiteral("FTP 设置未生效，已恢复原配置") : QStringLiteral("FTP 设置失败，原服务也无法恢复，请检查端口"));
        return false;
    }
    ftpPushRoot();
    emit ftpSettingsChanged();
    return true;
}

void AppController::setFtpRoot(const QString &root)
{
    if (AgcUtils::normalizedPath(root) != m_ftpRoot) applyFtpConfiguration(root, m_ftpPort);
}

void AppController::setFtpPort(int port)
{
    if (port != m_ftpPort) applyFtpConfiguration(m_ftpRoot.isEmpty() ? m_archiveDirectory : m_ftpRoot, port);
}

QVariantList AppController::ftpAccounts() const
{
    QVariantList list;
    for (auto it = m_ftpUsers.constBegin(); it != m_ftpUsers.constEnd(); ++it) {
        QVariantMap o;
        o.insert(QStringLiteral("user"), it.key());
        o.insert(QStringLiteral("hasPassword"), !it.value().isEmpty());
        list.append(o);
    }
    return list;
}

void AppController::addFtpAccount(const QString &user, const QString &pass)
{
    const QString cleanUser = user.trimmed();
    if (cleanUser.isEmpty() || cleanUser.size() > 64 || pass.isEmpty() || pass.size() > 256
        || (!m_ftpUsers.contains(cleanUser) && m_ftpUsers.size() >= 32)) return;
    const auto previous = m_ftpUsers;
    m_ftpUsers.insert(cleanUser, AgcUtils::encodePassword(pass));
    if (!saveFtpSettingsToFile()) { m_ftpUsers = previous; return; }
    if (m_ftpUser.isEmpty()) m_ftpUser = cleanUser;
    emit ftpSettingsChanged();
    ftpPushUsers();
    LOG_INFO("添加 FTP 账户成功: {}", cleanUser.toStdString());
}

void AppController::removeFtpAccount(const QString &user)
{
    if (!m_ftpUsers.contains(user)) return;
    const auto previous = m_ftpUsers;
    m_ftpUsers.remove(user);
    if (!saveFtpSettingsToFile()) { m_ftpUsers = previous; return; }
    if (m_ftpUser == user) m_ftpUser = m_ftpUsers.isEmpty() ? QString() : m_ftpUsers.firstKey();
    emit ftpSettingsChanged();
    ftpPushUsers();
    LOG_INFO("移除 FTP 账户成功: {}", user.toStdString());
}

void AppController::ensureDirectories()
{
    // 保证配置的源目录与点检图像目录存在
    if (!m_sourceDirectory.isEmpty()) {
        if (QDir().mkpath(m_sourceDirectory)) {
            LOG_DEBUG("创建/确认源目录成功: {}", m_sourceDirectory.toStdString());
        }
    }

    if (!m_archiveDirectory.isEmpty()) {
        if (QDir().mkpath(m_archiveDirectory)) {
            LOG_DEBUG("创建/确认图像目录成功: {}", m_archiveDirectory.toStdString());
            const QString markerPath = QDir(m_archiveDirectory).filePath(QStringLiteral(".carriervision-images"));
            QFile marker(markerPath);
            if (!marker.exists() && marker.open(QIODevice::WriteOnly)) {
                marker.write("CarrierVision managed images\n");
            }
        }
    }

    // 额外确保运行目录下的 images 也存在（兼容用户直接查看工作目录）
    const QString appImages = QDir::cleanPath(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("images"));
    if (QDir().mkpath(appImages)) {
        LOG_DEBUG("创建/确认应用 images 目录成功: {}", appImages.toStdString());
        QFile marker(QDir(appImages).filePath(QStringLiteral(".carriervision-images")));
        if (!marker.exists() && marker.open(QIODevice::WriteOnly)) {
            marker.write("CarrierVision managed images\n");
        }
    }
}

void AppController::rowSelected(int index)
{
    // Bound check; kept minimal without noisy debug logging
    if (index < 0) return;
    Q_UNUSED(index);
}

void AppController::setStatusMessage(const QString &message)
{
    const QString decorated = QStringLiteral("%1  %2")
        .arg(AgcUtils::formatDateTime(QDateTime::currentDateTime()))
        .arg(message);

    if (m_statusMessage == decorated) {
        return;
    }

    m_statusMessage = decorated;
    emit statusMessageChanged();
}

void AppController::clearSearch()
{
    m_searchImagesModel.clear();
    m_searchSummary = QStringLiteral("(debug) search cleared");
    emit searchSummaryChanged();
}

void AppController::loadSettings()
{
    // Minimal settings loader for build-time: set sensible defaults
    // 默认点检图像存储目录为 images
    const QString defaultImages = QDir::cleanPath(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("images")));
    const QString legacyArchive = QDir::cleanPath(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("archive")));
    if (!QDir(defaultImages).exists() && QDir(legacyArchive).exists()) {
        if (QDir().rename(legacyArchive, defaultImages)) {
            LOG_INFO("AppController: 已自动将历史图像目录 '{}' 迁移为 '{}'", legacyArchive.toStdString(), defaultImages.toStdString());
        }
    }
    const QString envSource = qEnvironmentVariable("AGCFTP_SOURCE_DIR").trimmed();
    const QString envArchive = qEnvironmentVariable("AGCFTP_ARCHIVE_DIR").trimmed();

    m_sourceDirectory = AgcUtils::normalizedPath(envSource.isEmpty() ? defaultImages : envSource);
    m_archiveDirectory = AgcUtils::normalizedPath(envArchive.isEmpty() ? defaultImages : envArchive);
    if (m_archiveDirectory.endsWith(QStringLiteral("/archive"))) {
        QString updated = m_archiveDirectory;
        updated.chop(7);
        updated += QStringLiteral("images");
        m_archiveDirectory = updated;
    }
    // Load persisted FTP-related settings (includes slot mapping)
    loadFtpSettingsFromFile();
    // ensure ftp server has the current users before start
    ftpPushUsers();
}

QStringList AppController::getAvailableLogDates()
{
    return AppLogger::getAvailableDates();
}

QVariantMap AppController::queryLogs(const QString &dateStr, const QString &level, const QString &keyword, int page, int pageSize)
{
    return AppLogger::queryLogs(dateStr, level, keyword, page, pageSize);
}

int AppController::requestLogs(const QString &date, const QString &level, const QString &keyword, int page, int pageSize)
{
    m_logRequest = {date,level,keyword,page,pageSize};
    ++m_logGeneration;
    if (!m_logBusy) startLogQuery();
    return m_logGeneration;
}

void AppController::startLogQuery()
{
    m_logBusy = true;
    const auto request = m_logRequest;
    m_activeLogRequest = m_logGeneration;
    m_logWatcher.setFuture(QtConcurrent::run(&m_logPool, [request]() {
        auto result = AppLogger::queryLogs(request[0].toString(),request[1].toString(),request[2].toString(),request[3].toInt(),request[4].toInt());
        result["stats"] = AppLogger::getLogStats();
        return result;
    }));
}

QVariantMap AppController::getLogStats()
{
    return AppLogger::getLogStats();
}

void AppController::openLogDirectory()
{
    const QString dirPath = AppLogger::getLogDirectory();
    QDesktopServices::openUrl(QUrl::fromLocalFile(dirPath));
    LOG_INFO("在系统管理器中打开日志目录: {}", dirPath.toStdString());
}

void AppController::copyToClipboard(const QString &text)
{
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
        LOG_DEBUG("已复制文本到剪贴板，长度: {} 字符", text.size());
    }
}

void AppController::resetSlotMapping()
{
    const auto previous = m_slotMapping;
    m_slotMapping = SettingsStore::defaultSlotMapping();
    if (!saveFtpSettingsToFile()) { m_slotMapping = previous; return; }
    emit mappingChanged();
    LOG_INFO("重置相机通道槽位映射为默认 1:1");
    setStatusMessage(QStringLiteral("已重置相机工位通道映射为默认 1:1"));
}

void AppController::openArchiveDirectory()
{
    if (!m_archiveDirectory.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_archiveDirectory));
    }
}

void AppController::openFtpRootDirectory()
{
    const QString root = m_ftpRoot.isEmpty() ? m_archiveDirectory : m_ftpRoot;
    if (!root.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(root));
    }
}
