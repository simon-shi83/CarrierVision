#pragma once

#include <QSqlDatabase>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

// 统计与监控查询。所有函数只读、无状态，调用方负责提供当前线程可用的数据库连接，
// 因此既可在主线程同步调用，也可在后台线程池中执行。
namespace StatsService {

// 各架合格/不合格汇总（50 行），wheelLow~wheelHigh 为轮位范围：走行轮 1~8，驱动轮 9~16
QVariantList wheelGroupRackStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                 int wheelLow, int wheelHigh);
QVariantList rackWheelMonitorStatus(const QSqlDatabase &db);
QVariantList rackPhotoCounts(const QSqlDatabase &db);
// preferredRack 不在 1~50 时取最新入库记录的架号
QVariantMap homepageCurrentDetection(const QSqlDatabase &db, int preferredRack);
QVariantList wheelRackResultStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                  int wheelNumber, const QString &resultType);
QVariantList rackWheelResultStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                  int rackNumber, const QString &resultType, int wheelType);

// 轮系汇总：按轮号统计 OK/NG 数量。rackno 为空表示全部架号；selectedTurns 为连续 8 个轮号时输出该范围，否则输出 1~8
QVariantList gearSum(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                     const QString &rackno, const QVariantList &selectedTurns);

// 按名称分发，供异步请求使用；kind 未知或参数不足时 ok 置为 false
QVariant run(const QSqlDatabase &db, const QString &kind, const QVariantList &args, bool *ok = nullptr);

} // namespace StatsService
