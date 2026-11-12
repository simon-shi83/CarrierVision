// AppController：内置 FTP / TCP 服务、FTP 账户与相机槽位映射、TCP 批次入库与图片回填。
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
using SearchService::RecordFilter;
using SearchService::buildRecordFilter;
using SearchService::parseResultFilter;
using SearchService::queryRecordPage;
using SearchService::resolveRecordImage;

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

void AppController::resetSlotMapping()
{
    const auto previous = m_slotMapping;
    m_slotMapping = SettingsStore::defaultSlotMapping();
    if (!saveFtpSettingsToFile()) { m_slotMapping = previous; return; }
    emit mappingChanged();
    LOG_INFO("重置相机通道槽位映射为默认 1:1");
    setStatusMessage(QStringLiteral("已重置相机工位通道映射为默认 1:1"));
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
    bool dateSubdirectories = true;
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        passiveMin = DBSchema::getConfigInt(db, QStringLiteral("ftp/passivePortMin"), passiveMin);
        passiveMax = DBSchema::getConfigInt(db, QStringLiteral("ftp/passivePortMax"), passiveMax);
        // 默认把传到根目录的图片按日期分子目录存放，避免单个目录文件过多；设为 false 恢复旧行为
        dateSubdirectories = DBSchema::getConfigBool(db, QStringLiteral("ftp/dateSubdirectories"), true);
    }
    if (passiveMin < 1024 || passiveMax > 65535 || passiveMax < passiveMin) {
        LOG_WARN("FTP 被动端口范围配置无效 ({}-{})，改用 50000-50100", passiveMin, passiveMax);
        passiveMin = 50000;
        passiveMax = 50100;
    }
    bool ok = false;
    QMetaObject::invokeMethod(service, [service, port, root, users, allowAnonymous, allowList, passiveMin, passiveMax, dateSubdirectories]() {
        service->setAccessPolicy(allowList, static_cast<quint16>(passiveMin), static_cast<quint16>(passiveMax));
        service->setDateSubdirectories(dateSubdirectories);
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
        return path.isEmpty() ? resolveRecordImage(QString(), imageName, m_archiveDirectory, m_sourceDirectory,
                                                  AgcUtils::formatDateTime(batch.timestamp)) : path;
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
            // 写成 COALESCE 表达式而不是 "image_path IS NULL OR image_path = ''"：后者会让 SQLite 改走
            // image_path 索引，逐行扫描全部未关联图片的历史记录（升级前的记录全部为空），
            // 记录越多越慢，且在主线程上每收到一张图执行一次。表达式形式只走最近 1 小时的时间索引
            "AND COALESCE(image_path, '') = ''"));
        update.bindValue(QStringLiteral(":path"), absolutePath);
        update.bindValue(QStringLiteral(":since"), AgcUtils::formatDateTime(QDateTime::currentDateTime().addSecs(-3600)));
        update.bindValue(QStringLiteral(":name"), requestedName);
        if (update.exec()) linkedRows = update.numRowsAffected();
        else LOG_ERROR("[FTP] 补写图片路径失败: 文件={}, 原因={}", requestedName.toStdString(), update.lastError().text().toStdString());
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

    ++m_loggedImageCount;
    m_loggedLinkedRows += qMax(0, linkedRows);
    if (linkedRows == 0) ++m_loggedCachedImages;
    LOG_DEBUG("[FTP] 图像文件入库归档: {}{}, 关联卡片={}, 关联记录={}, 待关联缓存={}",
             file.fileName().toStdString(),
             requestedName != file.fileName() ? (" (请求名 " + requestedName.toStdString() + ")") : std::string(),
             matchedCard, linkedRows, m_pendingImages.size());
}

void AppController::flushImageIngestLog()
{
    if (m_loggedImageCount == 0) return;
    LOG_INFO("[FTP] 图像接收汇总: 本期图片={} 张, 回填关联记录={} 轮, 进入缓存图片={} 张, 当前待关联缓存={} 张, 目录={}",
             m_loggedImageCount, m_loggedLinkedRows, m_loggedCachedImages,
             m_pendingImages.size(), m_archiveDirectory.toStdString());
    m_loggedImageCount = 0;
    m_loggedLinkedRows = 0;
    m_loggedCachedImages = 0;
}

QString AppController::ftpUser() const
{
    return m_ftpUser;
}

QString AppController::ftpRoot() const
{
    return m_archiveDirectory;
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

void AppController::openFtpRootDirectory()
{
    const QString root = m_archiveDirectory;
    if (!root.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(root));
    }
}
