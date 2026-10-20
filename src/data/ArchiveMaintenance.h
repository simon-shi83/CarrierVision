#pragma once
#include <QSqlDatabase>
#include <QStringList>
#include <QDateTime>
namespace ArchiveMaintenance {

struct CleanupStats {
    int selected = 0;        // 本轮选中的过期图片组
    int recordsDeleted = 0;  // 删除的检测记录
    int filesDeleted = 0;    // 删除的图片文件
    int skippedUnsafe = 0;   // 路径不在图像根目录内：只删记录、保留文件
};

// Deletes only DB-referenced, expired image files. Never deletes a directory.
// 记录按实际落盘路径 image_path 分组（为空时按 imagename）；路径不安全的组只删除记录，保证每轮都有进展。
bool cleanup(QSqlDatabase db, const QString &archiveRoot, const QStringList &managedRoots,
             const QDateTime &cutoff, int &removed, bool &more, QString &error,
             CleanupStats *stats = nullptr);

// 删除图像根目录下修改时间早于 olderThan、且没有任何记录引用的图片（孤儿文件）。
// 每次最多删除 maxFiles 个；返回删除数量。不删除目录、隐藏文件与仍有 .cv-pending 标记的文件。
int sweepOrphans(QSqlDatabase db, const QStringList &managedRoots, const QDateTime &olderThan,
                 int maxFiles, QString &error);
}
