#include "DbSchema.h"
#include "AgcUtils.h"
#include "AppLogger.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSettings>
#include <nlohmann/json.hpp>

QString DBSchema::defaultDatabasePath() {
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString dataDir = appDir + QDir::separator() + QStringLiteral("data");
    QDir().mkpath(dataDir);
    const QString targetDbPath = dataDir + QDir::separator() + QStringLiteral("dataAgc.db");
    const QString oldDbPath = appDir + QDir::separator() + QStringLiteral("dataAgc.db");

    // Auto-relocate legacy root dataAgc.db to data/ if target doesn't exist yet
    if (QFile::exists(oldDbPath) && !QFile::exists(targetDbPath)) {
        if (QFile::rename(oldDbPath, targetDbPath)) {
            LOG_INFO("DBSchema: 自动将根目录数据文件迁移至 data 目录: {} -> {}",
                     oldDbPath.toStdString(), targetDbPath.toStdString());
            const QString oldWal = oldDbPath + QStringLiteral("-wal");
            const QString targetWal = targetDbPath + QStringLiteral("-wal");
            if (QFile::exists(oldWal)) {
                QFile::rename(oldWal, targetWal);
            }
            const QString oldShm = oldDbPath + QStringLiteral("-shm");
            const QString targetShm = targetDbPath + QStringLiteral("-shm");
            if (QFile::exists(oldShm)) {
                QFile::rename(oldShm, targetShm);
            }
        } else {
            LOG_WARN("DBSchema: 迁移根目录数据文件至 data 目录失败，继续使用当前文件");
            return oldDbPath;
        }
    }
    return targetDbPath;
}

QString DBSchema::getConfig(QSqlDatabase &db, const QString &key, const QString &defaultValue) {
    if (!db.isOpen()) return defaultValue;
    QSqlQuery q(db);
    q.prepare("SELECT value FROM system_config WHERE key = ?");
    q.addBindValue(key);
    if (q.exec() && q.next()) {
        return q.value(0).toString();
    }
    return defaultValue;
}

int DBSchema::getConfigInt(QSqlDatabase &db, const QString &key, int defaultValue) {
    bool ok = false;
    int val = getConfig(db, key, QString()).toInt(&ok);
    return ok ? val : defaultValue;
}

bool DBSchema::getConfigBool(QSqlDatabase &db, const QString &key, bool defaultValue) {
    QString val = getConfig(db, key, QString()).toLower().trimmed();
    if (val.isEmpty()) return defaultValue;
    return (val == QStringLiteral("true") || val == QStringLiteral("1"));
}

bool DBSchema::setConfig(QSqlDatabase &db, const QString &key, const QString &value) {
    if (!db.isOpen()) return false;
    QSqlQuery q(db);
    q.prepare(R"(
        INSERT INTO system_config(key, value, updated_at)
        VALUES(?, ?, datetime('now', 'localtime'))
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = excluded.updated_at
    )");
    q.addBindValue(key);
    q.addBindValue(value);
    if (!q.exec()) {
        LOG_ERROR("DBSchema: setConfig 失败: key={}, err={}",
                  key.toStdString(), q.lastError().text().toStdString());
        return false;
    }
    return true;
}

