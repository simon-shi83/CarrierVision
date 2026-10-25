#include "common/WheelIdentity.h"
#include "ingest/IngestCoordinator.h"

#include <QFile>
#include <QFileInfo>
#include <QUrl>

namespace IngestCoordinator {

QString imageKey(const QString &name)
{
    return QFileInfo(name).fileName().toCaseFolded();
}

void PendingImageCache::add(const QString &imageName, const QString &filePath, const QDateTime &receivedAt)
{
    const QString key = imageKey(imageName);
    if (key.isEmpty()) return;
    m_entries.insert(key, {filePath, receivedAt});
}

QString PendingImageCache::find(const QString &imageName) const
{
    const auto it = m_entries.constFind(imageKey(imageName));
    if (it == m_entries.cend() || !QFile::exists(it->filePath)) return QString();
    return it->filePath;
}

void PendingImageCache::remove(const QString &imageName)
{
    m_entries.remove(imageKey(imageName));
}

void PendingImageCache::prune(const QDateTime &now)
{
    const QDateTime cutoff = now.addSecs(-kMaxAgeSecs);
    for (auto it = m_entries.begin(); it != m_entries.end();) {
        if (it->receivedAt < cutoff || !QFile::exists(it->filePath)) it = m_entries.erase(it);
        else ++it;
    }

    while (m_entries.size() > kMaxEntries) {
        auto oldest = m_entries.begin();
        for (auto it = std::next(m_entries.begin()); it != m_entries.end(); ++it) {
            if (it->receivedAt < oldest->receivedAt) oldest = it;
        }
        m_entries.erase(oldest);
    }
}

QVector<ImageItem> buildStationCards(const ImageIngest::BatchData &batch,
                                     const std::function<QString(const QString &)> &locateImage)
{
    QVector<ImageItem> cards(kStationCount);
    for (int i = 0; i < kStationCount; ++i) {
        const int camId = i + 1;
        cards[i].batchId = batch.batchId;
        cards[i].carrierId = batch.carrierId;
        cards[i].rack = batch.carrierId;
        cards[i].cameraId = camId;
        cards[i].slot = camId;
        cards[i].receivedAt = batch.timestamp;
        cards[i].result = 1;
        cards[i].serial = QStringLiteral("CAM %1").arg(camId, 2, 10, QLatin1Char('0'));
    }

    for (const auto &wheel : batch.wheels) {
        const int camIdx = wheel.cameraId - 1;
        if (camIdx < 0 || camIdx >= kStationCount) continue;

        ImageItem &card = cards[camIdx];
        if (wheel.result == 0) card.result = 0;
        if (card.fileName.isEmpty()) {
            card.fileName = wheel.imageName;
            card.wheelId = wheel.wheelId;
            card.distance = wheel.actualDistance;
            card.dist_norm = wheel.baseDistance;
            card.lower_tolerance = wheel.lowerTolerance;
        }

        const QString description = QStringLiteral("%1: %2mm (%3)")
                                        .arg(WheelIdentity::label(wheel.wheelId))
                                        .arg(wheel.actualDistance, 0, 'f', 1)
                                        .arg(wheel.result ? "OK" : "NG");
        card.wheelsInfo = card.wheelsInfo.isEmpty() ? description
                                                    : card.wheelsInfo + QStringLiteral(" · ") + description;

        if (wheel.imageName.isEmpty()) continue;
        if (card.fileName.isEmpty()) card.fileName = QFileInfo(wheel.imageName).fileName();
        const QString path = locateImage ? locateImage(wheel.imageName) : QString();
        if (!path.isEmpty()) {
            card.filePath = path;
            card.fileUrl = QUrl::fromLocalFile(path).toString();
        }
    }
    return cards;
}

} // namespace IngestCoordinator
