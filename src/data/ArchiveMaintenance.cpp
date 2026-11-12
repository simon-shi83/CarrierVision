#include "data/ArchiveMaintenance.h"
#include "common/AgcUtils.h"
#include "common/AppLogger.h"
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFile>
#include <QSet>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QCoreApplication>

namespace {
constexpr int kBatchSize = 500;

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

// 文件是否仍被记录引用：按实际路径，或按图片名（仅限尚未关联实际路径的记录）
bool referenced(QSqlDatabase &db, const QString &path, const QString &name, bool &ok)
{
    QSqlQuery refs(db);
    refs.prepare("SELECT 1 FROM record WHERE image_path=:path "
                 "UNION ALL SELECT 1 FROM record WHERE imagename=:name AND (image_path IS NULL OR image_path='') "
                 "LIMIT 1");
    refs.bindValue(":path", path);
    refs.bindValue(":name", name);
    ok = refs.exec();
    const bool found = ok && refs.next();
    refs.finish();
    return found;
}
}

bool ArchiveMaintenance::cleanup(QSqlDatabase db, const QString &archiveRoot,
    const QStringList &roots, const QDateTime &cutoff, int &removed, bool &more, QString &error,
    CleanupStats *stats)
{
    removed = 0; more = false;
    CleanupStats local;
    CleanupStats &s = stats ? *stats : local;
    s = {};
    if (!cutoff.isValid() || !db.isOpen()) { error = "数据库不可用"; return false; }
    const QString cutoffText = AgcUtils::formatDateTime(cutoff);

    // 候选组的扫描（整表分组，记录越多越慢）在写事务之外执行。若放在延迟事务（BEGIN）里，
    // 扫描期间主线程只要写入一批 TCP 数据，随后的首条写语句就会因读快照过期立即返回
    // "database is locked"（busy_timeout 不生效），整轮清理中止，数据越积越多。
    // 扫描与删除之间新到的记录不受影响：删除语句只删 cutoff 之前的记录，文件删除前还会再查引用。
    QSqlQuery select(db);
    select.prepare("SELECT COALESCE(NULLIF(image_path,''), imagename) AS image_key, "
                   "MAX(image_path IS NOT NULL AND image_path<>'') FROM record GROUP BY image_key "
                   "HAVING COUNT(*)=COUNT(datetime(createtime)) AND MAX(datetime(createtime)) < datetime(:cutoff) LIMIT 500");
    select.bindValue(":cutoff", cutoffText);
    if (!select.exec()) { error = select.lastError().text(); return false; }
    QStringList keys;
    QSet<QString> pathKeys; // 来自 image_path 列（实际落盘路径）的组
    while (select.next()) {
        keys.append(select.value(0).toString());
        if (select.value(1).toInt()) pathKeys.insert(keys.last());
    }
    select.finish();
    s.selected = keys.size();

    // 路径安全检查要访问文件系统，同样放在写事务之前，缩短持有写锁的时间（主线程入库会等这把锁）
    struct Group { QString key; QString path; bool safe; };
    QList<Group> groups;
    groups.reserve(keys.size());
    for (const auto &key : keys) {
        const bool pathKey = pathKeys.contains(key);
        const QString path = QDir::cleanPath(pathKey ? key : QDir(archiveRoot).absoluteFilePath(key));
        if (QFileInfo::exists(path + ".cv-pending")) continue; // 上传提交中，下轮再处理
        groups.append({key, path, !key.isEmpty() && safeFile(path, roots)});
    }

    // BEGIN IMMEDIATE 先拿写锁（受 busy_timeout 等待），之后的写入不会再因快照过期失败
    QSqlQuery begin(db);
    if (!begin.exec(QStringLiteral("BEGIN IMMEDIATE"))) { error = begin.lastError().text(); return false; }
    begin.finish();
    auto fail = [&](const QString &reason) { error = reason; db.rollback(); return false; };

    QSqlQuery queue(db);
    queue.prepare("INSERT OR IGNORE INTO cleanup_files(path,imagename) VALUES(:path,:name)");
    QSqlQuery erase(db);
    erase.prepare(QStringLiteral(
        "DELETE FROM record WHERE (image_path=:key OR (imagename=:key AND (image_path IS NULL OR image_path=''))) "
        "AND datetime(createtime)<datetime(:cutoff)"));
    for (const Group &group : std::as_const(groups)) {
        if (group.safe) {
            queue.bindValue(":path", group.path); queue.bindValue(":name", group.key);
            if (!queue.exec()) return fail(queue.lastError().text());
        } else {
            // 路径不在图像根目录内（历史数据中的绝对路径、../ 或非图片名）：保留文件，但必须删除记录，
            // 否则这些组每轮都会被重新选中，累计满一批后清理将永久停滞
            if (s.skippedUnsafe < 5)
                LOG_WARN("[CLEANUP] 图片路径不在图像根目录内，仅删除记录、保留文件: '{}'", group.key.left(256).toStdString());
            ++s.skippedUnsafe;
        }
        erase.bindValue(":key", group.key); erase.bindValue(":cutoff", cutoffText);
        if (!erase.exec()) return fail(erase.lastError().text());
        s.recordsDeleted += erase.numRowsAffected();
    }
    queue.finish();
    erase.finish();
    QSqlQuery alerts(db);
    alerts.prepare("DELETE FROM alertrecord WHERE datetime(createtime)<datetime(:cutoff)");
    alerts.bindValue(":cutoff", cutoffText);
    if (!alerts.exec()) return fail(alerts.lastError().text());
    // TCP 重发去重表此前从不清理，只增不减；记录过期后其 requestId 也不再需要
    QSqlQuery requests(db);
    requests.prepare("DELETE FROM ingest_requests WHERE committed_at < :cutoff");
    requests.bindValue(":cutoff", cutoffText);
    if (!requests.exec()) return fail(requests.lastError().text());
    s.requestsDeleted = requests.numRowsAffected();
    if (!db.commit()) return fail(db.lastError().text());
    if (s.skippedUnsafe > 5)
        LOG_WARN("[CLEANUP] 本轮共 {} 组图片路径不在图像根目录内，仅删除了记录", s.skippedUnsafe);

    // The committed queue survives failures between DB commit and file removal.
    // Recheck references on every retry, including records that arrived after a crash.
    QSqlQuery pending(db);
    if (!pending.exec("SELECT path,imagename FROM cleanup_files LIMIT 500")) { error = pending.lastError().text(); return false; }
    QList<QPair<QString,QString>> files;
    while (pending.next()) files.append({pending.value(0).toString(), pending.value(1).toString()});
    pending.finish();
    bool success = true;
    QStringList finished;
    for (const auto &file : files) {
        const auto &path = file.first;
        if (!safeFile(path, roots) || QFileInfo::exists(path + ".cv-pending")) { success = false; continue; }
        bool refsOk = false;
        const bool isReferenced = referenced(db, path, file.second, refsOk);
        if (!refsOk) { success = false; continue; }
        if (!isReferenced && QFileInfo::exists(path) && !QFile::remove(path)) { success = false; continue; }
        finished << path;
        if (!isReferenced) { ++removed; ++s.filesDeleted; }
    }
    // 已处理的队列项在一个事务中移除；若此前崩溃，残留项下一轮会重新检查（文件已不存在则直接移除）
    if (!finished.isEmpty()) {
        if (!db.transaction()) {
            success = false;
        } else {
            QSqlQuery done(db);
            done.prepare("DELETE FROM cleanup_files WHERE path=:path");
            for (const QString &path : std::as_const(finished)) {
                done.bindValue(":path", path);
                if (!done.exec()) { success = false; break; }
            }
            if (!success || !db.commit()) { db.rollback(); success = false; }
        }
    }
    more = success && (keys.size() == kBatchSize || files.size() == kBatchSize);
    if (!success) error = "部分文件未删除，已保留恢复队列";
    return success;
}

