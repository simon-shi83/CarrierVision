// AppController：构造与析构、界面状态属性、系统设置（主题、首页说明、密码）、图像另存为等。
// 维护任务、网络服务、查询统计分别在 AppControllerMaintenance / AppControllerNetwork / AppControllerQueries.cpp。
#include "app/AppController.h"
#include "app/AppControllerInternal.h"
#include "data/DbSchema.h"
#include "common/AppLogger.h"

#include "common/AgcUtils.h"
#include "ingest/ImageIngest.h"
#include "data/ArchiveMaintenance.h"
#include "data/StatsService.h"
#include "data/WeeklyReport.h"
#include "data/DatabaseGuard.h"
#include "data/SearchService.h"
#include "data/SettingsStore.h"
#include "ingest/IngestCoordinator.h"
#include "common/StorageMonitor.h"
#include "common/ImageExport.h"
#include <iostream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QHostAddress>
#include <QCoreApplication>
#include <QDirIterator>
#include <QElapsedTimer>

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

QSqlDatabase AppControllerInternal::getThreadDatabase()
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


using AppControllerInternal::getThreadDatabase;
using AppControllerInternal::kMaxPageSize;
using AppControllerInternal::legacyFtpLogPrefix;

namespace {

void migrateLegacyFtpLogs()
{
    const QDir appDir(QCoreApplication::applicationDirPath());
    const QDir logDir(AppLogger::getLogDirectory());
    for (const QString &name : {QStringLiteral("ftp.log"), QStringLiteral("ftp.log.1")}) {
        const QFileInfo legacy(appDir.filePath(name));
        if (!legacy.isFile()) continue;
        const QString suffix = name.endsWith(QLatin1String(".1")) ? QStringLiteral(".1.log") : QStringLiteral(".log");
        const QString target = logDir.filePath(legacyFtpLogPrefix()
                                               + legacy.lastModified().toString(QStringLiteral("yyyyMMdd_HHmmss")) + suffix);
        if (QFile::exists(target) || !QFile::rename(legacy.absoluteFilePath(), target)) {
            LOG_WARN("旧 FTP 日志移入日志目录失败，保留原文件: {} -> {}", legacy.absoluteFilePath().toStdString(), target.toStdString());
            continue;
        }
        LOG_INFO("FTP 日志已并入主日志，旧文件已移入日志目录: {} -> {}", legacy.absoluteFilePath().toStdString(), target.toStdString());
    }
}

} // namespace

