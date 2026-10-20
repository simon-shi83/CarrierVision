#include "data/StatsService.h"

#include "common/AgcUtils.h"
#include "common/AppLogger.h"

#include <QDate>
#include <QDateTime>
#include <QHash>
#include <QMap>
#include <QSqlError>
#include <QSqlQuery>
#include <QTime>
#include <QVector>

#include <algorithm>
#include <numeric>

namespace {

QString boundText(const QString &text, bool endOfDay)
{
    const QDateTime time = AgcUtils::parseFlexibleDateTime(text, endOfDay);
    return time.isValid() ? AgcUtils::formatDateTime(time) : text;
}

bool usable(const QSqlDatabase &db)
{
    return db.isValid() && db.isOpen();
}

} // namespace

namespace StatsService {

QVariantList wheelGroupRackStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                 int wheelLow, int wheelHigh)
{
    QVariantList out;
    if (!usable(db)) return out;

    QSqlQuery q(db);
    q.prepare(R"(
        SELECT carrier_id,
               SUM(CASE WHEN result = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN result = 0 THEN 1 ELSE 0 END)
        FROM record
        WHERE createtime >= :start AND createtime <= :end
          AND wheel_id BETWEEN :low AND :high
        GROUP BY carrier_id
    )");
    q.bindValue(":start", boundText(startDate, false));
    q.bindValue(":end", boundText(endDate, true));
    q.bindValue(":low", wheelLow);
    q.bindValue(":high", wheelHigh);
    if (!q.exec()) {
        LOG_ERROR("架号统计数据库查询失败: {}", q.lastError().text().toStdString());
        return out;
    }

    struct Stat { qint64 ok = 0; qint64 ng = 0; };
    QVector<Stat> stats(50);
    while (q.next()) {
        const int rack = q.value(0).toInt();
        if (rack < 1 || rack > 50) continue;
        stats[rack - 1].ok = q.value(1).toLongLong();
        stats[rack - 1].ng = q.value(2).toLongLong();
    }

    for (int i = 0; i < 50; ++i) {
        QVariantMap row;
        const qint64 total = stats[i].ok + stats[i].ng;
        row[QStringLiteral("carrierId")] = i + 1;
        row[QStringLiteral("rack")] = i + 1;
        row[QStringLiteral("ok")] = stats[i].ok;
        row[QStringLiteral("ng")] = stats[i].ng;
        row[QStringLiteral("loss")] = total > 0 ? stats[i].ng * 100.0 / total : 0.0;
        out.append(row);
    }
    return out;
}

QVariantList rackWheelMonitorStatus(const QSqlDatabase &db)
{
    QVariantList out;
    if (!usable(db)) return out;

    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT carrier_id, wheel_id, result, createtime FROM carrier_wheel_status "
        "WHERE carrier_id BETWEEN 1 AND 50 AND wheel_id BETWEEN 1 AND 16"));

    if (!query.exec()) {
        // 回退兼容无状态缓存表时的旧窗口函数查询
        query.prepare(QStringLiteral(
            "SELECT carrier_id, wheel_id, result, createtime FROM ("
            " SELECT carrier_id, wheel_id, result, createtime,"
            " ROW_NUMBER() OVER (PARTITION BY carrier_id, wheel_id"
            " ORDER BY createtime DESC, rowid DESC) AS position FROM record"
            ") WHERE position=1 AND wheel_id BETWEEN 1 AND 16"));
        if (!query.exec()) {
            LOG_ERROR("rackWheelMonitorStatus 数据库查询失败: {}", query.lastError().text().toStdString());
            return out;
        }
    }

    while (query.next()) {
        const int rack = query.value(0).toInt();
        const int wheel = query.value(1).toInt();
        if (rack < 1 || rack > 50) continue;

        QVariantMap item;
        item.insert(QStringLiteral("carrierId"), rack);
        item.insert(QStringLiteral("rack"), rack);
        item.insert(QStringLiteral("wheelId"), wheel);
        item.insert(QStringLiteral("wheel"), wheel);
        item.insert(QStringLiteral("result"), query.value(2).toInt());
        item.insert(QStringLiteral("time"), query.value(3).toString());
        out.append(item);
    }
    return out;
}

