#pragma once

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHostAddress>
#include <QJsonObject>
#include <QMap>
#include <QByteArray>
#include <functional>

class TcpDataReceiver : public QObject
{
    Q_OBJECT

public:
    explicit TcpDataReceiver(QObject *parent = nullptr);
    ~TcpDataReceiver() override;

    bool listen(const QHostAddress &address, quint16 port);
    void stop();
    bool isRunning() const;
    quint16 port() const;
    int clientCount() const;

    // Synchronous commit hook. Returning true means the message has been
    // durably accepted and may be acknowledged to the sender.
    std::function<bool(const QJsonObject &, QString &)> batchHandler;

signals:
    void runningChanged(bool running);
    void clientCountChanged(int count);
    void logMessage(const QString &message);
    void dataBatchReceived(const QJsonObject &batch);

private slots:
    void onNewConnection();
    void onClientReadyRead();
    void onClientDisconnected();

private:
    static constexpr int MaxClients = 32;
    QTcpServer m_server;
    QMap<QTcpSocket*, QByteArray> m_clientBuffers;
};
