#include "AppController.h"
#include "AppLogger.h"
#include <nlohmann/json.hpp>

#include "AgcUtils.h"
#include "ImageIngest.h"
#include "ArchiveMaintenance.h"
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

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {

constexpr int kMaxPageSize = 200;

int boundedJsonInt(const nlohmann::json &value, int fallback, int low, int high)
{
    if (!value.is_number_integer()) return fallback;
    const double number = value.get<double>();
    return number >= low && number <= high ? static_cast<int>(number) : fallback;
}

bool isSafeArchiveRoot(const QString &path)
{
    const QFileInfo info(path);
    const QString clean = QDir::cleanPath(info.absoluteFilePath());
    if (clean.isEmpty() || info.isSymbolicLink()) return false;
    const QString root = QDir::cleanPath(QDir(clean).rootPath());
    const QString home = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
    const QString appDir = QDir::cleanPath(QCoreApplication::applicationDirPath());
    if (clean == root || clean == home || clean == appDir) return false;
    return QFileInfo(QDir(clean).filePath(QStringLiteral(".carriervision-archive"))).isFile();
}

bool parseResultFilter(const QString &text, int &result)
{
    const QString token = text.trimmed();
    if (token.isEmpty()) return false;
    if (token.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0 || token == QStringLiteral("1")) {
        result = 1;
        return true;
    }
    if (token.compare(QStringLiteral("NG"), Qt::CaseInsensitive) == 0 || token == QStringLiteral("0")) {
        result = 0;
        return true;
    }
    return false;
}

QString encodePassword(const QString &password)
{
    QByteArray salt(16, Qt::Uninitialized);
    for (char &byte : salt) byte = static_cast<char>(QRandomGenerator::global()->generate() & 0xff);
    QByteArray digest = password.toUtf8();
    for (int i = 0; i < 20'000; ++i) {
        digest = QCryptographicHash::hash(salt + digest, QCryptographicHash::Sha256);
    }
    return QStringLiteral("sha256$%1$%2")
        .arg(QString::fromLatin1(salt.toHex()), QString::fromLatin1(digest.toHex()));
}

bool verifyEncodedPassword(const QString &password, const QString &stored)
{
    if (!stored.startsWith(QStringLiteral("sha256$"))) return password == stored;
    const QStringList fields = stored.split(u'$');
    if (fields.size() != 3) return false;
    const QByteArray salt = QByteArray::fromHex(fields.at(1).toLatin1());
    QByteArray digest = password.toUtf8();
    for (int i = 0; i < 20'000; ++i) {
        digest = QCryptographicHash::hash(salt + digest, QCryptographicHash::Sha256);
    }
    return QString::fromLatin1(digest.toHex()) == fields.at(2);
}

nlohmann::json batchToJson(const BatchRecord &record)
{
    nlohmann::json object;
    object["batchId"] = record.batchId.toStdString();
    object["roundNumber"] = record.roundNumber;
    object["serialsRaw"] = record.serialsRaw.toStdString();
    object["receivedAt"] = record.receivedAt.toString(Qt::ISODateWithMs).toStdString();
    object["targetDirectory"] = record.targetDirectory.toStdString();
    object["completed"] = record.completed;

    nlohmann::json serialArray = nlohmann::json::array();
    for (const QString &serial : record.serials) {
        serialArray.push_back(serial.toStdString());
    }
    object["serials"] = serialArray;

    nlohmann::json imageArray = nlohmann::json::array();
    for (const QString &imageFile : record.imageFiles) {
        imageArray.push_back(imageFile.toStdString());
    }
    object["imageFiles"] = imageArray;

    return object;
}

BatchRecord batchFromJson(const nlohmann::json &object)
{
    BatchRecord record;
    if (object.contains("batchId") && object["batchId"].is_string())
        record.batchId = QString::fromStdString(object["batchId"].get<std::string>());
    if (object.contains("roundNumber") && object["roundNumber"].is_number())
        record.roundNumber = boundedJsonInt(object["roundNumber"], 0, 0, std::numeric_limits<int>::max());
    if (object.contains("serialsRaw") && object["serialsRaw"].is_string())
        record.serialsRaw = QString::fromStdString(object["serialsRaw"].get<std::string>());
    if (object.contains("receivedAt") && object["receivedAt"].is_string()) {
        QString recStr = QString::fromStdString(object["receivedAt"].get<std::string>());
        record.receivedAt = QDateTime::fromString(recStr, Qt::ISODateWithMs);
        if (!record.receivedAt.isValid()) {
            record.receivedAt = QDateTime::fromString(recStr, Qt::ISODate);
        }
    }
    if (object.contains("targetDirectory") && object["targetDirectory"].is_string())
        record.targetDirectory = QString::fromStdString(object["targetDirectory"].get<std::string>());
    if (object.contains("completed") && object["completed"].is_boolean())
        record.completed = object["completed"].get<bool>();

    if (object.contains("serials") && object["serials"].is_array()) {
        for (const auto &value : object["serials"]) {
            if (value.is_string())
                record.serials.append(QString::fromStdString(value.get<std::string>()));
        }
    }

    if (object.contains("imageFiles") && object["imageFiles"].is_array()) {
        for (const auto &value : object["imageFiles"]) {
            if (value.is_string())
                record.imageFiles.append(QString::fromStdString(value.get<std::string>()));
        }
    }

    return record;
}

} // namespace

void AppController::triggerCleanup()
{
    const QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    const int keepDays = qBound(1, settings.value("cleanup/keepDays", 90).toInt(), 3650);
    const int logKeepDays = qBound(1, settings.value("cleanup/logKeepDays", 30).toInt(), 3650);

    LOG_INFO("执行历史数据清理任务: 图像保留天数={} 天, 日志保留天数={} 天", keepDays, logKeepDays);
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-keepDays);

    const QString archiveRoot = m_archiveDirectory.isEmpty()
        ? (QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("archive"))
        : m_archiveDirectory;
    if (!isSafeArchiveRoot(archiveRoot)) {
        setStatusMessage(QStringLiteral("已拒绝清理未标记或危险的归档目录: %1").arg(archiveRoot));
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
    int removed = 0;
    bool more = false;
    QString error;
    const bool removeOk = ArchiveMaintenance::cleanup(QSqlDatabase::database(), archiveRoot,
        {archiveRoot, m_ftpRoot}, cutoff, removed, more, error);
    if (!removeOk) {
        setStatusMessage(QStringLiteral("清理未完成: %1").arg(error));
        return;
    }
    if (more) QTimer::singleShot(50, this, &AppController::triggerCleanup);

    // 2. 清理超期运行日志文件 (超过 logKeepDays 天的日志自动删除)
    AppLogger::cleanupLogsOlderThanDays(logKeepDays);

    // 3. 检查并清理过期的 FTP 轮转日志
    if (!m_ftpLogPath.isEmpty()) {
        const QString rotatedLog = m_ftpLogPath + QStringLiteral(".1");
        QFileInfo fi(rotatedLog);
        if (fi.exists() && fi.lastModified() < QDateTime::currentDateTime().addDays(-logKeepDays)) {
            QFile::remove(rotatedLog);
            LOG_INFO("已自动删除超期 FTP 轮转日志: {}", rotatedLog.toStdString());
        }
    }

    setStatusMessage(removeOk ? QStringLiteral("历史图像与日志数据清理完成")
                              : QStringLiteral("数据库与日志已清理，部分隔离图像待下次删除"));
}

int AppController::cleanupKeepDays() const
{
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    return settings.value("cleanup/keepDays", 90).toInt();
}

int AppController::cleanupLogKeepDays() const
{
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    return settings.value("cleanup/logKeepDays", 30).toInt();
}

int AppController::cleanupRunHour() const
{
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    return settings.value("cleanup/runHour", 1).toInt();
}

QString AppController::homepageDescription() const
{
    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    return settings.value(
        "homepage/description",
        QStringLiteral("欢迎使用 AGC ImageViewer。系统用于接收、浏览和查询 AGC 检测图片，并提供批次监控、数据统计及参数设置等功能。"))
        .toString();
}

bool AppController::isDarkMode() const
{
    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    return settings.value("ui/isDark", false).toBool();
}

void AppController::setDarkMode(bool dark)
{
    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    if (settings.value("ui/isDark", false).toBool() == dark) {
        return;
    }
    settings.setValue("ui/isDark", dark);
    settings.sync();
    LOG_INFO("持久化保存颜色主题配置: {}", dark ? "深色模式 (Dark)" : "浅色模式 (Light)");
    emit darkModeChanged(dark);
}

void AppController::setCleanupKeepDays(int days)
{
    days = qBound(1, days, 3650);
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("cleanup/keepDays", days);
    settings.sync();
    LOG_DEBUG("设置图像清理保留天数: {} 天", days);
}

void AppController::setCleanupLogKeepDays(int days)
{
    days = qBound(1, days, 3650);
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("cleanup/logKeepDays", days);
    settings.sync();
    LOG_DEBUG("设置日志清理保留天数: {} 天", days);
}

void AppController::setCleanupRunHour(int hour)
{
    hour = qBound(0, hour, 23);
    QString configPath = QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("cleanup/runHour", hour);
    settings.sync();
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

    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("homepage/description", trimmedDescription);
    settings.sync();
    if (settings.status() != QSettings::NoError) {
        return false;
    }

    emit homepageDescriptionChanged();
    return true;
}

bool AppController::verifySettingsPassword(const QString &password) const
{
    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    const QString stored = settings.value("security/settingsPassword").toString();
    bool ok = !stored.isEmpty() && verifyEncodedPassword(password, stored);
    if (ok) {
        LOG_INFO("管理员安全密码验证成功");
    } else {
        LOG_WARN("管理员安全密码验证失败");
    }
    return ok;
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
    if (newPassword.size() < 6 || !verifySettingsPassword(currentPassword)) {
        LOG_WARN("修改密码被拒绝：当前密码不符或新密码长度不足6位");
        return false;
    }

    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("security/settingsPassword", encodePassword(newPassword));
    settings.sync();
    bool success = (settings.status() == QSettings::NoError);
    if (success) {
        LOG_INFO("管理员密码修改成功");
    } else {
        LOG_ERROR("管理员密码修改写入配置文件失败");
    }
    return success;
}

