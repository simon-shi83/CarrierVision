#include "ImageIngest.h"
#include "AgcUtils.h"
#include "AppLogger.h"
#include <QFileInfo>
#include <QFile>
#include <QSaveFile>
#include <QImageReader>
#include <QImage>
#include <QDateTime>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>
#include <QSet>
#include <cmath>

namespace ImageIngest {

bool parseBatchJson(const QJsonObject &obj, BatchData &out, QString &error)
{
    out = {};
    if (!obj.value(QStringLiteral("carrierId")).isDouble()
        || !obj.value(QStringLiteral("wheels")).isArray()) {
        error = QStringLiteral("JSON 缺少 carrierId 或 wheels 字段");
        return false;
    }

    const double carrierNumber = obj.value(QStringLiteral("carrierId")).toDouble();
    if (std::floor(carrierNumber) != carrierNumber) {
        error = QStringLiteral("载具号必须为整数");
        return false;
    }
    out.carrierId = static_cast<int>(carrierNumber);
    if (out.carrierId < 1 || out.carrierId > 50) {
        error = QStringLiteral("载具号 %1 超出有效范围 [1, 50]").arg(out.carrierId);
        return false;
    }

    const QString timeStr = obj.value(QStringLiteral("timestamp")).toString();
    if (!timeStr.isEmpty()) {
        out.timestamp = QDateTime::fromString(timeStr, QStringLiteral("yyyyMMdd_HHmmss"));
        if (!out.timestamp.isValid()) {
            out.timestamp = QDateTime::fromString(timeStr, QStringLiteral("yyyyMMddHHmmss"));
        }
        if (!out.timestamp.isValid()) {
            out.timestamp = QDateTime::fromString(timeStr, Qt::ISODate);
        }
    }
    if (!timeStr.isEmpty() && !out.timestamp.isValid()) {
        error = QStringLiteral("timestamp 格式无效");
        return false;
    }
    if (!out.timestamp.isValid()) {
        out.timestamp = QDateTime::currentDateTime();
    }

    out.requestId = obj.value(QStringLiteral("requestId")).toString().trimmed();
    if (out.requestId.size() > 128 || out.requestId.contains(QChar::Null)) {
        error = QStringLiteral("requestId 长度或内容无效");
        return false;
    }

    out.batchId = QStringLiteral("CARRIER_%1_%2")
                      .arg(out.carrierId)
                      .arg(out.timestamp.toString(QStringLiteral("yyyyMMdd_HHmmss")));

    const QJsonArray wheelsArr = obj.value(QStringLiteral("wheels")).toArray();
    if (wheelsArr.isEmpty() || wheelsArr.size() > 32) {
        error = QStringLiteral("wheels 数量必须在 [1, 32] 范围内");
        return false;
    }
    QSet<QString> wheelKeys;
    for (const QJsonValue &val : wheelsArr) {
        if (!val.isObject()) {
            error = QStringLiteral("wheels 中包含非对象元素");
            return false;
        }
        const QJsonObject wObj = val.toObject();

        if (!wObj.value(QStringLiteral("wheelId")).isDouble()) {
            error = QStringLiteral("wheelId 缺失或类型无效");
            return false;
        }

        WheelItem item;
        const double wheelNumber = wObj.value(QStringLiteral("wheelId")).toDouble();
        const QJsonValue cameraValue = wObj.value(QStringLiteral("cameraId"));
        const double cameraNumber = cameraValue.isUndefined() ? 1.0 : cameraValue.toDouble(-1.0);
        if (std::floor(wheelNumber) != wheelNumber || std::floor(cameraNumber) != cameraNumber) {
            error = QStringLiteral("wheelId 和 cameraId 必须为整数");
            return false;
        }
        item.wheelId = static_cast<int>(wheelNumber);
        item.cameraId = static_cast<int>(cameraNumber);
        item.actualDistance = wObj.value(QStringLiteral("actualDistance")).toDouble();
        item.baseDistance = wObj.value(QStringLiteral("baseDistance")).toDouble();
        item.lowerTolerance = wObj.value(QStringLiteral("lowerTolerance")).toDouble();

        item.imageName = wObj.value(QStringLiteral("imageName")).toString().trimmed();

        if (item.wheelId < 1 || item.wheelId > 16
            || item.cameraId < 1 || item.cameraId > 12
            || !std::isfinite(item.actualDistance)
            || !std::isfinite(item.baseDistance)
            || !std::isfinite(item.lowerTolerance)
            || item.imageName.size() > 512 || item.imageName.contains(QChar::Null)) {
            error = QStringLiteral("轮号、相机号、距离或图片名超出有效范围");
            return false;
        }

        const QJsonValue resultValue = wObj.value(QStringLiteral("result"));
        if (resultValue.isString()) {
            const QString token = resultValue.toString().trimmed().toUpper();
            if (token == QStringLiteral("OK")) item.result = 1;
            else if (token == QStringLiteral("NG") || token == QStringLiteral("NOK")
                     || token == QStringLiteral("BAD")) item.result = 0;
            else {
                error = QStringLiteral("未知检测结果: %1").arg(token.left(32));
                return false;
            }
        } else if (resultValue.isDouble()
                   && (resultValue.toDouble() == 0.0 || resultValue.toDouble() == 1.0)) {
            item.result = static_cast<int>(resultValue.toDouble());
        } else {
            error = QStringLiteral("result 必须为 OK/NG 或 0/1");
            return false;
        }

        const QString key = QStringLiteral("%1:%2").arg(item.cameraId).arg(item.wheelId);
        if (wheelKeys.contains(key)) {
            error = QStringLiteral("同一批次包含重复的相机/轮号: %1").arg(key);
            return false;
        }
        wheelKeys.insert(key);

        out.wheels.append(item);
    }

    if (out.wheels.isEmpty()) {
        error = QStringLiteral("wheels 列表为空");
        return false;
    }

    return true;
}

bool recordBatch(QSqlDatabase db, const BatchData &batch, QString &error)
{
    for (const WheelItem &wheel : batch.wheels) {
        if (wheel.wheelId < 1 || wheel.wheelId > 16) {
            error = QStringLiteral("轮号 %1 超出有效范围 [1, 16]").arg(wheel.wheelId);
            return false;
        }
    }
    if (!db.isOpen() || !db.transaction()) {
        error = db.lastError().text();
        return false;
    }

    const QString timeText = AgcUtils::formatDateTime(batch.timestamp);

    if (!batch.requestId.isEmpty()) {
        QSqlQuery request(db);
        request.prepare(QStringLiteral(
            "INSERT OR IGNORE INTO ingest_requests(request_id, carrier_id, item_count, committed_at) "
            "VALUES(:request, :carrier, :count, datetime('now','localtime'))"));
        request.bindValue(QStringLiteral(":request"), batch.requestId);
        request.bindValue(QStringLiteral(":carrier"), batch.carrierId);
        request.bindValue(QStringLiteral(":count"), batch.wheels.size());
        if (!request.exec()) {
            error = request.lastError().text();
            db.rollback();
            return false;
        }
        if (request.numRowsAffected() == 0) {
            QSqlQuery existing(db);
            existing.prepare(QStringLiteral(
                "SELECT carrier_id, item_count FROM ingest_requests WHERE request_id=:request"));
            existing.bindValue(QStringLiteral(":request"), batch.requestId);
            if (!existing.exec() || !existing.next()
                || existing.value(0).toInt() != batch.carrierId
                || existing.value(1).toInt() != batch.wheels.size()) {
                error = QStringLiteral("requestId 已被不同批次占用");
                db.rollback();
                return false;
            }
            db.rollback();
            return true;
        }
    }

    QSqlQuery q(db);
    if (!q.prepare(R"(
        INSERT INTO record(createtime, carrier_id, camera_id, wheel_id, result, distance, dist_norm, lower_tolerance, imagename, batch_id)
        VALUES(:time, :carrier, :camera, :wheel, :result, :dist, :norm, :tol, :image, :batch)
    )")) {
        error = q.lastError().text();
        db.rollback();
        return false;
    }

    for (const auto &wheel : batch.wheels) {
        q.bindValue(QStringLiteral(":time"), timeText);
        q.bindValue(QStringLiteral(":carrier"), batch.carrierId);
        q.bindValue(QStringLiteral(":camera"), wheel.cameraId);
        q.bindValue(QStringLiteral(":wheel"), wheel.wheelId);
        q.bindValue(QStringLiteral(":result"), wheel.result);
        q.bindValue(QStringLiteral(":dist"), wheel.actualDistance);
        q.bindValue(QStringLiteral(":norm"), wheel.baseDistance);
        q.bindValue(QStringLiteral(":tol"), wheel.lowerTolerance);
        q.bindValue(QStringLiteral(":image"), wheel.imageName);
        q.bindValue(QStringLiteral(":batch"), batch.batchId);

        if (!q.exec()) {
            error = q.lastError().text();
            db.rollback();
            return false;
        }
    }

    if (!db.commit()) {
        error = db.lastError().text();
        return false;
    }

    return true;
}

bool validate(const QString &file, const QString &target, QString &error)
{
    const QFileInfo info(file);
    const qint64 fileSize = info.exists() ? info.size() : -1;

    LOG_DEBUG("[INGEST] 收到上传文件: target='{}', staged='{}', 大小={} 字节",
              target.toStdString(), file.toStdString(), fileSize);

    if (!info.isFile() || info.isSymbolicLink() || fileSize <= 0
        || fileSize > 512LL * 1024 * 1024 || !AgcUtils::isImageFile(target)) {
        error = QStringLiteral("上传文件类型或大小无效");
        LOG_WARN("[INGEST] 文件类型或大小无效: target='{}', 大小={}", target.toStdString(), fileSize);
        return false;
    }
    QImageReader reader(file);
    reader.setDecideFormatFromContent(true);
    const QSize size = reader.size();
    if (!size.isValid() || qint64(size.width()) * size.height() > 200LL * 1000 * 1000
        || !reader.canRead()) {
        error = QStringLiteral("上传图片损坏或无法解码: %1").arg(reader.errorString());
        LOG_WARN("[INGEST] 图片解码校验失败: file='{}', target='{}', error='{}'",
                 file.toStdString(), target.toStdString(), error.toStdString());
        return false;
    }
    return true;
}

static bool sameContent(const QString &a, const QString &b)
{
    QFile left(a), right(b);
    if (!left.open(QIODevice::ReadOnly) || !right.open(QIODevice::ReadOnly) || left.size() != right.size()) return false;
    while (!left.atEnd()) {
        const QByteArray block = left.read(256 * 1024);
        if (block.isEmpty() || block != right.read(block.size())) return false;
    }
    return left.error() == QFileDevice::NoError && right.error() == QFileDevice::NoError;
}

bool accept(const QString &staged, const QString &target,
            const std::function<bool(const QString &)> &ingest, QString &error)
{
    if (!validate(staged, target, error)) return false;
    const bool exists = QFileInfo::exists(target);
    if (QFileInfo(target).isSymbolicLink() || (exists && !sameContent(staged, target))) {
        error = QStringLiteral("同名文件内容不同，已保留原图: %1").arg(target);
        LOG_WARN("[INGEST] 同名文件内容不同，保留原图: target='{}'", target.toStdString());
        return false;
    }
    const QString marker = target + QStringLiteral(".cv-pending");
    if (!QFileInfo::exists(marker)) {
        QSaveFile journal(marker);
        const QByteArray data = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss").toUtf8();
        if (!journal.open(QIODevice::WriteOnly) || journal.write(data) != data.size() || !journal.commit()) {
            error = QStringLiteral("无法保存上传恢复记录");
            LOG_ERROR("[INGEST] 无法保存上传恢复记录: {}", marker.toStdString());
            return false;
        }
    }
    if (!exists) {
        QFile stagedFile(staged);
        if (!stagedFile.rename(target)) {
            const QString renameError = stagedFile.errorString();

            // Windows 上临时上传文件可能在 close 后仍被短暂占用，导致同卷
            // rename 失败。复制到一个尚不存在的目标文件是安全回退：QFile::copy
            // 不会覆盖目标，因此不会破坏并发上传或已有归档。
            if (!QFile::copy(staged, target)) {
                error = QStringLiteral("无法提交上传文件，原图未替换: %1").arg(renameError);
                LOG_ERROR("[INGEST] 无法提交临时文件: staged='{}', target='{}', renameError='{}'",
                          staged.toStdString(), target.toStdString(), renameError.toStdString());
                return false;
            }

            if (!sameContent(staged, target)) {
                QFile::remove(target);
                error = QStringLiteral("上传文件复制校验失败，原图未替换");
                LOG_ERROR("[INGEST] 临时文件复制后校验失败: staged='{}', target='{}', renameError='{}'",
                          staged.toStdString(), target.toStdString(), renameError.toStdString());
                return false;
            }

            if (!stagedFile.remove()) {
                LOG_WARN("[INGEST] 临时文件已复制提交，但清理失败: staged='{}', error='{}'",
                         staged.toStdString(), stagedFile.errorString().toStdString());
            }
            LOG_WARN("[INGEST] 临时文件改名失败，已通过复制回退提交: staged='{}', target='{}', renameError='{}'",
                     staged.toStdString(), target.toStdString(), renameError.toStdString());
        }
    }
    if (ingest && !ingest(target)) {
        error = QStringLiteral("文件已保存，后续处理失败；保留恢复记录等待重试");
        LOG_ERROR("[INGEST] 文件入库后续处理失败: target='{}'", target.toStdString());
        return false;
    }
    if (!QFile::remove(marker)) {
        error = QStringLiteral("无法清除上传恢复记录");
        LOG_WARN("[INGEST] 无法清除恢复记录标记: {}", marker.toStdString());
        return false;
    }
    LOG_INFO("[INGEST] 图像归档成功: target='{}'", target.toStdString());
    return true;
}

}
