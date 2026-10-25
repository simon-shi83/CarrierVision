#include "app/AppController.h"
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

// 旧版本在程序目录单独写 ftp.log / ftp.log.1；现已并入主日志。
// 启动时把残留文件移入 logs/（不删除内容），之后随日志保留天数清理
const QString kLegacyFtpLogPrefix = QStringLiteral("ftp_legacy_");

void migrateLegacyFtpLogs()
{
    const QDir appDir(QCoreApplication::applicationDirPath());
    const QDir logDir(AppLogger::getLogDirectory());
    for (const QString &name : {QStringLiteral("ftp.log"), QStringLiteral("ftp.log.1")}) {
        const QFileInfo legacy(appDir.filePath(name));
        if (!legacy.isFile()) continue;
        const QString suffix = name.endsWith(QLatin1String(".1")) ? QStringLiteral(".1.log") : QStringLiteral(".log");
        const QString target = logDir.filePath(kLegacyFtpLogPrefix
                                               + legacy.lastModified().toString(QStringLiteral("yyyyMMdd_HHmmss")) + suffix);
        if (QFile::exists(target) || !QFile::rename(legacy.absoluteFilePath(), target)) {
            LOG_WARN("旧 FTP 日志移入日志目录失败，保留原文件: {} -> {}", legacy.absoluteFilePath().toStdString(), target.toStdString());
            continue;
        }
        LOG_INFO("FTP 日志已并入主日志，旧文件已移入日志目录: {} -> {}", legacy.absoluteFilePath().toStdString(), target.toStdString());
    }
}

void removeExpiredLegacyFtpLogs(int keepDays)
{
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-keepDays);
    const QDir logDir(AppLogger::getLogDirectory());
    for (const QFileInfo &file : logDir.entryInfoList({kLegacyFtpLogPrefix + QStringLiteral("*.log")}, QDir::Files)) {
        if (file.lastModified() < cutoff && QFile::remove(file.absoluteFilePath()))
            LOG_INFO("已自动删除超期的旧 FTP 日志: {}", file.absoluteFilePath().toStdString());
    }
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
    return QFileInfo(QDir(clean).filePath(QStringLiteral(".carriervision-images"))).isFile()
        || QFileInfo(QDir(clean).filePath(QStringLiteral(".carriervision-archive"))).isFile();
}

} // namespace

using SearchService::RecordFilter;
using SearchService::buildRecordFilter;
using SearchService::parseResultFilter;
using SearchService::queryRecordPage;
using SearchService::resolveImagePath;
using SearchService::resolveRecordImage;

namespace {

struct MaintenanceRequest {
    QString archiveRoot;
    QStringList managedRoots;
    QStringList storagePaths;
    int keepDays = 90;
    int logKeepDays = 30;
    bool emergency = false;
    int recoverPercent = 10;
};

struct MaintenanceResult {
    bool ok = true;
    QString error;
    int records = 0;
    int files = 0;
    int orphans = 0;
    int skippedUnsafe = 0;
    int effectiveKeepDays = 0;
    double freePercent = 100.0;
};

constexpr int kMinKeepDaysInEmergency = 7;  // 决策 D3：紧急清理最少保留最近 7 天
constexpr int kOrphanGraceDays = 7;          // 决策 D3：孤儿图片超过保留期 7 天后删除
constexpr int kMaxBatchesPerRun = 200;       // 单次运行最多 200 批（约 10 万组），其余留到下次

// 在维护线程执行：按批清理到没有更多过期数据为止，再清理孤儿图片与旧日志。
// 紧急模式下从保留天数开始逐步缩短，直到剩余空间恢复到 recoverPercent 或只剩最近 7 天。
MaintenanceResult runMaintenance(const MaintenanceRequest &request)
{
    MaintenanceResult result;
    QSqlDatabase db = getThreadDatabase();
    auto cleanTo = [&](int keepDays) {
        const QDateTime cutoff = QDateTime::currentDateTime().addDays(-keepDays);
        for (int batch = 0; batch < kMaxBatchesPerRun; ++batch) {
            int removed = 0;
            bool more = false;
            ArchiveMaintenance::CleanupStats stats;
            if (!ArchiveMaintenance::cleanup(db, request.archiveRoot, request.managedRoots, cutoff,
                                             removed, more, result.error, &stats)) {
                result.ok = false;
                return;
            }
            result.records += stats.recordsDeleted;
            result.files += stats.filesDeleted;
            result.skippedUnsafe += stats.skippedUnsafe;
            if (!more) break;
        }
        QString orphanError;
        result.orphans += ArchiveMaintenance::sweepOrphans(db, request.managedRoots,
            QDateTime::currentDateTime().addDays(-(request.emergency ? keepDays : keepDays + kOrphanGraceDays)),
            5000, orphanError);
        if (!orphanError.isEmpty()) LOG_WARN("[CLEANUP] 孤儿图片清理中断: {}", orphanError.toStdString());
    };

    int keepDays = request.keepDays;
    cleanTo(keepDays);
    result.freePercent = StorageMonitor::lowest(request.storagePaths).freePercent;
    while (request.emergency && result.ok && result.freePercent < request.recoverPercent
           && keepDays > kMinKeepDaysInEmergency) {
        keepDays = qMax(kMinKeepDaysInEmergency, keepDays - qMax(1, (keepDays - kMinKeepDaysInEmergency) / 4));
        LOG_WARN("[CLEANUP] 紧急清理：剩余空间 {:.1f}% 低于 {}%，临时缩短保留期至 {} 天",
                 result.freePercent, request.recoverPercent, keepDays);
        cleanTo(keepDays);
        result.freePercent = StorageMonitor::lowest(request.storagePaths).freePercent;
    }
    result.effectiveKeepDays = keepDays;
    if (result.ok) AppLogger::cleanupLogsOlderThanDays(request.logKeepDays);
    return result;
}

} // namespace

