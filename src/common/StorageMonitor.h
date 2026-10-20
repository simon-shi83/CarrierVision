#pragma once

#include <QString>
#include <QStringList>

// 磁盘剩余空间检查：图像目录、FTP 根目录、数据库与日志所在分区中取剩余比例最低者。
namespace StorageMonitor {

struct Usage {
    QString path;           // 剩余比例最低的分区上的路径
    qint64 freeBytes = 0;
    qint64 totalBytes = 0;
    double freePercent = 100.0;
    bool valid = false;
};

enum class Level {
    Ok,
    Warn,           // 低于告警阈值：提示
    RejectUploads,  // 低于拒收阈值：FTP 拒收新上传，触发紧急清理
    RejectData,     // 低于停止阈值：TCP 也停止入库，避免写坏数据库
};

Usage lowest(const QStringList &paths);
// 阈值为百分比，要求 warn > rejectUploads > rejectData
Level levelFor(double freePercent, int warnPercent, int rejectUploadsPercent, int rejectDataPercent);
QString levelName(Level level);

} // namespace StorageMonitor