bool AppController::resetSettingsPassword()
{
    const QString configPath = QCoreApplication::applicationDirPath()
        + QDir::separator() + "config.ini";
    QSettings settings(configPath, QSettings::IniFormat);
    settings.setValue("security/settingsPassword", encodePassword(QStringLiteral("123456")));
    settings.sync();
    LOG_WARN("管理员密码已被重置为默认密码");
    return settings.status() == QSettings::NoError;
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_logPool.setMaxThreadCount(1);
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
    connect(&m_cleanupTimer, &QTimer::timeout, this, [this]() {
        triggerCleanup();
        scheduleCleanup();
    });
    scheduleCleanup();
    loadArchiveIndex();
    // prepare ftp log path
    m_ftpLogPath = QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("ftp.log");
    // try loading existing ftp log file
    loadFtpLogs();

    connect(&m_tcpServer, &TcpMessageServer::statusChanged, this, [this](const QString &message) {
        setStatusMessage(message);
    });

    // 仅在构造时单次连接原始消息，避免每次收到架子信号时重复 connect 造成信号泄漏
    connect(&m_tcpServer, &TcpMessageServer::rawMessageReceived, this, [this](const QString &msg) {
        m_lastTcpMessage = msg;
        emit lastTcpMessageChanged();
    });

    connect(&m_ftpServer, &FtpServer::runningChanged, this, [this](bool) {
        emit ftpServerStateChanged();
    });
    connect(&m_ftpServer, &FtpServer::clientCountChanged, this, [this](int) {
        emit ftpServerStateChanged();
    });
    connect(&m_ftpServer, &FtpServer::logMessage, this, [this](const QString &message) {
        const QString boundedMessage = message.left(2048);
        setStatusMessage(boundedMessage);
        const QString entry = QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + " " + boundedMessage;
        m_ftpLogLines.append(entry);
        while (m_ftpLogLines.size() > 2000) m_ftpLogLines.removeFirst();

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

        QStringList visibleLines;
        visibleLines.reserve(m_ftpLogLines.size());
        for (const QVariant &line : std::as_const(m_ftpLogLines)) visibleLines.append(line.toString());
        m_ftpLogBuffer = visibleLines.join('\n');
        emit ftpLogChanged();
    });
    m_ftpServer.uploadHandler = [this](const QString &staged, const QString &target) {
        QString error;
        const bool accepted = ImageIngest::accept(staged, target,
            [this](const QString &path) { return ingestStoredImage(path); }, error);
        if (!accepted) setStatusMessage(error);
        return accepted;
    };
    connect(&m_ingestRetryTimer, &QTimer::timeout, this, &AppController::recoverPendingUploads);
    m_ingestRetryTimer.start(1000);

    connect(&m_tcpServer, &TcpMessageServer::serverStateChanged, this, [this](bool running, quint16 port) {
        const bool changed = (m_serverRunning != running);
        m_serverRunning = running;
        Q_UNUSED(port);
        if (changed) {
            emit serverRunningChanged();
        }
    });

    // start integrated FTP server
    startFtpServer();
    LOG_DEBUG("内置 FTP 服务初始化检测: ftpRunning={}", ftpRunning());
    // 如果内置 FTP 未能启动，记录警告并继续运行（避免因占用端口导致整个 UI 无法启动）
    if (!ftpRunning() && !m_ftpUsers.isEmpty()) {
        const QString failMsg = QStringLiteral("无法启动内置 FTP 服务（端口可能被占用），继续运行但部分功能不可用");
        LOG_WARN("内置 FTP 服务未能启动: 端口={}, 账户数={}", m_ftpPort, m_ftpUsers.size());
        setStatusMessage(failMsg);
        // 不退出，允许 UI 界面启动以便调试和使用其他功能
    }

    connect(
        &m_tcpServer,
        &TcpMessageServer::rackMessageReceived,
        this,
        [this](const QString &rackNumber, int roundNumber, int currentTotal)
        {
            const QString rackKey = rackNumber.trimmed();
            if (m_lastTotalByRack.contains(rackKey)) {
                const int prev = m_lastTotalByRack.value(rackKey);
                if (qint64(currentTotal) > qint64(prev) + 1) {
                    const QString gapMsg = QStringLiteral("检测到TCP跳号: rack=%1 total %2 -> %3")
                                               .arg(rackKey)
                                               .arg(prev)
                                               .arg(currentTotal);
                    setStatusMessage(gapMsg);
                    LOG_WARN("检测到TCP报文跳号: 架号={}, 上次计数={}, 当前计数={}", rackKey.toStdString(), prev, currentTotal);
                }
            }
            m_lastTotalByRack.insert(rackKey, currentTotal);

            LOG_INFO("TCP接收架轮报文: 架号={}, 轮号={}, 累计总数={}", rackNumber.toStdString(), roundNumber, currentTotal);

            // 更新可供 QML 显示的原始 TCP 消息
            m_lastTcpMessage = QStringLiteral("%1,%2,%3").arg(rackNumber).arg(roundNumber).arg(currentTotal);
            emit lastTcpMessageChanged();

            m_currentBatchId = QStringLiteral("RACK_%1_R%2_%3")
                .arg(rackNumber)
                .arg(roundNumber)
                .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss_zzz")));
            m_currentRoundNumber = roundNumber;
            m_currentReceivedAtText = AgcUtils::formatDateTime(QDateTime::currentDateTime());
            if (roundNumber == 0) {
                m_currentSerialsRaw = QStringLiteral("%1,%2").arg(rackNumber).arg(currentTotal);
            } else {
                m_currentSerialsRaw = QStringLiteral("%1,%2,%3").arg(rackNumber).arg(roundNumber).arg(currentTotal);
            }
            m_currentCopiedCount = 0;
            emit currentBatchChanged();

            LOG_DEBUG("收到架轮数据批次: batchId={} serials={}", m_currentBatchId.toStdString(), m_currentSerialsRaw.toStdString());
            setStatusMessage(
                QStringLiteral("架子 %1 轮号 %2 当前总数 %3 已接收")
                    .arg(rackNumber)
                    .arg(roundNumber)
                    .arg(currentTotal));
        });

    // CopyWorker removed — batchUpdated/completion now handled by FTP events
    m_tcpServer.start(static_cast<quint16>(m_listenPort));
    setStatusMessage(
        QStringLiteral("源目录 %1，归档目录 %2，TCP 端口 %3")
            .arg(m_sourceDirectory, m_archiveDirectory)
            .arg(m_listenPort));
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
    QVariantList out;
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return out;

    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    QSqlQuery q(db);
    // select records in time range and driver wheels 1..8
    q.prepare("SELECT rackno, wheelno, result FROM record WHERE createtime >= :start AND createtime <= :end");
    q.bindValue(":start", startTime.isValid() ? AgcUtils::formatDateTime(startTime) : startDate);
    q.bindValue(":end", endTime.isValid() ? AgcUtils::formatDateTime(endTime) : endDate);
    if (!q.exec()) {
        LOG_ERROR("driveWheelRackStats 数据库查询失败: {}", q.lastError().text().toStdString());
        return out;
    }

    // initialize counters for 1..50 racks
    struct Stat { int ok=0; int ng=0; };
    QVector<Stat> stats(50);

    while (q.next()) {
        QString rack = q.value(0).toString();
        QString wheel = q.value(1).toString();
        int res = q.value(2).toInt();
        bool okR=false; int rnum = rack.toInt(&okR);
        bool okW=false; int wnum = wheel.toInt(&okW);
        if (!okR || !okW) continue;
        if (rnum < 1 || rnum > 50) continue;
        // only driver wheels 1..8
        if (wnum < 1 || wnum > 8) continue;
        if (res == 1) stats[rnum-1].ok++;
        else stats[rnum-1].ng++;
    }

    // prepare output: for each rack produce {rack, ok, ng, loss}
    for (int i=0;i<50;i++) {
        QVariantMap m;
        m[QStringLiteral("rack")] = i+1;
        int okc = stats[i].ok;
        int ngc = stats[i].ng;
        m[QStringLiteral("ok")] = okc;
        m[QStringLiteral("ng")] = ngc;
        double loss = 0.0;
        int total = okc + ngc;
        if (total > 0) loss = (double)ngc * 100.0 / (double)total; // percent
        m[QStringLiteral("loss")] = loss;
        out.append(m);
    }

    return out;
}

QVariantList AppController::walkingWheelRackStats(const QString &startDate, const QString &endDate)
{
    QVariantList out;
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return out;

    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    QSqlQuery q(db);
    q.prepare("SELECT rackno, wheelno, result FROM record WHERE createtime >= :start AND createtime <= :end");
    q.bindValue(":start", startTime.isValid() ? AgcUtils::formatDateTime(startTime) : startDate);
    q.bindValue(":end", endTime.isValid() ? AgcUtils::formatDateTime(endTime) : endDate);
    if (!q.exec()) return out;

    struct Stat { int ok = 0; int ng = 0; };
    QVector<Stat> stats(50);
    while (q.next()) {
        bool rackOk = false;
        bool wheelOk = false;
        const int rack = q.value(0).toString().toInt(&rackOk);
        const int wheel = q.value(1).toString().toInt(&wheelOk);
        if (!rackOk || !wheelOk || rack < 1 || rack > 50 || wheel < 11 || wheel > 18) continue;
        if (q.value(2).toInt() == 1) stats[rack - 1].ok++;
        else stats[rack - 1].ng++;
    }

    for (int i = 0; i < 50; ++i) {
        QVariantMap row;
        const int total = stats[i].ok + stats[i].ng;
        row[QStringLiteral("rack")] = i + 1;
        row[QStringLiteral("ok")] = stats[i].ok;
        row[QStringLiteral("ng")] = stats[i].ng;
        row[QStringLiteral("loss")] = total > 0 ? stats[i].ng * 100.0 / total : 0.0;
        out.append(row);
    }
    return out;
}

QVariantList AppController::rackWheelMonitorStatus() const
{
    QVariantList out;
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return out;
    }

    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT rackno,wheelno,result,createtime FROM ("
        " SELECT rackno,wheelno,result,createtime,"
        " ROW_NUMBER() OVER (PARTITION BY CAST(rackno AS INTEGER),CAST(wheelno AS INTEGER)"
        " ORDER BY datetime(createtime) DESC,rowid DESC) AS position FROM record"
        ") WHERE position=1"));

    if (!query.exec()) {
        LOG_ERROR("rackWheelMonitorStatus 数据库查询失败: {}", query.lastError().text().toStdString());
        return out;
    }

    while (query.next()) {
        const int rack = query.value(0).toInt();
        const int wheel = query.value(1).toInt();
        if (rack < 1 || rack > 50 || !((wheel >= 1 && wheel <= 8)
                                        || (wheel >= 11 && wheel <= 18))) {
            continue;
        }

        QVariantMap item;
        item.insert(QStringLiteral("rack"), rack);
        item.insert(QStringLiteral("wheel"), wheel);
        item.insert(QStringLiteral("result"), query.value(2).toInt());
        item.insert(QStringLiteral("time"), query.value(3).toString());
        out.append(item);
    }
    return out;
}