QVariantList rackPhotoCounts(const QSqlDatabase &db)
{
    QVariantList out;
    if (!usable(db)) return out;

    QVector<int> counts(50, 0);
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT carrier_id, COUNT(*) FROM record "
        "WHERE carrier_id BETWEEN 1 AND 50 "
        "AND wheel_id = 1 "
        "GROUP BY carrier_id"));
    if (query.exec()) {
        while (query.next()) {
            const int rack = query.value(0).toInt();
            if (rack >= 1 && rack <= 50) counts[rack - 1] = query.value(1).toInt();
        }
    } else {
        LOG_ERROR("rackPhotoCounts 数据库统计失败: {}", query.lastError().text().toStdString());
    }

    for (int rack = 1; rack <= 50; ++rack) {
        QVariantMap item;
        item.insert(QStringLiteral("carrierId"), rack);
        item.insert(QStringLiteral("rack"), rack);
        item.insert(QStringLiteral("count"), counts[rack - 1]);
        out.append(item);
    }
    return out;
}

QVariantMap homepageCurrentDetection(const QSqlDatabase &db, int preferredRack)
{
    QVariantMap overview;
    QVariantList driveWheels;
    QVariantList walkingWheels;
    overview.insert(QStringLiteral("carrierId"), 0);
    overview.insert(QStringLiteral("rack"), 0);
    overview.insert(QStringLiteral("drive"), driveWheels);
    overview.insert(QStringLiteral("walking"), walkingWheels);
    overview.insert(QStringLiteral("drivePassRate"), 0.0);
    overview.insert(QStringLiteral("walkingPassRate"), 0.0);
    overview.insert(QStringLiteral("ngCount"), 0);
    overview.insert(QStringLiteral("totalCount"), 0);
    overview.insert(QStringLiteral("ngRate"), 0.0);
    if (!usable(db)) return overview;

    int rackNumber = preferredRack >= 1 && preferredRack <= 50 ? preferredRack : 0;
    if (rackNumber == 0) {
        QSqlQuery latestRackQuery(db);
        // 先经时间索引取最新时间，再在同一秒内按 rowid 取最后写入的记录；
        // 子查询过滤列加一元 + 号，避免规划器改走载具索引后整表排序
        if (latestRackQuery.exec(QStringLiteral(
                "SELECT carrier_id FROM record WHERE createtime = ("
                " SELECT createtime FROM record"
                " WHERE +carrier_id BETWEEN 1 AND 50 AND +wheel_id BETWEEN 1 AND 16"
                " ORDER BY createtime DESC LIMIT 1)"
                " AND carrier_id BETWEEN 1 AND 50 AND wheel_id BETWEEN 1 AND 16"
                " ORDER BY rowid DESC LIMIT 1"))
            && latestRackQuery.next()) {
            rackNumber = latestRackQuery.value(0).toInt();
        }
    }
    if (rackNumber < 1 || rackNumber > 50) return overview;
    overview.insert(QStringLiteral("carrierId"), rackNumber);
    overview.insert(QStringLiteral("rack"), rackNumber);

    auto placeholder = [](int wheel) {
        QVariantMap item;
        item.insert(QStringLiteral("wheelId"), wheel);
        item.insert(QStringLiteral("wheel"), wheel);
        item.insert(QStringLiteral("result"), -1);
        item.insert(QStringLiteral("time"), QString());
        item.insert(QStringLiteral("passRate"), 0.0);
        return item;
    };
    for (int wheel = 1; wheel <= 8; ++wheel) driveWheels.append(placeholder(wheel));
    for (int wheel = 9; wheel <= 16; ++wheel) walkingWheels.append(placeholder(wheel));

    QSqlQuery latestQuery(db);
    latestQuery.prepare(QStringLiteral(
        "SELECT wheel_id, result, createtime FROM carrier_wheel_status "
        "WHERE carrier_id = :rack AND wheel_id BETWEEN 1 AND 16"));
    latestQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    if (!latestQuery.exec()) {
        latestQuery.prepare(QStringLiteral(
            "SELECT r.wheel_id, r.result, r.createtime FROM record r "
            "INNER JOIN ("
            "  SELECT wheel_id AS wheel, MAX(createtime) AS latestTime "
            "  FROM record WHERE carrier_id = :rack AND wheel_id BETWEEN 1 AND 16 "
            "  GROUP BY wheel_id"
            ") latest ON r.wheel_id = latest.wheel "
            "AND r.createtime = latest.latestTime "
            "WHERE r.carrier_id = :rack AND r.wheel_id BETWEEN 1 AND 16"));
        latestQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    }
    if (latestQuery.exec()) {
        while (latestQuery.next()) {
            const int wheel = latestQuery.value(0).toInt();
            QVariantMap item;
            item.insert(QStringLiteral("wheelId"), wheel);
            item.insert(QStringLiteral("wheel"), wheel);
            item.insert(QStringLiteral("result"), latestQuery.value(1).toInt());
            item.insert(QStringLiteral("time"), latestQuery.value(2).toString());

            if (wheel >= 1 && wheel <= 8) driveWheels[wheel - 1] = item;
            else if (wheel >= 9 && wheel <= 16) walkingWheels[wheel - 9] = item;
        }
    }

    QSqlQuery rateQuery(db);
    rateQuery.prepare(QStringLiteral(
        "SELECT wheel_id, result FROM record "
        "WHERE carrier_id = :rack "
        "AND createtime >= :todayStart "
        "AND wheel_id BETWEEN 1 AND 16"));
    rateQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    rateQuery.bindValue(QStringLiteral(":todayStart"),
                        AgcUtils::formatDateTime(QDateTime(QDate::currentDate(), QTime(0, 0))));
    QHash<int, int> passedCounts;
    QHash<int, int> totalCounts;
    if (rateQuery.exec()) {
        while (rateQuery.next()) {
            const int wheel = rateQuery.value(0).toInt();
            ++totalCounts[wheel];
            if (rateQuery.value(1).toInt() == 1) ++passedCounts[wheel];
        }
    }

    int ngCount = 0;
    int totalCount = 0;
    QSqlQuery totalQuery(db);
    totalQuery.prepare(QStringLiteral(
        "SELECT COUNT(*), SUM(CASE WHEN result = 0 THEN 1 ELSE 0 END) FROM record "
        "WHERE carrier_id = :rack AND wheel_id BETWEEN 1 AND 16"));
    totalQuery.bindValue(QStringLiteral(":rack"), rackNumber);
    if (totalQuery.exec() && totalQuery.next()) {
        totalCount = totalQuery.value(0).toInt();
        ngCount = totalQuery.value(1).toInt();
    }

    auto applyPassRate = [&](QVariantList &wheels) {
        for (int i = 0; i < wheels.size(); ++i) {
            QVariantMap item = wheels.at(i).toMap();
            const int wheel = item.value(QStringLiteral("wheel")).toInt();
            item.insert(QStringLiteral("passRate"), totalCounts.value(wheel) > 0
                        ? passedCounts.value(wheel) * 100.0 / totalCounts.value(wheel) : 0.0);
            wheels[i] = item;
        }
    };
    applyPassRate(driveWheels);
    applyPassRate(walkingWheels);

    overview.insert(QStringLiteral("drive"), driveWheels);
    overview.insert(QStringLiteral("walking"), walkingWheels);
    overview.insert(QStringLiteral("ngCount"), ngCount);
    overview.insert(QStringLiteral("totalCount"), totalCount);
    overview.insert(QStringLiteral("ngRate"), totalCount > 0 ? ngCount * 100.0 / totalCount : 0.0);
    return overview;
}

