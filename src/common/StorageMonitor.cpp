#include "common/StorageMonitor.h"

#include <QDir>
#include <QFileInfo>
#include <QStorageInfo>

namespace StorageMonitor {

Usage lowest(const QStringList &paths)
{
    Usage worst;
    for (const QString &path : paths) {
        if (path.isEmpty()) continue;
        // 路径可能尚未创建：向上找到第一个存在的目录
        QString probe = QFileInfo(path).absoluteFilePath();
        while (!probe.isEmpty() && !QFileInfo::exists(probe)) {
            const QString parent = QFileInfo(probe).absolutePath();
            if (parent == probe) break;
            probe = parent;
        }
        QStorageInfo storage(probe);
        storage.refresh();
        if (!storage.isValid() || !storage.isReady() || storage.bytesTotal() <= 0) continue;
        const double percent = storage.bytesAvailable() * 100.0 / storage.bytesTotal();
        if (!worst.valid || percent < worst.freePercent) {
            worst.path = path;
            worst.freeBytes = storage.bytesAvailable();
            worst.totalBytes = storage.bytesTotal();
            worst.freePercent = percent;
            worst.valid = true;
        }
    }
    return worst;
}

Level levelFor(double freePercent, int warnPercent, int rejectUploadsPercent, int rejectDataPercent)
{
    if (freePercent < rejectDataPercent) return Level::RejectData;
    if (freePercent < rejectUploadsPercent) return Level::RejectUploads;
    if (freePercent < warnPercent) return Level::Warn;
    return Level::Ok;
}

QString levelName(Level level)
{
    switch (level) {
    case Level::Ok: return QStringLiteral("ok");
    case Level::Warn: return QStringLiteral("warn");
    case Level::RejectUploads: return QStringLiteral("rejectUploads");
    case Level::RejectData: return QStringLiteral("rejectData");
    }
    return QStringLiteral("ok");
}

} // namespace StorageMonitor