void AppController::triggerCleanup()
{
    startMaintenance(false);
}

void AppController::startMaintenance(bool emergency)
{
    if (m_cleanupRunning) {
        LOG_INFO("历史数据清理任务正在执行，忽略重复触发");
        return;
    }
    MaintenanceRequest request;
    request.emergency = emergency;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        request.keepDays = qBound(1, DBSchema::getConfigInt(db, "cleanup/keepDays", 90), 3650);
        request.logKeepDays = qBound(1, DBSchema::getConfigInt(db, "cleanup/logKeepDays", 30), 3650);
        request.recoverPercent = qBound(1, DBSchema::getConfigInt(db, "storage/warnPercent", 10), 90);
    }

    LOG_INFO("执行{}历史数据清理任务: 图像保留天数={} 天, 日志保留天数={} 天",
             emergency ? "紧急" : "", request.keepDays, request.logKeepDays);

    request.archiveRoot = m_archiveDirectory.isEmpty()
        ? (QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("images"))
        : m_archiveDirectory;
    if (!isSafeArchiveRoot(request.archiveRoot)) {
        setStatusMessage(QStringLiteral("已拒绝清理未标记或危险的图像目录: %1").arg(request.archiveRoot));
        return;
    }

    // Restore legacy directory staging conservatively; never recursively delete it.
    QDir archive(request.archiveRoot);
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
    request.managedRoots = {request.archiveRoot};
    request.storagePaths = storagePaths();

    // 数据库与文件删除在维护线程用独立连接执行，避免阻塞界面与上传处理
    m_cleanupRunning = true;
    (void)QtConcurrent::run(&m_maintenancePool, [this, request]() {
        const MaintenanceResult result = runMaintenance(request);
        QMetaObject::invokeMethod(this, [this, request, result]() {
            m_cleanupRunning = false;
            if (!result.ok) {
                setStatusMessage(QStringLiteral("清理未完成: %1").arg(result.error));
                return;
            }
            removeExpiredLegacyFtpLogs(request.logKeepDays);
            LOG_INFO("{}清理完成: 删除记录 {} 条, 图片 {} 张, 孤儿图片 {} 张, 路径异常仅删记录 {} 组, 剩余空间 {:.1f}%",
                     request.emergency ? "紧急" : "", result.records, result.files, result.orphans,
                     result.skippedUnsafe, result.freePercent);
            if (result.skippedUnsafe > 0)
                LOG_WARN("清理发现 {} 组图片路径不在图像目录内（已删除记录、保留文件），请检查客户端 imageName", result.skippedUnsafe);
            if (request.emergency && result.effectiveKeepDays < request.keepDays)
                LOG_WARN("紧急清理已临时将保留期缩短至 {} 天以释放空间", result.effectiveKeepDays);
            setStatusMessage(QStringLiteral("%1清理完成：记录 %2 条、图片 %3 张、孤儿图片 %4 张")
                                 .arg(request.emergency ? QStringLiteral("紧急") : QString())
                                 .arg(result.records).arg(result.files).arg(result.orphans));
            checkStorage();
        }, Qt::QueuedConnection);
    });
}

QStringList AppController::storagePaths() const
{
    return {m_archiveDirectory, QFileInfo(DBSchema::defaultDatabasePath()).absolutePath(),
            AppLogger::getLogDirectory()};
}