QVariantList AppController::rackPhotoCounts() const
{
    QVariantList out;
    QVector<int> counts(50, 0);
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return out;
    }

    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT CAST(rackno AS INTEGER), COUNT(*) FROM record "
        "WHERE CAST(rackno AS INTEGER) BETWEEN 1 AND 50 "
        "AND CAST(wheelno AS INTEGER) = 1 "
        "GROUP BY CAST(rackno AS INTEGER)"));
    if (query.exec()) {
        while (query.next()) {
            const int rack = query.value(0).toInt();
            if (rack >= 1 && rack <= 50) {
                counts[rack - 1] = query.value(1).toInt();
            }
        }
    } else {
        LOG_ERROR("rackPhotoCounts 数据库统计失败: {}", query.lastError().text().toStdString());
    }

    for (int rack = 1; rack <= 50; ++rack) {
        QVariantMap item;
        item.insert(QStringLiteral("rack"), rack);
        item.insert(QStringLiteral("count"), counts[rack - 1]);
        out.append(item);
    }
    return out;
}

QVariantMap AppController::homepageCurrentDetection() const
{
    QVariantMap overview;
    QVariantList driveWheels;
    QVariantList walkingWheels;
    overview.insert(QStringLiteral("rack"), 0);
    overview.insert(QStringLiteral("drive"), driveWheels);
    overview.insert(QStringLiteral("walking"), walkingWheels);
    overview.insert(QStringLiteral("drivePassRate"), 0.0);
    overview.insert(QStringLiteral("walkingPassRate"), 0.0);
	overview.insert(QStringLiteral("ngCount"), 0);
	overview.insert(QStringLiteral("totalCount"), 0);
	overview.insert(QStringLiteral("ngRate"), 0.0);

    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return overview;
    }

    bool rackOk = false;
    const int currentRack = m_lastTcpMessage.section(',', 0, 0).trimmed().toInt(&rackOk);
    int rackNumber = rackOk && currentRack >= 1 && currentRack <= 50 ? currentRack : 0;
    if (rackNumber == 0) {
        QSqlQuery latestRackQuery(db);
        if (latestRackQuery.exec(QStringLiteral(
                "SELECT CAST(rackno AS INTEGER) FROM record "
                "WHERE CAST(rackno AS INTEGER) BETWEEN 1 AND 50 "
                "ORDER BY createtime DESC, rowid DESC LIMIT 1"))
            && latestRackQuery.next()) {
            rackNumber = latestRackQuery.value(0).toInt();
        }
    }
    if (rackNumber < 1 || rackNumber > 50) {
        return overview;
    }
    overview.insert(QStringLiteral("rack"), rackNumber);

    for (int wheel = 1; wheel <= 8; ++wheel) {
        QVariantMap item;
        item.insert(QStringLiteral("wheel"), wheel);
        item.insert(QStringLiteral("result"), -1);
        item.insert(QStringLiteral("time"), QString());
        item.insert(QStringLiteral("passRate"), 0.0);
        driveWheels.append(item);
    }
    for (int wheel = 11; wheel <= 18; ++wheel) {
        QVariantMap item;
        item.insert(QStringLiteral("wheel"), wheel);
        item.insert(QStringLiteral("result"), -1);
        item.insert(QStringLiteral("time"), QString());
        item.insert(QStringLiteral("passRate"), 0.0);
        walkingWheels.append(item);
    }

    QSqlQuery latestQuery(db);
    latestQuery.prepare(QStringLiteral(
        "SELECT r.wheelno, r.result, r.createtime FROM record r "
        "INNER JOIN ("
        "  SELECT CAST(wheelno AS INTEGER) AS wheel, MAX(createtime) AS latestTime "
        "  FROM record WHERE CAST(rackno AS INTEGER) = :rack "
        "  AND (CAST(wheelno AS INTEGER) BETWEEN 1 AND 8 "
        "       OR CAST(wheelno AS INTEGER) BETWEEN 11 AND 18) "
        "  GROUP BY CAST(wheelno AS INTEGER)"
        ") latest ON CAST(r.wheelno AS INTEGER) = latest.wheel "
        "AND r.createtime = latest.latestTime "
        "WHERE CAST(r.rackno AS INTEGER) = :rack"));
    latestQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    if (latestQuery.exec()) {
        while (latestQuery.next()) {
            const int wheel = latestQuery.value(0).toInt();
            QVariantMap item;
            item.insert(QStringLiteral("wheel"), wheel);
            item.insert(QStringLiteral("result"), latestQuery.value(1).toInt());
            item.insert(QStringLiteral("time"), latestQuery.value(2).toString());
            if (wheel >= 1 && wheel <= 8) {
                driveWheels[wheel - 1] = item;
            } else if (wheel >= 11 && wheel <= 18) {
                walkingWheels[wheel - 11] = item;
            }
        }
    }

    QSqlQuery rateQuery(db);
    rateQuery.prepare(QStringLiteral(
        "SELECT CAST(wheelno AS INTEGER), result FROM record "
        "WHERE CAST(rackno AS INTEGER) = :rack "
        "AND createtime >= :todayStart"));
    rateQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    rateQuery.bindValue(QStringLiteral(":todayStart"),
                        AgcUtils::formatDateTime(QDateTime(QDate::currentDate(), QTime(0, 0))));
    QHash<int, int> passedCounts;
    QHash<int, int> totalCounts;
    if (rateQuery.exec()) {
        while (rateQuery.next()) {
            const int wheel = rateQuery.value(0).toInt();
            const bool passed = rateQuery.value(1).toInt() == 1;
            if ((wheel >= 1 && wheel <= 8) || (wheel >= 11 && wheel <= 18)) {
                ++totalCounts[wheel];
                if (passed) {
                    ++passedCounts[wheel];
                }
            }
        }
    }

	int ngCount = 0;
	int totalCount = 0;
	QSqlQuery totalQuery(db);
	totalQuery.prepare(QStringLiteral(
		"SELECT COUNT(*), SUM(CASE WHEN result = 0 THEN 1 ELSE 0 END) FROM record "
		"WHERE CAST(rackno AS INTEGER) = :rack "
		"AND (CAST(wheelno AS INTEGER) BETWEEN 1 AND 8 "
		"OR CAST(wheelno AS INTEGER) BETWEEN 11 AND 18)"));
	totalQuery.bindValue(QStringLiteral(":rack"), rackNumber);
	if (totalQuery.exec() && totalQuery.next()) {
		totalCount = totalQuery.value(0).toInt();
		ngCount = totalQuery.value(1).toInt();
	}
    for (int i = 0; i < driveWheels.size(); ++i) {
        QVariantMap item = driveWheels.at(i).toMap();
        const int wheel = item.value(QStringLiteral("wheel")).toInt();
        item.insert(QStringLiteral("passRate"), totalCounts.value(wheel) > 0
                    ? passedCounts.value(wheel) * 100.0 / totalCounts.value(wheel) : 0.0);
        driveWheels[i] = item;
    }
    for (int i = 0; i < walkingWheels.size(); ++i) {
        QVariantMap item = walkingWheels.at(i).toMap();
        const int wheel = item.value(QStringLiteral("wheel")).toInt();
        item.insert(QStringLiteral("passRate"), totalCounts.value(wheel) > 0
                    ? passedCounts.value(wheel) * 100.0 / totalCounts.value(wheel) : 0.0);
        walkingWheels[i] = item;
    }
    overview.insert(QStringLiteral("drive"), driveWheels);
    overview.insert(QStringLiteral("walking"), walkingWheels);
	overview.insert(QStringLiteral("ngCount"), ngCount);
	overview.insert(QStringLiteral("totalCount"), totalCount);
	overview.insert(QStringLiteral("ngRate"), totalCount > 0 ? ngCount * 100.0 / totalCount : 0.0);
    return overview;
}

QVariantMap AppController::latestRackWheelMonitorImage(int rackNumber, int wheelNumber) const
{
    QVariantMap image;
    if (rackNumber < 1 || rackNumber > 50 || !((wheelNumber >= 1 && wheelNumber <= 8)
                                                || (wheelNumber >= 11 && wheelNumber <= 18))) {
        return image;
    }

    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        return image;
    }

    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT imagename, createtime, result "
        "FROM record "
        "WHERE CAST(rackno AS INTEGER) = :rack AND CAST(wheelno AS INTEGER) = :wheel "
        "ORDER BY createtime DESC, rowid DESC LIMIT 1"));
    query.bindValue(QStringLiteral(":rack"), rackNumber);
    query.bindValue(QStringLiteral(":wheel"), wheelNumber);
    if (!query.exec() || !query.next()) {
        return image;
    }

    const QString imageName = query.value(0).toString();
    QString imagePath = imageName;
    if (QDir::isRelativePath(imagePath)) {
        const QString archiveDirectory = m_archiveDirectory.isEmpty()
            ? QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("archive"))
            : m_archiveDirectory;
        imagePath = QDir(archiveDirectory).filePath(imagePath);
    }

    image.insert(QStringLiteral("filePath"), imagePath);
    image.insert(QStringLiteral("fileName"), QFileInfo(imagePath).fileName());
    image.insert(QStringLiteral("time"), query.value(1).toString());
    image.insert(QStringLiteral("result"), query.value(2).toInt());
    return image;
}

QVariantList AppController::wheelRackResultStats(const QString &startDate, const QString &endDate,
                                                  int wheelNumber, const QString &resultType)
{
    QVariantList out;
    QVector<int> counts(50, 0);
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return out;

    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    const bool isOk = resultType.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0;
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT CAST(rackno AS INTEGER), COUNT(*) FROM record "
        "WHERE createtime >= :start AND createtime <= :end "
        "AND CAST(wheelno AS INTEGER) = :wheel AND result = :result "
        "GROUP BY CAST(rackno AS INTEGER)"));
    q.bindValue(QStringLiteral(":start"), startTime.isValid() ? AgcUtils::formatDateTime(startTime) : startDate);
    q.bindValue(QStringLiteral(":end"), endTime.isValid() ? AgcUtils::formatDateTime(endTime) : endDate);
    q.bindValue(QStringLiteral(":wheel"), wheelNumber);
    q.bindValue(QStringLiteral(":result"), isOk ? 1 : 0);

    if (q.exec()) {
        while (q.next()) {
            const int rack = q.value(0).toInt();
            if (rack >= 1 && rack <= 50) {
                counts[rack - 1] = q.value(1).toInt();
            }
        }
    } else {
        LOG_ERROR("wheelRackResultStats 数据库查询失败: {}", q.lastError().text().toStdString());
    }

    const int totalResultCount = std::accumulate(counts.cbegin(), counts.cend(), 0);
    for (int i = 0; i < 50; ++i) {
        QVariantMap row;
        row[QStringLiteral("rack")] = i + 1;
        row[QStringLiteral("count")] = counts[i];
        row[QStringLiteral("percent")] = totalResultCount > 0 ? counts[i] * 100.0 / totalResultCount : 0.0;
        out.append(row);
    }
    return out;
}

