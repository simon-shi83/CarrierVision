#pragma once

#include "network/FtpServer.h"

#include <QDirIterator>
#include <QHostAddress>
#include <QMap>
#include <QObject>
#include <QString>
#include <QTimer>
#include <atomic>
#include <memory>

// FTP 接收服务：在独立线程中运行 FTP 服务、上传图像校验/提交以及 .cv-pending 恢复扫描。
// 上传提交与恢复扫描在同一线程串行执行，扫描不会看到正在提交中的恢复标记。
// 除构造函数外，所有公有函数都必须在服务所在线程调用（由调用方经 QMetaObject::invokeMethod 投递）。
class FtpIngestService : public QObject
{
    Q_OBJECT
public:
    explicit FtpIngestService(QObject *parent = nullptr);

    bool start(quint16 port, const QString &root, const QMap<QString, QString> &users, bool allowAnonymous,
               const QHostAddress &address = QHostAddress::Any);
    quint16 port() const { return m_server.port(); }
    void stop();
    void setUsers(const QMap<QString, QString> &users, bool allowAnonymous);
    // 设置恢复扫描目录并从头扫描；启动恢复定时器
    void setRoot(const QString &root);
    // 停止服务与定时器，准备退出线程
    void shutdown();
    // 磁盘空间不足时由主线程设置为 false，新上传以 452 拒绝；线程安全
    void setAcceptUploads(bool accept) { m_acceptUploads.store(accept); }
    void setAccessPolicy(const QList<NetworkAccess::Subnet> &allowList, quint16 passiveMin, quint16 passiveMax);

signals:
    // filePath 为实际落盘路径；requestedPath 为客户端请求的路径（发生 _vN 版本化时两者不同）
    void imageStored(const QString &filePath, const QString &requestedPath);
    void ingestFailed(const QString &error);
    void runningChanged(bool running);
    void clientCountChanged(int count);
    void logMessage(const QString &message);

private:
    void recoverPendingUploads();

    FtpServer m_server;
    QTimer m_retryTimer;
    QString m_root;
    std::atomic<bool> m_acceptUploads{true};
    std::unique_ptr<QDirIterator> m_pendingScan;
};