static void migrateLegacyFiles(QSqlDatabase &db) {
    const QString appDir = QCoreApplication::applicationDirPath();

    // 1. config.ini
    const QString iniPath = appDir + QDir::separator() + QStringLiteral("config.ini");
    if (QFile::exists(iniPath)) {
        QSettings settings(iniPath, QSettings::IniFormat);
        auto copyVal = [&](const QString &key, const QString &defVal) {
            if (settings.contains(key)) {
                DBSchema::setConfig(db, key, settings.value(key).toString());
            } else if (!defVal.isEmpty()) {
                if (DBSchema::getConfig(db, key).isEmpty()) {
                    DBSchema::setConfig(db, key, defVal);
                }
            }
        };
        copyVal("ftp/port", "21");
        copyVal("ftp/rootDirectory", "images");
        copyVal("cleanup/keepDays", "90");
        copyVal("cleanup/logKeepDays", "30");
        copyVal("cleanup/runHour", "1");
        copyVal("ui/isDark", "false");
        copyVal("homepage/description", QStringLiteral("欢迎使用 AGC ImageViewer。系统用于接收、浏览和查询 AGC 检测图片，并提供批次监控、数据统计及参数设置等功能。"));
        if (settings.contains("security/settingsPassword")) {
            QString pwd = settings.value("security/settingsPassword").toString();
            if (!pwd.isEmpty()) {
                if (!pwd.startsWith("sha256$")) {
                    pwd = AgcUtils::encodePassword(pwd);
                }
                DBSchema::setConfig(db, "security/settingsPassword", pwd);
            }
        }
        const QString migratedIni = iniPath + QStringLiteral(".migrated");
        if (QFile::exists(migratedIni)) QFile::remove(migratedIni);
        if (QFile::rename(iniPath, migratedIni)) {
            LOG_INFO("DBSchema: 已成功从 config.ini 迁移配置并归档为 config.ini.migrated");
        } else {
            LOG_WARN("DBSchema: 归档 config.ini 失败");
        }
    }

    // 2. agc_ftp_config.json
    const QString ftpJsonPath = appDir + QDir::separator() + QStringLiteral("agc_ftp_config.json");
    if (QFile::exists(ftpJsonPath)) {
        QFile f(ftpJsonPath);
        if (f.open(QIODevice::ReadOnly) && f.size() <= 2 * 1024 * 1024) {
            try {
                QByteArray data = f.readAll();
                f.close();
                auto obj = nlohmann::json::parse(data.constData(), data.constData() + data.size());
                if (obj.is_object()) {
                    if (obj.contains("ftpPort") && obj["ftpPort"].is_number()) {
                        int p = obj["ftpPort"].get<int>();
                        if (p >= 1 && p <= 65535) DBSchema::setConfig(db, "ftp/port", QString::number(p));
                    }
                    if (obj.contains("ftpRoot") && obj["ftpRoot"].is_string()) {
                        QString r = QString::fromStdString(obj["ftpRoot"].get<std::string>()).trimmed();
                        if (r.endsWith("incoming", Qt::CaseInsensitive) || r.endsWith("archive", Qt::CaseInsensitive)) {
                            r = "images";
                        }
                        if (!r.isEmpty()) DBSchema::setConfig(db, "ftp/rootDirectory", r);
                    }
                    if (obj.contains("ftpUsers") && obj["ftpUsers"].is_array()) {
                        QSqlQuery qUsers(db);
                        qUsers.prepare(R"(
                            INSERT INTO ftp_users(username, password_hash, allow_anonymous, updated_at)
                            VALUES(?, ?, ?, datetime('now', 'localtime'))
                            ON CONFLICT(username) DO UPDATE SET
                                password_hash = excluded.password_hash,
                                allow_anonymous = excluded.allow_anonymous,
                                updated_at = excluded.updated_at
                        )");
                        for (const auto &v : obj["ftpUsers"]) {
                            if (!v.is_object()) continue;
                            std::string u = v.value("user", "");
                            std::string p = v.value("pass", "");
                            if (u.empty() || p.empty()) continue;
                            QString userStr = QString::fromStdString(u);
                            QString passStr = QString::fromStdString(p);
                            if (!passStr.startsWith("sha256$")) {
                                passStr = AgcUtils::encodePassword(passStr);
                            }
                            qUsers.bindValue(0, userStr);
                            qUsers.bindValue(1, passStr);
                            qUsers.bindValue(2, 0);
                            qUsers.exec();
                        }
                    }
                    if (obj.contains("slotMapping") && obj["slotMapping"].is_array()) {
                        const auto &arr = obj["slotMapping"];
                        QSqlQuery qSlot(db);
                        qSlot.prepare(R"(
                            INSERT INTO camera_slots(slot_id, mapped_target)
                            VALUES(?, ?)
                            ON CONFLICT(slot_id) DO UPDATE SET mapped_target = excluded.mapped_target
                        )");
                        for (size_t i = 0; i < 12 && i < arr.size(); ++i) {
                            int target = arr[i].is_number() ? arr[i].get<int>() : int(i + 1);
                            if (target < 1) target = 1;
                            if (target > 14) target = 14;
                            qSlot.bindValue(0, static_cast<int>(i + 1));
                            qSlot.bindValue(1, target);
                            qSlot.exec();
                        }
                    }
                    const QString migratedFtp = ftpJsonPath + QStringLiteral(".migrated");
                    if (QFile::exists(migratedFtp)) QFile::remove(migratedFtp);
                    if (QFile::rename(ftpJsonPath, migratedFtp)) {
                        LOG_INFO("DBSchema: 已成功从 agc_ftp_config.json 迁移配置并归档为 agc_ftp_config.json.migrated");
                    }
                }
            } catch (const std::exception &e) {
                LOG_WARN("DBSchema: 解析 agc_ftp_config.json 失败: {}", e.what());
            }
        }
    }

    // 3. data/agcRackWheelNorm.json
    const QString normJsonPath = appDir + QDir::separator() + QStringLiteral("data")
                               + QDir::separator() + QStringLiteral("agcRackWheelNorm.json");
    if (QFile::exists(normJsonPath)) {
        QFile f(normJsonPath);
        if (f.open(QIODevice::ReadOnly) && f.size() <= 5 * 1024 * 1024) {
            try {
                QByteArray data = f.readAll();
                f.close();
                auto arr = nlohmann::json::parse(data.constData(), data.constData() + data.size());
                if (arr.is_array()) {
                    if (db.transaction()) {
                        QSqlQuery qNorm(db);
                        qNorm.prepare(R"(
                            INSERT INTO carrier_wheel_norm(carrier_id, wheel_id, standard_distance, lower_tolerance, updated_at)
                            VALUES(?, ?, ?, 0.0, datetime('now', 'localtime'))
                            ON CONFLICT(carrier_id, wheel_id) DO UPDATE SET
                                standard_distance = excluded.standard_distance,
                                updated_at = excluded.updated_at
                        )");
                        for (const auto &rack : arr) {
                            if (!rack.is_object()) continue;
                            int rno = 0;
                            if (rack.contains("rackno")) {
                                if (rack["rackno"].is_number()) rno = rack["rackno"].get<int>();
                                else if (rack["rackno"].is_string()) rno = QString::fromStdString(rack["rackno"].get<std::string>()).toInt();
                            }
                            if (rno < 1 || rno > 50) continue;
                            if (rack.contains("wheels") && rack["wheels"].is_array()) {
                                for (const auto &wheel : rack["wheels"]) {
                                    if (!wheel.is_object()) continue;
                                    int wno = 0;
                                    if (wheel.contains("wheelno")) {
                                        if (wheel["wheelno"].is_number()) wno = wheel["wheelno"].get<int>();
                                        else if (wheel["wheelno"].is_string()) wno = QString::fromStdString(wheel["wheelno"].get<std::string>()).toInt();
                                    }
                                    if (wno < 1 || wno > 8) continue;
                                    int dist = 0;
                                    if (wheel.contains("distance")) {
                                        if (wheel["distance"].is_number()) dist = wheel["distance"].get<int>();
                                        else if (wheel["distance"].is_string()) dist = QString::fromStdString(wheel["distance"].get<std::string>()).toInt();
                                    }
                                    qNorm.bindValue(0, rno);
                                    qNorm.bindValue(1, wno);
                                    qNorm.bindValue(2, dist);
                                    qNorm.exec();
                                }
                            }
                        }
                        db.commit();
                    }
                    const QString migratedNorm = normJsonPath + QStringLiteral(".migrated");
                    if (QFile::exists(migratedNorm)) QFile::remove(migratedNorm);
                    if (QFile::rename(normJsonPath, migratedNorm)) {
                        LOG_INFO("DBSchema: 已成功从 agcRackWheelNorm.json 迁移配置并归档为 agcRackWheelNorm.json.migrated");
                    }
                }
            } catch (const std::exception &e) {
                LOG_WARN("DBSchema: 解析 agcRackWheelNorm.json 失败: {}", e.what());
            }
        }
    }
}

