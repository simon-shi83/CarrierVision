#include "ImageIngest.h"
#include "AgcUtils.h"
#include "AppLogger.h"
#include <QFileInfo>
#include <QFile>
#include <QSaveFile>
#include <QImageReader>
#include <QImage>
#include <QRegularExpression>
#include <QDateTime>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>

namespace ImageIngest {

bool parseBatchJson(const QJsonObject &obj, BatchData &out, QString &error)
{
    out = {};
    if (!obj.contains(QStringLiteral("carrierId")) || !obj.contains(QStringLiteral("wheels"))) {
        error = QStringLiteral("JSON 缺少 carrierId 或 wheels 字段");
        return false;
    }

    out.carrierId = obj.value(QStringLiteral("carrierId")).toInt();
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
    if (!out.timestamp.isValid()) {
        out.timestamp = QDateTime::currentDateTime();
    }

    out.batchId = QStringLiteral("CARRIER_%1_%2")
                      .arg(out.carrierId)
                      .arg(out.timestamp.toString(QStringLiteral("yyyyMMdd_HHmmss")));

    const QJsonArray wheelsArr = obj.value(QStringLiteral("wheels")).toArray();
    for (const QJsonValue &val : wheelsArr) {
        if (!val.isObject()) continue;
        const QJsonObject wObj = val.toObject();

        WheelItem item;
        item.wheelId = wObj.value(QStringLiteral("wheelId")).toInt();
        item.cameraId = wObj.value(QStringLiteral("cameraId")).toInt(1);
        item.actualDistance = wObj.value(QStringLiteral("actualDistance")).toDouble();
        item.baseDistance = wObj.value(QStringLiteral("baseDistance")).toDouble();
        item.lowerTolerance = wObj.value(QStringLiteral("lowerTolerance")).toDouble();

        const QString resStr = wObj.value(QStringLiteral("result")).toString();
        item.result = (resStr.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0) ? 1 : 0;
        item.imageName = wObj.value(QStringLiteral("imageName")).toString().trimmed();

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
    if (!db.isOpen() || !db.transaction()) {
        error = db.lastError().text();
        return false;
    }

    const QString timeText = AgcUtils::formatDateTime(batch.timestamp);

    for (const auto &wheel : batch.wheels) {
        QSqlQuery q(db);
        q.prepare(R"(
            INSERT INTO record(createtime, carrier_id, camera_id, wheel_id, result, distance, dist_norm, lower_tolerance, imagename, batch_id)
            VALUES(:time, :carrier, :camera, :wheel, :result, :dist, :norm, :tol, :image, :batch)
        )");
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

bool parse(const QString &path, Metadata &out, QString &error)
{
    out = {};
    QString base = QFileInfo(path).completeBaseName();
    static const QRegularExpression vSuffix(QStringLiteral("_v[0-9]+$"));
    base.remove(vSuffix);
    const auto parts = base.split('_');
    auto invalid = [&]() { error = QStringLiteral("无法识别的图片元数据: %1").arg(QFileInfo(path).fileName()); return false; };
    if (parts.size() != 8 && parts.size() != 9) return invalid();
    auto integer = [](const QString &text, int &value) {
        static const QRegularExpression digits(QStringLiteral("^[0-9]+$"));
        bool ok = false;
        value = text.toInt(&ok);
        return ok && digits.match(text).hasMatch();
    };
    if (!integer(parts[1], out.carrierId) || out.carrierId < 1 || out.carrierId > 50
        || !integer(parts[2], out.camera) || out.camera < 1 || out.camera > 12) return invalid();
    static const QRegularExpression wheelPattern(QStringLiteral("^([0-9]+)[- ]?(OK|NG|NOK|BAD)$"), QRegularExpression::CaseInsensitiveOption);
    const int count = parts.size() == 9 ? 2 : 1;
    for (int i = 0; i < count; ++i) {
        const auto match = wheelPattern.match(parts[3 + i]);
        if (!match.hasMatch()) return invalid();
        bool ok = false;
        const int wheel = match.captured(1).toInt(&ok);
        if (!ok || !((wheel >= 0 && wheel <= 15) || (wheel >= 1 && wheel <= 18))) return invalid();
        if (!out.wheels.isEmpty() && out.wheels.first().number == wheel) return invalid();
        out.wheels.append({wheel, match.captured(2).compare("OK", Qt::CaseInsensitive) == 0 ? 1 : 0});
    }
    int d = 0, m = 0, n = 0;
    if (!integer(parts[3 + count], d)
        || !integer(parts[4 + count], m)
        || !integer(parts[5 + count], n)) return invalid();
    out.distance = d;
    out.maximum = m;
    out.norm = n;
    return true;
}

QDateTime parseTimestamp(const QString &path, const QDateTime &fallbackTime)
{
    const auto parts = QFileInfo(path).completeBaseName().split('_');
    if (!parts.isEmpty()) {
        const QString &tag = parts.first();
        if (tag.size() == 14) {
            QDateTime dt = QDateTime::fromString(tag, "yyyyMMddHHmmss");
            if (dt.isValid()) return dt;
        } else if (tag.size() >= 15 && tag.at(8) == 'T') {
            QDateTime dt = QDateTime::fromString(tag, Qt::ISODate);
            if (dt.isValid()) return dt;
        }
    }
    return fallbackTime;
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
    if (!exists && !QFile::rename(staged, target)) {
        error = QStringLiteral("无法提交上传文件，原图未替换");
        LOG_ERROR("[INGEST] 无法重命名临时文件至目标文件: staged='{}', target='{}'",
                  staged.toStdString(), target.toStdString());
        return false;
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