int ArchiveMaintenance::sweepOrphans(QSqlDatabase db, const QStringList &managedRoots, const QDateTime &olderThan,
                                     int maxFiles, QString &error)
{
    if (!db.isOpen() || !olderThan.isValid() || maxFiles <= 0) { error = "数据库不可用"; return 0; }

    // 去重并去掉嵌套的根目录，避免同一文件被扫描两次
    QStringList roots;
    for (const QString &raw : managedRoots) {
        const QString canonical = QFileInfo(raw).canonicalFilePath();
        if (!canonical.isEmpty() && !roots.contains(canonical)) roots << canonical;
    }
    QStringList topRoots;
    for (const QString &root : roots) {
        bool nested = false;
        for (const QString &other : roots)
            if (other != root && root.startsWith(other + '/')) nested = true;
        if (!nested) topRoots << root;
    }

    int deleted = 0;
    for (const QString &root : std::as_const(topRoots)) {
        QDirIterator it(root, QDir::Files | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDirIterator::Subdirectories);
        while (it.hasNext() && deleted < maxFiles) {
            const QString path = QDir::cleanPath(it.next());
            const QFileInfo info = it.fileInfo();
            if (info.fileName().startsWith('.') || !AgcUtils::isImageFile(path)) continue;
            if (info.lastModified() >= olderThan || QFileInfo::exists(path + ".cv-pending")) continue;
            if (!safeFile(path, {root})) continue;
            // 按实际路径或文件名任一被引用都保留（文件名匹配比清理更保守，覆盖未关联路径的历史记录）
            QSqlQuery refs(db);
            refs.prepare("SELECT 1 FROM record WHERE image_path=:path UNION ALL "
                         "SELECT 1 FROM record WHERE imagename=:name LIMIT 1");
            refs.bindValue(":path", path);
            refs.bindValue(":name", info.fileName());
            if (!refs.exec()) { error = refs.lastError().text(); return deleted; }
            const bool used = refs.next();
            refs.finish();
            if (used) continue;
            if (QFile::remove(path)) {
                ++deleted;
                LOG_INFO("[CLEANUP] 删除超期未被引用的孤儿图片: {}", path.toStdString());
            }
        }
    }
    return deleted;
}
