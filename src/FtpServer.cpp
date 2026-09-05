#include "FtpServer.h"
#include "AppLogger.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QFileInfo>
#include <QTextStream>
#include <QTimer>
#include <QRegularExpression>
#include <QCryptographicHash>
#include <QDirIterator>

namespace {

QString ftpLogPrefix()
{
    return QDateTime::currentDateTime().toString(Qt::ISODateWithMs) + QStringLiteral(" [FTP] ");
}

}

// --- FtpControlConnection ---
FtpControlConnection::FtpControlConnection(QTcpSocket *sock, const QString &root, const QMap<QString, QString> &users, bool allowAnonymous, QObject *parent)
    : QObject(parent), m_ctrl(sock), m_root(root), m_cwd(root), m_users(users), m_allowAnonymous(allowAnonymous)
{
    m_ctrl->setReadBufferSize(64 * 1024 + 1);
    m_transferTimer.setSingleShot(true);
    m_transferTimer.setInterval(30'000);
    m_deadlineTimer.setSingleShot(true);
    m_deadlineTimer.setInterval(10 * 60'000);
    auto timeout = [this]() {
        sendReply(426, "Data transfer timed out.");
        shutdown();
    };
    connect(&m_transferTimer, &QTimer::timeout, this, timeout);
    connect(&m_deadlineTimer, &QTimer::timeout, this, timeout);
    m_idleTimer = new QTimer(this);
    m_idleTimer->setSingleShot(true);
    m_idleTimer->setInterval(120'000);
    connect(m_idleTimer, &QTimer::timeout, this, &FtpControlConnection::shutdown);
    m_idleTimer->start();
    connect(m_ctrl, &QTcpSocket::readyRead, this, &FtpControlConnection::onReadyRead);
    connect(m_ctrl, &QTcpSocket::disconnected, this, &FtpControlConnection::onDisconnected);
    emit logMessage(ftpLogPrefix() + QStringLiteral("客户端连接: %1:%2")
        .arg(m_ctrl->peerAddress().toString())
        .arg(m_ctrl->peerPort()));
    sendReply(220, "Simple Qt FTP Server");
}

void FtpControlConnection::shutdown()
{
    if (m_closed) return;
    m_closed = true;
    if (m_idleTimer) m_idleTimer->stop();
    closeDataConnection();
    m_waitingForStore = false;
    m_storeSuccess = false;
    m_storeFailed = false;
    m_storeBytesReceived = 0;
    m_pendingStorePath.clear();

    if (m_storeFile) {
        m_storeFile->remove();
        m_storeFile->deleteLater();
        m_storeFile = nullptr;
    }

    if (m_ctrl) {
        m_ctrl->disconnect(this);
        m_ctrl->abort();
        m_ctrl->deleteLater();
        m_ctrl = nullptr;
    }

    emit connectionClosed();
    deleteLater();
}

void FtpControlConnection::onReadyRead()
{
    if (!m_ctrl) {
        return;
    }
    if (m_idleTimer) m_idleTimer->start();
    // 保护控制连接缓冲区不被无换行的数据耗尽（上限 64KB）
    static constexpr int kMaxCtrlBuf = 64 * 1024;
    const qsizetype remaining = kMaxCtrlBuf - m_buffer.size();
    if (remaining < 0 || m_ctrl->bytesAvailable() > remaining) {
        m_buffer.clear();
        sendReply(500, "Command line too long.");
        if (m_ctrl) m_ctrl->disconnectFromHost();
        return;
    }
    m_buffer.append(m_ctrl->read(remaining));
    while (true) {
        int idx = m_buffer.indexOf("\r\n");
        if (idx < 0) break;
        QByteArray line = m_buffer.left(idx);
        m_buffer.remove(0, idx + 2);
        processCommand(QString::fromUtf8(line));
        if (m_closed || !m_ctrl || m_ctrl->state() != QAbstractSocket::ConnectedState) break;
    }
}

void FtpControlConnection::onDisconnected()
{
    emit logMessage(ftpLogPrefix() + QStringLiteral("客户端断开: %1:%2")
        .arg(m_ctrl ? m_ctrl->peerAddress().toString() : QStringLiteral("<unknown>"))
        .arg(m_ctrl ? m_ctrl->peerPort() : 0));
    shutdown();
}

void FtpControlConnection::sendReply(int code, const QString &text)
{
    if (!m_ctrl) {
        return;
    }
    QString s = QString::number(code) + " " + text + "\r\n";
    emit logMessage(ftpLogPrefix() + QStringLiteral("RSP %1 %2").arg(code).arg(text));
    const QByteArray response = s.toUtf8();
    if (m_ctrl->bytesToWrite() + response.size() > 256 * 1024) { shutdown(); return; }
    m_ctrl->write(response);
}

QString FtpControlConnection::makePasvReply(quint16 port)
{
    // Advertise the interface used by this control connection (multi-NIC safe).
    QHostAddress selected = m_ctrl ? m_ctrl->localAddress() : QHostAddress(QHostAddress::LocalHost);
    bool ipv4 = false;
    const auto address = selected.toIPv4Address(&ipv4);
    selected = ipv4 ? QHostAddress(address) : QHostAddress(QHostAddress::LocalHost);
    QByteArray ip = selected.toString().toUtf8();
    QList<QByteArray> parts = ip.split('.');
    if (parts.size() != 4) {
        // defensive: ensure we return a valid IPv4 tuple
        ip = QHostAddress(QHostAddress::LocalHost).toString().toUtf8();
        parts = ip.split('.');
    }
    quint16 p1 = port / 256;
    quint16 p2 = port % 256;
    QStringList numbers;
    for (auto &b : parts) numbers << QString::fromUtf8(b);
    numbers << QString::number(p1) << QString::number(p2);
    emit logMessage(ftpLogPrefix() + QStringLiteral("PASV advertise: %1 port=%2 -> %3").arg(QString::fromUtf8(ip)).arg(port).arg(numbers.join(',')));
    return numbers.join(",");
}

QString FtpControlConnection::listDirectory(const QString &path)
{
    QStringList lines;
    lines.reserve(1024);
    QDirIterator iterator(path, QDir::NoDotAndDotDot | QDir::AllEntries,
                          QDirIterator::NoIteratorFlags);
    while (iterator.hasNext() && lines.size() < 10'000) {
        iterator.next();
        const QFileInfo fi = iterator.fileInfo();
        QString perms = fi.isDir() ? "drwxr-xr-x" : "-rw-r--r--";
        QString t = QString("%1 1 owner group %2 %3 %4")
                .arg(perms)
                .arg(fi.size())
                .arg(fi.lastModified().toString("MMM dd yyyy"))
                .arg(fi.fileName());
        lines << t;
    }
    if (iterator.hasNext()) lines << "-rw-r--r-- 1 owner group 0 ...listing-truncated...";
    return lines.join("\r\n") + "\r\n";
}

void FtpControlConnection::attachDataSocket(QTcpSocket *socket)
{
    if (!socket) return;
    socket->setParent(this);
    socket->setReadBufferSize(256 * 1024);
    if (m_dataSocket && m_dataSocket != socket) {
        m_dataSocket->disconnect(this);
        m_dataSocket->deleteLater();
    }
    m_dataSocket = socket;
    m_transferTimer.start();
    connect(socket, &QTcpSocket::bytesWritten, this, [this](qint64 bytes) {
        if (bytes > 0) { m_transferTimer.start(); if (m_idleTimer) m_idleTimer->start(); }
        pumpDownload();
    });
    emit logMessage(ftpLogPrefix() + QStringLiteral("attachDataSocket: peer=%1:%2 state=%3")
        .arg(m_dataSocket->peerAddress().toString())
        .arg(m_dataSocket->peerPort())
        .arg(m_dataSocket->state()));
    connect(m_dataSocket, &QTcpSocket::readyRead, this, &FtpControlConnection::onDataReadyRead);
    connect(m_dataSocket, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError err) {
        if (err != QAbstractSocket::RemoteHostClosedError) {
            emit logMessage(ftpLogPrefix() + QStringLiteral("数据连接异常: %1").arg(err));
            m_storeSuccess = false;
            m_storeFailed = true;
        }
    });
    connect(m_dataSocket, &QTcpSocket::disconnected, this, [this]() {
        if (m_sending) { finishDownload(false); return; }
        // Drain bytes delivered together with FIN before deciding upload success.
        onDataReadyRead();
        if (m_waitingForStore && !m_storeFailed && m_storeBytesReceived > 0 && m_storeFile
            && m_storeFile->error() == QFileDevice::NoError) {
            if (m_dataSocket && (m_dataSocket->error() == QAbstractSocket::UnknownSocketError ||
                                 m_dataSocket->error() == QAbstractSocket::RemoteHostClosedError)) {
                m_storeSuccess = true;
            }
        }
        if (m_waitingForStore) {
            finishDataTransferAndCleanup();
        } else {
            closeDataConnection();
        }
    });
    QTimer::singleShot(0, this, [this]() { onDataReadyRead(); pumpDownload(); });
}

bool passwordMatches(const QString &password, const QString &stored)
{
    if (!stored.startsWith(QStringLiteral("sha256$"))) return password == stored;
    const QStringList fields = stored.split(u'$');
    if (fields.size() != 3) return false;
    const QByteArray salt = QByteArray::fromHex(fields.at(1).toLatin1());
    const QByteArray expected = QByteArray::fromHex(fields.at(2).toLatin1());
    QByteArray digest = password.toUtf8();
    for (int i = 0; i < 20'000; ++i) {
        digest = QCryptographicHash::hash(salt + digest, QCryptographicHash::Sha256);
    }
    if (digest.size() != expected.size()) return false;
    unsigned char difference = 0;
    for (qsizetype i = 0; i < digest.size(); ++i) {
        difference |= static_cast<unsigned char>(digest.at(i) ^ expected.at(i));
    }
    return difference == 0;
}

void FtpControlConnection::closeDataConnection()
{
    m_transferTimer.stop();
    m_deadlineTimer.stop();
    m_connecting = false;
    m_sending = false;
    m_listing.clear();
    if (m_download) { delete m_download; m_download = nullptr; }
    if (m_pasvServer) {
        m_pasvServer->close();
        m_pasvServer->deleteLater();
        m_pasvServer = nullptr;
    }
    if (m_dataSocket) {
        m_dataSocket->disconnect(this);
        m_dataSocket->abort();
        m_dataSocket->deleteLater();
        m_dataSocket = nullptr;
    }
}

void FtpControlConnection::startActiveConnection(const QHostAddress &address, quint16 port)
{
    closeDataConnection();
    auto *socket = new QTcpSocket(this);
    attachDataSocket(socket);
    m_connecting = true;
    m_transferTimer.start(5000);
    connect(socket, &QTcpSocket::connected, this, [this]() {
        m_connecting = false;
        m_transferTimer.start();
        sendReply(200, "Active data connection ready.");
    });
    connect(socket, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (m_connecting) {
            sendReply(425, "Can't open active data connection.");
            closeDataConnection();
        }
    });
    socket->connectToHost(address, port);
}

void FtpControlConnection::finishDownload(bool success)
{
    if (!m_sending) return;
    sendReply(success ? 226 : 426, success ? "Transfer complete." : "Transfer aborted.");
    closeDataConnection();
}

void FtpControlConnection::pumpDownload()
{
    if (!m_sending || !m_dataSocket || m_dataSocket->state() != QAbstractSocket::ConnectedState) return;
    // One bounded chunk per callback, with backpressure from bytesWritten.
    if (m_dataSocket->bytesToWrite() != 0) return;
    QByteArray chunk;
    if (m_download) {
        if (m_download->atEnd()) { finishDownload(true); return; }
        chunk = m_download->read(64 * 1024);
        if (chunk.isEmpty()) { finishDownload(false); return; }
    } else {
        if (m_listing.isEmpty()) { finishDownload(true); return; }
        chunk = m_listing.left(64 * 1024);
        m_listing.remove(0, chunk.size());
    }
    if (m_dataSocket->write(chunk) != chunk.size()) finishDownload(false);
}

void FtpControlConnection::finishDataTransferAndCleanup(bool sendStoreReply)
{
    const QString finalPath = m_pendingStorePath;
    if (!sendStoreReply) {
        m_storeSuccess = false;
    }

    bool finalizeOk = false;
    if (m_storeFile) {
        if (m_storeSuccess && m_storeBytesReceived > 0
            && m_storeFile->error() == QFileDevice::NoError) {
            if (m_storeFile->flush()) {
                const QString temporaryPath = m_storeFile->fileName();
                m_storeFile->close();
                finalizeOk = uploadHandler && uploadHandler(temporaryPath, finalPath);
            }
        } else {
            m_storeFile->remove();
        }
        m_storeFile->deleteLater();
        m_storeFile = nullptr;
    }

    m_storeSuccess = finalizeOk;
    if (!finalPath.isEmpty()) {
        if (!finalizeOk) {
            emit logMessage(ftpLogPrefix() + QStringLiteral("上传中断或提交失败，未替换目标文件: %1 (bytes=%2)")
                                .arg(finalPath)
                                .arg(m_storeBytesReceived));
        }

        QFileInfo fi(finalPath);
        emit logMessage(ftpLogPrefix() + QStringLiteral("上传处理完成: %1 (%2 bytes) finalized=%3")
            .arg(finalPath)
            .arg(fi.exists() ? fi.size() : 0)
            .arg(finalizeOk ? QStringLiteral("Y") : QStringLiteral("N")));
        if (finalizeOk) {
            // notify listeners that an image file has been stored
            emit imageStored(finalPath);
        }
    }

    if (sendStoreReply && m_waitingForStore) {
        m_waitingForStore = false;
        if (m_storeSuccess) {
            sendReply(226, "Transfer complete.");
        } else {
            sendReply(451, "Upload not accepted. Check server status and retry.");
        }
    }
    m_waitingForStore = false;
    m_storeSuccess = false;
    m_storeFailed = false;
    m_storeBytesReceived = 0;
    m_pendingStorePath.clear();
    closeDataConnection();
}

void FtpControlConnection::onPasvNewConnection()
{
    if (!m_pasvServer) return;
    QTcpSocket *s = m_pasvServer->nextPendingConnection();
    if (!s) return;
    // 被动模式的数据连接也必须来自控制连接的同一客户端，防止第三方
    // 抢占临时端口并读取目录/文件或注入上传内容。
    if (m_dataSocket || !m_ctrl || !s->peerAddress().isEqual(m_ctrl->peerAddress(), QHostAddress::ConvertV4MappedToIPv4)) {
        emit logMessage(ftpLogPrefix() + QStringLiteral("拒绝非控制端来源的数据连接: %1")
                            .arg(s->peerAddress().toString()));
        s->abort();
        s->deleteLater();
        return;
    }
    emit logMessage(ftpLogPrefix() + QStringLiteral("onPasvNewConnection: incoming data connection from %1:%2")
        .arg(s->peerAddress().toString()).arg(s->peerPort()));
    attachDataSocket(s);
    m_pasvServer->close();
    pumpDownload();
}

void FtpControlConnection::onDataReadyRead()
{
    if (!m_waitingForStore) return;
    if (m_idleTimer) m_idleTimer->start();
    m_transferTimer.start();
    if (!m_dataSocket || !m_storeFile) return;
    while (m_dataSocket && m_storeFile && m_dataSocket->bytesAvailable() > 0) {
        const qint64 remaining = MaxUploadBytes - m_storeBytesReceived;
        if (remaining <= 0) {
            m_storeSuccess = false;
            m_storeFailed = true;
            m_dataSocket->abort();
            return;
        }
        const QByteArray data = m_dataSocket->read(qMin<qint64>(256 * 1024, remaining + 1));
        if (data.isEmpty()) break;
        if (data.size() > remaining || m_storeFile->write(data) != data.size()) {
            m_storeSuccess = false;
            m_storeFailed = true;
            emit logMessage(ftpLogPrefix() + QStringLiteral("上传写入失败或超出大小限制: %1")
                                .arg(m_pendingStorePath));
            m_dataSocket->abort();
            return;
        }
        m_storeBytesReceived += data.size();
    }
}

void FtpControlConnection::processCommand(const QString &cmdLine)
{
    QStringList parts = cmdLine.split(' ', Qt::SkipEmptyParts);
    if (parts.isEmpty()) return;
    QString cmd = parts[0].toUpper();
    if (m_closed || !m_ctrl) return;
    if ((m_waitingForStore || m_sending || m_connecting) && cmd != "QUIT" && cmd != "NOOP" && cmd != "ABOR") {
        sendReply(503, "A data transfer is already active.");
        return;
    }
    if (cmd == "ABOR") {
        finishDataTransferAndCleanup(false);
        sendReply(226, "Transfer cancelled.");
        return;
    }
    QString arg = parts.mid(1).join(' ');

    // 常见客户端命令别名兼容
    if (cmd == "XPWD") cmd = "PWD";
    else if (cmd == "XCWD") cmd = "CWD";
    else if (cmd == "XMKD") cmd = "MKD";

    const QString configuredRoot = QDir::cleanPath(QFileInfo(m_root).absoluteFilePath());
    const QString canonicalRoot = QFileInfo(configuredRoot).canonicalFilePath();
    const QString rootCanonical = canonicalRoot.isEmpty() ? configuredRoot : canonicalRoot;
    auto toVirtualPath = [rootCanonical](const QString &absPath) -> QString {
        const QString cleanAbs = QDir::cleanPath(absPath);
        const QString rootCmp = rootCanonical
#ifdef Q_OS_WIN
                                    .toLower()
#endif
            ;
        const QString absCmp = cleanAbs
#ifdef Q_OS_WIN
                                   .toLower()
#endif
            ;
        if (absCmp == rootCmp) {
            return QStringLiteral("/");
        }
        if (!absCmp.startsWith(rootCmp + '/')) {
            return QStringLiteral("/");
        }
        QString rel = QDir(rootCanonical).relativeFilePath(cleanAbs);
        rel = QDir::fromNativeSeparators(rel);
        if (rel.isEmpty() || rel == QStringLiteral(".")) {
            return QStringLiteral("/");
        }
        if (!rel.startsWith('/')) {
            rel.prepend('/');
        }
        return rel;
    };
    auto resolveWithinRoot = [this, rootCanonical](const QString &input, bool forDirectory) -> QString {
        if (rootCanonical.isEmpty()) {
            return QString();
        }
        QString normalized = input.trimmed();
        if (normalized.isEmpty()) {
            return QDir::cleanPath(m_cwd.absolutePath());
        }
        normalized.replace('\\', '/');
        QString basePath;
        QString rel;
        if (normalized.startsWith('/')) {
            basePath = rootCanonical;
            rel = normalized.mid(1);
        } else {
            basePath = QDir::cleanPath(m_cwd.absolutePath());
            rel = normalized;
        }

        QString candidate = QDir(basePath).filePath(rel);
        candidate = QDir::cleanPath(candidate);
        if (forDirectory && !candidate.endsWith('/')) {
            candidate += '/';
        }

        const QString rootCmp = rootCanonical
#ifdef Q_OS_WIN
                                    .toLower()
#endif
            ;
        const QString candCmp = candidate
#ifdef Q_OS_WIN
                                    .toLower()
#endif
            ;
        if (candCmp == rootCmp || candCmp.startsWith(rootCmp + '/')) {
            if (forDirectory && candidate.endsWith('/')) {
                candidate.chop(1);
            }
            const QString relPath = QDir(rootCanonical).relativeFilePath(candidate);
            QString walked = rootCanonical;
            const QStringList components = relPath.split('/', Qt::SkipEmptyParts);
            for (const QString &component : components) {
                if (component == QStringLiteral(".")) continue;
                if (component.startsWith('.') || component.endsWith(".cv-pending")) return QString();
                walked = QDir(walked).filePath(component);
                const QFileInfo info(walked);
                if (info.exists() && info.isSymbolicLink()) {
                    return QString();
                }
                if (!info.exists()) break;
            }
            const QFileInfo checkInfo(forDirectory ? candidate : QFileInfo(candidate).absolutePath());
            const QString canonicalExisting = checkInfo.canonicalFilePath();
            if (!canonicalExisting.isEmpty()) {
                QString canonicalCmp = canonicalExisting;
#ifdef Q_OS_WIN
                canonicalCmp = canonicalCmp.toLower();
#endif
                if (canonicalCmp != rootCmp && !canonicalCmp.startsWith(rootCmp + '/')) {
                    return QString();
                }
            }
            return candidate;
        }
        return QString();
    };

    // 记录所有命令（密码用 * 遮盖），并附带会话 id
    const QString logArg = (cmd == QStringLiteral("PASS")) ? QStringLiteral("***") : arg.left(512);
    quint32 sid = 0;
    bool ok = false;
    QVariant p = QVariant::fromValue((qulonglong)0);
    if (this->property("sessionId").isValid()) p = this->property("sessionId");
    if (p.isValid()) sid = static_cast<quint32>(p.toULongLong(&ok));
    const QString peer = m_ctrl ? m_ctrl->peerAddress().toString() : QStringLiteral("-");
    emit logMessage(ftpLogPrefix() + QStringLiteral("[s%1][%2] CMD %3 %4").arg(sid).arg(peer).arg(cmd).arg(logArg).trimmed());

    // 强制登录鉴权校验：未登录状态下只允许基础协商和认证命令
    if (!m_loggedIn) {
        if (cmd != "USER" && cmd != "PASS" && cmd != "QUIT" && cmd != "NOOP" && cmd != "FEAT" && cmd != "SYST" && cmd != "AUTH" && cmd != "OPTS") {
            sendReply(530, "Please login with USER and PASS first.");
            return;
        }
    }

    if (cmd == "USER") {
        m_loggedIn = false;
        m_user.clear();
        if (m_users.contains(arg)) {
            m_user = arg;
            sendReply(331, "User name okay, need password.");
        } else if (m_allowAnonymous && (arg.compare("anonymous", Qt::CaseInsensitive) == 0)) {
            m_loggedIn = true;
            sendReply(230, "Anonymous login OK.");
        } else {
            m_user.clear();
            ++m_failedLoginAttempts;
            sendReply(530, "Invalid username.");
            if (m_failedLoginAttempts >= 5 && m_ctrl) m_ctrl->disconnectFromHost();
        }
    } else if (cmd == "PASS") {
        if (m_loggedIn) { sendReply(230, "Already logged in."); }
        else if (!m_user.isEmpty() && passwordMatches(arg, m_users.value(m_user))) {
            m_loggedIn = true;
            m_failedLoginAttempts = 0;
            sendReply(230, "User logged in, proceed.");
        } else {
            ++m_failedLoginAttempts;
            sendReply(530, "Login incorrect.");
            if (m_failedLoginAttempts >= 5 && m_ctrl) m_ctrl->disconnectFromHost();
        }
    } else if (cmd == "SYST") {
        sendReply(215, "UNIX Type: L8");
    } else if (cmd == "FEAT") {
        sendReply(211, "Features: UTF8, PASV, EPSV");
    } else if (cmd == "OPTS") {
        sendReply(200, "Option okay.");
    } else if (cmd == "AUTH") {
        sendReply(534, "TLS not supported.");
    } else if (cmd == "PBSZ") {
        sendReply(200, "PBSZ=0");
    } else if (cmd == "PROT") {
        sendReply(200, "Protection set.");
    } else if (cmd == "PWD") {
        const QString virtualPwd = toVirtualPath(m_cwd.absolutePath());
        sendReply(257, QStringLiteral("\"%1\"").arg(virtualPwd));
    } else if (cmd == "CWD") {
        const QString targetPath = arg.isEmpty() ? rootCanonical : resolveWithinRoot(arg, true);
        if (targetPath.isEmpty()) {
            sendReply(550, "Invalid path.");
        } else {
            QDir d(targetPath);
            if (d.exists()) {
                m_cwd = d;
                sendReply(250, "Directory changed.");
            } else {
                sendReply(550, "Failed to change directory.");
            }
        }
    } else if (cmd == "MKD") {
        if (arg.isEmpty()) { sendReply(501, "No directory name."); return; }
        const QString targetPath = resolveWithinRoot(arg, true);
        emit logMessage(ftpLogPrefix() + QStringLiteral("[s%1][%2] MKD debug: arg='%3' resolved='%4'")
            .arg(this->property("sessionId").toULongLong())
            .arg(m_ctrl ? m_ctrl->peerAddress().toString() : QStringLiteral("-"))
            .arg(arg)
            .arg(targetPath));
        if (targetPath.isEmpty()) {
            sendReply(550, "Invalid path.");
            return;
        }
        if (QDir().mkpath(targetPath)) {
            sendReply(257, QStringLiteral("\"%1\" created.").arg(toVirtualPath(targetPath)));
            emit logMessage(ftpLogPrefix() + QStringLiteral("创建目录: %1").arg(targetPath));
        } else {
            sendReply(550, "Create directory failed.");
        }
    } else if (cmd == "TYPE") {
        sendReply(200, "Type set.");
    } else if (cmd == "PORT") {
        const QStringList nums = arg.split(',', Qt::SkipEmptyParts);
        if (nums.size() != 6) { sendReply(501, "Invalid PORT argument."); return; }
        for (int i = 0; i < 4; ++i) {
            bool octetOk = false;
            const int octet = nums.at(i).toInt(&octetOk);
            if (!octetOk || octet < 0 || octet > 255) {
                sendReply(501, "Invalid PORT argument.");
                return;
            }
        }
        bool ok1 = false, ok2 = false;
        const int p1 = nums[4].toInt(&ok1);
        const int p2 = nums[5].toInt(&ok2);
        if (!ok1 || !ok2 || p1 < 0 || p1 > 255 || p2 < 0 || p2 > 255) { sendReply(501, "Invalid PORT argument."); return; }
        const QString host = QStringLiteral("%1.%2.%3.%4").arg(nums[0], nums[1], nums[2], nums[3]);
        const QHostAddress activeAddress(host);
        const int activePort = p1 * 256 + p2;
        if (activeAddress.isNull() || activePort <= 0 || !m_ctrl
            || !activeAddress.isEqual(m_ctrl->peerAddress(), QHostAddress::ConvertV4MappedToIPv4)) {
            sendReply(501, "Active data address must match the control peer.");
            return;
        }
        const quint16 port = static_cast<quint16>(activePort);

        startActiveConnection(activeAddress, port);
    } else if (cmd == "EPRT") {
        if (arg.size() < 5) { sendReply(501, "Invalid EPRT argument."); return; }
        const QChar delim = arg.at(0);
        const QStringList partsE = arg.split(delim, Qt::KeepEmptyParts);
        if (partsE.size() < 4) { sendReply(501, "Invalid EPRT argument."); return; }
        const QString host = partsE.at(2).trimmed();
        bool okPort = false;
        const int parsedPort = partsE.at(3).trimmed().toInt(&okPort);
        const QHostAddress activeAddress(host);
        if (!okPort || parsedPort <= 0 || parsedPort > 65535 || activeAddress.isNull() || !m_ctrl
            || !activeAddress.isEqual(m_ctrl->peerAddress(), QHostAddress::ConvertV4MappedToIPv4)) { sendReply(501, "Invalid EPRT argument."); return; }
        const quint16 port = static_cast<quint16>(parsedPort);

        startActiveConnection(activeAddress, port);
    } else if (cmd == "PASV") {
        closeDataConnection();
        m_transferTimer.start();
        if (m_dataSocket) {
            m_dataSocket->disconnect(this);
            m_dataSocket->deleteLater();
            m_dataSocket = nullptr;
        }
        if (m_pasvServer) { m_pasvServer->close(); delete m_pasvServer; m_pasvServer = nullptr; }
        m_pasvServer = new QTcpServer(this);
        connect(m_pasvServer, &QTcpServer::newConnection, this, &FtpControlConnection::onPasvNewConnection);
        if (!m_pasvServer->listen(QHostAddress::Any, 0)) {
            sendReply(425, "Can't open data connection.");
            return;
        }
        quint16 port = m_pasvServer->serverPort();
        QString nums = makePasvReply(port);
        sendReply(227, "Entering Passive Mode (" + nums + ")");
    } else if (cmd == "EPSV") {
        closeDataConnection();
        m_transferTimer.start();
        if (m_dataSocket) {
            m_dataSocket->disconnect(this);
            m_dataSocket->deleteLater();
            m_dataSocket = nullptr;
        }
        if (m_pasvServer) { m_pasvServer->close(); delete m_pasvServer; m_pasvServer = nullptr; }
        m_pasvServer = new QTcpServer(this);
        connect(m_pasvServer, &QTcpServer::newConnection, this, &FtpControlConnection::onPasvNewConnection);
        if (!m_pasvServer->listen(QHostAddress::Any, 0)) {
            sendReply(425, "Can't open data connection.");
            return;
        }
        const quint16 port = m_pasvServer->serverPort();
        sendReply(229, QStringLiteral("Entering Extended Passive Mode (|||%1|)").arg(port));
    } else if (cmd == "LIST" || cmd == "RETR") {
        if (!m_pasvServer && !m_dataSocket) { sendReply(425, "Use PASV/PORT first."); return; }
        if (cmd == "RETR") {
            const QString path = resolveWithinRoot(arg, false);
            if (arg.isEmpty() || path.isEmpty() || !QFileInfo(path).isFile()) { sendReply(550, "Invalid file."); return; }
            m_download = new QFile(path, this);
            if (!m_download->open(QIODevice::ReadOnly)) {
                delete m_download; m_download = nullptr;
                sendReply(550, "Can't open file."); return;
            }
        } else {
            m_listing = listDirectory(m_cwd.absolutePath()).toUtf8();
        }
        m_sending = true;
        m_transferTimer.start();
        m_deadlineTimer.start();
        sendReply(150, "Opening data connection.");
        pumpDownload();
    } else if (cmd == "STOR") {
        if (arg.isEmpty()) { sendReply(501, "No filename."); return; }
        if (m_waitingForStore) { sendReply(503, "Another upload is already active."); return; }
        if (!m_pasvServer && !m_dataSocket) { sendReply(425, "Use PASV/PORT first."); return; }
        QString path = resolveWithinRoot(arg, false);
        emit logMessage(ftpLogPrefix() + QStringLiteral("[s%1][%2] STOR debug: arg='%3' resolved='%4'")
            .arg(this->property("sessionId").toULongLong())
            .arg(m_ctrl ? m_ctrl->peerAddress().toString() : QStringLiteral("-"))
            .arg(arg)
            .arg(path));
        if (path.isEmpty()) { sendReply(550, "Invalid path."); return; }
        QDir().mkpath(QFileInfo(path).absolutePath());
        m_pendingStorePath = path;
        m_storeSuccess = false;
        m_storeFailed = false;
        m_storeBytesReceived = 0;
        m_storeFile = new QTemporaryFile(QDir(QFileInfo(path).absolutePath()).filePath(".cv-upload-XXXXXX"), this);
        if (!m_storeFile->open()) {
            delete m_storeFile;
            m_storeFile = nullptr;
            emit logMessage(ftpLogPrefix() + QStringLiteral("无法创建临时文件: %1").arg(m_pendingStorePath));
            sendReply(550, "Can't open file for writing: " + path);
            return;
        }
        emit logMessage(ftpLogPrefix() + QStringLiteral("开始接收上传: %1").arg(m_pendingStorePath));
        m_waitingForStore = true;
        m_transferTimer.start();
        m_deadlineTimer.start();
        sendReply(150, "Ok to send data.");
        if (m_dataSocket && m_dataSocket->bytesAvailable() > 0) {
            onDataReadyRead();
        }
        // 纯异步：客户端可在 STOR 后稍后建立数据连接，
        // onPasvNewConnection/onDataReadyRead 会接管后续写入与结束回复。
    } else if (cmd == "NOOP") {
        sendReply(200, "OK");
    } else if (cmd == "QUIT") {
            sendReply(221, "Goodbye.");
        if (m_ctrl) m_ctrl->disconnectFromHost();
    } else {
        sendReply(502, "Command not implemented.");
    }
}

// --- FtpServer ---
FtpServer::FtpServer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server, &QTcpServer::newConnection, this, &FtpServer::onNewConnection);
}

