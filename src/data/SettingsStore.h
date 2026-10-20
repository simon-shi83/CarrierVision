#pragma once

#include <QMap>
#include <QSqlDatabase>
#include <QString>
#include <QVariantList>
#include <QVector>

// 持久化配置：FTP 账户/目录/端口与相机槽位映射、设置页密码、载具标准轮距。
// 无状态，调用方提供当前线程可用的数据库连接并负责加锁。
namespace SettingsStore {

constexpr int kMaxFtpUsers = 32;
constexpr int kSlotCount = 12;
constexpr int kMaxSlotTarget = 14;

struct FtpSettings {
    QMap<QString, QString> users;   // 用户名 -> 密码哈希
    QString root;                   // 规范化后的根目录；不安全时为空
    int port = 21;
    QVector<int> slotMapping;       // kSlotCount 项，取值 1..kMaxSlotTarget
};

// 读取 FTP 配置；defaultPort 用于库中端口缺失或越界时。会把历史的 archive 根目录迁移为 images。
FtpSettings loadFtpSettings(QSqlDatabase &db, int defaultPort);
// 在一个事务中保存端口、根目录、账户与槽位映射；失败时回滚并给出原因
bool saveFtpSettings(QSqlDatabase &db, const FtpSettings &settings, QString &error);
QVector<int> defaultSlotMapping();

bool verifySettingsPassword(QSqlDatabase &db, const QString &password);
// 新密码至少 6 位且当前密码正确才写入
bool changeSettingsPassword(QSqlDatabase &db, const QString &currentPassword, const QString &newPassword);
bool resetSettingsPassword(QSqlDatabase &db);

// 维护口令：独立于设置密码，用于忘记设置密码时授权重置。默认未设置，未设置时校验总是失败。
bool hasMaintenancePassword(QSqlDatabase &db);
bool verifyMaintenancePassword(QSqlDatabase &db, const QString &password);
// 需当前设置密码正确；新口令至少 6 位，且不能与设置密码相同（否则失去独立恢复的意义）
bool setMaintenancePassword(QSqlDatabase &db, const QString &currentSettingsPassword, const QString &newPassword);
// 当前设置密码或维护口令任一正确时，才将设置密码重置为默认
bool resetSettingsPasswordAuthorized(QSqlDatabase &db, const QString &password);

// 架号 1..50 的 8 个驱动轮标准轮距（字符串，两位小数），缺失为 "0"
QVariantList rackWheelDistances(QSqlDatabase &db, int rackNumber);
// 全部为非负数字时才在一个事务中写入
bool saveRackWheelDistances(QSqlDatabase &db, int rackNumber, const QVariantList &distances);

} // namespace SettingsStore