QVariantList wheelRackResultStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                  int wheelNumber, const QString &resultType)
{
    QVariantList out;
    if (wheelNumber < 1 || wheelNumber > 16 || !usable(db)) return out;

    QVector<int> counts(50, 0);
    const bool isOk = resultType.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0;
    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "SELECT carrier_id, COUNT(*) FROM record "
        "WHERE createtime >= :start AND createtime <= :end "
        "AND wheel_id = :wheel AND result = :result "
        "GROUP BY carrier_id"));
    q.bindValue(QStringLiteral(":start"), boundText(startDate, false));
    q.bindValue(QStringLiteral(":end"), boundText(endDate, true));
    q.bindValue(QStringLiteral(":wheel"), wheelNumber);
    q.bindValue(QStringLiteral(":result"), isOk ? 1 : 0);

    if (q.exec()) {
        while (q.next()) {
            const int rack = q.value(0).toInt();
            if (rack >= 1 && rack <= 50) counts[rack - 1] = q.value(1).toInt();
        }
    } else {
        LOG_ERROR("wheelRackResultStats 数据库查询失败: {}", q.lastError().text().toStdString());
    }

    const int totalResultCount = std::accumulate(counts.cbegin(), counts.cend(), 0);
    for (int i = 0; i < 50; ++i) {
        QVariantMap row;
        row[QStringLiteral("carrierId")] = i + 1;
        row[QStringLiteral("rack")] = i + 1;
        row[QStringLiteral("count")] = counts[i];
        row[QStringLiteral("percent")] = totalResultCount > 0 ? counts[i] * 100.0 / totalResultCount : 0.0;
        out.append(row);
    }
    return out;
}