QVariantList AppController::rackWheelResultStats(const QString &startDate, const QString &endDate,
                                                  int rackNumber, const QString &resultType,
                                                  int wheelType) const
{
    QVariantList out;
    if (rackNumber < 1 || rackNumber > 50 || (wheelType != 0 && wheelType != 1)) {
        return out;
    }

    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    const int firstWheel = wheelType == 0 ? 1 : 11;
    const int lastWheel = wheelType == 0 ? 8 : 18;
    const bool isOk = resultType.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0;

    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return out;

    QHash<int, int> counts;
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT CAST(wheelno AS INTEGER), COUNT(*) FROM record "
        "WHERE CAST(rackno AS INTEGER) = :rack "
        "AND CAST(wheelno AS INTEGER) BETWEEN :firstWheel AND :lastWheel "
        "AND result = :result "
        "AND createtime >= :start AND createtime <= :end "
        "GROUP BY CAST(wheelno AS INTEGER)"));
    query.bindValue(QStringLiteral(":rack"), rackNumber);
    query.bindValue(QStringLiteral(":firstWheel"), firstWheel);
    query.bindValue(QStringLiteral(":lastWheel"), lastWheel);
    query.bindValue(QStringLiteral(":result"), isOk ? 1 : 0);
    query.bindValue(QStringLiteral(":start"), startTime.isValid() ? AgcUtils::formatDateTime(startTime) : startDate);
    query.bindValue(QStringLiteral(":end"), endTime.isValid() ? AgcUtils::formatDateTime(endTime) : endDate);
    if (query.exec()) {
        while (query.next()) {
            counts.insert(query.value(0).toInt(), query.value(1).toInt());
        }
    } else {
        LOG_ERROR("rackWheelResultStats 数据库查询失败: {}", query.lastError().text().toStdString());
    }

    for (int wheel = firstWheel; wheel <= lastWheel; ++wheel) {
        QVariantMap row;
        row.insert(QStringLiteral("rack"), rackNumber);
        row.insert(QStringLiteral("wheel"), wheel);
        row.insert(QStringLiteral("count"), counts.value(wheel));
        row.insert(QStringLiteral("result"), isOk ? QStringLiteral("OK") : QStringLiteral("NG"));
        out.append(row);
    }
    return out;
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

void AppController::onFtpImageStored(const QString &filePath)
{
    ingestStoredImage(filePath);
}

bool AppController::ingestStoredImage(const QString &filePath)
{
    ImageIngest::Metadata metadata;
    QString error;
    if (!ImageIngest::parse(filePath, metadata, error)) {
        setStatusMessage(error); return false;
    }
    const QFileInfo file(filePath);
    if (!file.isFile() || file.isSymbolicLink()) return false;
    QDateTime received = file.lastModified();
    QFile journal(filePath + QStringLiteral(".cv-pending"));
    if (journal.open(QIODevice::ReadOnly)) {
        const auto saved = QDateTime::fromString(QString::fromUtf8(journal.read(64)), "yyyy-MM-dd HH:mm:ss");
        if (saved.isValid()) received = saved;
    }
    const QString imageName = QDir(m_archiveDirectory).relativeFilePath(file.absoluteFilePath());
    bool inserted = false;
    {
        QMutexLocker lock(&m_dbMutex);
        if (!ImageIngest::record(QSqlDatabase::database(), metadata, imageName,
                                AgcUtils::formatDateTime(received), rackWheelDistances(metadata.rack), inserted, error)) {
            LOG_ERROR("图片入库失败: {}: {}", filePath.toStdString(), error.toStdString());
            setStatusMessage(QStringLiteral("图片入库失败，等待重试: %1").arg(file.fileName()));
            return false;
        }
    }
    if (!inserted) return true;
    ImageItem item;
    item.filePath = file.absoluteFilePath();
    item.fileName = file.fileName();
    item.receivedAt = received;
    item.rack = metadata.rack;
    item.slot = m_slotMapping.value(metadata.camera - 1, 0);
    item.distance = metadata.distance;
    item.dist_max = metadata.maximum;
    item.dist_norm = metadata.norm;
    item.result = 1;
    for (const auto &wheel : metadata.wheels) if (wheel.result == 0) item.result = 0;
    const int index = item.slot - 1;
    // Recovery of an old upload must not replace a newer live image.
    if (index >= 0 && (!m_currentImagesModel.itemAt(index).receivedAt.isValid()
        || m_currentImagesModel.itemAt(index).receivedAt <= received)
        && m_currentImagesModel.updateSlotItem(index, item)) emit slotUpdated(index);
    emit rackWheelMonitorUpdated();
    return true;
}

