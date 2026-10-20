#include "network/FtpIngestService.h"

#include "common/AppLogger.h"
#include "ingest/ImageIngest.h"

#include <QFile>
#include <QFileInfo>

FtpIngestService::FtpIngestService(QObject *parent)
    : QObject(parent)
    , m_server(this)
    , m_retryTimer(this)
{
    connect(&m_server, &FtpServer::runningChanged, this, &FtpIngestService::runningChanged);
    connect(&m_server, &FtpServer::clientCountChanged, this, &FtpIngestService::clientCountChanged);
    connect(&m_server, &FtpServer::warningRaised, this, &FtpIngestService::warningRaised);
    m_server.uploadHandler = [this](const QString &staged, const QString &target, const QString &requested) {
        QString error;
        const bool accepted = ImageIngest::accept(staged, target,
            [this, &requested](const QString &path) { emit imageStored(path, requested); return true; }, error);
        if (!accepted) emit ingestFailed(error);
        return accepted;
    };
    m_server.uploadGate = [this]() { return m_acceptUploads.load(); };
    connect(&m_retryTimer, &QTimer::timeout, this, &FtpIngestService::recoverPendingUploads);
}

bool FtpIngestService::start(quint16 port, const QString &root, const QMap<QString, QString> &users,
                             bool allowAnonymous, const QHostAddress &address)
{
    if (m_server.isRunning()) return true;
    return m_server.listen(address, port, root, users, allowAnonymous);
}

void FtpIngestService::setAccessPolicy(const QList<NetworkAccess::Subnet> &allowList, quint16 passiveMin, quint16 passiveMax)
{
    m_server.setAllowList(allowList);
    m_server.setPassivePortRange(passiveMin, passiveMax);
}

void FtpIngestService::stop()
{
    m_server.stop();
}

void FtpIngestService::setUsers(const QMap<QString, QString> &users, bool allowAnonymous)
{
    m_server.setUsers(users, allowAnonymous);
}

void FtpIngestService::setRoot(const QString &root)
{
    if (root != m_root) {
        m_root = root;
        m_pendingScan.reset();
    }
    if (!m_retryTimer.isActive()) m_retryTimer.start(1000);
}

void FtpIngestService::shutdown()
{
    m_retryTimer.stop();
    m_pendingScan.reset();
    m_server.stop();
}

void FtpIngestService::recoverPendingUploads()
{
    if (m_root.isEmpty()) return;
    if (!m_pendingScan) {
        m_pendingScan = std::make_unique<QDirIterator>(m_root,
            QDir::Files | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDirIterator::Subdirectories);
    }
    int scanned = 0;
    while (m_pendingScan->hasNext() && scanned++ < 100) {
        const QString marker = m_pendingScan->next();
        if (!marker.endsWith(QStringLiteral(".cv-pending"))) continue;
        const QString path = marker.chopped(QStringLiteral(".cv-pending").size());
        QString error;
        if (ImageIngest::validate(path, path, error)) {
            emit imageStored(path, path); // 恢复时已无法得知原请求名，按实际文件名关联
            if (!QFile::remove(marker)) LOG_WARN("无法移除已恢复记录: {}", marker.toStdString());
        } else {
            // 如果目标文件不存在，或者标记已超过 5 分钟且无法通过验证（例如损坏或名称不符），清理该标记避免死循环
            const QFileInfo markerInfo(marker);
            const bool targetExists = QFileInfo::exists(path);
            if (!targetExists || markerInfo.lastModified().secsTo(QDateTime::currentDateTime()) > 300) {
                LOG_WARN("恢复未决上传失败，清理孤立恢复标记: marker='{}', error='{}'",
                         marker.toStdString(), error.toStdString());
                QFile::remove(marker);
            }
        }
    }
    if (!m_pendingScan->hasNext()) {
        m_pendingScan.reset();
        m_retryTimer.setInterval(60'000);
    } else {
        m_retryTimer.setInterval(1000);
    }
}