bool DBSchema::ensureAllTables(QSqlDatabase &db){
    if(!db.isOpen()){
        LOG_ERROR("DBSchema: 数据库未打开，无法校验表结构");
        return false;
    }
    QSqlQuery q(db);
    q.exec("PRAGMA busy_timeout = 5000;");

    // 1. record (检测历史明细)
    const QString createRecord = R"(
        CREATE TABLE IF NOT EXISTS record (
            createtime DATETIME NOT NULL,
            carrier_id INTEGER NOT NULL,
            camera_id INTEGER NOT NULL DEFAULT 1,
            wheel_id INTEGER NOT NULL,
            result INTEGER CHECK(result IN (0,1)),
            distance REAL NOT NULL DEFAULT 0.0,
            dist_norm REAL NOT NULL DEFAULT 0.0,
            lower_tolerance REAL NOT NULL DEFAULT 0.0,
            imagename TEXT NOT NULL,
            batch_id TEXT DEFAULT ''
        )
    )";
    if(!q.exec(createRecord)){
        LOG_ERROR("DBSchema: 创建 record 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    const auto execRequired = [&q](const QString &sql, const char *operation) {
        if (q.exec(sql)) return true;
        LOG_ERROR("DBSchema: {}失败: {}", operation, q.lastError().text().toStdString());
        return false;
    };
    if (!execRequired("CREATE INDEX IF NOT EXISTS idx_record_carrier_time ON record(carrier_id, createtime DESC)", "创建载具时间索引")
        || !execRequired("CREATE INDEX IF NOT EXISTS idx_record_carrier_wheel ON record(carrier_id, wheel_id, createtime DESC)", "创建载具轮号索引")
        || !execRequired("CREATE INDEX IF NOT EXISTS idx_record_createtime ON record(createtime DESC)", "创建时间索引")
        || !execRequired("CREATE INDEX IF NOT EXISTS idx_record_batch ON record(batch_id)", "创建批次索引")
        || !execRequired("CREATE INDEX IF NOT EXISTS idx_record_image ON record(imagename)", "创建图片名索引")) {
        return false;
    }

    if (!q.exec("CREATE TABLE IF NOT EXISTS cleanup_files(path TEXT PRIMARY KEY, imagename TEXT NOT NULL)")) return false;
    if (!q.exec(R"(
        CREATE TABLE IF NOT EXISTS ingest_requests (
            request_id TEXT PRIMARY KEY,
            carrier_id INTEGER NOT NULL,
            item_count INTEGER NOT NULL,
            committed_at DATETIME NOT NULL
        )
    )")) return false;

    // 2. alertrecord (当前各载具、轮号最新的 NG 报警记录)
    const QString createAlertRecord = R"(
        CREATE TABLE IF NOT EXISTS alertrecord (
            createtime DATETIME NOT NULL,
            carrier_id INTEGER NOT NULL,
            camera_id INTEGER NOT NULL DEFAULT 1,
            wheel_id INTEGER NOT NULL,
            result INTEGER CHECK(result IN (0,1)),
            distance REAL NOT NULL DEFAULT 0.0,
            dist_norm REAL NOT NULL DEFAULT 0.0,
            lower_tolerance REAL NOT NULL DEFAULT 0.0,
            imagename TEXT NOT NULL,
            UNIQUE(carrier_id, wheel_id)
        )
    )";
    if(!q.exec(createAlertRecord)){
        LOG_ERROR("DBSchema: 创建 alertrecord 表失败: {}", q.lastError().text().toStdString());
        return false;
    }
    if (!execRequired("CREATE INDEX IF NOT EXISTS idx_alertrecord_createtime ON alertrecord(createtime DESC)", "创建报警时间索引")) return false;

    // 2.1 carrier_wheel_status (各载具、轮号最新的综合遥测状态高速常驻表，最大 50x16=800 行)
    const QString createCarrierWheelStatus = R"(
        CREATE TABLE IF NOT EXISTS carrier_wheel_status (
            carrier_id INTEGER NOT NULL,
            wheel_id INTEGER NOT NULL,
            result INTEGER NOT NULL DEFAULT 1,
            createtime DATETIME NOT NULL,
            imagename TEXT NOT NULL DEFAULT '',
            PRIMARY KEY(carrier_id, wheel_id)
        )
    )";
    if (!q.exec(createCarrierWheelStatus)) {
        LOG_ERROR("DBSchema: 创建 carrier_wheel_status 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    if (!q.exec("DROP TRIGGER IF EXISTS trg_record_wheel_status")) return false;
    if (!q.exec(R"(
        CREATE TRIGGER trg_record_wheel_status
        AFTER INSERT ON record
        BEGIN
            INSERT INTO carrier_wheel_status(carrier_id, wheel_id, result, createtime, imagename)
            VALUES(NEW.carrier_id, NEW.wheel_id, NEW.result, NEW.createtime, NEW.imagename)
            ON CONFLICT(carrier_id, wheel_id) DO UPDATE SET
                result = excluded.result,
                createtime = excluded.createtime,
                imagename = excluded.imagename
            WHERE datetime(excluded.createtime) >= datetime(carrier_wheel_status.createtime);
        END
    )")) return false;

    // 若 carrier_wheel_status 为空且 record 表已有历史数据，进行一次性补全迁移
    {
        QSqlQuery checkStatus(db);
        if (checkStatus.exec("SELECT COUNT(*) FROM carrier_wheel_status") && checkStatus.next() && checkStatus.value(0).toInt() == 0) {
            if (!q.exec(R"(
                INSERT OR IGNORE INTO carrier_wheel_status(carrier_id, wheel_id, result, createtime, imagename)
                SELECT carrier_id, wheel_id, result, createtime, imagename FROM (
                    SELECT carrier_id, wheel_id, result, createtime, imagename,
                    ROW_NUMBER() OVER (PARTITION BY carrier_id, wheel_id ORDER BY datetime(createtime) DESC, rowid DESC) AS pos
                    FROM record
                ) WHERE pos = 1
            )")) {
                LOG_ERROR("DBSchema: 初始化轮位状态缓存失败: {}", q.lastError().text().toStdString());
                return false;
            }
        }
    }

    if (!q.exec("DROP TRIGGER IF EXISTS trg_record_ng_alert")) return false;
    if (!q.exec("DROP TRIGGER IF EXISTS trg_record_ok_alert")) return false;

    if (!q.exec(R"(
        CREATE TRIGGER trg_record_ng_alert
        AFTER INSERT ON record WHEN NEW.result=0 AND NOT EXISTS (
            SELECT 1 FROM record WHERE carrier_id=NEW.carrier_id AND wheel_id=NEW.wheel_id
              AND (datetime(createtime)>datetime(NEW.createtime)
                   OR (datetime(createtime)=datetime(NEW.createtime) AND rowid>NEW.rowid))
        )
        BEGIN
            INSERT INTO alertrecord(createtime,carrier_id,camera_id,wheel_id,result,distance,dist_norm,lower_tolerance,imagename)
            VALUES(NEW.createtime,NEW.carrier_id,NEW.camera_id,NEW.wheel_id,0,NEW.distance,NEW.dist_norm,NEW.lower_tolerance,NEW.imagename)
            ON CONFLICT(carrier_id,wheel_id) DO UPDATE SET
                createtime=excluded.createtime,result=0,camera_id=excluded.camera_id,imagename=excluded.imagename,
                distance=excluded.distance,dist_norm=excluded.dist_norm,lower_tolerance=excluded.lower_tolerance
            WHERE datetime(excluded.createtime)>=datetime(alertrecord.createtime);
        END
    )")) return false;

    if (!q.exec(R"(
        CREATE TRIGGER trg_record_ok_alert AFTER INSERT ON record WHEN NEW.result=1
        BEGIN
            DELETE FROM alertrecord WHERE carrier_id=NEW.carrier_id AND wheel_id=NEW.wheel_id
                AND datetime(createtime)<=datetime(NEW.createtime);
        END
    )")) return false;

    // 3. weekly_reports
    if(!q.exec("CREATE TABLE IF NOT EXISTS weekly_reports (createtime DATETIME NOT NULL, drivers_filename TEXT, deformed_filename TEXT)")){
        LOG_ERROR("DBSchema: 创建 weekly_reports 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    // 4. system_config
    const QString createSystemConfig = R"(
        CREATE TABLE IF NOT EXISTS system_config (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at DATETIME NOT NULL
        )
    )";
    if(!q.exec(createSystemConfig)){
        LOG_ERROR("DBSchema: 创建 system_config 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    // 5. ftp_users
    const QString createFtpUsers = R"(
        CREATE TABLE IF NOT EXISTS ftp_users (
            username TEXT PRIMARY KEY,
            password_hash TEXT NOT NULL,
            allow_anonymous INTEGER DEFAULT 0,
            updated_at DATETIME NOT NULL
        )
    )";
    if(!q.exec(createFtpUsers)){
        LOG_ERROR("DBSchema: 创建 ftp_users 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    // 6. camera_slots
    const QString createCameraSlots = R"(
        CREATE TABLE IF NOT EXISTS camera_slots (
            slot_id INTEGER PRIMARY KEY,
            mapped_target INTEGER NOT NULL
        )
    )";
    if(!q.exec(createCameraSlots)){
        LOG_ERROR("DBSchema: 创建 camera_slots 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    // 7. carrier_wheel_norm (标准基准与公差配置: 50 carriers x 16 wheels)
    const QString createCarrierWheelNorm = R"(
        CREATE TABLE IF NOT EXISTS carrier_wheel_norm (
            carrier_id INTEGER NOT NULL,
            wheel_id INTEGER NOT NULL,
            standard_distance REAL NOT NULL DEFAULT 0.0,
            lower_tolerance REAL NOT NULL DEFAULT 0.0,
            updated_at DATETIME NOT NULL,
            PRIMARY KEY(carrier_id, wheel_id)
        )
    )";
    if(!q.exec(createCarrierWheelNorm)){
        LOG_ERROR("DBSchema: 创建 carrier_wheel_norm 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    // system_config defaults
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('tcp/port', '9000', datetime('now', 'localtime'))");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('ftp/port', '21', datetime('now', 'localtime'))");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('ftp/rootDirectory', 'images', datetime('now', 'localtime'))");
    // 自动将历史默认配置 'archive' 升级为规范的 'images'
    q.exec("UPDATE system_config SET value = 'images', updated_at = datetime('now', 'localtime') WHERE key = 'ftp/rootDirectory' AND value = 'archive'");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('cleanup/keepDays', '90', datetime('now', 'localtime'))");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('cleanup/logKeepDays', '30', datetime('now', 'localtime'))");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('cleanup/runHour', '1', datetime('now', 'localtime'))");
    q.exec("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('ui/isDark', 'false', datetime('now', 'localtime'))");
    {
        QSqlQuery qDef(db);
        qDef.prepare("INSERT OR IGNORE INTO system_config(key, value, updated_at) VALUES('homepage/description', ?, datetime('now', 'localtime'))");
        qDef.addBindValue(QStringLiteral("欢迎使用 CarrierVision。系统用于接收、浏览和查询载具检测数据与图片，并提供工位监控、数据统计及参数设置等功能。"));
        qDef.exec();
    }
    {
        QSqlQuery checkPwd(db);
        checkPwd.prepare("SELECT value FROM system_config WHERE key = 'security/settingsPassword'");
        if (checkPwd.exec() && !checkPwd.next()) {
            QSqlQuery insPwd(db);
            insPwd.prepare("INSERT INTO system_config(key, value, updated_at) VALUES('security/settingsPassword', ?, datetime('now', 'localtime'))");
            insPwd.addBindValue(AgcUtils::encodePassword(QStringLiteral("123456")));
            insPwd.exec();
        }
    }

    // ftp_users default
    {
        QSqlQuery checkUser(db);
        if (checkUser.exec("SELECT COUNT(*) FROM ftp_users") && checkUser.next() && checkUser.value(0).toInt() == 0) {
            QSqlQuery insUser(db);
            insUser.prepare("INSERT INTO ftp_users(username, password_hash, allow_anonymous, updated_at) VALUES('agc', ?, 0, datetime('now', 'localtime'))");
            insUser.addBindValue(AgcUtils::encodePassword(QStringLiteral("123456")));
            insUser.exec();
        }
    }

    // camera_slots default (1..12)
    {
        QSqlQuery checkSlots(db);
        if (checkSlots.exec("SELECT COUNT(*) FROM camera_slots") && checkSlots.next() && checkSlots.value(0).toInt() == 0) {
            if (db.transaction()) {
                QSqlQuery insSlot(db);
                insSlot.prepare("INSERT INTO camera_slots(slot_id, mapped_target) VALUES(?, ?)");
                for (int i = 1; i <= 12; ++i) {
                    insSlot.bindValue(0, i);
                    insSlot.bindValue(1, i);
                    insSlot.exec();
                }
                db.commit();
            }
        }
    }

    // carrier_wheel_norm default (50 carriers x 16 wheels: 1..16)
    {
        if (db.transaction()) {
            QSqlQuery insNorm(db);
            insNorm.prepare("INSERT OR IGNORE INTO carrier_wheel_norm(carrier_id, wheel_id, standard_distance, lower_tolerance, updated_at) VALUES(?, ?, 10.0, -2.0, datetime('now', 'localtime'))");
            for (int r = 1; r <= 50; ++r) {
                for (int w = 1; w <= 16; ++w) {
                    insNorm.bindValue(0, r);
                    insNorm.bindValue(1, w);
                    if (!insNorm.exec()) {
                        db.rollback();
                        LOG_ERROR("DBSchema: 初始化轮号标准值失败: {}", insNorm.lastError().text().toStdString());
                        return false;
                    }
                }
            }
            if (!db.commit()) return false;
        }
    }

    // Migrate any legacy config files (.ini, .json)
    migrateLegacyFiles(db);

    LOG_INFO("DBSchema: 数据库表结构及触发器校验完成");
    return true;
}