void AppController::checkStorage()
{
    int warn = 10, rejectUploads = 5, rejectData = 2;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        warn = qBound(1, DBSchema::getConfigInt(db, "storage/warnPercent", 10), 90);
        rejectUploads = qBound(1, DBSchema::getConfigInt(db, "storage/rejectUploadsPercent", 5), warn);
        rejectData = qBound(1, DBSchema::getConfigInt(db, "storage/rejectDataPercent", 2), rejectUploads);
    }
    const StorageMonitor::Usage usage = StorageMonitor::lowest(storagePaths());
    if (!usage.valid) return;
    const StorageMonitor::Level level = StorageMonitor::levelFor(usage.freePercent, warn, rejectUploads, rejectData);
    const bool changed = level != m_storageLevel;
    m_storageLevel = level;
    m_storageStatus = QVariantMap{
        {QStringLiteral("level"), StorageMonitor::levelName(level)},
        {QStringLiteral("path"), usage.path},
        {QStringLiteral("freeBytes"), usage.freeBytes},
        {QStringLiteral("totalBytes"), usage.totalBytes},
        {QStringLiteral("freePercent"), usage.freePercent},
    };
    emit storageStatusChanged();
    m_ftpService->setAcceptUploads(level < StorageMonitor::Level::RejectUploads);

    if (changed) {
        const QString text = QStringLiteral("%1 所在分区剩余 %2%（%3 GB）")
                                 .arg(usage.path).arg(usage.freePercent, 0, 'f', 1)
                                 .arg(usage.freeBytes / 1024.0 / 1024.0 / 1024.0, 0, 'f', 1);
        switch (level) {
        case StorageMonitor::Level::Ok:
            LOG_INFO("存储空间恢复正常: {}", text.toStdString());
            break;
        case StorageMonitor::Level::Warn:
            LOG_WARN("存储空间不足 {}%: {}", warn, text.toStdString());
            break;
        case StorageMonitor::Level::RejectUploads:
            LOG_ERROR("存储空间低于 {}%，已暂停接收 FTP 上传: {}", rejectUploads, text.toStdString());
            break;
        case StorageMonitor::Level::RejectData:
            LOG_ERROR("存储空间低于 {}%，已暂停 FTP 上传与 TCP 入库: {}", rejectData, text.toStdString());
            break;
        }
        if (level != StorageMonitor::Level::Ok)
            setStatusMessage(QStringLiteral("存储空间不足：%1").arg(text));
    }
    // 空间无法恢复时（如被其他程序占满）不必每分钟重跑，至少间隔 10 分钟，等级恶化时立即执行
    const bool worsened = changed && level >= StorageMonitor::Level::RejectUploads;
    if (level >= StorageMonitor::Level::RejectUploads && !m_cleanupRunning
        && (worsened || !m_lastEmergencyCleanup.isValid()
            || m_lastEmergencyCleanup.secsTo(QDateTime::currentDateTime()) >= 600)) {
        m_lastEmergencyCleanup = QDateTime::currentDateTime();
        startMaintenance(true);
    }
}

QVariantMap AppController::storageStatus() const
{
    return m_storageStatus;
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
    LOG_DEBUG("设置清理执行时间点: 每天 {} 时", hour);
}

