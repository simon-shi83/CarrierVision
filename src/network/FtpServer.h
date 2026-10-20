#pragma once

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QDir>
#include <QTemporaryFile>
#include <functional>
#include <QFile>
#include <QNetworkInterface>
#include <QMap>
#include <QPointer>
#include <QTimer>
#include "network/NetworkAccess.h"

class FtpControlConnection : public QObject {
    Q_OBJECT
public:
    explicit FtpControlConnection(QTcpSocket *sock, const QString &root, const QMap<QString, QString> &users, bool allowAnonymous, QObject *parent = nullptr);
    void shutdown();
    // (暂存文件, 最终落盘路径, 客户端请求的路径)；同名不同内容时最终路径带 _vN 后缀
    std::function<bool(const QString &, const QString &, const QString &)> uploadHandler;
    // STOR 前调用；返回 false 时以 452 拒绝本次上传（如磁盘空间不足）
    std::function<bool()> uploadGate;

    // 被动模式监听端口范围；min 为 0 时由系统随机分配
    quint16 passivePortMin = 0;
    quint16 passivePortMax = 0;

signals:
    void connectionClosed();
    void loginFailed();
    void loginSucceeded();
    // 需要在界面状态栏提示的异常（已写入主日志）
    void warningRaised(const QString &message);
    void imageStored(const QString &filePath);

private slots:
    void onReadyRead();
    void onDisconnected();
    void onPasvNewConnection();
    void onDataReadyRead();

private:
    void reportWarning(const QString &message);
    void sendReply(int code, const QString &text);
    void processCommand(const QString &cmdLine);
    QString makePasvReply(quint16 port);
    QString listDirectory(const QString &path);
    void attachDataSocket(QTcpSocket *socket);
    void finishDataTransferAndCleanup(bool sendStoreReply = true);
    void closeDataConnection();
    void pumpDownload();
    void startActiveConnection(const QHostAddress &address, quint16 port);
    void finishDownload(bool success);
    bool listenPassive();
    bool m_closed = false;
    bool m_connecting = false;
    bool m_sending = false;
    QByteArray m_listing;
    QPointer<QFile> m_download;
    QTimer m_transferTimer;
    QTimer m_deadlineTimer;

    QPointer<QTcpSocket> m_ctrl;
    QPointer<QTimer> m_idleTimer;
    quint32 m_sessionId{0};
    QPointer<QTcpServer> m_pasvServer;
    QPointer<QTcpSocket> m_dataSocket;
    QString m_root;
    QDir m_cwd;
    QMap<QString, QString> m_users;
    bool m_allowAnonymous{false};
    QString m_user;
    bool m_loggedIn{false};
    int m_failedLoginAttempts{0};
    QByteArray m_buffer;
    bool m_waitingForStore{false};
    bool m_storeSuccess{false};
    bool m_storeFailed{false};
    qint64 m_storeBytesReceived{0};
    QString m_pendingStorePath;
    QPointer<QTemporaryFile> m_storeFile;

    static constexpr qint64 MaxUploadBytes = 512LL * 1024 * 1024;
};

class FtpServer : public QObject {
    Q_OBJECT
public:
    explicit FtpServer(QObject *parent = nullptr);
    void stop();
    // (暂存文件, 最终落盘路径, 客户端请求的路径)；同名不同内容时最终路径带 _vN 后缀
    std::function<bool(const QString &, const QString &, const QString &)> uploadHandler;
    // STOR 前调用；返回 false 时以 452 拒绝本次上传（如磁盘空间不足）
    std::function<bool()> uploadGate;
    bool isRunning() const;
    int clientCount() const;
    quint16 port() const { return m_server.serverPort(); }
    // users: map username -> password
    bool listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QMap<QString, QString> &users, bool allowAnonymous = false);
    // backward-compatible overload: single user/pass
    bool listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QString &user, const QString &pass);
    void setUsers(const QMap<QString, QString> &users, bool allowAnonymous = false);
    // 来源 IP 白名单，空列表表示不限制；对新连接生效
    void setAllowList(const QList<NetworkAccess::Subnet> &allowList) { m_allowList = allowList; }
    void setPassivePortRange(quint16 min, quint16 max) { m_passiveMin = min; m_passiveMax = max; }

signals:
    void runningChanged(bool running);
    void clientCountChanged(int count);
    // 需要在界面状态栏提示的异常（已写入主日志）
    void warningRaised(const QString &message);
    void imageStored(const QString &filePath);

private slots:
    void onNewConnection();

private:
    void reportWarning(const QString &message);
    static constexpr int MaxClients = 64;
    QTcpServer m_server;
    QString m_rootDir;
    QMap<QString, QString> m_users;
    bool m_allowAnonymous = false;
    int m_clientCount = 0;
    QList<NetworkAccess::Subnet> m_allowList;
    NetworkAccess::LoginThrottle m_loginThrottle;
    quint16 m_passiveMin = 0;
    quint16 m_passiveMax = 0;
};
