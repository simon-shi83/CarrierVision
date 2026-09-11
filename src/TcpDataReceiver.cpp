#include "TcpDataReceiver.h"
#include "AppLogger.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

TcpDataReceiver::TcpDataReceiver(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &TcpDataReceiver::onNewConnection);
}

TcpDataReceiver::~TcpDataReceiver()
{
    stop();
}

bool TcpDataReceiver::listen(const QHostAddress &address, quint16 port)
{
    if (m_server.isListening()) {
        if (m_server.serverPort() == port && m_server.serverAddress() == address) {
            return true;
        }
        stop();
    }

    if (!m_server.listen(address, port)) {
        LOG_ERROR("[TCP] 监听失败: 地址={}, 端口={}, 错误={}",
                  address.toString().toStdString(), port, m_server.errorString().toStdString());
        emit logMessage(QStringLiteral("[TCP] 监听失败: %1").arg(m_server.errorString()));
        emit runningChanged(false);
        return false;
    }

    LOG_INFO("[TCP] 服务已启动: 端口={}", port);
    emit logMessage(QStringLiteral("[TCP] 服务已启动: 端口=%1").arg(port));
    emit runningChanged(true);
    return true;
}

void TcpDataReceiver::stop()
{
    if (!m_server.isListening()) return;

    for (auto it = m_clientBuffers.begin(); it != m_clientBuffers.end(); ++it) {
        QTcpSocket *sock = it.key();
        if (sock) {
            sock->disconnect(this);
            sock->close();
            sock->deleteLater();
        }
    }
    m_clientBuffers.clear();
    m_server.close();

    LOG_INFO("[TCP] 服务已停止");
    emit logMessage(QStringLiteral("[TCP] 服务已停止"));
    emit runningChanged(false);
    emit clientCountChanged(0);
}

bool TcpDataReceiver::isRunning() const
{
    return m_server.isListening();
}

quint16 TcpDataReceiver::port() const
{
    return m_server.serverPort();
}

int TcpDataReceiver::clientCount() const
{
    return m_clientBuffers.size();
}

void TcpDataReceiver::onNewConnection()
{
    while (m_server.hasPendingConnections()) {
        QTcpSocket *sock = m_server.nextPendingConnection();
        if (!sock) continue;

        m_clientBuffers.insert(sock, QByteArray());

        connect(sock, &QTcpSocket::readyRead, this, &TcpDataReceiver::onClientReadyRead);
        connect(sock, &QTcpSocket::disconnected, this, &TcpDataReceiver::onClientDisconnected);

        const QString peer = QStringLiteral("%1:%2").arg(sock->peerAddress().toString()).arg(sock->peerPort());
        LOG_INFO("[TCP] 客户端已连接: {}", peer.toStdString());
        emit logMessage(QStringLiteral("[TCP] 客户端连接: %1").arg(peer));
        emit clientCountChanged(m_clientBuffers.size());
    }
}

void TcpDataReceiver::onClientReadyRead()
{
    auto *sock = qobject_cast<QTcpSocket*>(sender());
    if (!sock || !m_clientBuffers.contains(sock)) return;

    QByteArray &buffer = m_clientBuffers[sock];
    buffer.append(sock->readAll());

    // 协议规范：以换行符 '\n' 分包
    int newlineIndex = -1;
    while ((newlineIndex = buffer.indexOf('\n')) != -1) {
        QByteArray line = buffer.left(newlineIndex).trimmed();
        buffer.remove(0, newlineIndex + 1);

        if (line.isEmpty()) continue;

        QJsonParseError parseError{};
        QJsonDocument doc = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
            LOG_WARN("[TCP] JSON 解析失败: 错误={}, 原始报文={}",
                     parseError.errorString().toStdString(), line.constData());
            emit logMessage(QStringLiteral("[TCP] JSON解析失败: %1").arg(parseError.errorString()));

            const QByteArray errRsp = "{\"status\":\"ERROR\",\"message\":\"Invalid JSON format\"}\n";
            sock->write(errRsp);
            sock->flush();
            continue;
        }

        const QJsonObject obj = doc.object();
        if (!obj.contains(QStringLiteral("carrierId")) || !obj.contains(QStringLiteral("wheels"))) {
            LOG_WARN("[TCP] 报文缺少必要字段 (carrierId 或 wheels): {}", line.constData());
            const QByteArray errRsp = "{\"status\":\"ERROR\",\"message\":\"Missing carrierId or wheels\"}\n";
            sock->write(errRsp);
            sock->flush();
            continue;
        }

        const int carrierId = obj.value(QStringLiteral("carrierId")).toInt();
        const QJsonArray wheels = obj.value(QStringLiteral("wheels")).toArray();

        LOG_INFO("[TCP] 成功接收载具 {} 数据包, 包含 {} 轮检测数据", carrierId, wheels.size());
        emit logMessage(QStringLiteral("[TCP] 收到载具 %1 数据包 (轮数=%2)").arg(carrierId).arg(wheels.size()));
        emit dataBatchReceived(obj);

        const QByteArray okRsp = QStringLiteral("{\"status\":\"OK\",\"carrierId\":%1,\"wheelCount\":%2}\n")
                                     .arg(carrierId)
                                     .arg(wheels.size())
                                     .toUtf8();
        sock->write(okRsp);
        sock->flush();
    }
}

void TcpDataReceiver::onClientDisconnected()
{
    auto *sock = qobject_cast<QTcpSocket*>(sender());
    if (!sock) return;

    m_clientBuffers.remove(sock);
    sock->deleteLater();

    LOG_INFO("[TCP] 客户端已断开");
    emit logMessage(QStringLiteral("[TCP] 客户端断开"));
    emit clientCountChanged(m_clientBuffers.size());
}
