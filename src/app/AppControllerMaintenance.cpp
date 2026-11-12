// AppController：历史数据清理、存储空间监控、每日备份与周报等定时任务。
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


using AppControllerInternal::getThreadDatabase;
using AppControllerInternal::kMaxPageSize;
using AppControllerInternal::legacyFtpLogPrefix;

namespace {

void removeExpiredLegacyFtpLogs(int keepDays)
{
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-keepDays);
    const QDir logDir(AppLogger::getLogDirectory());
    for (const QFileInfo &file : logDir.entryInfoList({legacyFtpLogPrefix() + QStringLiteral("*.log")}, QDir::Files)) {
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
    int requests = 0;
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
            result.requests += stats.requestsDeleted;
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
    // 日志清理与数据库无关，数据库清理失败时也照常执行
    AppLogger::cleanupLogsOlderThanDays(request.logKeepDays);
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
                LOG_ERROR("{}清理未完成（已删除记录 {} 条、图片 {} 张）: {}", request.emergency ? "紧急" : "",
                          result.records, result.files, result.error.toStdString());
                setStatusMessage(QStringLiteral("清理未完成: %1").arg(result.error));
                return;
            }
            removeExpiredLegacyFtpLogs(request.logKeepDays);
            LOG_INFO("{}清理完成: 删除记录 {} 条, 图片 {} 张, 孤儿图片 {} 张, 路径异常仅删记录 {} 组, 过期重发去重记录 {} 条, 剩余空间 {:.1f}%",
                     request.emergency ? "紧急" : "", result.records, result.files, result.orphans,
                     result.skippedUnsafe, result.requests, result.freePercent);
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