bool FtpServer::isRunning() const
{
    return m_server.isListening();
}

int FtpServer::clientCount() const
{
    return m_clientCount;
}

bool FtpServer::listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QMap<QString, QString> &users, bool allowAnonymous)
{
    m_rootDir = rootDir;
    m_users = users;
    m_allowAnonymous = allowAnonymous;
    if (!m_server.listen(addr, port)) {
        LOG_ERROR("FTP 底层监听失败: 地址={}, 端口={}", addr.toString().toStdString(), port);
        emit logMessage(ftpLogPrefix() + QStringLiteral("FTP listen failed: port=%1 root=%2").arg(port).arg(rootDir));
        return false;
    }
    emit runningChanged(true);
    emit logMessage(ftpLogPrefix() + QStringLiteral("FTP 服务启动: port=%1 root=%2").arg(port).arg(rootDir));
    LOG_INFO("FTP 底层监听成功: 端口={}, 根目录={}", port, rootDir.toStdString());
    return true;
}

bool FtpServer::listen(const QHostAddress &addr, quint16 port, const QString &rootDir, const QString &user, const QString &pass)
{
    QMap<QString, QString> map;
    if (!user.isEmpty()) map.insert(user, pass);
    return listen(addr, port, rootDir, map, false);
}

void FtpServer::stop()
{
    // Ensure all active control/data sessions are closed, otherwise process
    // can linger on exit while sockets are still alive.
    const QList<FtpControlConnection*> sessions = findChildren<FtpControlConnection*>();
    for (FtpControlConnection *session : sessions) {
        if (session) {
            session->shutdown();
        }
    }

    if (m_server.isListening()) {
        m_server.close();
    }

    m_clientCount = 0;
    emit clientCountChanged(m_clientCount);
    emit runningChanged(false);
    emit logMessage(ftpLogPrefix() + QStringLiteral("FTP 服务停止"));
    LOG_INFO("FTP 底层服务已停止");
}