QVariantList rackWheelResultStats(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                                  int rackNumber, const QString &resultType, int wheelType)
{
    QVariantList out;
    if (rackNumber < 1 || rackNumber > 50 || !usable(db)) return out;

    const bool isOk = resultType.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0;
    const int firstWheel = wheelType == 0 ? 1 : 9;

    QVector<int> slotCounts(8, 0);
    QSqlQuery query(db);
    query.prepare(QStringLiteral(
        "SELECT wheel_id, COUNT(*) FROM record "
        "WHERE carrier_id = :rack "
        "AND result = :result "
        "AND createtime >= :start AND createtime <= :end "
        "AND wheel_id BETWEEN :low AND :high "
        "GROUP BY wheel_id"));
    query.bindValue(QStringLiteral(":rack"), rackNumber);
    query.bindValue(QStringLiteral(":result"), isOk ? 1 : 0);
    query.bindValue(QStringLiteral(":start"), boundText(startDate, false));
    query.bindValue(QStringLiteral(":end"), boundText(endDate, true));
    query.bindValue(QStringLiteral(":low"), firstWheel);
    query.bindValue(QStringLiteral(":high"), firstWheel + 7);

    if (query.exec()) {
        while (query.next()) {
            const int slot = query.value(0).toInt() - firstWheel;
            if (slot >= 0 && slot < 8) slotCounts[slot] += query.value(1).toInt();
        }
    } else {
        LOG_ERROR("rackWheelResultStats 数据库查询失败: {}", query.lastError().text().toStdString());
    }

    for (int s = 0; s < 8; ++s) {
        QVariantMap row;
        row.insert(QStringLiteral("rack"), rackNumber);
        row.insert(QStringLiteral("wheel"), firstWheel + s);
        row.insert(QStringLiteral("slot"), s + 1);
        row.insert(QStringLiteral("count"), slotCounts[s]);
        row.insert(QStringLiteral("result"), isOk ? QStringLiteral("OK") : QStringLiteral("NG"));
        out.append(row);
    }
    return out;
}

