#include "network/NetworkAccess.h"

#include <QRegularExpression>

namespace NetworkAccess {

namespace {
QHostAddress normalized(const QHostAddress &address)
{
    bool isV4 = false;
    const quint32 v4 = address.toIPv4Address(&isV4);
    return isV4 ? QHostAddress(v4) : address;
}
} // namespace

QString peerKey(const QHostAddress &address)
{
    return normalized(address).toString();
}

QList<Subnet> parseAllowList(const QString &text, bool &ok, QString &error)
{
    ok = true;
    QList<Subnet> result;
    static const QRegularExpression separators(QStringLiteral("[,;\\s]+"));
    for (const QString &item : text.split(separators, Qt::SkipEmptyParts)) {
        Subnet subnet;
        if (item.contains(u'/')) {
            subnet = QHostAddress::parseSubnet(item);
        } else {
            const QHostAddress address(item);
            if (!address.isNull())
                subnet = {address, address.protocol() == QAbstractSocket::IPv6Protocol ? 128 : 32};
        }
        if (subnet.first.isNull() || subnet.second < 0) {
            ok = false;
            error = QStringLiteral("无法解析的地址: %1").arg(item.left(64));
            continue;
        }
        result << subnet;
    }
    return result;
}

bool isAllowed(const QHostAddress &address, const QList<Subnet> &allowList)
{
    if (allowList.isEmpty()) return true;
    const QHostAddress peer = normalized(address);
    for (const Subnet &subnet : allowList) {
        if (peer.isInSubnet(subnet)) return true;
    }
    return false;
}

bool LoginThrottle::recordFailure(const QString &peer, const QDateTime &now)
{
    prune(now);
    Entry &entry = m_entries[peer];
    if (!entry.windowStart.isValid() || entry.windowStart.secsTo(now) > m_windowSecs) {
        entry.windowStart = now;
        entry.failures = 0;
    }
    ++entry.failures;
    if (entry.failures >= m_maxFailures && !(entry.bannedUntil.isValid() && entry.bannedUntil > now)) {
        entry.bannedUntil = now.addSecs(m_banSecs);
        entry.failures = 0;
        entry.windowStart = QDateTime();
        return true;
    }
    return false;
}

void LoginThrottle::recordSuccess(const QString &peer)
{
    auto it = m_entries.find(peer);
    if (it != m_entries.end() && !(it->bannedUntil.isValid())) m_entries.erase(it);
}

bool LoginThrottle::isBanned(const QString &peer, const QDateTime &now) const
{
    const auto it = m_entries.constFind(peer);
    return it != m_entries.cend() && it->bannedUntil.isValid() && it->bannedUntil > now;
}

void LoginThrottle::prune(const QDateTime &now)
{
    // 防止大量不同来源地址无限增长
    if (m_entries.size() < 4096) return;
    for (auto it = m_entries.begin(); it != m_entries.end();) {
        const bool banActive = it->bannedUntil.isValid() && it->bannedUntil > now;
        const bool windowActive = it->windowStart.isValid() && it->windowStart.secsTo(now) <= m_windowSecs;
        if (!banActive && !windowActive) it = m_entries.erase(it);
        else ++it;
    }
}

} // namespace NetworkAccess
