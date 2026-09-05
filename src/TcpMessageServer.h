#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>

class TcpMessageServer : public QObject
{
    Q_OBJECT

public:
    explicit TcpMessageServer(QObject *parent = nullptr);

    bool start(quint16 port);
    void stop();

    bool isRunning() const;
    quint16 port() const;

signals:
    void rawMessageReceived(const QString &message);
    void rackMessageReceived(const QString &rackNumber, int roundNumber, int currentTotal);
    void serverStateChanged(bool running, quint16 port);
    void statusChanged(const QString &message);

private:
    static constexpr int MaxConnections = 64;
    static constexpr qsizetype MaxBufferSize = 64 * 1024;

    void handleSocketReadyRead(QTcpSocket *socket);
    void processBuffer(QTcpSocket *socket, bool flushAll);
    void processMessage(const QString &message, QTcpSocket *socket = nullptr);

    QTcpServer m_server;
    QHash<QTcpSocket *, QByteArray> m_socketBuffers;
};
