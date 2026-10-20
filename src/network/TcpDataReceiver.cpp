#include "network/TcpDataReceiver.h"
#include "common/AppLogger.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

TcpDataReceiver::TcpDataReceiver(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &TcpDataReceiver::onNewConnection);
    connect(&m_idleTimer, &QTimer::timeout, this, &TcpDataReceiver::dropIdleClients);
    m_idleTimer.setInterval(30'000);
}

void TcpDataReceiver::setIdleTimeoutMs(int ms)
{
    m_idleTimeoutMs = qMax(100, ms);
    m_idleTimer.setInterval(qBound(50, m_idleTimeoutMs / 2, 30'000));
}

void TcpDataReceiver::dropIdleClients()
{
    QList<QTcpSocket *> idle;
    for (auto it = m_clientBuffers.cbegin(); it != m_clientBuffers.cend(); ++it)
        if (it.value().lastActivity.hasExpired(m_idleTimeoutMs)) idle << it.key();
    for (QTcpSocket *sock : std::as_const(idle))
        dropClient(sock, QStringLiteral("超过 %1 秒无数据").arg(m_idleTimeoutMs / 1000));
}

void TcpDataReceiver::dropClient(QTcpSocket *sock, const QString &reason)
{
    if (!m_clientBuffers.remove(sock)) return;
    LOG_WARN("[TCP] 断开客户端 {}: {}", sock->peerAddress().toString().toStdString(), reason.toStdString());
    emit logMessage(QStringLiteral("[TCP] 断开客户端: %1").arg(reason));
    sock->disconnect(this);
    sock->abort();
    sock->deleteLater();
    emit clientCountChanged(m_clientBuffers.size());
}

void TcpDataReceiver::rejectConnection(QTcpSocket *sock, const QByteArray &message)
{
    // 先发出拒绝原因再断开；断开完成后再删除，否则未发出的数据会随套接字一起丢失
    connect(sock, &QAbstractSocket::disconnected, sock, &QObject::deleteLater);
    sock->write(message);
    sock->flush();
    sock->disconnectFromHost();
    if (sock->state() == QAbstractSocket::UnconnectedState) sock->deleteLater();
}

void TcpDataReceiver::reply(QTcpSocket *sock, const QByteArray &line)
{
    if (sock->bytesToWrite() + line.size() > MaxPendingWriteBytes) {
        dropClient(sock, QStringLiteral("未读取的回包超过 1 MB"));
        return;
    }
    sock->write(line);
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

    m_idleTimer.start();
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
    m_idleTimer.stop();

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

        if (!NetworkAccess::isAllowed(sock->peerAddress(), m_allowList)) {
            LOG_WARN("[TCP] 来源 {} 不在白名单内，拒绝连接", NetworkAccess::peerKey(sock->peerAddress()).toStdString());
            rejectConnection(sock, "{\"status\":\"ERROR\",\"message\":\"Access denied\"}\n");
            continue;
        }
        if (m_clientBuffers.size() >= MaxClients) {
            LOG_WARN("[TCP] 达到最大客户端数 {}，拒绝新连接", MaxClients);
            rejectConnection(sock, "{\"status\":\"ERROR\",\"message\":\"Too many connections\"}\n");
            continue;
        }

        ClientState state;
        state.lastActivity.start();
        m_clientBuffers.insert(sock, state);
        sock->setSocketOption(QAbstractSocket::KeepAliveOption, 1);

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

    ClientState &state = m_clientBuffers[sock];
    state.lastActivity.restart();
    state.buffer.append(sock->readAll());

    // 协议规范：以换行符 '\n' 分包
    qsizetype consumed = 0;
    while (true) {
        const qsizetype newlineIndex = state.buffer.indexOf('\n', consumed);
        if (newlineIndex < 0) break;
        const QByteArray line = state.buffer.mid(consumed, newlineIndex - consumed).trimmed();
        consumed = newlineIndex + 1;
        if (line.isEmpty()) continue;
        if (line.size() > MaxLineBytes) {
            dropClient(sock, QStringLiteral("单条报文超过 %1 KB").arg(MaxLineBytes / 1024));
            return;
        }
        handleLine(sock, line);
        if (!m_clientBuffers.contains(sock)) return; // 回包积压被断开
    }
    // 一次性移除已处理部分，避免逐行 remove 造成的重复内存搬移
    m_clientBuffers[sock].buffer.remove(0, consumed);

    // 防御无换行垃圾数据耗尽内存
    if (m_clientBuffers[sock].buffer.size() > MaxLineBytes) {
        dropClient(sock, QStringLiteral("无换行数据超过 %1 KB").arg(MaxLineBytes / 1024));
    }
}

void TcpDataReceiver::handleLine(QTcpSocket *sock, const QByteArray &line)
{
    QJsonParseError parseError{};
    const QJsonDocument doc = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        LOG_WARN("[TCP] JSON 解析失败: 错误={}, 报文({} 字节)前 256 字节={}",
                 parseError.errorString().toStdString(), line.size(), line.left(256).toStdString());
        emit logMessage(QStringLiteral("[TCP] JSON解析失败: %1").arg(parseError.errorString()));
        reply(sock, "{\"status\":\"ERROR\",\"message\":\"Invalid JSON format\"}\n");
        return;
    }

    const QJsonObject obj = doc.object();
    if (!obj.contains(QStringLiteral("carrierId")) || !obj.contains(QStringLiteral("wheels"))) {
        LOG_WARN("[TCP] 报文缺少必要字段 (carrierId 或 wheels): {}", line.left(256).toStdString());
        reply(sock, "{\"status\":\"ERROR\",\"message\":\"Missing carrierId or wheels\"}\n");
        return;
    }

    const int carrierId = obj.value(QStringLiteral("carrierId")).toInt();
    const QJsonArray wheels = obj.value(QStringLiteral("wheels")).toArray();

    LOG_INFO("[TCP] 收到载具 {} 数据包, 包含 {} 轮检测数据", carrierId, wheels.size());
    emit logMessage(QStringLiteral("[TCP] 收到载具 %1 数据包 (轮数=%2)").arg(carrierId).arg(wheels.size()));
    QString processingError;
    bool accepted = true;
    if (batchHandler) {
        accepted = batchHandler(obj, processingError);
    } else {
        emit dataBatchReceived(obj);
    }
    if (!m_clientBuffers.contains(sock)) return; // 处理期间连接已断开

    if (!accepted) {
        const QJsonObject errorObject{
            {QStringLiteral("status"), QStringLiteral("ERROR")},
            {QStringLiteral("message"), processingError.left(512)}
        };
        reply(sock, QJsonDocument(errorObject).toJson(QJsonDocument::Compact) + '\n');
        return;
    }

    reply(sock, QStringLiteral("{\"status\":\"OK\",\"carrierId\":%1,\"wheelCount\":%2}\n")
                    .arg(carrierId).arg(wheels.size()).toUtf8());
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