void AppController::recoverPendingUploads()
{
    if (m_ftpRoot.isEmpty()) return;
    if (!m_pendingScan) {
        m_pendingScan = std::make_unique<QDirIterator>(m_ftpRoot,
            QDir::Files | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDirIterator::Subdirectories);
    }
    int scanned = 0;
    while (m_pendingScan->hasNext() && scanned++ < 100) {
        const QString marker = m_pendingScan->next();
        if (!marker.endsWith(QStringLiteral(".cv-pending"))) continue;
        const QString path = marker.chopped(QStringLiteral(".cv-pending").size());
        QString error;
        if (ImageIngest::validate(path, path, error) && ingestStoredImage(path)) {
            if (!QFile::remove(marker)) LOG_WARN("无法移除已恢复记录: {}", marker.toStdString());
        }
    }
    if (!m_pendingScan->hasNext()) {
        m_pendingScan.reset();
        m_ingestRetryTimer.setInterval(60'000);
    } else {
        m_ingestRetryTimer.setInterval(20);
    }
}

AppController::~AppController()
{
    m_logPool.waitForDone();
    m_tcpServer.stop();
    stopFtpServer();
    // CopyWorker removed
}

QString AppController::sourceDirectory() const
{
    return m_sourceDirectory;
}

QString AppController::archiveDirectory() const
{
    return m_archiveDirectory;
}

int AppController::listenPort() const
{
    return m_listenPort;
}

bool AppController::serverRunning() const
{
    return m_serverRunning;
}

QString AppController::statusMessage() const
{
    return m_statusMessage;
}

QString AppController::currentSerialsRaw() const
{
    return m_currentSerialsRaw;
}

QString AppController::lastTcpMessage() const
{
    return m_lastTcpMessage;
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
    if (!query.exec(QStringLiteral(R"(
        SELECT CAST(rackno AS INTEGER)
        FROM record
        WHERE CAST(wheelno AS INTEGER) BETWEEN 1 AND 8
          AND result = 1
          AND distance > 0
        ORDER BY createtime DESC, rowid DESC
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
    // For each wheel (1..8) count matching rows, return the max count as total pages (1 record per page per wheel)
    const QString sql = QStringLiteral(R"(
        SELECT MAX(cnt) FROM (
            SELECT CAST(wheelno AS INTEGER) AS w, COUNT(*) AS cnt
            FROM record
            WHERE rackno = :rack AND result = 1 AND distance > 0 AND CAST(wheelno AS INTEGER) BETWEEN 1 AND 8
            GROUP BY CAST(wheelno AS INTEGER)
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
            SELECT rowid, createtime, rackno, wheelno, result, imagename, distance, dist_max, dist_norm
            FROM record
            WHERE rackno = :rack AND result = 1 AND distance > 0 AND CAST(wheelno AS INTEGER) = :wheel
            ORDER BY createtime DESC, rowid DESC
            LIMIT 1 OFFSET %1
        )").arg((page - 1));

        for (int wheel = 1; wheel <= 8; ++wheel) {
            if (!q.prepare(sql)) {
                queryError = q.lastError().text();
                LOG_ERROR("loadLatestRackWheelImagesPage 预处理 SQL 失败: {}", queryError.toStdString());
                break;
            }
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
                item.rack = q.value(2).toInt();
                item.slot = q.value(3).toInt();
                item.result = q.value(4).toInt();
                item.fileName = QFileInfo(q.value(5).toString().trimmed()).fileName();
                item.distance = q.value(6).toInt();
                item.dist_max = q.value(7).toInt();
                item.dist_norm = q.value(8).toInt();

                const QString rawName = q.value(5).toString().trimmed();
                if (QFile::exists(rawName)) {
                    item.filePath = QFileInfo(rawName).absoluteFilePath();
                } else {
                    const QStringList candidates = {
                        QDir(m_archiveDirectory).filePath(rawName),
                        QDir(m_sourceDirectory).filePath(rawName),
                        QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("archive")).filePath(rawName),
                        QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("incoming")).filePath(rawName)
                    };
                    for (const QString &candidate : candidates) {
                        if (QFile::exists(candidate)) { item.filePath = QFileInfo(candidate).absoluteFilePath(); break; }
                    }
                }
                if (!item.filePath.isEmpty()) item.fileUrl = QUrl::fromLocalFile(item.filePath).toString();
                items.append(item);
            }
            q.finish();
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

void AppController::search(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter)
{
    auto parseQueryDateTime = [](const QString &text, bool endOfDay) -> QDateTime {
        const QString trimmed = text.trimmed();
        if (trimmed.isEmpty()) {
            return QDateTime();
        }

        const QDate dateOnly = QDate::fromString(trimmed, QStringLiteral("yyyy-MM-dd"));
        if (dateOnly.isValid() && trimmed.size() == 10) {
            return QDateTime(dateOnly, endOfDay ? QTime(23, 59, 59, 999) : QTime(0, 0, 0));
        }

        QDateTime parsed = QDateTime::fromString(trimmed, QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        if (!parsed.isValid()) parsed = QDateTime::fromString(trimmed, Qt::ISODate);
        return parsed;
    };

    // 纯日期输入按整天范围处理；带时间输入则按原值处理。
    QDateTime startTime = parseQueryDateTime(startText, false);
    QDateTime endTime = parseQueryDateTime(endText, true);

    // 如果用户没有在 UI 输入任何日期（两个文本均为空），默认使用当天整天范围
    if (startText.trimmed().isEmpty() && endText.trimmed().isEmpty()) {
        QDate today = QDate::currentDate();
        startTime = QDateTime(today, QTime(0,0,0));
        endTime = QDateTime(today, QTime(23,59,59,999));
    }
    const QString serialToken = serialKeyword.trimmed();
    const int rackNum = rackNumber;
    const QString wheelToken = wheelNo.trimmed();
    const QString resToken = resultFilter.trimmed();
    int parsedResult = 0;
    const bool hasResultFilter = parseResultFilter(resToken, parsedResult);

    // 如果没有内存中批次数据（m_records）或需要直接从数据库查询，则使用 record 表查询
    bool usedDbQuery = false;
    QVector<ImageItem> resultItems;
    int matchedBatchCount = 0;

    QVector<ImageItem> items;
    QSqlDatabase db = QSqlDatabase::database();
    if (db.isValid() && db.isOpen()) {
        QSqlQuery q(db);
        QStringList where;
        QString sql = "SELECT createtime, rackno, wheelno, result, imagename, distance, dist_max, dist_norm FROM record";

        if (startTime.isValid()) {
            where << "createtime >= :start";
        }
        if (endTime.isValid()) {
            where << "createtime <= :end";
        }
        if (!serialToken.isEmpty()) {
            // imagename or other text fields may contain the serial keyword
            where << "imagename LIKE :filename";
        }
        if (rackNum > 0) {
            where << "rackno = :rack";
        }
        if (wheelToken == QStringLiteral("0")) {
            where << "CAST(wheelno AS INTEGER) BETWEEN 1 AND 8";
        } else if (wheelToken == QStringLiteral("10")) {
            where << "CAST(wheelno AS INTEGER) BETWEEN 11 AND 18";
        } else if (wheelToken.contains(',')) {
            QStringList wheelNumbers;
            for (const QString &part : wheelToken.split(',', Qt::SkipEmptyParts)) {
                bool ok = false;
                const int wheel = part.trimmed().toInt(&ok);
                if (ok && ((wheel >= 1 && wheel <= 8) || (wheel >= 11 && wheel <= 18)))
                    wheelNumbers << QString::number(wheel);
            }
            if (!wheelNumbers.isEmpty())
                where << QStringLiteral("CAST(wheelno AS INTEGER) IN (%1)").arg(wheelNumbers.join(','));
        } else if (!wheelToken.isEmpty()) {
            where << "wheelno = :wheel";
        }
        if (hasResultFilter) where << "result = :res";

        if (!where.isEmpty()) sql += " WHERE " + where.join(" AND ");
        sql += " ORDER BY createtime DESC LIMIT 1000";

        if (!q.prepare(sql)) {
            LOG_ERROR("搜索 SQL 预处理失败: {}", q.lastError().text().toStdString());
        } else {
            if (startTime.isValid()) q.bindValue(":start", AgcUtils::formatDateTime(startTime));
            if (endTime.isValid()) q.bindValue(":end", AgcUtils::formatDateTime(endTime));
            if (!serialToken.isEmpty()) q.bindValue(":filename", QString("%1").arg(serialToken.contains('%') ? serialToken : QString("%") + serialToken + QString("%")));
            if (rackNum > 0) q.bindValue(":rack", rackNum);
            if (!wheelToken.isEmpty() && wheelToken != QStringLiteral("0") && wheelToken != QStringLiteral("10")
                && !wheelToken.contains(',')) q.bindValue(":wheel", wheelToken);
            if (hasResultFilter) q.bindValue(":res", parsedResult);

            if (q.exec()) {
                int rowIndex = 0;
                while (q.next()) {
                    ImageItem it;
                    it.receivedAt = QDateTime::fromString(q.value(0).toString(), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
                    if (!it.receivedAt.isValid()) it.receivedAt = QDateTime::fromString(q.value(0).toString(), Qt::ISODate);
                    it.rack = q.value(1).toInt();
                    it.slot = q.value(2).toInt();
                    it.result = q.value(3).toInt();
                    QString rawName = q.value(4).toString().trimmed();
                    it.distance = q.value(5).toInt();
                    it.dist_max = q.value(6).toInt();
                    it.dist_norm = q.value(7).toInt();
                    it.fileName = QFileInfo(rawName).fileName();
                    // Resolve stored relative path to an absolute local file path for preview/use in QML.
                    QString resolvedPath;
                    if (QFile::exists(rawName)) {
                        resolvedPath = QFileInfo(rawName).absoluteFilePath();
                    } else {
                        const QStringList candidates = {
                            QDir(m_archiveDirectory).filePath(rawName),
                            QDir(m_sourceDirectory).filePath(rawName),
                            QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("archive")).filePath(rawName),
                            QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("incoming")).filePath(rawName)
                        };
                        for (const QString &candidate : candidates) {
                            if (QFile::exists(candidate)) {
                                resolvedPath = QFileInfo(candidate).absoluteFilePath();
                                break;
                            }
                        }
                    }

                    if (resolvedPath.isEmpty() || !QFile::exists(resolvedPath)) {
                        LOG_WARN("搜索记录中图片文件缺失: raw={} resolved={}", rawName.toStdString(), resolvedPath.toStdString());
                        continue;
                    }

                    it.filePath = resolvedPath;
                    it.fileUrl = QUrl::fromLocalFile(resolvedPath).toString();
                    items.append(it);
                    ++rowIndex;
                }
            } else {
                LOG_ERROR("搜索查询执行失败: {}", q.lastError().text().toStdString());
            }
        }
    } else {
        LOG_ERROR("搜索查询失败，数据库未处于打开状态");
    }

    // Update model on the object's thread
    QMetaObject::invokeMethod(&m_searchImagesModel, [this, items]() mutable {
        m_searchImagesModel.setItems(items);
        m_searchSummary = QStringLiteral("取得 %1 条记录").arg(items.size());
        emit searchSummaryChanged();
    }, Qt::QueuedConnection);
    return;

}

void AppController::searchPaged(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter, int page, int pageSize)
{
    // Basic validation
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startText, false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endText, true);

    const QString serialToken = serialKeyword.trimmed();
    const int rackNum = rackNumber;
    const QString wheelToken = wheelNo.trimmed();
    const QString resToken = resultFilter.trimmed();
    int parsedResult = 0;
    const bool hasResultFilter = parseResultFilter(resToken, parsedResult);

    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) {
        LOG_ERROR("分页搜索失败，数据库未处于打开状态");
        return;
    }

    QSqlQuery q(db);
    QStringList where;
    if (startTime.isValid()) where << "createtime >= :start";
    if (endTime.isValid()) where << "createtime <= :end";
    if (!serialToken.isEmpty()) where << "imagename LIKE :filename";
    if (rackNum > 0) where << "rackno = :rack";
    if (wheelToken == QStringLiteral("0")) {
        where << "CAST(wheelno AS INTEGER) BETWEEN 1 AND 8";
    } else if (wheelToken == QStringLiteral("10")) {
        where << "CAST(wheelno AS INTEGER) BETWEEN 11 AND 18";
    } else if (wheelToken.contains(',')) {
        QStringList wheelNumbers;
        for (const QString &part : wheelToken.split(',', Qt::SkipEmptyParts)) {
            bool ok = false;
            const int wheel = part.trimmed().toInt(&ok);
            if (ok && ((wheel >= 1 && wheel <= 8) || (wheel >= 11 && wheel <= 18)))
                wheelNumbers << QString::number(wheel);
        }
        if (!wheelNumbers.isEmpty())
            where << QStringLiteral("CAST(wheelno AS INTEGER) IN (%1)").arg(wheelNumbers.join(','));
    } else if (!wheelToken.isEmpty()) {
        where << "wheelno = :wheel";
    }
    if (hasResultFilter) where << "result = :res";

    QString countSql = "SELECT COUNT(*) FROM record";
    if (!where.isEmpty()) countSql += " WHERE " + where.join(" AND ");

    if (!q.prepare(countSql)) {
        LOG_ERROR("分页搜索统计 COUNT SQL 预处理失败: {}", q.lastError().text().toStdString());
        return;
    }

    // bind parameters for count (must bind before exec)
    if (startTime.isValid()) q.bindValue(":start", AgcUtils::formatDateTime(startTime));
    if (endTime.isValid()) q.bindValue(":end", AgcUtils::formatDateTime(endTime));
    if (!serialToken.isEmpty()) q.bindValue(":filename", QString("%1").arg(serialToken.contains('%') ? serialToken : QString("%") + serialToken + QString("%")));
    if (rackNum > 0) q.bindValue(":rack", rackNum);
    if (!wheelToken.isEmpty() && wheelToken != QStringLiteral("0") && wheelToken != QStringLiteral("10")
        && !wheelToken.contains(',')) q.bindValue(":wheel", wheelToken);
    if (hasResultFilter) q.bindValue(":res", parsedResult);

    if (!q.exec()) {
        LOG_ERROR("分页搜索统计记录失败: {}", q.lastError().text().toStdString());
        return;
    }

    int totalCount = 0;
    if (q.next()) totalCount = static_cast<int>(qMin<qint64>(
        q.value(0).toLongLong(), std::numeric_limits<int>::max()));

    LOG_DEBUG("searchPaged: start={} end={} serial={} rack={} wheel={} res={} page={} pageSize={} count={}",
              startText.toStdString(), endText.toStdString(), serialToken.toStdString(),
              rackNum, wheelToken.toStdString(), resToken.toStdString(), page, pageSize, totalCount);

    const qint64 offset = static_cast<qint64>(page - 1) * pageSize;
    QString dataSql = QStringLiteral("SELECT createtime, rackno, wheelno, result, imagename, distance, dist_max, dist_norm FROM record");
    if (!where.isEmpty()) dataSql += " WHERE " + where.join(" AND ");
    dataSql += QStringLiteral(" ORDER BY createtime DESC LIMIT %1 OFFSET %2").arg(pageSize).arg(offset);

    if (!q.prepare(dataSql)) {
        LOG_ERROR("分页搜索数据 SQL 预处理失败: {}", q.lastError().text().toStdString());
        return;
    }

    // bind parameters for data query
    if (startTime.isValid()) q.bindValue(":start", AgcUtils::formatDateTime(startTime));
    if (endTime.isValid()) q.bindValue(":end", AgcUtils::formatDateTime(endTime));
    if (!serialToken.isEmpty()) q.bindValue(":filename", QString("%1").arg(serialToken.contains('%') ? serialToken : QString("%") + serialToken + QString("%")));
    if (rackNum > 0) q.bindValue(":rack", rackNum);
    if (!wheelToken.isEmpty() && wheelToken != QStringLiteral("0") && wheelToken != QStringLiteral("10")
        && !wheelToken.contains(',')) q.bindValue(":wheel", wheelToken);
    if (hasResultFilter) q.bindValue(":res", parsedResult);

    QVector<ImageItem> items;
    if (q.exec()) {
        while (q.next()) {
            ImageItem it;
            it.receivedAt = QDateTime::fromString(q.value(0).toString(), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
            if (!it.receivedAt.isValid()) it.receivedAt = QDateTime::fromString(q.value(0).toString(), Qt::ISODate);
            it.rack = q.value(1).toInt();
            it.slot = q.value(2).toInt();
            it.result = q.value(3).toInt();
            QString rawName = q.value(4).toString().trimmed();
            it.distance = q.value(5).toInt();
            it.dist_max = q.value(6).toInt();
            it.dist_norm = q.value(7).toInt();
            it.fileName = QFileInfo(rawName).fileName();

            QString resolvedPath;
            if (QFile::exists(rawName)) resolvedPath = QFileInfo(rawName).absoluteFilePath();
            else {
                const QStringList candidates = {
                    QDir(m_archiveDirectory).filePath(rawName),
                    QDir(m_sourceDirectory).filePath(rawName),
                    QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("archive")).filePath(rawName),
                    QDir(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("incoming")).filePath(rawName)
                };
                for (const QString &candidate : candidates) {
                    if (QFile::exists(candidate)) { resolvedPath = QFileInfo(candidate).absoluteFilePath(); break; }
                }
            }

            if (resolvedPath.isEmpty() || !QFile::exists(resolvedPath)) {
                LOG_WARN("分页搜索结果中图片文件缺失: raw={} resolved={}", rawName.toStdString(), resolvedPath.toStdString());
                it.filePath = QString();
                it.fileUrl.clear();
            } else {
                it.filePath = resolvedPath;
                it.fileUrl = QUrl::fromLocalFile(resolvedPath).toString();
            }
            items.append(it);
        }
    } else {
        LOG_ERROR("分页搜索数据执行失败: {}", q.lastError().text().toStdString());
    }

    // If COUNT returned 0 but data query returned rows, adjust totalCount to reflect actual rows
    if (totalCount == 0 && !items.isEmpty()) {
        LOG_DEBUG("分页搜索 COUNT 为 0 但获取到 {} 条记录，使用实际获取数", items.size());
        totalCount = items.size();
    }

    // Update model and paging info atomically on the object's thread
    QMetaObject::invokeMethod(this, [this, items, totalCount]() mutable {
        m_searchImagesModel.clear();
        m_searchImagesModel.setItems(items);
        // Log a short summary of returned items for debugging
        QString sample;
        for (int i=0;i<qMin(6, items.size());++i) {
            const ImageItem &it = items.at(i);
            sample += QStringLiteral("[%1]{rack=%2 wheel=%3 name=%4} ").arg(i).arg(it.rack).arg(it.slot).arg(it.fileName);
        }
        LOG_DEBUG("searchPaged 采样: {}", sample.toStdString());
        m_searchSummary = QStringLiteral("取得 %1 条记录").arg(totalCount);
        emit searchSummaryChanged();
        emit searchPagedResult(totalCount);
    }, Qt::QueuedConnection);
}

void AppController::alertSearchPaged(const QString &startText, const QString &endText,
                                     int rackNumber, const QString &wheelNo,
                                     int page, int pageSize)
{
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const QDateTime startDT = AgcUtils::parseFlexibleDateTime(startText.trimmed(), false);
    const QDateTime endDT = AgcUtils::parseFlexibleDateTime(endText.trimmed(), true);
    const QString wheelToken = wheelNo.trimmed();
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return;

    QStringList where;
    if (startDT.isValid()) where << QStringLiteral("createtime >= :start");
    if (endDT.isValid()) where << QStringLiteral("createtime <= :end");
    if (rackNumber > 0) where << QStringLiteral("rackno = :rack");
    if (wheelToken == QStringLiteral("0")) {
        where << QStringLiteral("CAST(wheelno AS INTEGER) BETWEEN 1 AND 8");
    } else if (wheelToken == QStringLiteral("10")) {
        where << QStringLiteral("CAST(wheelno AS INTEGER) BETWEEN 11 AND 18");
    } else if (wheelToken.contains(',')) {
        QStringList wheelNumbers;
        for (const QString &part : wheelToken.split(',', Qt::SkipEmptyParts)) {
            bool ok = false;
            const int wheel = part.trimmed().toInt(&ok);
            if (ok && ((wheel >= 1 && wheel <= 8) || (wheel >= 11 && wheel <= 18)))
                wheelNumbers << QString::number(wheel);
        }
        if (!wheelNumbers.isEmpty())
            where << QStringLiteral("CAST(wheelno AS INTEGER) IN (%1)").arg(wheelNumbers.join(','));
    } else if (!wheelToken.isEmpty()) {
        where << QStringLiteral("wheelno = :wheel");
    }

    const QString filter = where.isEmpty() ? QString() : QStringLiteral(" WHERE ") + where.join(QStringLiteral(" AND "));
    auto bindFilters = [&](QSqlQuery &query) {
        if (startDT.isValid()) query.bindValue(QStringLiteral(":start"), AgcUtils::formatDateTime(startDT));
        if (endDT.isValid()) query.bindValue(QStringLiteral(":end"), AgcUtils::formatDateTime(endDT));
        if (rackNumber > 0) query.bindValue(QStringLiteral(":rack"), rackNumber);
        if (!wheelToken.isEmpty() && wheelToken != QStringLiteral("0") && wheelToken != QStringLiteral("10") && !wheelToken.contains(','))
            query.bindValue(QStringLiteral(":wheel"), wheelToken);
    };

    int totalCount = 0;
    QSqlQuery countQuery(db);
    countQuery.prepare(QStringLiteral("SELECT COUNT(*) FROM alertrecord") + filter);
    bindFilters(countQuery);
    if (countQuery.exec() && countQuery.next()) {
        totalCount = static_cast<int>(qMin<qint64>(
            countQuery.value(0).toLongLong(), std::numeric_limits<int>::max()));
    }

    QVector<ImageItem> items;
    QSqlQuery dataQuery(db);
    dataQuery.prepare(QStringLiteral("SELECT createtime, rackno, wheelno, result, imagename, distance, dist_max, dist_norm FROM alertrecord")
                      + filter + QStringLiteral(" ORDER BY createtime DESC LIMIT %1 OFFSET %2")
                          .arg(pageSize).arg(static_cast<qint64>(page - 1) * pageSize));
    bindFilters(dataQuery);
    if (dataQuery.exec()) {
        while (dataQuery.next()) {
            ImageItem item;
            item.receivedAt = QDateTime::fromString(dataQuery.value(0).toString(), QStringLiteral("yyyy-MM-dd HH:mm:ss"));
            item.rack = dataQuery.value(1).toInt();
            item.slot = dataQuery.value(2).toInt();
            item.result = dataQuery.value(3).toInt();
            const QString imageName = dataQuery.value(4).toString().trimmed();
            item.fileName = QFileInfo(imageName).fileName();
            item.distance = dataQuery.value(5).toInt();
            item.dist_max = dataQuery.value(6).toInt();
            item.dist_norm = dataQuery.value(7).toInt();
            const QString imagePath = QFile::exists(imageName) ? imageName : QDir(m_archiveDirectory).filePath(imageName);
            if (QFile::exists(imagePath)) {
                item.filePath = QFileInfo(imagePath).absoluteFilePath();
                item.fileUrl = QUrl::fromLocalFile(item.filePath).toString();
            }
            items.append(item);
        }
    }
    locker.unlock();

    QMetaObject::invokeMethod(this, [this, items, totalCount]() {
        m_searchImagesModel.setItems(items);
        m_searchSummary = QStringLiteral("取得 %1 条报警记录").arg(totalCount);
        emit searchSummaryChanged();
        emit searchPagedResult(totalCount);
    }, Qt::QueuedConnection);
}

void AppController::loadFtpSettingsFromFile()
{
    const QString path = QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("agc_ftp_config.json");
    QFile f(path);
    if (!f.exists()) return;
    if (!f.open(QIODevice::ReadOnly)) return;
    if (f.size() > 1024 * 1024) return;
    const QByteArray data = f.readAll();
    f.close();

    nlohmann::json obj;
    try {
        obj = nlohmann::json::parse(data.constData(), data.constData() + data.size());
    } catch (...) {
        return;
    }
    if (!obj.is_object()) return;

    if (obj.contains("ftpUsers") && obj["ftpUsers"].is_array()) {
        m_ftpUsers.clear();
        for (const auto &v : obj["ftpUsers"]) {
            if (m_ftpUsers.size() >= 32) break;
            if (!v.is_object()) continue;
            QString u = v.contains("user") && v["user"].is_string() ? QString::fromStdString(v["user"].get<std::string>()) : QString();
            QString p = v.contains("pass") && v["pass"].is_string() ? QString::fromStdString(v["pass"].get<std::string>()) : QString();
            if (!u.isEmpty() && u.size() <= 64 && !p.isEmpty() && p.size() <= 256) {
                if (!p.startsWith(QStringLiteral("sha256$"))) p = encodePassword(p);
                m_ftpUsers.insert(u, p);
            }
        }
    }
    m_ftpAllowAnonymous = false; // 内置服务不允许匿名上传。
    if (obj.contains("ftpRoot") && obj["ftpRoot"].is_string()) {
        m_ftpRoot = AgcUtils::normalizedPath(QString::fromStdString(obj["ftpRoot"].get<std::string>()));
        const QString fsRoot = QDir::cleanPath(QDir(m_ftpRoot).rootPath());
        const QString home = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
        if (m_ftpRoot.isEmpty() || m_ftpRoot == fsRoot || m_ftpRoot == home
            || QFileInfo(m_ftpRoot).isSymbolicLink()) {
            m_ftpRoot.clear();
        }
        // If ftpRoot points to an "incoming" folder, prefer using the corresponding "archive" folder
        QDir ftpDir(m_ftpRoot);
        if (!m_ftpRoot.isEmpty() && ftpDir.dirName().compare(QStringLiteral("incoming"), Qt::CaseInsensitive) == 0) {
            ftpDir.cdUp();
            if (!ftpDir.mkpath(QStringLiteral("archive")) || !ftpDir.cd(QStringLiteral("archive"))) {
                setStatusMessage(QStringLiteral("无法创建兼容归档目录"));
                m_ftpRoot.clear();
                return;
            }
            m_ftpRoot = AgcUtils::normalizedPath(ftpDir.absolutePath());
            LOG_INFO("loadFtpSettingsFromFile: 检测到 incoming 根目录，已自动重定向至 archive: {}", m_ftpRoot.toStdString());
        }
    }
    if (obj.contains("ftpPort") && obj["ftpPort"].is_number()) {
        const int configuredPort = boundedJsonInt(obj["ftpPort"], m_ftpPort, 1, 65535);
        if (configuredPort >= 1 && configuredPort <= 65535) m_ftpPort = configuredPort;
    }
    // load slot mapping
    loadSlotMappingFromJson(obj);
    if (!m_ftpUsers.isEmpty()) m_ftpUser = m_ftpUsers.firstKey();
    // notify QML that ftp account list may have changed
    emit ftpSettingsChanged();
    // diagnostic: log effective value after loading
    LOG_DEBUG("loadFtpSettingsFromFile: 有效端口={}, 用户={}", m_ftpPort, m_ftpUser.toStdString());
    saveFtpSettingsToFile(); // 原子写回，同时完成旧版明文密码迁移。
}

bool AppController::saveFtpSettingsToFile()
{
    const QString path = QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("agc_ftp_config.json");
    nlohmann::json obj;
    nlohmann::json usersArr = nlohmann::json::array();
    for (auto it = m_ftpUsers.constBegin(); it != m_ftpUsers.constEnd(); ++it) {
        nlohmann::json uo;
        uo["user"] = it.key().toStdString();
        uo["pass"] = it.value().toStdString();
        usersArr.push_back(uo);
    }
    obj["ftpUsers"] = usersArr;
    obj["ftpAllowAnonymous"] = m_ftpAllowAnonymous;
    obj["ftpRoot"] = m_ftpRoot.toStdString();
    obj["ftpPort"] = m_ftpPort;
    // save slot mapping
    saveSlotMappingToJson(obj);

    std::string jsonStr = obj.dump(4);
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(jsonStr.data(), jsonStr.size()) != qint64(jsonStr.size()) || !f.commit()) {
        setStatusMessage(QStringLiteral("FTP 配置保存失败: %1").arg(f.errorString()));
        return false;
    }
    LOG_INFO("保存 FTP 配置到 {}, 账户列表: {}", path.toStdString(), m_ftpUsers.keys().join(',').toStdString());
    return true;
}

void AppController::loadSlotMappingFromJson(const nlohmann::json &obj)
{
    if (!obj.contains("slotMapping") || !obj["slotMapping"].is_array()) return;
    const auto &arr = obj["slotMapping"];
    if (arr.size() < 12) return;
    m_slotMapping.resize(12);
    for (size_t i = 0; i < 12 && i < arr.size(); ++i) {
        int v = boundedJsonInt(arr[i], int(i) + 1, 1, 14);
        if (v < 1) v = 1; if (v > 14) v = 14; // allow mapping targets up to 14
        m_slotMapping[i] = v;
    }
}

void AppController::saveSlotMappingToJson(nlohmann::json &obj) const
{
    nlohmann::json arr = nlohmann::json::array();
    for (int i = 0; i < m_slotMapping.size(); ++i) arr.push_back(m_slotMapping.at(i));
    obj["slotMapping"] = arr;
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
    QVariantList distances;
    for (int wheel = 0; wheel < 8; ++wheel) {
        distances.append(QStringLiteral("0"));
    }

    if (rackNumber < 1 || rackNumber > 50) {
        return distances;
    }

    const QString path = QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("data/agcRackWheelNorm.json"));
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return distances;
    }
    if (file.size() > 5 * 1024 * 1024) return distances;

    const QByteArray jsonData = file.readAll();
    file.close();

    nlohmann::json document;
    try {
        document = nlohmann::json::parse(jsonData.constData(), jsonData.constData() + jsonData.size());
    } catch (...) {
        return distances;
    }
    if (!document.is_array()) {
        return distances;
    }

    for (const auto &rack : document) {
        if (!rack.is_object()) continue;
        int rno = 0;
        if (rack.contains("rackno")) {
            if (rack["rackno"].is_number()) rno = boundedJsonInt(rack["rackno"], 0, 1, 50);
            else if (rack["rackno"].is_string()) rno = QString::fromStdString(rack["rackno"].get<std::string>()).toInt();
        }
        if (rno != rackNumber) continue;

        if (rack.contains("wheels") && rack["wheels"].is_array()) {
            for (const auto &wheel : rack["wheels"]) {
                if (!wheel.is_object()) continue;
                int wno = 0;
                if (wheel.contains("wheelno")) {
                    if (wheel["wheelno"].is_number()) wno = boundedJsonInt(wheel["wheelno"], 0, 1, 8);
                    else if (wheel["wheelno"].is_string()) wno = QString::fromStdString(wheel["wheelno"].get<std::string>()).toInt();
                }
                if (wno >= 1 && wno <= 8) {
                    QString dist = QStringLiteral("0");
                    if (wheel.contains("distance")) {
                        if (wheel["distance"].is_string()) dist = QString::fromStdString(wheel["distance"].get<std::string>());
                        else if (wheel["distance"].is_number()) dist = QString::number(wheel["distance"].get<double>());
                    }
                    distances[wno - 1] = dist;
                }
            }
        }
        break;
    }

    return distances;
}