// 每分钟检查一次定时任务：与 system_config 中记录的上次执行日期比较，
// 不受系统改时间、休眠唤醒影响，程序关闭期间错过的任务会在启动后补跑
void AppController::runScheduledTasks()
{
    const QDateTime now = QDateTime::currentDateTime();
    const QString today = now.date().toString(Qt::ISODate);
    const QDate thisMonday = now.date().addDays(1 - now.date().dayOfWeek());
    const QString lastWeek = thisMonday.addDays(-7).toString(Qt::ISODate);
    int runHour = 1;
    QString lastCleanup;
    QString lastReport;
    QString lastBackup;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        runHour = qBound(0, DBSchema::getConfigInt(db, "cleanup/runHour", 1), 23);
        lastCleanup = DBSchema::getConfig(db, "cleanup/lastRunDate");
        lastReport = DBSchema::getConfig(db, "report/lastWeek");
        lastBackup = DBSchema::getConfig(db, "db/lastBackupDate");
    }

    if (now.time().hour() >= runHour && lastCleanup != today && !m_cleanupRunning) {
        {
            QMutexLocker locker(&m_dbMutex);
            QSqlDatabase db = QSqlDatabase::database();
            DBSchema::setConfig(db, "cleanup/lastRunDate", today);
        }
        triggerCleanup();
    }

    // 数据库每日完整性检查与备份：与清理同一时段，在维护线程串行执行
    if (now.time().hour() >= runHour && lastBackup != today && !m_backupRunning) {
        m_backupRunning = true;
        const QString dbPath = DBSchema::defaultDatabasePath();
        const QString backupDir = QFileInfo(dbPath).absolutePath() + QStringLiteral("/backup");
        const bool lowDisk = m_storageLevel >= StorageMonitor::Level::Warn;
        (void)QtConcurrent::run(&m_maintenancePool, [this, dbPath, backupDir, lowDisk, today]() {
            QSqlDatabase db = getThreadDatabase();
            QString detail;
            const bool healthy = DatabaseGuard::quickCheck(db, detail);
            QString backupError, backupPath;
            const bool backedUp = healthy && !lowDisk && DatabaseGuard::backup(db, backupDir, 3, backupError, &backupPath);
            QMetaObject::invokeMethod(this, [=]() {
                m_backupRunning = false;
                if (!healthy) {
                    // 运行中无法替换数据库：标记后由下次启动自动检查并从备份恢复
                    QFile marker(DatabaseGuard::corruptMarkerPath(dbPath));
                    if (marker.open(QIODevice::WriteOnly)) marker.write(detail.toUtf8());
                    LOG_CRITICAL("[DB] 数据库完整性检查失败: {}；请尽快重启程序，启动时将自动从备份恢复", detail.toStdString());
                    setStatusMessage(QStringLiteral("数据库完整性检查失败，请尽快重启程序以自动恢复"));
                    return;
                }
                if (lowDisk) LOG_WARN("[DB] 存储空间不足，跳过今日数据库备份");
                else if (!backedUp) { LOG_ERROR("[DB] 数据库备份失败: {}", backupError.toStdString()); return; }
                else LOG_INFO("[DB] 数据库检查通过，已备份到 {}", backupPath.toStdString());
                QMutexLocker locker(&m_dbMutex);
                QSqlDatabase mainDb = QSqlDatabase::database();
                DBSchema::setConfig(mainDb, "db/lastBackupDate", today);
            }, Qt::QueuedConnection);
        });
    }

    // 周报：上周的报表在本周一 00:10 之后生成一次；与清理共用维护线程，串行执行
    if (lastReport != lastWeek && now >= QDateTime(thisMonday, QTime(0, 10)) && !m_reportRunning) {
        m_reportRunning = true;
        const QDate monday = thisMonday.addDays(-7);
        (void)QtConcurrent::run(&m_maintenancePool, [this, monday, lastWeek]() {
            const bool ok = WeeklyReport::generateForWeek(getThreadDatabase(), monday);
            QMetaObject::invokeMethod(this, [this, ok, lastWeek]() {
                m_reportRunning = false;
                if (!ok) return; // 失败时下一分钟重试
                QMutexLocker locker(&m_dbMutex);
                QSqlDatabase db = QSqlDatabase::database();
                DBSchema::setConfig(db, "report/lastWeek", lastWeek);
            }, Qt::QueuedConnection);
        });
    }
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
    return StatsService::wheelGroupRackStats(QSqlDatabase::database(), startDate, endDate, 9, 16);
}

