#include "data/SettingsStore.h"

#include "common/AgcUtils.h"
#include "common/AppLogger.h"
#include "data/DbSchema.h"

#include <QDir>
#include <QFileInfo>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>

namespace SettingsStore {

namespace {
bool isEncoded(const QString &stored)
{
    return stored.startsWith(QStringLiteral("sha256$"));
}
} // namespace

QVector<int> defaultSlotMapping()
{
    QVector<int> mapping(kSlotCount);
    for (int i = 0; i < kSlotCount; ++i) mapping[i] = i + 1;
    return mapping;
}

FtpSettings loadFtpSettings(QSqlDatabase &db, int defaultPort)
{
    FtpSettings settings;
    settings.port = defaultPort;
    settings.slotMapping = defaultSlotMapping();
    if (!db.isOpen()) return settings;

    QSqlQuery qUsers(db);
    if (qUsers.exec("SELECT username, password_hash, allow_anonymous FROM ftp_users")) {
        while (qUsers.next() && settings.users.size() < kMaxFtpUsers) {
            const QString user = qUsers.value(0).toString();
            const QString hash = qUsers.value(1).toString();
            if (!user.isEmpty() && user.size() <= 64 && !hash.isEmpty() && hash.size() <= 256)
                settings.users.insert(user, hash);
        }
    }

    // 历史/手工写入的明文密码：内存中立即改为哈希，并尽量写回数据库
    for (auto it = settings.users.begin(); it != settings.users.end(); ++it) {
        if (isEncoded(it.value())) continue;
        it.value() = AgcUtils::encodePassword(it.value());
        QSqlQuery upgrade(db);
        upgrade.prepare("UPDATE ftp_users SET password_hash = ?, updated_at = datetime('now','localtime') WHERE username = ?");
        upgrade.addBindValue(it.value());
        upgrade.addBindValue(it.key());
        if (upgrade.exec()) LOG_WARN("FTP 账户 {} 的明文密码已升级为哈希存储", it.key().toStdString());
        else LOG_ERROR("FTP 账户 {} 明文密码升级写库失败: {}", it.key().toStdString(), upgrade.lastError().text().toStdString());
    }

    QString root = DBSchema::getConfig(db, "ftp/rootDirectory", QStringLiteral("images"));
    if (root == QStringLiteral("archive") || root.endsWith(QStringLiteral("/archive"))) {
        root = QStringLiteral("images");
        DBSchema::setConfig(db, "ftp/rootDirectory", root);
    }
    // 保留配置原值（默认相对路径 images），使用时再按程序目录解析，安装目录整体搬迁后仍指向新位置
    settings.root = root.trimmed();
    const QString resolved = AgcUtils::resolveAppPath(settings.root);
    const QString fsRoot = QDir::cleanPath(QDir(resolved).rootPath());
    const QString home = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
    if (resolved.isEmpty() || resolved == fsRoot || resolved == home
        || QFileInfo(resolved).isSymbolicLink()) {
        settings.root.clear();
    }

    const int configuredPort = DBSchema::getConfigInt(db, "ftp/port", defaultPort);
    if (configuredPort >= 1 && configuredPort <= 65535) settings.port = configuredPort;

    QSqlQuery qSlots(db);
    if (qSlots.exec("SELECT slot_id, mapped_target FROM camera_slots ORDER BY slot_id ASC")) {
        while (qSlots.next()) {
            const int slot = qSlots.value(0).toInt();
            if (slot >= 1 && slot <= kSlotCount)
                settings.slotMapping[slot - 1] = qBound(1, qSlots.value(1).toInt(), kMaxSlotTarget);
        }
    }
    return settings;
}

bool saveFtpSettings(QSqlDatabase &db, const FtpSettings &settings, QString &error)
{
    if (!db.isOpen() || !db.transaction()) {
        error = QStringLiteral("FTP 配置保存失败：数据库不可用");
        return false;
    }
    auto fail = [&](const QString &reason) {
        db.rollback();
        error = reason;
        return false;
    };

    if (!DBSchema::setConfig(db, "ftp/port", QString::number(settings.port))
        || !DBSchema::setConfig(db, "ftp/rootDirectory", settings.root)) {
        return fail(QStringLiteral("FTP 配置保存失败"));
    }

    QSqlQuery qDelUsers(db);
    if (!qDelUsers.exec("DELETE FROM ftp_users")) return fail(QStringLiteral("FTP 账户保存失败"));
    QSqlQuery qInsUser(db);
    qInsUser.prepare("INSERT INTO ftp_users(username, password_hash, allow_anonymous, updated_at) VALUES(?, ?, 0, datetime('now','localtime'))");
    for (auto it = settings.users.constBegin(); it != settings.users.constEnd(); ++it) {
        qInsUser.bindValue(0, it.key());
        qInsUser.bindValue(1, it.value());
        if (!qInsUser.exec())
            return fail(QStringLiteral("FTP 账户插入失败: %1").arg(qInsUser.lastError().text()));
    }

    QSqlQuery qInsSlot(db);
    qInsSlot.prepare(R"(
        INSERT INTO camera_slots(slot_id, mapped_target)
        VALUES(?, ?)
        ON CONFLICT(slot_id) DO UPDATE SET mapped_target = excluded.mapped_target
    )");
    for (int i = 0; i < settings.slotMapping.size() && i < kSlotCount; ++i) {
        qInsSlot.bindValue(0, i + 1);
        qInsSlot.bindValue(1, settings.slotMapping.at(i));
        if (!qInsSlot.exec())
            return fail(QStringLiteral("相机槽位保存失败: %1").arg(qInsSlot.lastError().text()));
    }

    if (!db.commit()) return fail(QStringLiteral("FTP 配置提交事务失败"));
    LOG_INFO("保存 FTP 配置至数据库成功, 账户列表: {}", settings.users.keys().join(',').toStdString());
    return true;
}

bool verifySettingsPassword(QSqlDatabase &db, const QString &password)
{
    const QString stored = DBSchema::getConfig(db, "security/settingsPassword");
    const bool ok = !stored.isEmpty() && AgcUtils::verifyEncodedPassword(password, stored);
    if (ok && !isEncoded(stored)
        && DBSchema::setConfig(db, "security/settingsPassword", AgcUtils::encodePassword(password))) {
        LOG_WARN("设置密码由明文存储升级为哈希存储");
    }
    if (ok) LOG_INFO("管理员安全密码验证成功");
    else LOG_WARN("管理员安全密码验证失败");
    return ok;
}

bool changeSettingsPassword(QSqlDatabase &db, const QString &currentPassword, const QString &newPassword)
{
    if (newPassword.size() < 6 || !verifySettingsPassword(db, currentPassword)) {
        LOG_WARN("修改密码被拒绝：当前密码不符或新密码长度不足6位");
        return false;
    }
    const bool success = DBSchema::setConfig(db, "security/settingsPassword",
                                             AgcUtils::encodePassword(newPassword));
    if (success) LOG_INFO("管理员密码修改成功");
    else LOG_ERROR("管理员密码修改写入数据库失败");
    return success;
}

bool resetSettingsPassword(QSqlDatabase &db)
{
    const bool success = DBSchema::setConfig(db, "security/settingsPassword",
                                             AgcUtils::encodePassword(QStringLiteral("123456")));
    LOG_WARN("管理员密码已被重置为默认密码");
    return success;
}

bool hasMaintenancePassword(QSqlDatabase &db)
{
    return isEncoded(DBSchema::getConfig(db, "security/maintenancePassword"));
}

bool verifyMaintenancePassword(QSqlDatabase &db, const QString &password)
{
    const QString stored = DBSchema::getConfig(db, "security/maintenancePassword");
    // 维护口令只接受哈希存储，避免手工写入的明文成为后门
    return isEncoded(stored) && !password.isEmpty() && AgcUtils::verifyEncodedPassword(password, stored);
}

bool setMaintenancePassword(QSqlDatabase &db, const QString &currentSettingsPassword, const QString &newPassword)
{
    if (newPassword.size() < 6 || newPassword == currentSettingsPassword
        || !verifySettingsPassword(db, currentSettingsPassword)) {
        LOG_WARN("设置维护口令被拒绝：设置密码不符、口令不足6位或与设置密码相同");
        return false;
    }
    const bool success = DBSchema::setConfig(db, "security/maintenancePassword",
                                             AgcUtils::encodePassword(newPassword));
    if (success) LOG_INFO("维护口令已更新");
    else LOG_ERROR("维护口令写入数据库失败");
    return success;
}

bool resetSettingsPasswordAuthorized(QSqlDatabase &db, const QString &password)
{
    const bool bySettings = verifySettingsPassword(db, password);
    const bool byMaintenance = !bySettings && verifyMaintenancePassword(db, password);
    if (!bySettings && !byMaintenance) {
        LOG_WARN("重置设置密码被拒绝：口令验证失败");
        return false;
    }
    LOG_WARN("设置密码重置授权方式: {}", bySettings ? "当前设置密码" : "维护口令");
    return resetSettingsPassword(db);
}

QVariantList rackWheelDistances(QSqlDatabase &db, int rackNumber)
{
    QVariantList distances;
    for (int wheel = 0; wheel < 8; ++wheel) distances.append(QStringLiteral("0"));
    if (rackNumber < 1 || rackNumber > 50 || !db.isOpen()) return distances;

    QSqlQuery q(db);
    q.prepare("SELECT wheel_id, standard_distance FROM carrier_wheel_norm WHERE carrier_id = ? ORDER BY wheel_id ASC");
    q.addBindValue(rackNumber);
    if (q.exec()) {
        while (q.next()) {
            const int wheel = q.value(0).toInt();
            if (wheel >= 1 && wheel <= 8)
                distances[wheel - 1] = QString::number(q.value(1).toDouble(), 'f', 2);
        }
    }
    return distances;
}

bool saveRackWheelDistances(QSqlDatabase &db, int rackNumber, const QVariantList &distances)
{
    if (rackNumber < 1 || rackNumber > 50 || distances.isEmpty()) return false;

    QVector<double> values;
    for (const auto &distance : distances) {
        bool ok = false;
        const double value = distance.toString().toDouble(&ok);
        if (!ok || value < 0) return false;
        values.append(value);
    }

    if (!db.isOpen() || !db.transaction()) return false;

    QSqlQuery q(db);
    q.prepare(R"(
        INSERT INTO carrier_wheel_norm(carrier_id, wheel_id, standard_distance, lower_tolerance, updated_at)
        VALUES(?, ?, ?, 0.0, datetime('now', 'localtime'))
        ON CONFLICT(carrier_id, wheel_id) DO UPDATE SET
            standard_distance = excluded.standard_distance,
            updated_at = excluded.updated_at
    )");
    for (int wheel = 0; wheel < values.size(); ++wheel) {
        q.bindValue(0, rackNumber);
        q.bindValue(1, wheel + 1);
        q.bindValue(2, values.at(wheel));
        if (!q.exec()) {
            LOG_ERROR("保存载具轮标准距离失败: 架号={}, 轮号={}, 错误={}",
                      rackNumber, wheel, q.lastError().text().toStdString());
            db.rollback();
            return false;
        }
    }

    if (!db.commit()) {
        db.rollback();
        return false;
    }
    LOG_INFO("保存载具轮标准距离成功: 架号={}", rackNumber);
    return true;
}

} // namespace SettingsStore
