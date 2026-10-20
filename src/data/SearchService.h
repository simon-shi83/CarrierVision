#pragma once

#include "app/ImageListModel.h"

#include <QPair>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVector>

// 检测记录查询：过滤条件构建、分页查询与图片路径解析。
// 均为无状态函数，可在任意线程使用该线程自己的数据库连接调用。
namespace SearchService {

// 记录查询的公共过滤条件：时间范围、架号、轮号（DRIVE / WALK / 逗号列表 / 单个轮号）
struct RecordFilter {
    QStringList where;
    QVector<QPair<QString, QVariant>> binds;

    QString clause() const { return QStringLiteral(" WHERE ") + where.join(QStringLiteral(" AND ")); }
    void bind(QSqlQuery &query) const
    {
        for (const auto &value : binds) query.bindValue(value.first, value.second);
    }
};

RecordFilter buildRecordFilter(const QString &startText, const QString &endText, int rackNumber, const QString &wheelNo);

// 按 filter 查询 table（record / alertrecord，列结构相同）的一页并统计总数；COUNT 失败时返回 false
bool queryRecordPage(const QSqlDatabase &db, const QString &table, const RecordFilter &filter,
                     int page, int pageSize, const QString &archiveDir, const QString &sourceDir,
                     int &totalCount, QVector<ImageItem> &items);

// "OK"/"1" -> 1，"NG"/"0" -> 0；其余返回 false
bool parseResultFilter(const QString &text, int &result);

// 在原路径、归档目录、源目录及程序目录附近查找图片；只返回已确认存在的绝对路径，找不到返回空串
QString resolveImagePath(const QString &rawName, const QString &archiveDir, const QString &sourceDir);

} // namespace SearchService
