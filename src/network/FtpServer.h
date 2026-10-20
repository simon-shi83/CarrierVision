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

class FtpControlConnection : public QObject {
    Q_OBJECT
public:
    explicit FtpControlConnection(QTcpSocket *sock, const QString &root, const QMap<QString, QString> &users, bool allowAnonymous, QObject *parent = nullptr);
    void shutdown();
    std::function<bool(const QString &, const QString &)> uploadHandler;

signals:
    void connectionClosed();
    void logMessage(const QString &message);
    void imageStored(const QString &filePath);

private slots:
    void onReadyRead();
    void onDisconnected();
    void onPasvNewConnection();
    void onDataReadyRead();

private:
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
    std::function<bool(const QString &, const QString &)> uploadHandler;
    bool isRunning() const;
    int clientCount() const;
    quint16 port() const { return m_server.serverPort(); }
    // users: map username -> password
    bool listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QMap<QString, QString> &users, bool allowAnonymous = false);
    // backward-compatible overload: single user/pass
    bool listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QString &user, const QString &pass);
    void setUsers(const QMap<QString, QString> &users, bool allowAnonymous = false);

signals:
    void runningChanged(bool running);
    void clientCountChanged(int count);
    void logMessage(const QString &message);
    void imageStored(const QString &filePath);

private slots:
    void onNewConnection();

private:
    static constexpr int MaxClients = 64;
    QTcpServer m_server;
    QString m_rootDir;
    QMap<QString, QString> m_users;
    bool m_allowAnonymous = false;
    int m_clientCount = 0;
};
