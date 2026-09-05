#include "ImageIngest.h"
#include "AgcUtils.h"
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
    if (!integer(parts[1], out.rack) || out.rack < 1 || out.rack > 50
        || !integer(parts[2], out.camera) || out.camera < 1 || out.camera > 12) return invalid();
    static const QRegularExpression wheelPattern(QStringLiteral("^([0-9]+)[- ]?(OK|NG|NOK|BAD)$"), QRegularExpression::CaseInsensitiveOption);
    const int count = parts.size() == 9 ? 2 : 1;
    for (int i = 0; i < count; ++i) {
        const auto match = wheelPattern.match(parts[3 + i]);
        if (!match.hasMatch()) return invalid();
        bool ok = false;
        const int wheel = match.captured(1).toInt(&ok);
        if (!ok || !((wheel >= 1 && wheel <= 8) || (wheel >= 11 && wheel <= 18))) return invalid();
        if (!out.wheels.isEmpty() && out.wheels.first().number == wheel) return invalid();
        out.wheels.append({wheel, match.captured(2).compare("OK", Qt::CaseInsensitive) == 0 ? 1 : 0});
    }
    if (!integer(parts[3 + count], out.distance)
        || !integer(parts[4 + count], out.maximum)
        || !integer(parts[5 + count], out.norm)) return invalid();
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

bool record(QSqlDatabase db, const Metadata &metadata, const QString &imageName,
            const QString &time, const QVariantList &standards, bool &inserted, QString &error,
            const QString &batchId, int roundNo)
{
    inserted = false;
    if (!db.isOpen() || !db.transaction()) { error = db.lastError().text(); return false; }
    auto fail = [&](const QString &reason) { error = reason; db.rollback(); inserted = false; return false; };
    for (const auto &wheel : metadata.wheels) {
        QSqlQuery q(db);
        q.prepare("INSERT INTO record(createtime,rackno,wheelno,result,imagename,distance,dist_max,dist_norm,batch_id,round_no) "
                  "SELECT :t,:r,:w,:result,:image,:d,:max,:norm,:b,:rnd "
                  "WHERE NOT EXISTS (SELECT 1 FROM record WHERE imagename=:image AND wheelno=:w)");
        q.bindValue(":t", time);
        q.bindValue(":r", QString::number(metadata.rack));
        q.bindValue(":w", QString::number(wheel.number));
        q.bindValue(":result", wheel.result);
        q.bindValue(":image", imageName);
        const bool single = metadata.wheels.size() == 1;
        q.bindValue(":d", single ? metadata.distance : 0);
        q.bindValue(":max", single ? metadata.maximum : 0);
        q.bindValue(":norm", single ? metadata.norm : 0);
        q.bindValue(":b", batchId);
        q.bindValue(":rnd", roundNo);
        if (!q.exec()) return fail(q.lastError().text());
        if (q.numRowsAffected() == 0) continue;
        inserted = true;
        const int standard = standards.value(wheel.number - 1).toInt();
        if (wheel.number > 8 || standard <= 0 || metadata.distance >= standard) continue;
        QSqlQuery norm(db);
        norm.prepare("INSERT OR IGNORE INTO rackwheelnorm(createtime,rackno,wheelno,distance,imagename) "
                     "VALUES(:t,:r,:w,:d,:image)");
        norm.bindValue(":t", time);
        norm.bindValue(":r", metadata.rack);
        norm.bindValue(":w", wheel.number);
        norm.bindValue(":d", metadata.distance);
        norm.bindValue(":image", imageName);
        if (!norm.exec()) return fail(norm.lastError().text());
    }
    if (!db.commit()) return fail(db.lastError().text());
    return true;
}

bool validate(const QString &file, const QString &target, QString &error)
{
    Metadata metadata;
    if (!parse(target, metadata, error)) return false;
    const QFileInfo info(file);
    if (!info.isFile() || info.isSymbolicLink() || info.size() <= 0
        || info.size() > 512LL * 1024 * 1024 || !AgcUtils::isImageFile(target)) {
        error = QStringLiteral("上传文件类型或大小无效"); return false;
    }
    QImageReader reader(file);
    reader.setDecideFormatFromContent(true);
    const QSize size = reader.size();
    if (!size.isValid() || qint64(size.width()) * size.height() > 200LL * 1000 * 1000
        || !reader.canRead() || reader.read().isNull()) {
        error = QStringLiteral("上传图片损坏或无法解码: %1").arg(reader.errorString()); return false;
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
        error = QStringLiteral("同名文件内容不同，已保留原图: %1").arg(target); return false;
    }
    const QString marker = target + QStringLiteral(".cv-pending");
    if (!QFileInfo::exists(marker)) {
        QSaveFile journal(marker);
        const QByteArray data = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss").toUtf8();
        if (!journal.open(QIODevice::WriteOnly) || journal.write(data) != data.size() || !journal.commit()) {
            error = QStringLiteral("无法保存上传恢复记录"); return false;
        }
    }
    if (!exists && !QFile::rename(staged, target)) {
        error = QStringLiteral("无法提交上传文件，原图未替换"); return false;
    }
    if (!ingest || !ingest(target)) {
        error = QStringLiteral("文件已保存，数据库处理失败；保留恢复记录等待重试"); return false;
    }
    if (!QFile::remove(marker)) {
        error = QStringLiteral("无法清除上传恢复记录"); return false;
    }
    return true;
}
}
