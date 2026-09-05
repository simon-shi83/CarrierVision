#include "TcpMessageServer.h"
#include "AppLogger.h"
#include <iostream>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QTextStream>
#include <QTimer>

namespace {

bool parseRackCountMessage(const QString &message, QString &rackNumber, int &roundNumber, int &currentTotal)
{
    static const QRegularExpression pattern3(
        QStringLiteral(R"(^\s*([^,，]+)\s*[,，]\s*(\d+)\s*[,，]\s*(\d+)\s*$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m3 = pattern3.match(message);
    if (m3.hasMatch()) {
        rackNumber = m3.captured(1).trimmed();
        bool roundOk = false;
        bool totalOk = false;
        roundNumber = m3.captured(2).toInt(&roundOk);
        currentTotal = m3.captured(3).toInt(&totalOk);
        // 容错：如果捕获到的 rack 字段中包含噪声（例如二进制或前缀），
        // 则尝试提取最后一段连续数字作为实际的架子号。
        {
            static const QRegularExpression lastDigitsRe(QStringLiteral("(\\d+)$"));
            const QRegularExpressionMatch md = lastDigitsRe.match(rackNumber);
            if (md.hasMatch()) {
                rackNumber = md.captured(1);
            } else {
                // 退回到查找最后一个数字段的策略
                static const QRegularExpression anyDigitsRe(QStringLiteral("\\d+"));
                QRegularExpressionMatchIterator it = anyDigitsRe.globalMatch(rackNumber);
                QString last;
                while (it.hasNext()) {
                    last = it.next().captured(0);
                }
                if (!last.isEmpty()) {
                    rackNumber = last;
                }
            }
        }
        bool rackOk = false;
        const int rack = rackNumber.toInt(&rackOk);
        return rackOk && rack >= 1 && rack <= 50 && roundOk && roundNumber >= 0
               && totalOk && currentTotal >= 0;
    }

    // 允许两项格式：rack,currentTotal
    static const QRegularExpression pattern2(
        QStringLiteral(R"(^\s*([^,，]+)\s*[,，]\s*(\d+)\s*$)"),
        QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m2 = pattern2.match(message);
    if (m2.hasMatch()) {
        rackNumber = m2.captured(1).trimmed();
        roundNumber = 0; // 未提供轮号
        bool totalOk = false;
        currentTotal = m2.captured(2).toInt(&totalOk);
        // 同样对两项格式做容错处理，优先取最后的连续数字段
        {
            static const QRegularExpression lastDigitsRe(QStringLiteral("(\\d+)$"));
            const QRegularExpressionMatch md = lastDigitsRe.match(rackNumber);
            if (md.hasMatch()) {
                rackNumber = md.captured(1);
            } else {
                static const QRegularExpression anyDigitsRe(QStringLiteral("\\d+"));
                QRegularExpressionMatchIterator it = anyDigitsRe.globalMatch(rackNumber);
                QString last;
                while (it.hasNext()) {
                    last = it.next().captured(0);
                }
                if (!last.isEmpty()) {
                    rackNumber = last;
                }
            }
        }
        bool rackOk = false;
        const int rack = rackNumber.toInt(&rackOk);
        return rackOk && rack >= 1 && rack <= 50 && totalOk && currentTotal >= 0;
    }
    return false;
}

// 只含数字的心跳包过滤（允许前后空白）
const QRegularExpression heartbeatPattern(QStringLiteral(R"(^\s*\d+\s*$)"));

} // namespace

TcpMessageServer::TcpMessageServer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, [this]() {
        while (m_server.hasPendingConnections()) {
            QTcpSocket *socket = m_server.nextPendingConnection();
            if (!socket) {
                continue;
            }

            if (m_socketBuffers.size() >= MaxConnections) {
                socket->write("BUSY\n");
                socket->disconnectFromHost();
                socket->deleteLater();
                continue;
            }

            socket->setReadBufferSize(MaxBufferSize + 1);
            auto *idleTimer = new QTimer(socket);
            idleTimer->setSingleShot(true);
            idleTimer->setInterval(60'000);
            connect(idleTimer, &QTimer::timeout, socket, &QTcpSocket::disconnectFromHost);
            idleTimer->start();

            m_socketBuffers.insert(socket, {});

            connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
                if (auto *timer = socket->findChild<QTimer *>()) {
                    timer->start();
                }
                handleSocketReadyRead(socket);
            });

            connect(socket, &QTcpSocket::disconnected, this, [this, socket]() {
                processBuffer(socket, true);
                m_socketBuffers.remove(socket);
                socket->deleteLater();
            });
        }
    });
}

