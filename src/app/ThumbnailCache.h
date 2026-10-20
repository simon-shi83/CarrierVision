#pragma once

#include <QCache>
#include <QImage>
#include <QMutex>
#include <QSize>
#include <QString>

// 缩略图解码与内存缓存：热力图像一屏要显示上百张现场大图，不能按原图解码常驻内存。
// 解码时直接缩放到 maxEdge（JPEG 在解码阶段按比例缩小，不生成原尺寸位图），
// 结果按实际字节数计入 LRU 缓存，超过上限时淘汰最久未用的缩略图。线程安全。
class ThumbnailCache
{
public:
    // 缩略图长边只取这几档，窗口缩放时不会为同一张图生成大量不同尺寸的缓存
    static constexpr int kEdgeSteps[] = {160, 320, 480, 640};
    static constexpr int kDefaultEdge = 480;

    explicit ThumbnailCache(qint64 maxBytes);

    // 把界面请求的尺寸映射到最近的档位（不小于请求的长边，最大 640）
    static int edgeFor(const QSize &requested);
    // 解码并缩放到长边不超过 maxEdge；失败返回空图并给出原因
    static QImage decode(const QString &path, int maxEdge, QString *error = nullptr);

    // 先查缓存（以路径、修改时间、大小和档位为键，文件被覆盖后自动失效），未命中则解码并放入缓存
    QImage thumbnail(const QString &path, int maxEdge, QString *error = nullptr);

    qint64 maxBytes() const;
    qint64 usedBytes() const;
    int count() const;
    void clear();

private:
    static QString keyFor(const QString &path, int maxEdge);

    mutable QMutex m_mutex;
    // 成本单位为 KB，避免 qsizetype 在 32 位平台上溢出
    QCache<QString, QImage> m_cache;
};
