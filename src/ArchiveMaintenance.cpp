#include "ArchiveMaintenance.h"
#include "AgcUtils.h"
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QCoreApplication>

namespace {
bool safeFile(const QString &path, const QStringList &roots)
{
    const QString absolute = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    if (!AgcUtils::isImageFile(absolute)) return false;
    for (const QString &raw : roots) {
        const QFileInfo info(raw);
        const QString root = info.canonicalFilePath();
        if (root.isEmpty() || info.isSymbolicLink() || root == QDir::rootPath()
            || root == QDir::homePath() || root == QCoreApplication::applicationDirPath()) continue;
        const QString relative = QDir(root).relativeFilePath(absolute);
        if (relative == ".." || relative.startsWith("../") || QDir::isAbsolutePath(relative)) continue;
        QString current = root;
        bool safe = true;
        for (const QString &component : relative.split('/')) {
            current = QDir(current).filePath(component);
            if (QFileInfo(current).isSymbolicLink()) { safe = false; break; }
        }
        if (safe) return true;
    }
    return false;
}
}

bool ArchiveMaintenance::cleanup(QSqlDatabase db, const QString &archiveRoot,
    const QStringList &roots, const QDateTime &cutoff, int &removed, bool &more, QString &error)
{
    removed = 0; more = false;
    if (!cutoff.isValid() || !db.isOpen() || !db.transaction()) { error = "数据库不可用"; return false; }
    auto fail = [&](const QString &reason) { error = reason; db.rollback(); return false; };
    QSqlQuery select(db);
    select.prepare("SELECT imagename FROM record GROUP BY imagename "
                   "HAVING COUNT(*)=COUNT(datetime(createtime)) AND MAX(datetime(createtime)) < datetime(:cutoff) LIMIT 500");
    select.bindValue(":cutoff", AgcUtils::formatDateTime(cutoff));
    if (!select.exec()) return fail(select.lastError().text());
    QStringList names;
    while (select.next()) names.append(select.value(0).toString());
    select.finish();
    int queued = 0;
    for (const auto &name : names) {
        const QString path = QDir::cleanPath(QDir(archiveRoot).absoluteFilePath(name));
        if (!safeFile(path, roots) || QFileInfo::exists(path + ".cv-pending")) continue;
        QSqlQuery queue(db);
        queue.prepare("INSERT OR IGNORE INTO cleanup_files(path,imagename) VALUES(:path,:name)");
        queue.bindValue(":path", path); queue.bindValue(":name", name);
        if (!queue.exec()) return fail(queue.lastError().text());
        for (const auto &table : {"record", "alertrecord", "rackwheelnorm"}) {
            QSqlQuery erase(db);
            erase.prepare(QString("DELETE FROM %1 WHERE imagename=:name AND datetime(createtime)<datetime(:cutoff)").arg(table));
            erase.bindValue(":name", name); erase.bindValue(":cutoff", AgcUtils::formatDateTime(cutoff));
            if (!erase.exec()) return fail(erase.lastError().text());
        }
        ++queued;
    }
    if (!db.commit()) return fail(db.lastError().text());
    // The committed queue survives failures between DB commit and file removal.
    // Recheck references on every retry, including records that arrived after a crash.
    QSqlQuery pending(db);
    if (!pending.exec("SELECT path,imagename FROM cleanup_files LIMIT 500")) { error = pending.lastError().text(); return false; }
    QList<QPair<QString,QString>> files;
    while (pending.next()) files.append({pending.value(0).toString(), pending.value(1).toString()});
    pending.finish();
    bool success = true;
    for (const auto &file : files) {
        const auto &path = file.first;
        if (!safeFile(path, roots) || QFileInfo::exists(path + ".cv-pending")) { success = false; continue; }
        QSqlQuery refs(db);
        refs.prepare("SELECT 1 FROM record WHERE imagename=:name LIMIT 1");
        refs.bindValue(":name", file.second);
        if (!refs.exec()) { success = false; continue; }
        const bool referenced = refs.next(); refs.finish();
        if (!referenced && QFileInfo::exists(path) && !QFile::remove(path)) { success = false; continue; }
        QSqlQuery done(db);
        done.prepare("DELETE FROM cleanup_files WHERE path=:path"); done.bindValue(":path", path);
        if (!done.exec()) { success = false; continue; }
        if (!referenced) ++removed;
    }
    more = success && (queued == 500 || files.size() == 500);
    if (!success) error = "部分文件未删除，已保留恢复队列";
    return success;
}