bool TcpMessageServer::start(quint16 port)
{
    stop();

    if (!m_server.listen(QHostAddress::Any, port)) {
        LOG_ERROR("TCP 服务启动失败: 端口={}, 原因={}", port, m_server.errorString().toStdString());
        emit statusChanged(QStringLiteral("TCP 服务启动失败: %1").arg(m_server.errorString()));
        emit serverStateChanged(false, 0);
        return false;
    }

    LOG_INFO("TCP 服务启动成功: 监听端口={}", m_server.serverPort());
    emit statusChanged(QStringLiteral("TCP 服务已启动，监听端口 %1").arg(m_server.serverPort()));
    emit serverStateChanged(true, m_server.serverPort());
    return true;
}

void TcpMessageServer::stop()
{
    if (!m_server.isListening()) {
        return;
    }

    const auto sockets = m_socketBuffers.keys();
    for (QTcpSocket *socket : sockets) {
        if (!socket) {
            continue;
        }

        socket->disconnectFromHost();
        socket->deleteLater();
    }

    m_socketBuffers.clear();
    m_server.close();
    LOG_INFO("TCP 服务已停止");
    emit statusChanged(QStringLiteral("TCP 服务已停止"));
    emit serverStateChanged(false, 0);
}

bool TcpMessageServer::isRunning() const
{
    return m_server.isListening();
}

quint16 TcpMessageServer::port() const
{
    return m_server.isListening() ? m_server.serverPort() : 0;
}

void TcpMessageServer::handleSocketReadyRead(QTcpSocket *socket)
{
    if (!socket) {
        return;
    }
    QByteArray &buffer = m_socketBuffers[socket];
    const qsizetype remaining = MaxBufferSize - buffer.size();
    if (remaining < 0 || socket->bytesAvailable() > remaining) {
        LOG_WARN("TCP 客户端发送数据量超过单次限制 ({} 字节)，已断开该连接", MaxBufferSize);
        socket->disconnectFromHost();
        return;
    }
    const QByteArray data = socket->read(remaining);
    if (!data.isEmpty()) {
        buffer.append(data);
        processBuffer(socket, false);
    }
}

void TcpMessageServer::processBuffer(QTcpSocket *socket, bool flushAll)
{
    if (!socket || !m_socketBuffers.contains(socket)) {
        return;
    }
    QByteArray &buffer = m_socketBuffers[socket];

    // 防止客户端发送无换行的超长垃圾数据耗尽内存（上限 64KB）
    if (buffer.size() > MaxBufferSize) {
        LOG_WARN("TCP 接收缓冲区异常超出上限 ({} 字节)，已重置丢弃", buffer.size());
        buffer.clear();
        return;
    }

    // 按行切分处理粘包与分包（支持 \r\n 和 \n）
    int newlineIndex = -1;
    while ((newlineIndex = buffer.indexOf('\n')) >= 0) {
        QByteArray line = buffer.left(newlineIndex).trimmed();
        buffer.remove(0, newlineIndex + 1);

        if (!line.isEmpty()) {
            QString text = QString::fromUtf8(line).trimmed();
            text.replace(QChar(0xFF0C), ','); // 全角逗号转半角
            if (!text.isEmpty() && !heartbeatPattern.match(text).hasMatch()) {
                processMessage(text, socket);
            }
        }
    }

    // socket 断开或被关闭时，若缓冲区还有未以换行结尾的残留数据，尝试最后处理
    if (flushAll && !buffer.isEmpty()) {
        QString text = QString::fromUtf8(buffer).trimmed();
        text.replace(QChar(0xFF0C), ',');
        if (!text.isEmpty() && !heartbeatPattern.match(text).hasMatch()) {
            processMessage(text, socket);
        }
        buffer.clear();
    }
}

void TcpMessageServer::processMessage(const QString &message, QTcpSocket *socket)
{
    if (message.isEmpty()) {
        return;
    }
    // 直接广播原始接收到的消息（不经解析），以便 UI 能直接显示收到的原始字符串
    emit rawMessageReceived(message);
    QString rackNumber;
    int currentTotal = 0;
    int roundNumber = 0;
    if (parseRackCountMessage(message, rackNumber, roundNumber, currentTotal)) {
        QString prefix;
        if (socket) {
            prefix = QStringLiteral("来自 %1:%2 ").arg(socket->peerAddress().toString()).arg(socket->peerPort());
        }
        emit statusChanged(prefix + QStringLiteral("收到 TCP 数据: 架子号=%1, 轮号=%2, 当前总数=%3").arg(rackNumber).arg(roundNumber).arg(currentTotal));
        emit rackMessageReceived(rackNumber, roundNumber, currentTotal);
        return;
    }

    QString prefix;
    if (socket) {
        prefix = QStringLiteral("来自 %1:%2 ").arg(socket->peerAddress().toString()).arg(socket->peerPort());
    }
    LOG_DEBUG("收到无法识别的 TCP 消息: {}", message.toStdString());
    emit statusChanged(prefix + QStringLiteral("收到无法识别的消息: %1").arg(message));
}
