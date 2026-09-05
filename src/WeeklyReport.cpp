#include "WeeklyReport.h"
#include "AppLogger.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QTextStream>
#include <QTimer>
#include <array>

using namespace std;

namespace WeeklyReport {

static const array<int,8> DRIVERS = {1,2,3,4,5,6,7,8};
static const array<int,8> DEFORMED = {11,12,13,14,15,16,17,18};
static const array<int,50> RACKS = [](){ array<int,50> a{}; for(int i=0;i<50;i++) a[i]=i+1; return a;}();

static QDate lastMondayForDate(const QDate &d){
    QDate monday = d.addDays(-d.dayOfWeek()+1);
    return monday.addDays(-7); // last week's monday
}

static QString ensureOutDir(){
    QString out = QCoreApplication::applicationDirPath() + QDir::separator() + "data";
    QDir dir;
    dir.mkpath(out);
    return out;
}

static bool writeCsv(const QString &path, const QList<QList<QVariant>> &rows){
    QSaveFile f(path);
    if(!f.open(QIODevice::WriteOnly|QIODevice::Text)) return false;
    QTextStream out(&f);
    out << "rack,wheelno,ok_count,ng_count,total,loss_rate\n";
    for(const auto &r : rows){
        int rack = r[0].toInt();
        int wheel = r[1].toInt();
        int ok = r[2].toInt();
        int ng = r[3].toInt();
        int total = ok + ng;
        double loss = (total>0)? double(ng)/double(total) : 0.0;
        out << rack << "," << wheel << "," << ok << "," << ng << "," << total << "," << QString::number(loss,'f',4) << "\n";
    }
    out.flush();
    if (out.status() != QTextStream::Ok || f.error() != QFileDevice::NoError) {
        f.cancelWriting();
        return false;
    }
    return f.commit();
}

bool generateForWeek(const QDate &monday){
    // monday is the week start (Mon)
    QDate start = monday;
    QDate end = monday.addDays(6);

    QString dbPath = QCoreApplication::applicationDirPath() + QDir::separator() + "dataAgc.db";
    QString startTag = start.toString("yyyyMMdd");
    QString endTag = end.toString("yyyyMMdd");
    QString outDir = ensureOutDir();
    QString driversPath = outDir + QDir::separator() + QString("%1-%2_drivers.csv").arg(startTag, endTag);
    QString deformedPath = outDir + QDir::separator() + QString("%1-%2_deformed.csv").arg(startTag, endTag);

    bool ok1 = false;
    bool ok2 = false;
    bool dbOk = true;
    bool needRemoveConn = false;

    {
        QSqlDatabase db = QSqlDatabase::database();
        bool useExternal = db.isValid() && db.isOpen();
        if(!useExternal){
            db = QSqlDatabase::addDatabase("QSQLITE", "weekly_report_conn");
            db.setDatabaseName(dbPath);
            if(!db.open()){
                LOG_ERROR("WeeklyReport: 打开数据库失败: {}", db.lastError().text().toStdString());
                needRemoveConn = true;
            } else {
                needRemoveConn = true;
            }
        }

        if(db.isOpen()){
            QSqlQuery q(db);
            QString qs = QString("SELECT rackno, wheelno, result FROM record WHERE createtime >= '%1' AND createtime < '%2'")
                    .arg(start.toString(Qt::ISODate)).arg(end.addDays(1).toString(Qt::ISODate));
            if(!q.exec(qs)){
                LOG_ERROR("WeeklyReport: 执行查询失败: {}", q.lastError().text().toStdString());
            } else {
                // map key (rack,wheel) -> pair(ok,ng)
                QMap<QPair<int,int>, QPair<int,int>> aggr;
                while(q.next()){
                    bool okR, okW;
                    int r = q.value(0).toInt(&okR);
                    int w = q.value(1).toInt(&okW);
                    if(!okR || !okW) continue;
                    if (r < 1 || r > 50 || !((w >= 1 && w <= 8) || (w >= 11 && w <= 18))) continue;
                    int res = q.value(2).toInt();
                    auto key = qMakePair(r,w);
                    auto cur = aggr.value(key, qMakePair(0,0));
                    if(res==1) cur.first++; else cur.second++;
                    aggr.insert(key, cur);
                }

                if (aggr.isEmpty()) {
                    LOG_INFO("WeeklyReport: {} 至 {} 无巡检记录，跳过生成周报", startTag.toStdString(), endTag.toStdString());
                } else {
                    // build rows
                    QList<QList<QVariant>> driversRows;
                    QList<QList<QVariant>> deformedRows;
                    for(int rack : RACKS){
                        for(int wheel : DRIVERS){
                            auto p = aggr.value(qMakePair(rack,wheel), qMakePair(0,0));
                            driversRows.append({rack, wheel, p.first, p.second});
                        }
                        for(int i = 0; i < DEFORMED.size(); ++i){
                            int sourceWheel = DEFORMED[i]; // 11..18
                            int outputWheel = i + 1; // 1..8
                            auto p = aggr.value(qMakePair(rack, sourceWheel), qMakePair(0,0));
                            deformedRows.append({rack, outputWheel, p.first, p.second});
                        }
                    }

                    // 如果本周的文件已存在于 weekly_reports，则跳过重复生成
                    bool alreadyExists = false;
                    QSqlQuery checkExist(db);
                    checkExist.prepare("SELECT COUNT(1) FROM weekly_reports WHERE drivers_filename = :d1 AND deformed_filename = :d2");
                    checkExist.bindValue(":d1", QFileInfo(driversPath).fileName());
                    checkExist.bindValue(":d2", QFileInfo(deformedPath).fileName());
                    if (checkExist.exec() && checkExist.next() && checkExist.value(0).toInt() > 0) {
                        LOG_INFO("WeeklyReport: {} 至 {} 的周报已存在，跳过重复生成", startTag.toStdString(), endTag.toStdString());
                        alreadyExists = true;
                    }

                    if (!alreadyExists) {
                        ok1 = writeCsv(driversPath, driversRows);
                        ok2 = writeCsv(deformedPath, deformedRows);

                        if (!ok1 || !ok2) {
                            if (ok1) QFile::remove(driversPath);
                            if (ok2) QFile::remove(deformedPath);
                            dbOk = false;
                            LOG_ERROR("WeeklyReport: 生成 CSV 失败，取消写入数据库记录");
                        } else {
                            QSqlQuery qq(db);
                            if(!qq.exec("CREATE TABLE IF NOT EXISTS weekly_reports (createtime DATETIME NOT NULL, drivers_filename TEXT, deformed_filename TEXT)")){
                                LOG_ERROR("WeeklyReport: 创建 weekly_reports 表失败: {}", qq.lastError().text().toStdString());
                                dbOk = false;
                            } else {
                                QSqlQuery ins(db);
                                ins.prepare("INSERT INTO weekly_reports(createtime, drivers_filename, deformed_filename) VALUES(:t, :d1, :d2)");
                                QString genTime = QDateTime::currentDateTime().toString(Qt::ISODate);
                                ins.bindValue(":t", genTime);
                                ins.bindValue(":d1", QFileInfo(driversPath).fileName());
                                ins.bindValue(":d2", QFileInfo(deformedPath).fileName());
                                if(!db.transaction() || !ins.exec() || !db.commit()){
                                    db.rollback();
                                    LOG_ERROR("WeeklyReport: 插入 weekly_reports 记录失败: {}", ins.lastError().text().toStdString());
                                    dbOk = false;
                                }
                            }
                        }
                    } else {
                        ok1 = true;
                        ok2 = true;
                    }
                }
            }
        }
    }

    if(needRemoveConn){
        QSqlDatabase::removeDatabase("weekly_report_conn");
    }

    LOG_INFO("WeeklyReport: 生成完成: {} 与 {}", driversPath.toStdString(), deformedPath.toStdString());
    return ok1 && ok2 && dbOk;
}

static void scheduleNextWeeklyReport(){
    QDate today = QDate::currentDate();
    QDate monday = today.addDays(-today.dayOfWeek()+1);
    QDate nextMonday = monday.addDays(7);

    QDateTime nextRun(nextMonday, QTime(0,10));
    qint64 msecs = QDateTime::currentDateTime().msecsTo(nextRun);
    if(msecs < 1) msecs = 1;

    QTimer::singleShot(static_cast<int>(msecs), qApp, [](){
        QDate monday = QDate::currentDate().addDays(-QDate::currentDate().dayOfWeek()+1);
        generateForWeek(monday.addDays(-7));
        scheduleNextWeeklyReport();
    });
}

void scheduleWeeklyReports(){
    scheduleNextWeeklyReport();
}

} // namespace WeeklyReport
