#pragma once

#include <QString>
#include <QVector>
#include <QDateTime>
#include <QJsonObject>
#include <QJsonArray>
#include <functional>
#include <QSqlDatabase>
#include <QVariantList>

namespace ImageIngest {

struct WheelItem {
    int wheelId = 1;
    int cameraId = 1;
    double actualDistance = 0.0;
    double baseDistance = 0.0;
    double lowerTolerance = 0.0;
    int result = 1; // 0=NG, 1=OK
    QString imageName;  // 规范化后的纯文件名
    QString imagePath;  // 已关联到的实际落盘文件（绝对路径），未关联时为空
};

struct BatchData {
    int carrierId = 0;
    QDateTime timestamp;
    QString batchId;
    QString requestId;
    QVector<WheelItem> wheels;
};

// 时间戳允许范围：now 无效时不限制；maxAgeDays 为 0 时不限制过去
struct ParseLimits {
    QDateTime now;
    int maxAgeDays = 0;
    int maxFutureSecs = 600;
};

bool parseBatchJson(const QJsonObject &obj, BatchData &out, QString &error, const ParseLimits &limits = {});
// 取 imageName 的文件名部分（兼容 / 与 \ 分隔）；空名、"."、".." 开头或非图片扩展名返回空串并给出原因
// strippedPath 非空时报告是否去掉了路径部分（由调用方汇总记录告警）
QString normalizeImageName(const QString &raw, QString &error, bool *strippedPath = nullptr);
bool recordBatch(QSqlDatabase db, const BatchData &batch, QString &error);

bool validate(const QString &file, const QString &target, QString &error);
// 接收并归档上传图像
bool accept(const QString &staged, const QString &target,
            const std::function<bool(const QString &)> &ingest, QString &error);

}
