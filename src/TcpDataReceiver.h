#pragma once

#include <QObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QHostAddress>
#include <QJsonObject>
#include <QMap>
#include <QByteArray>

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
    QTcpServer m_server;
    QMap<QTcpSocket*, QByteArray> m_clientBuffers;
};
