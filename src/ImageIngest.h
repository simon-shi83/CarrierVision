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
    QString imageName;
};

struct BatchData {
    int carrierId = 0;
    QDateTime timestamp;
    QString batchId;
    QString requestId;
    QVector<WheelItem> wheels;
};

bool parseBatchJson(const QJsonObject &obj, BatchData &out, QString &error);
bool recordBatch(QSqlDatabase db, const BatchData &batch, QString &error);

bool validate(const QString &file, const QString &target, QString &error);
// 接收并归档上传图像
bool accept(const QString &staged, const QString &target,
            const std::function<bool(const QString &)> &ingest, QString &error);

}
