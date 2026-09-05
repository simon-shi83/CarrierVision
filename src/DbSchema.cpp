#include "DbSchema.h"
#include "AppLogger.h"
#include <QSqlQuery>
#include <QSqlError>

bool DBSchema::ensureAllTables(QSqlDatabase &db){
    if(!db.isOpen()){
        LOG_ERROR("DBSchema: 数据库未打开，无法校验表结构");
        return false;
    }
    QSqlQuery q(db);
    q.exec("PRAGMA busy_timeout = 5000;");
    // record
    const QString createRecord = R"(
        CREATE TABLE IF NOT EXISTS record (
            createtime DATETIME NOT NULL,
            rackno TEXT NOT NULL,
            wheelno TEXT NOT NULL,
            result INTEGER CHECK(result IN (0,1)),
            imagename TEXT NOT NULL,
            distance INTEGER NOT NULL DEFAULT 0,
            dist_max INTEGER NOT NULL DEFAULT 0,
            dist_norm INTEGER NOT NULL DEFAULT 0
        )
    )";
    if(!q.exec(createRecord)){
        LOG_ERROR("DBSchema: 创建 record 表失败: {}", q.lastError().text().toStdString());
        return false;
    }
    if(!q.exec("CREATE INDEX IF NOT EXISTS idx_record_rack_result_time ON record(rackno, result, createtime DESC)")){
        LOG_ERROR("DBSchema: 创建索引 idx_record_rack_result_time 失败: {}", q.lastError().text().toStdString());
    }
    if(!q.exec("CREATE INDEX IF NOT EXISTS idx_record_rack_result_distance_createtime_wheel ON record(rackno, result, distance, dist_max, dist_norm, createtime, wheelno)")){
        LOG_ERROR("DBSchema: 创建复合索引 idx_record_rack_result_distance_createtime_wheel 失败: {}", q.lastError().text().toStdString());
    }

    if (!q.exec("CREATE INDEX IF NOT EXISTS idx_record_image_wheel ON record(imagename,wheelno)")) return false;
    if (!q.exec("CREATE INDEX IF NOT EXISTS idx_record_rack_wheel_time ON record(rackno,wheelno,createtime DESC)")) return false;
    if (!q.exec("CREATE TABLE IF NOT EXISTS cleanup_files(path TEXT PRIMARY KEY, imagename TEXT NOT NULL)")) return false;

    // alertrecord：仅保存各架号、轮号当前最新的 NG 报警记录。
    const QString createAlertRecord = R"(
        CREATE TABLE IF NOT EXISTS alertrecord (
            createtime DATETIME NOT NULL,
            rackno TEXT NOT NULL,
            wheelno TEXT NOT NULL,
            result INTEGER CHECK(result IN (0,1)),
            imagename TEXT NOT NULL,
            distance INTEGER NOT NULL DEFAULT 0,
            dist_max INTEGER NOT NULL DEFAULT 0,
            dist_norm INTEGER NOT NULL DEFAULT 0,
            UNIQUE(rackno, wheelno)
        )
    )";
    if(!q.exec(createAlertRecord)){
        LOG_ERROR("DBSchema: 创建 alertrecord 表失败: {}", q.lastError().text().toStdString());
        return false;
    }
    // Transactional replacement also upgrades existing installations.
    // Keep timestamp comparisons consistent for legacy ISO 'T' and space formats.
    if (!db.transaction()) return false;
    auto migrate = [&](const QString &sql) {
        if (q.exec(sql)) return true;
        LOG_ERROR("报警结构升级失败: {}", q.lastError().text().toStdString());
        db.rollback();
        return false;
    };
    if (!migrate("DROP TRIGGER IF EXISTS trg_record_ng_alert")
        || !migrate("DROP TRIGGER IF EXISTS trg_record_ok_alert")) return false;
    if (!migrate(R"(
        CREATE TRIGGER trg_record_ng_alert
        AFTER INSERT ON record WHEN NEW.result=0 AND NOT EXISTS (
            SELECT 1 FROM record WHERE rackno=NEW.rackno AND wheelno=NEW.wheelno
              AND (datetime(createtime)>datetime(NEW.createtime)
                   OR (datetime(createtime)=datetime(NEW.createtime) AND rowid>NEW.rowid))
        )
        BEGIN
            INSERT INTO alertrecord(createtime,rackno,wheelno,result,imagename,distance,dist_max,dist_norm)
            VALUES(NEW.createtime,NEW.rackno,NEW.wheelno,0,NEW.imagename,NEW.distance,NEW.dist_max,NEW.dist_norm)
            ON CONFLICT(rackno,wheelno) DO UPDATE SET
                createtime=excluded.createtime,result=0,imagename=excluded.imagename,
                distance=excluded.distance,dist_max=excluded.dist_max,dist_norm=excluded.dist_norm
            WHERE datetime(excluded.createtime)>=datetime(alertrecord.createtime);
        END
    )")) return false;
    if (!migrate(R"(
        CREATE TRIGGER trg_record_ok_alert AFTER INSERT ON record WHEN NEW.result=1
        BEGIN
            DELETE FROM alertrecord WHERE rackno=NEW.rackno AND wheelno=NEW.wheelno
                AND datetime(createtime)<=datetime(NEW.createtime);
        END
    )")) return false;
    if (!db.commit()) { db.rollback(); return false; }

    // rackwheelnorm
    const QString createRack = R"(
        CREATE TABLE IF NOT EXISTS rackwheelnorm (
            createtime DATETIME NOT NULL,
            rackno INTEGER NOT NULL,
            wheelno INTEGER NOT NULL,
            distance INTEGER NOT NULL,
            imagename TEXT NOT NULL,
            UNIQUE(imagename, wheelno)
        )
    )";
    if(!q.exec(createRack)){
        LOG_ERROR("DBSchema: 创建 rackwheelnorm 表失败: {}", q.lastError().text().toStdString());
        return false;
    }
    if(!q.exec("CREATE INDEX IF NOT EXISTS idx_rackwheelnorm_rack_wheel ON rackwheelnorm(rackno, wheelno)")){
        LOG_ERROR("DBSchema: 创建索引 idx_rackwheelnorm_rack_wheel 失败: {}", q.lastError().text().toStdString());
    }

    // weekly_reports
    if(!q.exec("CREATE TABLE IF NOT EXISTS weekly_reports (createtime DATETIME NOT NULL, drivers_filename TEXT, deformed_filename TEXT)")){
        LOG_ERROR("DBSchema: 创建 weekly_reports 表失败: {}", q.lastError().text().toStdString());
        return false;
    }

    LOG_INFO("DBSchema: 数据库表结构及触发器校验完成");
    return true;
}
