#pragma once

#include "app/ThumbnailCache.h"

#include <QQuickAsyncImageProvider>
#include <QThreadPool>

// QML 缩略图来源：Image { source: "image://thumb/" + encodeURIComponent(本地路径) }。
// 解码在专用线程池中进行（线程数有限，控制同时解码的原图数量和峰值内存），
// 结果进入 ThumbnailCache；列表快速滚动时，已移出视野的请求会被取消，不再解码。
class ThumbnailProvider final : public QQuickAsyncImageProvider
{
public:
    static constexpr const char *kProviderId = "thumb";

    explicit ThumbnailProvider(qint64 cacheBytes);
    ~ThumbnailProvider() override;

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private:
    ThumbnailCache m_cache;
    QThreadPool m_pool;
};