QUrl AppController::homeModelUrl() const
{
    const QString path = AgcUtils::resolveAppPath(QStringLiteral("assets/models/Assembly.glb"));
    if (!QFileInfo::exists(path)) {
        LOG_WARN("未找到首页三维模型文件（{}），三维视图将不显示载具", path.toStdString());
        return {};
    }
    return QUrl::fromLocalFile(path);
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
    m_exportPool.setMaxThreadCount(1);
    connect(&m_logWatcher, &QFutureWatcher<QVariantMap>::finished, this, [this]() {
        m_logBusy = false;
        if (m_activeLogRequest == m_logGeneration) emit logQueryFinished(m_activeLogRequest, m_logWatcher.result());
        else startLogQuery();
    });

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
    connect(&m_scheduleTimer, &QTimer::timeout, this, &AppController::runScheduledTasks);
    // 端口被占用等原因启动失败的服务每 30 秒自动重试；用户手动停止的不重试
    connect(&m_serviceRetryTimer, &QTimer::timeout, this, [this]() {
        if (!m_ftpRunning && !m_ftpStoppedByUser && !m_ftpUsers.isEmpty()) {
            LOG_INFO("FTP 服务未运行，尝试重新启动");
            startFtpServer();
        }
        if (!m_tcpReceiver.isRunning() && !m_tcpStoppedByUser) {
            LOG_INFO("TCP 数据服务未运行，尝试重新启动");
            startTcpServer();
        }
    });
    m_serviceRetryTimer.start(30'000);
    m_scheduleTimer.start(60'000);
    connect(&m_imageIngestLogTimer, &QTimer::timeout, this, &AppController::flushImageIngestLog);
    m_imageIngestLogTimer.start(60'000);

    connect(&m_storageTimer, &QTimer::timeout, this, &AppController::checkStorage);
    m_storageTimer.start(60'000);

    // FTP 日志已并入主日志，旧版本留在程序目录的 ftp.log 移入 logs/ 按日志保留天数清理
    migrateLegacyFtpLogs();

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
    // FTP 日志由 FtpServer 直接写入主日志，这里只把异常提示到状态栏
    connect(m_ftpService, &FtpIngestService::warningRaised, this, [this](const QString &message) {
        setStatusMessage(message.left(2048));
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
    // TcpDataReceiver 自身已写日志，logMessage 不再转发写入，避免每条记录两次
    m_tcpReceiver.batchHandler = [this](const QJsonObject &data, QString &error) {
        return processTcpBatch(data, error);
    };

    startTcpServer();
    QTimer::singleShot(0, this, &AppController::checkStorage); // 启动后立即检查一次磁盘空间
    QTimer::singleShot(5'000, this, &AppController::runScheduledTasks); // 补跑程序关闭期间错过的定时任务

    setStatusMessage(
        QStringLiteral("源目录 %1，归档目录 %2")
            .arg(m_sourceDirectory, m_archiveDirectory));
}

AppController::~AppController()
{
    stopFtpServer();
    FtpIngestService *service = m_ftpService;
    QMetaObject::invokeMethod(service, [service]() { service->shutdown(); }, Qt::BlockingQueuedConnection);
    m_ftpThread.quit();
    m_ftpThread.wait(); // finished 时 deleteLater 回收 m_ftpService
    m_ftpService = nullptr;
    flushImageIngestLog();
    stopTcpServer();
    ++m_searchGeneration;
    ++m_alertSearchGeneration;
    m_searchPool.clear();
    m_searchPool.waitForDone();
    m_statsPool.clear();
    m_statsPool.waitForDone();
    m_maintenancePool.waitForDone();
    m_exportPool.waitForDone();
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

void AppController::copyToClipboard(const QString &text)
{
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
        LOG_DEBUG("已复制文本到剪贴板，长度: {} 字符", text.size());
    }
}

void AppController::openArchiveDirectory()
{
    if (!m_archiveDirectory.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_archiveDirectory));
    }
}

QVariantMap AppController::imageFileInfo(const QString &source) const
{
    return ImageExport::probe(source);
}

QStringList AppController::imageSaveSuffixes(const QString &source) const
{
    return ImageExport::supportedTargetSuffixes(QFileInfo(ImageExport::localPathFromSource(source)).suffix());
}

QString AppController::imageSaveFolderUrl() const
{
    QString dir = m_lastImageSaveDir;
    if (dir.isEmpty() || !QFileInfo(dir).isDir())
        dir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (dir.isEmpty() || !QFileInfo(dir).isDir())
        dir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    return dir.isEmpty() ? QString() : QUrl::fromLocalFile(dir).toString();
}

int AppController::saveImageAs(const QString &source, const QString &target)
{
    const int requestId = ++m_imageSaveSeq;
    // 原图可达数百 MB，复制或转码放到后台线程，避免阻塞界面
    (void)QtConcurrent::run(&m_exportPool, [this, requestId, source, target]() {
        QElapsedTimer timer;
        timer.start();
        const ImageExport::Result result = ImageExport::exportImage(source, target);
        const QString sourceName = QFileInfo(ImageExport::localPathFromSource(source)).fileName();
        if (result.ok) {
            LOG_INFO("图像另存为完成: 原图={}, 目标={}, 耗时={}ms", sourceName.toStdString(),
                     result.targetPath.toStdString(), timer.elapsed());
        } else {
            LOG_WARN("图像另存为失败: 原图={}, 目标={}, 原因={}", sourceName.toStdString(),
                     target.toStdString(), result.message.toStdString());
        }
        QMetaObject::invokeMethod(this, [this, requestId, result]() {
            if (result.ok) m_lastImageSaveDir = QFileInfo(result.targetPath).absolutePath();
            emit imageSaveFinished(requestId, result.ok, result.message, result.targetPath);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

void AppController::revealFileInFolder(const QString &path)
{
    const QString local = ImageExport::localPathFromSource(path);
    if (local.isEmpty()) return;
    const QFileInfo fi(local);
    const QString dir = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    if (QFileInfo(dir).isDir()) QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}