bool AppController::saveRackWheelDistances(int rackNumber, const QVariantList &distances)
{
    if (rackNumber < 1 || rackNumber > 50 || distances.size() != 8) {
        return false;
    }

    for (const auto &distance : distances) {
        bool ok = false;
        const int value = distance.toString().toInt(&ok);
        if (!ok || value < 0) return false;
    }

    const QString path = QDir(QCoreApplication::applicationDirPath())
        .filePath(QStringLiteral("data/agcRackWheelNorm.json"));
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }
    if (file.size() > 5 * 1024 * 1024) return false;

    const QByteArray jsonData = file.readAll();
    file.close();

    nlohmann::json document;
    try {
        document = nlohmann::json::parse(jsonData.constData(), jsonData.constData() + jsonData.size());
    } catch (...) {
        return false;
    }
    if (!document.is_array()) {
        return false;
    }

    bool rackFound = false;
    for (auto &rack : document) {
        if (!rack.is_object()) continue;
        int rno = 0;
        if (rack.contains("rackno")) {
            if (rack["rackno"].is_number()) rno = boundedJsonInt(rack["rackno"], 0, 1, 50);
            else if (rack["rackno"].is_string()) rno = QString::fromStdString(rack["rackno"].get<std::string>()).toInt();
        }
        if (rno != rackNumber) continue;

        nlohmann::json wheels = nlohmann::json::array();
        for (int wheel = 0; wheel < 8; ++wheel) {
            wheels.push_back({
                {"wheelno", std::to_string(wheel + 1)},
                {"distance", distances.at(wheel).toString().toStdString()}
            });
        }
        rack["wheels"] = wheels;
        rackFound = true;
        break;
    }

    if (!rackFound) {
        return false;
    }

    QSaveFile output(path);
    if (!output.open(QIODevice::WriteOnly)) {
        return false;
    }
    std::string jsonStr = document.dump(4);
    if (output.write(jsonStr.data(), jsonStr.size()) != qint64(jsonStr.size())) return false;
    bool committed = output.commit();
    if (committed) {
        LOG_INFO("保存架轮标准距离成功: 架号={}", rackNumber);
    }
    return committed;
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
        for (const QVariant &v : arr) wheelList << QString::number(v.toInt());
    }

    // default counts map
    QMap<int,QPair<int,int>> counts; // wheel -> (ok,ng)
    int outputRangeStart = 1;
    int outputRangeEnd = 8;
    // If user provided explicit wheel list, try to adapt output range (support 11..18)
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
        QString sql = QStringLiteral("SELECT wheelno, result, COUNT(*) as c FROM record");
        QStringList where;
        if (startTime.isValid()) where << "createtime >= :start";
        if (endTime.isValid()) where << "createtime <= :end";
        if (filterByRack) where << "rackno = :rack";
        if (!wheelList.isEmpty()) where << QStringLiteral("wheelno IN (%1)").arg(wheelList.join(","));
        if (!where.isEmpty()) sql += " WHERE " + where.join(" AND ");
        sql += " GROUP BY wheelno, result";

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
    nlohmann::json outArr = nlohmann::json::array();
    for (int i = outputRangeStart; i <= outputRangeEnd; ++i) {
        QVariantMap mapItem;
        mapItem.insert(QStringLiteral("wheel"), i);
        mapItem.insert(QStringLiteral("ok"), counts[i].first);
        mapItem.insert(QStringLiteral("ng"), counts[i].second);
        out.append(mapItem);

        nlohmann::json j;
        j["wheel"] = i;
        j["ok"] = counts[i].first;
        j["ng"] = counts[i].second;
        outArr.push_back(j);
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
    if (m_ftpServer.isRunning()) return;
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
    if (m_ftpServer.listen(QHostAddress::Any, static_cast<quint16>(m_ftpPort), m_ftpRoot, m_ftpUsers, m_ftpAllowAnonymous)) {
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
    emit serverRunningChanged();
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

void AppController::stopFtpServer()
{
    m_ftpServer.stop();
    setStatusMessage(QStringLiteral("FTP 服务器已停止"));
    LOG_INFO("FTP 服务器已停止运行");
    emit serverRunningChanged();
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
    return m_ftpServer.isRunning();
}

int AppController::ftpClientCount() const
{
    return m_ftpServer.clientCount();
}

void AppController::setFtpUser(const QString &user)
{
    // update the single-legency displayed ftpUser and also update users map
    if (m_ftpUsers.contains(user) && m_ftpUsers.value(user) == m_ftpPass) return;
    // if user exists keep its password, otherwise create default pass
    if (user.trimmed().isEmpty() || user.size() > 64 || !m_ftpUsers.contains(user)) return;
    m_ftpUser = user;
    emit ftpSettingsChanged();
    m_ftpServer.setUsers(m_ftpUsers, m_ftpAllowAnonymous);
    saveFtpSettingsToFile();
}

void AppController::setFtpPass(const QString &pass)
{
    if (m_ftpUser.isEmpty() || pass.isEmpty() || pass.size() > 256) return;
    const auto previous = m_ftpUsers;
    m_ftpUsers.insert(m_ftpUser, encodePassword(pass));
    if (!saveFtpSettingsToFile()) { m_ftpUsers = previous; return; }
    m_ftpPass.clear();
    emit ftpSettingsChanged();
    m_ftpServer.setUsers(m_ftpUsers, m_ftpAllowAnonymous);
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
    const bool running = m_ftpServer.isRunning();
    if (running) m_ftpServer.stop();
    m_ftpRoot = normalized; m_ftpPort = port;
    bool success = !running || m_ftpServer.listen(QHostAddress::Any, quint16(port), normalized, m_ftpUsers, m_ftpAllowAnonymous);
    if (success) success = saveFtpSettingsToFile();
    if (!success) {
        if (m_ftpServer.isRunning()) m_ftpServer.stop();
        m_ftpRoot = previousRoot; m_ftpPort = previousPort;
        const bool restored = !running || m_ftpServer.listen(QHostAddress::Any, quint16(previousPort), previousRoot, m_ftpUsers, m_ftpAllowAnonymous);
        setStatusMessage(restored ? QStringLiteral("FTP 设置未生效，已恢复原配置") : QStringLiteral("FTP 设置失败，原服务也无法恢复，请检查端口"));
        return false;
    }
    m_pendingScan.reset();
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
    m_ftpUsers.insert(cleanUser, encodePassword(pass));
    if (!saveFtpSettingsToFile()) { m_ftpUsers = previous; return; }
    if (m_ftpUser.isEmpty()) m_ftpUser = cleanUser;
    emit ftpSettingsChanged();
    m_ftpServer.setUsers(m_ftpUsers, m_ftpAllowAnonymous);
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
    m_ftpServer.setUsers(m_ftpUsers, m_ftpAllowAnonymous);
    LOG_INFO("移除 FTP 账户成功: {}", user.toStdString());
}

void AppController::ensureDirectories()
{
    // 保证配置的源目录与归档目录存在
    if (!m_sourceDirectory.isEmpty()) {
        if (QDir().mkpath(m_sourceDirectory)) {
            LOG_DEBUG("创建/确认源目录成功: {}", m_sourceDirectory.toStdString());
        }
    }

    if (!m_archiveDirectory.isEmpty()) {
        if (QDir().mkpath(m_archiveDirectory)) {
            LOG_DEBUG("创建/确认归档目录成功: {}", m_archiveDirectory.toStdString());
            const QString markerPath = QDir(m_archiveDirectory).filePath(QStringLiteral(".carriervision-archive"));
            QFile marker(markerPath);
            if (!marker.exists() && marker.open(QIODevice::WriteOnly)) {
                marker.write("CarrierVision managed archive\n");
            }
        }
    }

    // 额外确保运行目录下的 incoming 和 archive 也存在（兼容用户直接查看工作目录）
    const QString appIncoming = QDir::cleanPath(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("incoming"));
    const QString appArchive = QDir::cleanPath(QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("archive"));
    if (QDir().mkpath(appIncoming)) {
        LOG_DEBUG("创建/确认应用 incoming 目录成功: {}", appIncoming.toStdString());
    }
    if (QDir().mkpath(appArchive)) {
        LOG_DEBUG("创建/确认应用 archive 目录成功: {}", appArchive.toStdString());
        QFile marker(QDir(appArchive).filePath(QStringLiteral(".carriervision-archive")));
        if (!marker.exists() && marker.open(QIODevice::WriteOnly)) {
            marker.write("CarrierVision managed archive\n");
        }
    }
}

void AppController::loadArchiveIndex()
{
    m_records.clear();

    QFile inputFile(archiveIndexPath());
    if (!inputFile.exists()) {
        return;
    }

    if (!inputFile.open(QIODevice::ReadOnly)) {
        setStatusMessage(QStringLiteral("无法读取索引文件: %1").arg(inputFile.errorString()));
        return;
    }
    if (inputFile.size() > 50 * 1024 * 1024) {
        setStatusMessage(QStringLiteral("索引文件超过 50 MiB，已拒绝加载"));
        return;
    }

    const QByteArray data = inputFile.readAll();
    inputFile.close();

    nlohmann::json document;
    try {
        document = nlohmann::json::parse(data.constData(), data.constData() + data.size());
    } catch (...) {
        return;
    }

    nlohmann::json batchArray = nlohmann::json::array();
    if (document.is_array()) {
        batchArray = document;
    } else if (document.is_object() && document.contains("batches") && document["batches"].is_array()) {
        batchArray = document["batches"];
    }

    for (const auto &value : batchArray) {
        if (!value.is_object()) {
            continue;
        }

        const BatchRecord record = batchFromJson(value);
        if (!record.batchId.isEmpty()) {
            m_records.append(record);
        }
    }

    std::sort(m_records.begin(), m_records.end(), [](const BatchRecord &left, const BatchRecord &right) {
        return left.receivedAt > right.receivedAt;
    });
}

void AppController::saveArchiveIndex() const
{
    nlohmann::json batchArray = nlohmann::json::array();
    for (const BatchRecord &record : m_records) {
        batchArray.push_back(batchToJson(record));
    }

    nlohmann::json root;
    root["version"] = 1;
    root["batches"] = batchArray;

    QSaveFile outputFile(archiveIndexPath());
    if (!outputFile.open(QIODevice::WriteOnly)) {
        return;
    }

    std::string jsonStr = root.dump(4);
    outputFile.write(jsonStr.data(), jsonStr.size());
    outputFile.commit();
}

void AppController::rowSelected(int index)
{
    // Bound check; kept minimal without noisy debug logging
    if (index < 0) return;
    Q_UNUSED(index);
}

QString AppController::archiveIndexPath() const
{
    return QDir(m_archiveDirectory).filePath(QStringLiteral("agc_batches.json"));
}

QVector<ImageItem> AppController::buildImageItems(const BatchRecord &record) const
{
    QVector<ImageItem> items;
    items.reserve(record.imageFiles.size());

    // 构建固定 12 个槽位的列表，槽号 1..12，未匹配的槽 filePath 为空
    items.resize(12);
    for (int i = 0; i < 12; ++i) {
        ImageItem placeholder;
        placeholder.batchId = record.batchId;
        placeholder.roundNumber = record.roundNumber;
        placeholder.slot = i + 1;
        placeholder.serial.clear();
        placeholder.fileName.clear();
        placeholder.filePath.clear();
        placeholder.receivedAt = record.receivedAt;
        items[i] = placeholder;
    }

    const QRegularExpression grpRx(QStringLiteral("GRP(\\d{1,2})"), QRegularExpression::CaseInsensitiveOption);
    const QRegularExpression digitsRx(QStringLiteral("(\\d{1,2})"));

    for (int index = 0; index < record.imageFiles.size(); ++index) {
        const QString &filePath = record.imageFiles.at(index);
        if (filePath.trimmed().isEmpty() || !QFile::exists(filePath)) {
            continue;
        }
        int slot = -1;
        const QString parentDirName = QDir(QFileInfo(filePath).absolutePath()).dirName();
        QRegularExpressionMatch m = grpRx.match(parentDirName);
        if (m.hasMatch()) {
            slot = m.captured(1).toInt();
        } else {
            QRegularExpressionMatch m2 = digitsRx.match(parentDirName);
            if (m2.hasMatch()) slot = m2.captured(1).toInt();
        }

        if (slot >= 1 && slot <= 12) {
            ImageItem item;
            item.batchId = record.batchId;
            item.roundNumber = record.roundNumber;
            item.slot = slot;
            item.filePath = filePath;
            item.fileName = QFileInfo(filePath).fileName();
            item.serial = index < record.serials.size() ? record.serials.at(index) : QFileInfo(filePath).completeBaseName();
            item.receivedAt = record.receivedAt;
            items[slot - 1] = item; // 覆盖对应槽位
        }
    }

    return items;
}

void AppController::upsertRecord(const BatchRecord &record)
{
    for (BatchRecord &existingRecord : m_records) {
        if (existingRecord.batchId == record.batchId) {
            existingRecord = record;
            std::sort(m_records.begin(), m_records.end(), [](const BatchRecord &left, const BatchRecord &right) {
                return left.receivedAt > right.receivedAt;
            });
            return;
        }
    }

    m_records.append(record);
    std::sort(m_records.begin(), m_records.end(), [](const BatchRecord &left, const BatchRecord &right) {
        return left.receivedAt > right.receivedAt;
    });
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
    // 默认源目录固定为归档目录（避免显示运行目录下的 incoming）
    const QString defaultSource = QDir::cleanPath(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("archive")));
    const QString defaultArchive = QDir::cleanPath(QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("archive")));
    const QString envSource = qEnvironmentVariable("AGCFTP_SOURCE_DIR").trimmed();
    const QString envArchive = qEnvironmentVariable("AGCFTP_ARCHIVE_DIR").trimmed();

    m_sourceDirectory = AgcUtils::normalizedPath(envSource.isEmpty() ? defaultSource : envSource);
    m_archiveDirectory = AgcUtils::normalizedPath(envArchive.isEmpty() ? defaultArchive : envArchive);
    {
        QSettings settings(QCoreApplication::applicationDirPath() + QDir::separator() + "config.ini",
                           QSettings::IniFormat);
        m_listenPort = settings.value("network/tcpPort", kListenPort).toInt();
        if (m_listenPort < 1024 || m_listenPort > 65535) {
            m_listenPort = kListenPort;
        }
        QString stored = settings.value("security/settingsPassword").toString();
        if (stored.isEmpty()) stored = QStringLiteral("123456");
        if (!stored.startsWith(QStringLiteral("sha256$"))) {
            settings.setValue("security/settingsPassword", encodePassword(stored));
            settings.sync();
        }
    }
    // Load persisted FTP-related settings (includes slot mapping)
    loadFtpSettingsFromFile();
    // ensure ftp server has the current users before start
    m_ftpServer.setUsers(m_ftpUsers, m_ftpAllowAnonymous);
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

void AppController::startTcpServer()
{
    if (m_tcpServer.isRunning()) return;
    if (m_tcpServer.start(static_cast<quint16>(m_listenPort))) {
        m_serverRunning = true;
        emit serverRunningChanged();
        LOG_INFO("已启动 TCP 点检监听服务: 端口={}", m_listenPort);
        setStatusMessage(QStringLiteral("TCP 监听服务已启动 (端口 %1)").arg(m_listenPort));
    } else {
        LOG_WARN("启动 TCP 点检服务失败: 端口={}", m_listenPort);
        setStatusMessage(QStringLiteral("启动 TCP 监听服务失败 (端口 %1)").arg(m_listenPort));
    }
}

void AppController::stopTcpServer()
{
    if (!m_tcpServer.isRunning()) return;
    m_tcpServer.stop();
    m_serverRunning = false;
    emit serverRunningChanged();
    LOG_INFO("已停止 TCP 点检监听服务");
    setStatusMessage(QStringLiteral("TCP 监听服务已停止"));
}

void AppController::setListenPort(int port)
{
    if (port < 1024 || port > 65535) { setStatusMessage(QStringLiteral("TCP 端口范围必须为 1024..65535")); return; }
    if (m_listenPort == port) return;
    const int previous = m_listenPort;
    const bool running = m_tcpServer.isRunning();
    if (running && !m_tcpServer.start(quint16(port))) {
        const bool restored = m_tcpServer.start(quint16(previous));
        setStatusMessage(restored ? QStringLiteral("新端口不可用，已恢复原 TCP 服务") : QStringLiteral("新旧 TCP 端口均无法监听"));
        return;
    }
    QSettings settings(QCoreApplication::applicationDirPath() + "/config.ini", QSettings::IniFormat);
    settings.setValue("network/tcpPort", port);
    settings.sync();
    if (settings.status() != QSettings::NoError) {
        settings.setValue("network/tcpPort", previous);
        settings.sync();
        if (running) m_tcpServer.start(quint16(previous));
        setStatusMessage(QStringLiteral("TCP 配置保存失败，已恢复原端口"));
        return;
    }
    m_listenPort = port;
    emit listenPortChanged();
}

void AppController::resetSlotMapping()
{
    const auto previous = m_slotMapping;
    m_slotMapping.resize(12);
    for (int i = 0; i < 12; ++i) {
        m_slotMapping[i] = i + 1;
    }
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


