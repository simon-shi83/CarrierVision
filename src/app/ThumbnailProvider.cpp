#include "app/ThumbnailProvider.h"

#include "common/AppLogger.h"

#include <QFileInfo>
#include <QQuickTextureFactory>
#include <QRunnable>
#include <QThread>
#include <QUrl>

#include <algorithm>
#include <atomic>

namespace {

class ThumbnailResponse final : public QQuickImageResponse, public QRunnable
{
public:
    ThumbnailResponse(ThumbnailCache *cache, QString path, int edge)
        : m_cache(cache), m_path(std::move(path)), m_edge(edge)
    {
        // 由 QML 引擎在 finished 之后删除
        setAutoDelete(false);
    }

    void run() override
    {
        if (!m_cancelled.load()) {
            QString error;
            if (!QFileInfo(m_path).isFile()) {
                error = QStringLiteral("文件不存在");
            } else {
                m_image = m_cache->thumbnail(m_path, m_edge, &error);
            }
            if (m_image.isNull()) {
                m_error = QStringLiteral("缩略图生成失败: %1").arg(error);
                LOG_WARN("热力图像：缩略图生成失败，文件={}，原因={}", m_path.toStdString(), error.toStdString());
            }
        }
        emit finished();
    }

    void cancel() override { m_cancelled.store(true); }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override { return m_error; }

private:
    ThumbnailCache *m_cache;
    QString m_path;
    int m_edge;
    QImage m_image;
    QString m_error;
    std::atomic_bool m_cancelled{false};
};

} // namespace

ThumbnailProvider::ThumbnailProvider(qint64 cacheBytes)
    : m_cache(cacheBytes)
{
    // 同时解码的原图数量决定峰值内存：现场机 28 线程时取 4，低配机器至少 2
    m_pool.setMaxThreadCount(std::clamp(QThread::idealThreadCount() / 6, 2, 4));
    m_pool.setObjectName(QStringLiteral("ThumbnailDecode"));
    LOG_INFO("热力图像：缩略图解码线程={}，缓存上限={}MB", m_pool.maxThreadCount(), cacheBytes / (1024 * 1024));
}

ThumbnailProvider::~ThumbnailProvider()
{
    m_pool.clear();
    m_pool.waitForDone();
}

QQuickImageResponse *ThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    const QString path = QUrl::fromPercentEncoding(id.toUtf8());
    auto *response = new ThumbnailResponse(&m_cache, path, ThumbnailCache::edgeFor(requestedSize));
    m_pool.start(response);
    return response;
}
