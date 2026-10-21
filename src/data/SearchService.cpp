#include "common/WheelIdentity.h"
#include "data/SearchService.h"

#include "common/AgcUtils.h"
#include "common/AppLogger.h"
#include "ingest/IngestCoordinator.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSqlError>
#include <QUrl>

#include <limits>

namespace SearchService {

QString resolveImagePath(const QString &rawName, const QString &archiveDir, const QString &sourceDir)
{
    // 只在图像根目录内查找：绝对路径、盘符路径或带 .. 的名称只取文件名，不访问根目录之外的文件
    const QString normalized = QDir::fromNativeSeparators(rawName.trimmed());
    if (normalized.isEmpty()) return QString();
    const bool unsafe = QDir::isAbsolutePath(normalized)
        || (normalized.size() > 1 && normalized.at(1) == u':')
        || normalized.split(u'/').contains(QStringLiteral(".."));
    const QString trimmed = unsafe ? QFileInfo(normalized).fileName() : normalized;
    if (trimmed.isEmpty()) return QString();

    // 缓存上次命中的有效根路径（线程局部），在连续解析同一批次图像时几乎 100% 首测命中
    static thread_local QString s_lastHitRoot;

    auto testCandidate = [](const QString &root, const QString &rel) -> QString {
        if (root.isEmpty() || rel.isEmpty()) return QString();
        const QString candidate = QDir(root).filePath(rel);
        if (QFile::exists(candidate)) {
            s_lastHitRoot = root;
            return QFileInfo(candidate).absoluteFilePath();
        }
        return QString();
    };

    // 剥离历史前缀提取相对子路径
    QString subPath = trimmed;
    int idx = subPath.indexOf(QStringLiteral("images/"));
    if (idx >= 0) {
        subPath = subPath.mid(idx + 7);
    } else {
        idx = subPath.indexOf(QStringLiteral("archive/"));
        if (idx >= 0) subPath = subPath.mid(idx + 8);
    }

    // 1. 优先尝试上次命中的有效根目录（单次 I/O 检查直接命中）
    if (!s_lastHitRoot.isEmpty()) {
        QString hit = testCandidate(s_lastHitRoot, trimmed);
        if (!hit.isEmpty()) return hit;
        if (subPath != trimmed) {
            hit = testCandidate(s_lastHitRoot, subPath);
            if (!hit.isEmpty()) return hit;
        }
    }

    // 2. 尝试当前配置的归档目录与源目录
    if (archiveDir != s_lastHitRoot) {
        QString hit = testCandidate(archiveDir, trimmed);
        if (!hit.isEmpty()) return hit;
        if (subPath != trimmed) {
            hit = testCandidate(archiveDir, subPath);
            if (!hit.isEmpty()) return hit;
        }
    }
    if (sourceDir != s_lastHitRoot && sourceDir != archiveDir) {
        QString hit = testCandidate(sourceDir, trimmed);
        if (!hit.isEmpty()) return hit;
        if (subPath != trimmed) {
            hit = testCandidate(sourceDir, subPath);
            if (!hit.isEmpty()) return hit;
        }
    }

    // 3. 静态备用相对路径（避免每次重复分配构造 QStringList）
    static const QString appDir = QCoreApplication::applicationDirPath();
    static const QStringList fallbackRoots = {
        QDir(appDir).filePath(QStringLiteral("images")),
        QDir(appDir).filePath(QStringLiteral("archive")),
        QDir(appDir).filePath(QStringLiteral("../images")),
        QDir(appDir).filePath(QStringLiteral("../archive")),
        QDir(appDir).filePath(QStringLiteral("../../../images")),
        QDir(appDir).filePath(QStringLiteral("../../../archive")),
        QDir(appDir).filePath(QStringLiteral("../../../../images")),
        QDir(appDir).filePath(QStringLiteral("../../../../archive"))
    };

    for (const QString &root : fallbackRoots) {
        if (root == s_lastHitRoot || root == archiveDir || root == sourceDir) continue;
        QString hit = testCandidate(root, trimmed);
        if (!hit.isEmpty()) return hit;
        if (subPath != trimmed) {
            hit = testCandidate(root, subPath);
            if (!hit.isEmpty()) return hit;
        }
    }

    return QString();
}

QString resolveRecordImage(const QString &imagePath, const QString &imageName,
                           const QString &archiveDir, const QString &sourceDir)
{
    if (!imagePath.isEmpty()) {
        const QFileInfo stored(imagePath);
        if (stored.isAbsolute() && stored.isFile()) return stored.absoluteFilePath();
    }
    return resolveImagePath(imageName, archiveDir, sourceDir);
}

QVariantList latestRoundImages(const QSqlDatabase &db, const QString &archiveDir, const QString &sourceDir)
{
    using IngestCoordinator::kStationCount;
    constexpr int kRackCount = 50;
    // 一轮最多两批、每批最多 32 轮，留余量
    constexpr int kRoundRowLimit = 128;

    struct Camera {
        bool hasRecord = false;
        int result = 1;
        QString time;
        QString imageName;
        QString imagePath;
        QStringList wheels;
        QVariantList wheelIds;
    };

    QVariantList out;
    const bool usable = db.isValid() && db.isOpen();
    QSqlQuery rows(db);
    if (usable) {
        // 走 idx_record_carrier_time 索引，每架只读最近的少量记录
        rows.prepare(QStringLiteral(
            "SELECT camera_id, wheel_id, result, createtime, imagename, image_path, distance FROM record "
            "WHERE carrier_id = :rack ORDER BY createtime DESC, rowid DESC LIMIT %1").arg(kRoundRowLimit));
    }

    for (int rack = 1; rack <= kRackCount; ++rack) {
        QVector<Camera> cameras(kStationCount);
        QString latestText;
        if (usable) {
            rows.bindValue(QStringLiteral(":rack"), rack);
            if (!rows.exec()) {
                LOG_ERROR("热力图像：查询架号 #{} 本轮记录失败: {}", rack, rows.lastError().text().toStdString());
            } else {
                QDateTime newest;
                while (rows.next()) {
                    const QString time = rows.value(3).toString();
                    const QDateTime at = AgcUtils::parseFlexibleDateTime(time, false);
                    if (latestText.isEmpty()) {
                        latestText = time;
                        newest = at;
                    }
                    if (newest.isValid() && at.isValid()
                        && at.secsTo(newest) > IngestCoordinator::kSameCarrierMergeSecs) {
                        break; // 按时间倒序，之后都是上一轮
                    }
                    const int cameraId = rows.value(0).toInt();
                    if (cameraId < 1 || cameraId > kStationCount) continue;
                    Camera &camera = cameras[cameraId - 1];
                    const QString imageName = rows.value(4).toString().trimmed();
                    if (!camera.hasRecord) {
                        camera.hasRecord = true;
                        camera.time = time;
                        camera.imageName = imageName;
                        camera.imagePath = rows.value(5).toString();
                    } else if (IngestCoordinator::imageKey(imageName) != IngestCoordinator::imageKey(camera.imageName)) {
                        continue; // 同一相机本轮较早的另一张图，不计入当前显示的图像
                    } else if (camera.imagePath.isEmpty()) {
                        camera.imagePath = rows.value(5).toString(); // 同一张图的其他轮可能已补写落盘路径
                    }
                    const int result = rows.value(2).toInt();
                    if (result == 0) camera.result = 0;
                    camera.wheelIds.prepend(rows.value(1));
                    camera.wheels.prepend(QStringLiteral("%1 %2 %3mm")
                                              .arg(WheelIdentity::label(rows.value(1)))
                                              .arg(result ? QStringLiteral("OK") : QStringLiteral("NG"))
                                              .arg(rows.value(6).toDouble(), 0, 'f', 1));
                }
                rows.finish();
            }
        }

        QVariantList images;
        int cameraCount = 0;
        int imageCount = 0;
        int ngCount = 0;
        for (int i = 0; i < kStationCount; ++i) {
            const Camera &camera = cameras[i];
            QVariantMap image;
            image.insert(QStringLiteral("cameraId"), i + 1);
            image.insert(QStringLiteral("hasRecord"), camera.hasRecord);
            image.insert(QStringLiteral("result"), camera.result);
            image.insert(QStringLiteral("time"), camera.time);
            image.insert(QStringLiteral("fileName"), QFileInfo(camera.imageName).fileName());
            image.insert(QStringLiteral("wheels"), camera.wheels);
            image.insert(QStringLiteral("wheelIds"), camera.wheelIds);
            QString path;
            if (camera.hasRecord) {
                ++cameraCount;
                if (camera.result == 0) ++ngCount;
                path = resolveRecordImage(camera.imagePath, camera.imageName, archiveDir, sourceDir);
                if (!path.isEmpty()) ++imageCount;
            }
            image.insert(QStringLiteral("hasImage"), !path.isEmpty());
            image.insert(QStringLiteral("filePath"), path);
            image.insert(QStringLiteral("fileUrl"), path.isEmpty() ? QString() : QUrl::fromLocalFile(path).toString());
            images.append(image);
        }

        QVariantMap group;
        group.insert(QStringLiteral("rack"), rack);
        group.insert(QStringLiteral("time"), latestText);
        group.insert(QStringLiteral("status"), cameraCount == 0 ? QStringLiteral("none")
                                               : (ngCount > 0 ? QStringLiteral("ng") : QStringLiteral("ok")));
        group.insert(QStringLiteral("cameraCount"), cameraCount);
        group.insert(QStringLiteral("imageCount"), imageCount);
        group.insert(QStringLiteral("ngCount"), ngCount);
        group.insert(QStringLiteral("images"), images);
        out.append(group);
    }
    return out;
}

RecordFilter buildRecordFilter(const QString &startText, const QString &endText, int rackNumber, const QString &wheelNo)
{
    RecordFilter filter;
    filter.where << QStringLiteral("wheel_id BETWEEN 1 AND 16");
    const QDateTime startTime = AgcUtils::parseFlexibleDateTime(startText.trimmed(), false);
    const QDateTime endTime = AgcUtils::parseFlexibleDateTime(endText.trimmed(), true);
    if (startTime.isValid()) {
        filter.where << QStringLiteral("createtime >= :start");
        filter.binds.append({QStringLiteral(":start"), AgcUtils::formatDateTime(startTime)});
    }
    if (endTime.isValid()) {
        filter.where << QStringLiteral("createtime <= :end");
        filter.binds.append({QStringLiteral(":end"), AgcUtils::formatDateTime(endTime)});
    }
    if (rackNumber > 0) {
        filter.where << QStringLiteral("carrier_id = :rack");
        filter.binds.append({QStringLiteral(":rack"), rackNumber});
    }

    const QString wheelToken = wheelNo.trimmed();
    if (wheelToken == QStringLiteral("DRIVE")) {
        filter.where << QStringLiteral("wheel_id BETWEEN 1 AND 8");
    } else if (wheelToken == QStringLiteral("WALK")) {
        filter.where << QStringLiteral("wheel_id BETWEEN 9 AND 16");
    } else if (wheelToken.contains(',')) {
        QStringList wheelNumbers;
        for (const QString &part : wheelToken.split(',', Qt::SkipEmptyParts)) {
            bool ok = false;
            const int wheel = part.trimmed().toInt(&ok);
            if (ok && wheel >= 1 && wheel <= 16) wheelNumbers << QString::number(wheel);
        }
        if (!wheelNumbers.isEmpty())
            filter.where << QStringLiteral("wheel_id IN (%1)").arg(wheelNumbers.join(','));
    } else if (!wheelToken.isEmpty() && wheelToken != QStringLiteral("0")) {
        bool ok = false;
        const int wheel = wheelToken.toInt(&ok);
        if (ok && wheel >= 1 && wheel <= 16) {
            filter.where << QStringLiteral("wheel_id = :wheel");
            filter.binds.append({QStringLiteral(":wheel"), wheel});
        } else {
            filter.where << QStringLiteral("1 = 0");
        }
    }
    return filter;
}

bool queryRecordPage(const QSqlDatabase &db, const QString &table, const RecordFilter &filter,
                     int page, int pageSize, const QString &archiveDir, const QString &sourceDir,
                     int &totalCount, QVector<ImageItem> &items)
{
    QSqlQuery countQuery(db);
    if (!countQuery.prepare(QStringLiteral("SELECT COUNT(*) FROM ") + table + filter.clause())) {
        LOG_ERROR("分页查询 COUNT 预处理失败({}): {}", table.toStdString(), countQuery.lastError().text().toStdString());
        return false;
    }
    filter.bind(countQuery);
    if (!countQuery.exec()) {
        LOG_ERROR("分页查询统计失败({}): {}", table.toStdString(), countQuery.lastError().text().toStdString());
        return false;
    }
    totalCount = countQuery.next()
        ? static_cast<int>(qMin<qint64>(countQuery.value(0).toLongLong(), std::numeric_limits<int>::max()))
        : 0;

    const qint64 offset = static_cast<qint64>(page - 1) * pageSize;
    QSqlQuery dataQuery(db);
    if (!dataQuery.prepare(QStringLiteral(
            "SELECT createtime, carrier_id, wheel_id, camera_id, result, imagename, distance, dist_norm, lower_tolerance, %1 FROM ")
            .arg(table == QLatin1String("record") ? QStringLiteral("image_path") : QStringLiteral("NULL"))
            + table + filter.clause()
            + QStringLiteral(" ORDER BY createtime DESC LIMIT %1 OFFSET %2").arg(pageSize).arg(offset))) {
        LOG_ERROR("分页查询数据预处理失败({}): {}", table.toStdString(), dataQuery.lastError().text().toStdString());
        return false;
    }
    filter.bind(dataQuery);
    if (!dataQuery.exec()) {
        LOG_ERROR("分页查询数据执行失败({}): {}", table.toStdString(), dataQuery.lastError().text().toStdString());
        return true; // 保持原行为：数据查询失败时仍返回总数与空页
    }
    while (dataQuery.next()) {
        ImageItem item;
        const QString timeText = dataQuery.value(0).toString();
        item.receivedAt = QDateTime::fromString(timeText, QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        if (!item.receivedAt.isValid()) item.receivedAt = QDateTime::fromString(timeText, Qt::ISODate);
        item.carrierId = dataQuery.value(1).toInt();
        item.rack = item.carrierId;
        item.wheelId = dataQuery.value(2).toInt();
        item.slot = item.wheelId;
        item.cameraId = dataQuery.value(3).toInt();
        item.result = dataQuery.value(4).toInt();
        const QString rawName = dataQuery.value(5).toString().trimmed();
        item.distance = dataQuery.value(6).toDouble();
        item.dist_norm = dataQuery.value(7).toDouble();
        item.lower_tolerance = dataQuery.value(8).toDouble();
        item.fileName = QFileInfo(rawName).fileName();
        // resolveRecordImage 只返回已确认存在的路径，无需再次检查
        const QString resolvedPath = resolveRecordImage(dataQuery.value(9).toString(), rawName, archiveDir, sourceDir);
        if (!resolvedPath.isEmpty()) {
            item.filePath = resolvedPath;
            item.fileUrl = QUrl::fromLocalFile(resolvedPath).toString();
        }
        items.append(item);
    }
    if (totalCount == 0 && !items.isEmpty()) totalCount = items.size();
    return true;
}

bool parseResultFilter(const QString &text, int &result)
{
    const QString token = text.trimmed();
    if (token.isEmpty()) return false;
    if (token.compare(QStringLiteral("OK"), Qt::CaseInsensitive) == 0 || token == QStringLiteral("1")) {
        result = 1;
        return true;
    }
    if (token.compare(QStringLiteral("NG"), Qt::CaseInsensitive) == 0 || token == QStringLiteral("0")) {
        result = 0;
        return true;
    }
    return false;
}

} // namespace SearchService