QVariantList AppController::walkingWheelRackStats(const QString &startDate, const QString &endDate)
{
    QMutexLocker locker(&m_dbMutex);
    return StatsService::wheelGroupRackStats(QSqlDatabase::database(), startDate, endDate, 1, 8);
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

int AppController::requestAlertOperation(const QString &kind, const QString &start, const QString &end,
                                         int rack, int wheel, int page)
{
    const int requestId = ++m_statsRequestSeq;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;
    (void)QtConcurrent::run(&m_statsPool, [this, requestId, kind, start, end, rack, wheel, page, archiveDir, sourceDir]() {
        const QVariantMap result = SearchService::alertOperation(getThreadDatabase(), kind, start, end,
                                                                 rack, wheel, page, archiveDir, sourceDir);
        QMetaObject::invokeMethod(this, [this, requestId, result]() {
            emit alertOperationFinished(requestId, result);
        }, Qt::QueuedConnection);
    });
    return requestId;
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

int AppController::requestRoundImages()
{
    const int requestId = ++m_roundImagesRequestSeq;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;
    (void)QtConcurrent::run(&m_searchPool, [this, requestId, archiveDir, sourceDir]() {
        QElapsedTimer timer;
        timer.start();
        const QVariantList racks = SearchService::latestRoundImages(getThreadDatabase(), archiveDir, sourceDir);
        int rackCount = 0;
        int imageCount = 0;
        int missingCount = 0;
        for (const QVariant &value : racks) {
            const QVariantMap rack = value.toMap();
            const int cameras = rack.value(QStringLiteral("cameraCount")).toInt();
            const int images = rack.value(QStringLiteral("imageCount")).toInt();
            if (cameras > 0) ++rackCount;
            imageCount += images;
            missingCount += cameras - images;
        }
        LOG_INFO("热力图像：本轮汇总完成，有记录的架={}，可显示图像={}，有记录缺图像={}，耗时={}ms",
                 rackCount, imageCount, missingCount, timer.elapsed());
        QMetaObject::invokeMethod(this, [this, requestId, racks]() {
            emit roundImagesReady(requestId, racks);
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
        "SELECT imagename, createtime, result, image_path FROM record "
        "WHERE carrier_id = :rack AND wheel_id = :wheel "
        "ORDER BY createtime DESC, rowid DESC LIMIT 1");

    query.prepare(sql);
    query.bindValue(QStringLiteral(":rack"), rackNumber);
    query.bindValue(QStringLiteral(":wheel"), wheelNumber);
    if (!query.exec() || !query.next()) {
        return image;
    }

    const QString imageName = query.value(0).toString().trimmed();
    QString imagePath = resolveRecordImage(query.value(3).toString(), imageName, m_archiveDirectory, m_sourceDirectory);
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

void AppController::debugLog(const QString &text)
{
    LOG_DEBUG("QML调试信息: {}", text.toStdString());
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
    QMutexLocker locker(&m_dbMutex);
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
            WHERE +result = 1 AND +distance > 0 AND +wheel_id BETWEEN 9 AND 16
            ORDER BY createtime DESC LIMIT 1)
          AND result = 1
          AND distance > 0
          AND wheel_id BETWEEN 9 AND 16
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
    QMutexLocker locker(&m_dbMutex);
    if (rackNumber < 1) return 0;
    QSqlDatabase db = QSqlDatabase::database();
    if (!db.isValid() || !db.isOpen()) return 0;
    QSqlQuery q(db);
    const QString sql = QStringLiteral(R"(
        SELECT MAX(cnt) FROM (
            SELECT wheel_id AS w, COUNT(*) AS cnt
            FROM record
            WHERE carrier_id = :rack AND result = 1 AND distance > 0
              AND wheel_id BETWEEN 9 AND 16
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
    QMutexLocker locker(&m_dbMutex);
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
            SELECT rowid, createtime, carrier_id, wheel_id, camera_id, result, imagename, distance, dist_norm, lower_tolerance, image_path
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
            // 标定对象是驱动轮，轮位 9～16
            for (int wheel = 9; wheel <= 16; ++wheel) {
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
                    item.wheelId = wheel;
                    item.slot = wheel;
                    item.cameraId = q.value(4).toInt();
                    item.result = q.value(5).toInt();
                    item.fileName = QFileInfo(q.value(6).toString().trimmed()).fileName();
                    item.distance = q.value(7).toDouble();
                    item.dist_norm = q.value(8).toDouble();
                    item.lower_tolerance = q.value(9).toDouble();

                    const QString rawName = q.value(6).toString().trimmed();
                    item.filePath = resolveRecordImage(q.value(10).toString(), rawName, m_archiveDirectory, m_sourceDirectory);
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
        m_imageDirSetting = settings.root.isEmpty() ? QStringLiteral("images") : settings.root;
        m_ftpPort = settings.port;
        m_slotMapping = settings.slotMapping;
    }
    // FTP 上传目录即图像存储目录；环境变量 AGCFTP_ARCHIVE_DIR 优先
    if (qEnvironmentVariable("AGCFTP_ARCHIVE_DIR").trimmed().isEmpty()) {
        const QString resolved = AgcUtils::resolveAppPath(m_imageDirSetting);
        if (resolved != m_archiveDirectory) {
            m_archiveDirectory = resolved;
            emit archiveDirectoryChanged();
        }
    }
    m_ftpAllowAnonymous = false; // 内置服务不允许匿名上传。
    if (!m_ftpUsers.isEmpty()) m_ftpUser = m_ftpUsers.firstKey();
    emit ftpSettingsChanged();
    LOG_DEBUG("loadFtpSettings: 有效端口={}, 用户={}", m_ftpPort, m_ftpUser.toStdString());
}

bool AppController::saveFtpSettingsToFile()
{
    const SettingsStore::FtpSettings settings{m_ftpUsers, m_imageDirSetting, m_ftpPort, m_slotMapping};
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
    // 按日期范围对全部架号分组统计，在统计线程执行；只采用最后一次请求的结果
    const int generation = ++m_gearSumGeneration;
    const QVariantList turns = selectedTurns.isValid() ? selectedTurns.toList() : QVariantList();
    (void)QtConcurrent::run(&m_statsPool, [this, generation, startDate, endDate, rackno, turns]() {
        const QVariantList out = StatsService::gearSum(getThreadDatabase(), startDate, endDate, rackno, turns);
        QMetaObject::invokeMethod(this, [this, generation, out]() {
            if (generation != m_gearSumGeneration) return;
            m_gearSumResult = out;
            LOG_DEBUG("gearSum 汇总统计计算完成，已触发更新");
            emit gearSumResultChanged();
        }, Qt::QueuedConnection);
    });
}

void AppController::openGenericSearch(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType)
{
    emit genericSearchRequested(startDate, endDate, wheelNumber, resultType);
}

void AppController::startFtpServer()
{
    m_ftpStoppedByUser = false;
    if (m_ftpRunning) return;
    if (m_ftpUsers.isEmpty()) {
        setStatusMessage(QStringLiteral("请先创建 FTP 账户，服务未启动"));
        return;
    }
    const QString root = m_archiveDirectory;
    QTemporaryFile probe(QDir(root).filePath(".cv-write-test-XXXXXX"));
    if (!QSqlDatabase::database().isOpen() || root.isEmpty() || !QDir().mkpath(root) || !probe.open()) {
        setStatusMessage(QStringLiteral("FTP 未启动：数据库或上传目录不可用")); return;
    }
    if (ftpListen(m_ftpPort, root)) {
        const QString msg = QStringLiteral("FTP 服务器已启动：端口 %1，目录 %2").arg(m_ftpPort).arg(root);
        setStatusMessage(msg);
        LOG_INFO("FTP 服务器已成功启动: 监听端口={}, 根目录={}, 账户={}", m_ftpPort, root.toStdString(),
                 QStringList(m_ftpUsers.keys()).join(QLatin1Char(',')).toStdString());
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

// 来源 IP 白名单（决策 D4）：system_config 中 network/allowList，默认空表示不限制
QList<NetworkAccess::Subnet> AppController::networkAllowList() const
{
    QString text;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        text = DBSchema::getConfig(db, QStringLiteral("network/allowList"));
    }
    bool ok = true;
    QString error;
    const auto list = NetworkAccess::parseAllowList(text, ok, error);
    if (!ok) LOG_WARN("来源 IP 白名单配置有误，已忽略无法解析的项: {}", error.toStdString());
    if (!list.isEmpty()) LOG_INFO("已启用来源 IP 白名单: {}", text.toStdString());
    return list;
}

bool AppController::ftpListen(int port, const QString &root)
{
    FtpIngestService *service = m_ftpService;
    const auto users = m_ftpUsers;
    const bool allowAnonymous = m_ftpAllowAnonymous;
    const auto allowList = networkAllowList();
    int passiveMin = 50000, passiveMax = 50100; // 决策 D5
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        passiveMin = DBSchema::getConfigInt(db, QStringLiteral("ftp/passivePortMin"), passiveMin);
        passiveMax = DBSchema::getConfigInt(db, QStringLiteral("ftp/passivePortMax"), passiveMax);
    }
    if (passiveMin < 1024 || passiveMax > 65535 || passiveMax < passiveMin) {
        LOG_WARN("FTP 被动端口范围配置无效 ({}-{})，改用 50000-50100", passiveMin, passiveMax);
        passiveMin = 50000;
        passiveMax = 50100;
    }
    bool ok = false;
    QMetaObject::invokeMethod(service, [service, port, root, users, allowAnonymous, allowList, passiveMin, passiveMax]() {
        service->setAccessPolicy(allowList, static_cast<quint16>(passiveMin), static_cast<quint16>(passiveMax));
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
    const QString root = m_archiveDirectory;
    QMetaObject::invokeMethod(service, [service, root]() { service->setRoot(root); }, Qt::QueuedConnection);
}

void AppController::stopFtpServer()
{
    m_ftpStoppedByUser = true;
    ftpStop();
    setStatusMessage(QStringLiteral("FTP 服务器已停止"));
    LOG_INFO("FTP 服务器已停止运行");
    emit ftpServerStateChanged();
}

void AppController::startTcpServer()
{
    m_tcpStoppedByUser = false;
    if (m_tcpReceiver.isRunning()) return;
    QSqlDatabase db = QSqlDatabase::database();
    if (db.isOpen()) {
        m_tcpPort = DBSchema::getConfigInt(db, QStringLiteral("tcp/port"), 9000);
    }
    m_tcpReceiver.setAllowList(networkAllowList());
    if (!m_tcpReceiver.listen(QHostAddress::Any, static_cast<quint16>(m_tcpPort)))
        setStatusMessage(QStringLiteral("TCP 数据服务启动失败（端口 %1 可能被占用），将每 30 秒自动重试").arg(m_tcpPort));
    emit tcpServerStateChanged();
}

void AppController::stopTcpServer()
{
    m_tcpStoppedByUser = true;
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
    if (m_storageLevel >= StorageMonitor::Level::RejectData) {
        error = QStringLiteral("服务器存储空间不足，暂停接收数据");
        LOG_ERROR("[TCP] {}", error.toStdString());
        return false;
    }
    ImageIngest::ParseLimits limits;
    limits.now = QDateTime::currentDateTime();
    limits.maxAgeDays = qBound(1, cleanupKeepDays(), 3650);
    ImageIngest::BatchData batch;
    if (!ImageIngest::parseBatchJson(batchData, batch, error, limits)) {
        LOG_ERROR("[TCP] 批次数据解析失败: {}", error.toStdString());
        setStatusMessage(QStringLiteral("TCP 报文解析失败: %1").arg(error));
        return false;
    }

    // FTP 图像可能先于本批次到达：按客户端请求的文件名匹配缓存，实际路径随记录一起入库
    QStringList consumed;
    for (ImageIngest::WheelItem &wheel : batch.wheels) {
        wheel.imagePath = m_pendingImages.find(wheel.imageName);
        if (!wheel.imagePath.isEmpty()) consumed << wheel.imageName;
    }

    {
        QMutexLocker lock(&m_dbMutex);
        if (!ImageIngest::recordBatch(QSqlDatabase::database(), batch, error)) {
            LOG_ERROR("[TCP] 数据原子入库失败: {}", error.toStdString());
            setStatusMessage(QStringLiteral("数据入库失败: %1").arg(error));
            return false;
        }
    }
    for (const QString &imageName : std::as_const(consumed)) m_pendingImages.remove(imageName);

    m_currentCarrierId = batch.carrierId;
    m_currentRoundNumber = 0;
    QHash<QString, QString> associated;
    for (const ImageIngest::WheelItem &wheel : std::as_const(batch.wheels)) {
        if (!wheel.imagePath.isEmpty()) associated.insert(wheel.imageName, wheel.imagePath);
    }
    QVector<ImageItem> cards = IngestCoordinator::buildStationCards(batch, [&](const QString &imageName) {
        const QString path = associated.value(imageName);
        // 图片尚未到达：先按文件名在归档目录查找用于显示，到达后由 onFtpImageStored 更新卡片与记录
        return path.isEmpty() ? resolveImagePath(imageName, m_archiveDirectory, m_sourceDirectory) : path;
    });
    // 一个载具分多次触发（每次 6 个相机）：同一载具的后续批次只刷新本批相机，
    // 其余工位保留该载具前几批的卡片；换载具或间隔过久时整屏刷新
    int keptCards = 0;
    int totalWheels = 0;
    for (int i = 0; i < cards.size(); ++i) {
        if (cards[i].wheelsInfo.isEmpty() && i < m_currentImagesModel.count()) {
            const ImageItem previous = m_currentImagesModel.itemAt(i);
            if (previous.carrierId == batch.carrierId && !previous.wheelsInfo.isEmpty()
                && previous.receivedAt.isValid()
                && qAbs(previous.receivedAt.secsTo(batch.timestamp)) <= IngestCoordinator::kSameCarrierMergeSecs) {
                cards[i] = previous;
                ++keptCards;
            }
        }
        if (!cards[i].wheelsInfo.isEmpty())
            totalWheels += cards[i].wheelsInfo.count(QStringLiteral(" · ")) + 1;
    }
    m_currentImagesModel.setItems(cards);

    m_currentReceivedAtText = AgcUtils::formatDateTime(batch.timestamp);
    m_currentSerialsRaw = QStringLiteral("载具 #%1 (轮数=%2)").arg(batch.carrierId).arg(totalWheels);
    m_currentCopiedCount = totalWheels;
    emit currentBatchChanged();
    emit recordImagesChanged();
    LOG_INFO("[TCP] 载具 #{} 数据已成功入库并刷新 12 宫格卡片: 轮数={}, 已关联图片的轮={}, 待图片到达的轮={}, 保留同载具前批卡片={}",
             batch.carrierId, batch.wheels.size(), consumed.size(), batch.wheels.size() - consumed.size(), keptCards);
    setStatusMessage(QStringLiteral("载具 #%1 测量数据已接收，共 %2 轮").arg(batch.carrierId).arg(batch.wheels.size()));
    return true;
}

void AppController::onFtpImageStored(const QString &filePath, const QString &requestedPath)
{
    const QFileInfo file(filePath);
    if (!file.isFile() || file.isSymbolicLink()) return;
    const QString absolutePath = file.absoluteFilePath();
    // 以客户端请求的文件名关联：同名不同内容被保存为 _vN 时，仍对应报文中的 imageName
    const QString requestedName = QFileInfo(requestedPath.isEmpty() ? filePath : requestedPath).fileName();
    const QString resolvedUrl = QUrl::fromLocalFile(absolutePath).toString();

    // 记录先到的情况：补写实际路径。仅限最近 1 小时、尚未关联的记录，
    // 避免升级前的历史记录（image_path 均为空）被同名新图误关联
    int linkedRows = 0;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlQuery update(QSqlDatabase::database());
        update.prepare(QStringLiteral(
            "UPDATE record SET image_path = :path "
            "WHERE createtime >= :since AND imagename = :name COLLATE NOCASE "
            "AND (image_path IS NULL OR image_path = '')"));
        update.bindValue(QStringLiteral(":path"), absolutePath);
        update.bindValue(QStringLiteral(":since"), AgcUtils::formatDateTime(QDateTime::currentDateTime().addSecs(-3600)));
        update.bindValue(QStringLiteral(":name"), requestedName);
        if (update.exec()) linkedRows = update.numRowsAffected();
        else LOG_ERROR("[FTP] 补写图片路径失败: {}", update.lastError().text().toStdString());
    }

    // 只更新正在等待这张图的批次卡片；否则（如 _vN 新图先于其批次到达）放入缓存，
    // 避免把新图显示到界面上同名的上一批次卡片上
    bool matchedCard = false;
    if (linkedRows > 0) {
        const QString imageKey = IngestCoordinator::imageKey(requestedName);
        for (int i = 0; i < m_currentImagesModel.count(); ++i) {
            ImageItem item = m_currentImagesModel.itemAt(i);
            if (!imageKey.isEmpty() && IngestCoordinator::imageKey(item.fileName) == imageKey) {
                item.filePath = absolutePath;
                item.fileUrl = resolvedUrl;
                m_currentImagesModel.updateSlotItem(i, item);
                matchedCard = true;
            }
        }
    } else {
        const QDateTime now = QDateTime::currentDateTime();
        m_pendingImages.add(requestedName, absolutePath, now);
        m_pendingImages.prune(now);
    }

    if (linkedRows > 0) emit recordImagesChanged();

    LOG_INFO("[FTP] 图像文件入库归档: {}{}, 关联卡片={}, 关联记录={}, 待关联缓存={}",
             file.fileName().toStdString(),
             requestedName != file.fileName() ? (" (请求名 " + requestedName.toStdString() + ")") : std::string(),
             matchedCard, linkedRows, m_pendingImages.size());
}

QString AppController::ftpUser() const
{
    return m_ftpUser;
}



QString AppController::ftpRoot() const
{
    return m_archiveDirectory;
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
    const QString normalized = AgcUtils::resolveAppPath(root);
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
    const QString previousRoot = m_archiveDirectory;
    const QString previousSetting = m_imageDirSetting;
    const int previousPort = m_ftpPort;
    const bool running = m_ftpRunning;
    if (running) ftpStop();
    m_archiveDirectory = normalized; m_ftpPort = port;
    // 程序目录内的路径按相对路径保存，安装目录整体搬迁后仍然有效
    m_imageDirSetting = AgcUtils::toAppRelativePath(normalized);
    bool success = !running || ftpListen(port, normalized);
    if (success) success = saveFtpSettingsToFile();
    if (!success) {
        if (m_ftpRunning) ftpStop();
        m_archiveDirectory = previousRoot; m_imageDirSetting = previousSetting; m_ftpPort = previousPort;
        const bool restored = !running || ftpListen(previousPort, previousRoot);
        ftpPushRoot();
        setStatusMessage(restored ? QStringLiteral("FTP 设置未生效，已恢复原配置") : QStringLiteral("FTP 设置失败，原服务也无法恢复，请检查端口"));
        return false;
    }
    ftpPushRoot();
    if (normalized != previousRoot) {
        ensureDirectories();
        LOG_INFO("图像存储目录已变更: {} -> {}", previousRoot.toStdString(), normalized.toStdString());
        emit archiveDirectoryChanged();
    }
    emit ftpSettingsChanged();
    return true;
}

void AppController::setFtpRoot(const QString &root)
{
    if (AgcUtils::resolveAppPath(root) != m_archiveDirectory) applyFtpConfiguration(root, m_ftpPort);
}

void AppController::setFtpPort(int port)
{
    if (port != m_ftpPort) applyFtpConfiguration(m_archiveDirectory, port);
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
    const QString root = m_archiveDirectory;
    if (!root.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(root));
    }
}
