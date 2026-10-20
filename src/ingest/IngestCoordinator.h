#pragma once

#include "ingest/ImageIngest.h"
#include "app/ImageListModel.h"

#include <QDateTime>
#include <QHash>
#include <QString>
#include <QVector>
#include <functional>

// FTP 图像与 TCP 测量数据的关联：两者到达顺序不定，先到的图像暂存在缓存中，
// 等 TCP 批次按 imageName 取用；先到的批次则在图像到达时由调用方更新卡片。
namespace IngestCoordinator {

constexpr int kStationCount = 12;
// 同一载具相邻两批数据的最大间隔（一个载具分两次触发、每次 6 个相机）：
// 不超过该间隔的批次属于同一轮检测，超过则视为重新检测
constexpr qint64 kSameCarrierMergeSecs = 120;

// 文件名大小写不敏感的匹配键
QString imageKey(const QString &name);

class PendingImageCache
{
public:
    static constexpr int kMaxEntries = 512;
    static constexpr int kMaxAgeSecs = 5 * 60;

    // imageName 为客户端请求的文件名（匹配键），filePath 为实际落盘路径
    void add(const QString &imageName, const QString &filePath, const QDateTime &receivedAt);
    // 按图像名查找仍存在的缓存文件路径，找不到返回空串
    QString find(const QString &imageName) const;
    void remove(const QString &imageName);
    // 丢弃超时或已被删除的文件，并将数量限制在 kMaxEntries
    void prune(const QDateTime &now);
    int size() const { return m_entries.size(); }

private:
    struct Entry {
        QString filePath;
        QDateTime receivedAt;
    };
    QHash<QString, Entry> m_entries;
};

// 将 TCP 批次映射为 12 张工位相机卡片（CAM 01 ~ CAM 12）：
// 同一相机任一轮 NG 则整卡 NG；卡片的图像与测量值取该相机的第一条轮数据；
// locateImage(imageName) 返回已落盘图像的路径（找不到返回空串）。
QVector<ImageItem> buildStationCards(const ImageIngest::BatchData &batch,
                                     const std::function<QString(const QString &)> &locateImage);

} // namespace IngestCoordinator
