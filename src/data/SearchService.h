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

// 报警轮位汇总、单幅去重原图分页和批量人工处置。所有请求均强制有效日期范围。
// kind: racks / groups / image / handled / falseAlarm；page 为从 1 开始的图像页号。
// racks 支持 rack=0 汇总全部架号；groups 支持 wheel=0 汇总全部轮位，其他值保留轮系筛选。
QVariantMap alertOperation(const QSqlDatabase &db, const QString &kind,
                          const QString &start, const QString &end, int rack, int wheel,
                          int page, const QString &archiveDir, const QString &sourceDir);

// "OK"/"1" -> 1，"NG"/"0" -> 0；其余返回 false
bool parseResultFilter(const QString &text, int &result);

// 在原路径、归档目录、源目录及程序目录附近查找图片；只返回已确认存在的绝对路径，找不到返回空串
QString resolveImagePath(const QString &rawName, const QString &archiveDir, const QString &sourceDir);
// 优先使用记录中的实际落盘路径 image_path（存在时），否则按图片名查找
QString resolveRecordImage(const QString &imagePath, const QString &imageName,
                           const QString &archiveDir, const QString &sourceDir);

// 热力图像：50 个架号各自最近一轮检测的 12 个相机图像，固定返回 50 组、每组 12 项（CAM 01 ~ CAM 12）。
// 一轮 = 该架号最新记录往前 IngestCoordinator::kSameCarrierMergeSecs 秒内的记录（两次触发各 6 个相机）；
// 每个相机取本轮最新的图像，该图像覆盖的任一轮 NG 则该相机 NG。
// 架项：rack、time、status（none / ok / ng）、cameraCount、imageCount、ngCount、images；
// 图像项：cameraId、hasRecord、hasImage、result、time、fileName、fileUrl、wheels（"轮1 OK 125.4mm" 列表）。
QVariantList latestRoundImages(const QSqlDatabase &db, const QString &archiveDir, const QString &sourceDir);

} // namespace SearchService
