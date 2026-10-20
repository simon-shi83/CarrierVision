#pragma once

#include <QDateTime>
#include <QHash>
#include <QHostAddress>
#include <QList>
#include <QPair>
#include <QString>

// 网络访问控制：来源 IP 白名单与登录失败封禁。
namespace NetworkAccess {

using Subnet = QPair<QHostAddress, int>;

// 解析逗号/分号/空白分隔的地址列表，支持单个 IP 与 CIDR（如 192.168.1.0/24）。
// 空字符串表示不限制（返回空列表）。有无法解析的项时 ok 为 false，error 给出该项。
QList<Subnet> parseAllowList(const QString &text, bool &ok, QString &error);
// 列表为空时允许所有来源；IPv4 映射的 IPv6 地址按 IPv4 比较
bool isAllowed(const QHostAddress &address, const QList<Subnet> &allowList);

// 按来源 IP 统计登录失败：window 内失败达到 maxFailures 次即封禁 banDuration。
class LoginThrottle
{
public:
    LoginThrottle(int maxFailures = 10, int windowSecs = 600, int banSecs = 900)
        : m_maxFailures(maxFailures), m_windowSecs(windowSecs), m_banSecs(banSecs) {}

    // 记录一次失败；本次导致封禁时返回 true
    bool recordFailure(const QString &peer, const QDateTime &now);
    void recordSuccess(const QString &peer);
    bool isBanned(const QString &peer, const QDateTime &now) const;

private:
    struct Entry {
        int failures = 0;
        QDateTime windowStart;
        QDateTime bannedUntil;
    };
    void prune(const QDateTime &now);

    int m_maxFailures;
    int m_windowSecs;
    int m_banSecs;
    QHash<QString, Entry> m_entries;
};

// 统一的来源地址键：IPv4 映射的 IPv6 地址转为 IPv4 文本
QString peerKey(const QHostAddress &address);

} // namespace NetworkAccess
