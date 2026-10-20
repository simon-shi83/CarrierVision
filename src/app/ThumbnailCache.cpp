#include "app/ThumbnailCache.h"

#include <QFileInfo>
#include <QImageReader>
#include <QMutexLocker>

#include <algorithm>
#include <iterator>

namespace {

qint64 costKb(const QImage &image)
{
    return std::max<qint64>(1, (image.sizeInBytes() + 1023) / 1024);
}

} // namespace

ThumbnailCache::ThumbnailCache(qint64 maxBytes)
{
    m_cache.setMaxCost(std::max<qint64>(1, maxBytes / 1024));
}

int ThumbnailCache::edgeFor(const QSize &requested)
{
    const int edge = std::max(requested.width(), requested.height());
    if (edge <= 0) return kDefaultEdge;
    for (int step : kEdgeSteps) {
        if (edge <= step) return step;
    }
    return kEdgeSteps[std::size(kEdgeSteps) - 1];
}

QImage ThumbnailCache::decode(const QString &path, int maxEdge, QString *error)
{
    maxEdge = std::max(16, maxEdge);
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize source = reader.size();
    if (source.isValid() && (source.width() > maxEdge || source.height() > maxEdge)) {
        // 支持按比例解码的格式（JPEG）直接输出小图；其余格式由 Qt 解码后立即缩放并释放原图
        reader.setScaledSize(source.scaled(maxEdge, maxEdge, Qt::KeepAspectRatio));
    }

    QImage image = reader.read();
    if (image.isNull()) {
        if (error) *error = reader.errorString();
        return QImage();
    }
    if (image.width() > maxEdge || image.height() > maxEdge) {
        image = image.scaled(maxEdge, maxEdge, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    // 灰度图保持单通道（工业相机常见），其余统一为便于上传纹理的 32 位格式
    if (image.format() != QImage::Format_Grayscale8) {
        image = image.convertToFormat(image.hasAlphaChannel() ? QImage::Format_ARGB32_Premultiplied
                                                              : QImage::Format_RGB32);
    }
    return image;
}

QString ThumbnailCache::keyFor(const QString &path, int maxEdge)
{
    const QFileInfo info(path);
    return QStringLiteral("%1|%2|%3|%4")
        .arg(info.absoluteFilePath())
        .arg(info.lastModified().toMSecsSinceEpoch())
        .arg(info.size())
        .arg(maxEdge);
}

QImage ThumbnailCache::thumbnail(const QString &path, int maxEdge, QString *error)
{
    const QString key = keyFor(path, maxEdge);
    {
        QMutexLocker locker(&m_mutex);
        if (const QImage *hit = m_cache.object(key)) return *hit;
    }

    // 解码在锁外进行，多个工作线程可并行解码不同图片
    QImage image = decode(path, maxEdge, error);
    if (image.isNull()) return image;

    QMutexLocker locker(&m_mutex);
    m_cache.insert(key, new QImage(image), costKb(image));
    return image;
}

qint64 ThumbnailCache::maxBytes() const
{
    QMutexLocker locker(&m_mutex);
    return qint64(m_cache.maxCost()) * 1024;
}

qint64 ThumbnailCache::usedBytes() const
{
    QMutexLocker locker(&m_mutex);
    return qint64(m_cache.totalCost()) * 1024;
}

int ThumbnailCache::count() const
{
    QMutexLocker locker(&m_mutex);
    return int(m_cache.count());
}

void ThumbnailCache::clear()
{
    QMutexLocker locker(&m_mutex);
    m_cache.clear();
}