void FtpServer::setUsers(const QMap<QString, QString> &users, bool allowAnonymous)
{
    if (m_users == users && m_allowAnonymous == allowAnonymous) return;
    m_users = users;
    m_allowAnonymous = allowAnonymous;
    // Credentials are snapshots per session: revoke them immediately on change.
    for (auto *session : findChildren<FtpControlConnection *>()) session->shutdown();
}

void FtpServer::onNewConnection()
{
    while (m_server.hasPendingConnections()) {
        QTcpSocket *sock = m_server.nextPendingConnection();
        if (!sock) continue;
        if (m_clientCount >= MaxClients) {
            sock->write("421 Too many connections.\r\n");
            sock->disconnectFromHost();
            sock->deleteLater();
            continue;
        }
        sock->setReadBufferSize(64 * 1024 + 1);
        // create connection handler
        auto *conn = new FtpControlConnection(sock, m_rootDir, m_users, m_allowAnonymous, this);
        conn->uploadHandler = uploadHandler;
        // log client connect with session id and peer address when available
        const QString peer = sock->peerAddress().toString();
        const quint32 sid = static_cast<quint32>(reinterpret_cast<quintptr>(conn) & 0xffffffff);
        conn->moveToThread(this->thread());
        conn->setProperty("sessionId", (qulonglong)sid);
        emit logMessage(ftpLogPrefix() + QStringLiteral("New connection: session=%1 peer=%2").arg(sid).arg(peer));
        LOG_DEBUG("FTP 客户端建立连接: session={} peer={}", sid, peer.toStdString());
        ++m_clientCount;
        emit clientCountChanged(m_clientCount);
        connect(conn, &FtpControlConnection::connectionClosed, this, [this]() {
            if (m_clientCount > 0) {
                --m_clientCount;
            }
            emit clientCountChanged(m_clientCount);
        });
        connect(conn, &FtpControlConnection::logMessage, this, &FtpServer::logMessage);
        // forward stored image notifications
        connect(conn, &FtpControlConnection::imageStored, this, &FtpServer::imageStored);
    }
}