QVariantList gearSum(const QSqlDatabase &db, const QString &startDate, const QString &endDate,
                     const QString &rackno, const QVariantList &selectedTurns)
{
    // Build date bounds
    QDateTime startTime = AgcUtils::parseFlexibleDateTime(startDate, false);
    QDateTime endTime = AgcUtils::parseFlexibleDateTime(endDate, true);
    const QString rackTrimmed = rackno.trimmed();
    bool rackOk = false;
    const int rackValue = rackTrimmed.toInt(&rackOk);
    const bool filterByRack = !rackTrimmed.isEmpty() && (!rackOk || rackValue > 0);

    // prepare wheel filter
    QStringList wheelList;
    {
        for (const QVariant &v : selectedTurns) {
            const int wheel = v.toInt();
            if (wheel >= 1 && wheel <= 16) wheelList << QString::number(wheel);
        }
    }

    // default counts map
    QMap<int,QPair<int,int>> counts; // wheel -> (ok,ng)
    int outputRangeStart = 1;
    int outputRangeEnd = 8;
    // If user provided an explicit contiguous eight-wheel list, adapt the output range.
    if (!wheelList.isEmpty()) {
        QList<int> wheels;
        for (const QString &s : wheelList) wheels.append(s.toInt());
        std::sort(wheels.begin(), wheels.end());
        int minw = wheels.first();
        int maxw = wheels.last();
        if (wheels.size() == 8 && maxw - minw == 7) {
            outputRangeStart = minw;
            outputRangeEnd = maxw;
        }
    }
    for (int i=outputRangeStart;i<=outputRangeEnd;i++) counts[i] = qMakePair(0,0);

    if (db.isValid() && db.isOpen()) {
        QSqlQuery q(db);
        QString sql = QStringLiteral("SELECT wheel_id, result, COUNT(*) as c FROM record");
        QStringList where{QStringLiteral("wheel_id BETWEEN 1 AND 16")};
        if (startTime.isValid()) where << "createtime >= :start";
        if (endTime.isValid()) where << "createtime <= :end";
        if (filterByRack) where << "carrier_id = :rack";
        if (!wheelList.isEmpty()) where << QStringLiteral("wheel_id IN (%1)").arg(wheelList.join(","));
        if (!where.isEmpty()) sql += " WHERE " + where.join(" AND ");
        sql += " GROUP BY wheel_id, result";

        if (!q.prepare(sql)) {
            LOG_ERROR("gearSum SQL 预处理失败: {}", q.lastError().text().toStdString());
        } else {
            if (startTime.isValid()) q.bindValue(":start", AgcUtils::formatDateTime(startTime));
            if (endTime.isValid()) q.bindValue(":end", AgcUtils::formatDateTime(endTime));
            if (filterByRack) q.bindValue(":rack", rackValue);

            // Log final SQL and parameters for debugging
            QString debugSql = sql;
            LOG_DEBUG("gearSum SQL: {}", debugSql.toStdString());
            QStringList paramLog;
            if (startTime.isValid()) paramLog << QStringLiteral(":start=%1").arg(AgcUtils::formatDateTime(startTime));
            if (endTime.isValid()) paramLog << QStringLiteral(":end=%1").arg(AgcUtils::formatDateTime(endTime));
            if (filterByRack) paramLog << QStringLiteral(":rack=%1").arg(rackValue);
            else paramLog << QStringLiteral(":rack=ALL");
            if (!wheelList.isEmpty()) paramLog << QStringLiteral("wheels=%1").arg(wheelList.join(","));
            LOG_DEBUG("gearSum 参数: {}", paramLog.join(" ").toStdString());

            if (q.exec()) {
                while (q.next()) {
                    int wheel = q.value(0).toInt();
                    int res = q.value(1).toInt();
                    int c = q.value(2).toInt();
                    LOG_DEBUG("gearSum 行数据: wheel={} res={} count={}", wheel, res, c);
                    if (wheel >= outputRangeStart && wheel <= outputRangeEnd) {
                        if (res == 1) counts[wheel].first += c; else counts[wheel].second += c;
                    }
                }
            } else {
                LOG_ERROR("gearSum 数据库查询失败: {}", q.lastError().text().toStdString());
            }
        }
    } else {
        LOG_ERROR("gearSum 无法执行查询，数据库未连接");
    }

    QVariantList out;
    for (int i = outputRangeStart; i <= outputRangeEnd; ++i) {
        QVariantMap mapItem;
        mapItem.insert(QStringLiteral("wheel"), i);
        mapItem.insert(QStringLiteral("ok"), counts[i].first);
        mapItem.insert(QStringLiteral("ng"), counts[i].second);
        out.append(mapItem);
    }
    return out;
}

QVariant run(const QSqlDatabase &db, const QString &kind, const QVariantList &args, bool *ok)
{
    auto arg = [&](int i) { return args.value(i); };
    auto need = [&](int count) { return args.size() >= count; };
    bool known = true;
    QVariant result;

    if (kind == QLatin1String("driveWheelRackStats") && need(2)) {
        result = wheelGroupRackStats(db, arg(0).toString(), arg(1).toString(), 1, 8);
    } else if (kind == QLatin1String("walkingWheelRackStats") && need(2)) {
        result = wheelGroupRackStats(db, arg(0).toString(), arg(1).toString(), 9, 16);
    } else if (kind == QLatin1String("rackWheelMonitorStatus")) {
        result = rackWheelMonitorStatus(db);
    } else if (kind == QLatin1String("rackPhotoCounts")) {
        result = rackPhotoCounts(db);
    } else if (kind == QLatin1String("homepageCurrentDetection")) {
        result = homepageCurrentDetection(db, arg(0).toInt());
    } else if (kind == QLatin1String("wheelRackResultStats") && need(4)) {
        result = wheelRackResultStats(db, arg(0).toString(), arg(1).toString(),
                                      arg(2).toInt(), arg(3).toString());
    } else if (kind == QLatin1String("rackWheelResultStats") && need(5)) {
        result = rackWheelResultStats(db, arg(0).toString(), arg(1).toString(),
                                      arg(2).toInt(), arg(3).toString(), arg(4).toInt());
    } else {
        known = false;
    }

    if (ok) *ok = known;
    return result;
}

} // namespace StatsService
