#include "data/DatabaseGuard.h"

#include "common/AppLogger.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>

namespace DatabaseGuard {

bool quickCheck(QSqlDatabase &db, QString &detail)
{
    QSqlQuery q(db);
    if (!q.exec(QStringLiteral("PRAGMA quick_check(5)"))) {
        detail = q.lastError().text();
        return false;
    }
    QStringList problems;
    while (q.next()) problems << q.value(0).toString();
    if (problems == QStringList{QStringLiteral("ok")}) return true;
    detail = problems.join(QStringLiteral("; ")).left(512);
    return false;
}

QStringList backups(const QString &backupDir)
{
    QDir dir(backupDir);
    QStringList result;
    // 文件名中的时间戳按字典序即时间序
    const QStringList names = dir.entryList({QStringLiteral("dataAgc-*.db")}, QDir::Files, QDir::Name | QDir::Reversed);
    for (const QString &name : names) result << dir.filePath(name);
    return result;
}

bool backup(QSqlDatabase &db, const QString &backupDir, int keep, QString &error, QString *createdPath)
{
    if (!QDir().mkpath(backupDir)) {
        error = QStringLiteral("无法创建备份目录 %1").arg(backupDir);
        return false;
    }
    const QString target = QDir(backupDir).filePath(
        QStringLiteral("dataAgc-%1.db").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"))));
    // 先写临时文件，完成后改名，避免恢复时选中写了一半的备份
    const QString temp = target + QStringLiteral(".partial");
    QFile::remove(temp);
    QSqlQuery q(db);
    q.prepare(QStringLiteral("VACUUM INTO ?"));
    q.addBindValue(temp);
    if (!q.exec()) {
        error = q.lastError().text();
        QFile::remove(temp);
        return false;
    }
    QFile::remove(target);
    if (!QFile::rename(temp, target)) {
        error = QStringLiteral("备份改名失败: %1").arg(target);
        QFile::remove(temp);
        return false;
    }
    if (createdPath) *createdPath = target;
    const QStringList all = backups(backupDir);
    for (int i = qMax(1, keep); i < all.size(); ++i) QFile::remove(all.at(i));
    return true;
}

namespace {

bool checkFile(const QString &path, QString &detail)
{
    const QString name = QStringLiteral("integrity_%1").arg(QUuid::createUuid().toString(QUuid::Id128));
    bool ok = false;
    {
        QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), name);
        db.setDatabaseName(path);
        if (!db.open()) {
            detail = db.lastError().text();
        } else {
            ok = quickCheck(db, detail);
            db.close();
        }
    }
    QSqlDatabase::removeDatabase(name);
    return ok;
}

} // namespace

QString recoverIfCorrupt(const QString &dbPath, const QString &backupDir)
{
    if (!QFileInfo::exists(dbPath)) return QString();
    QString detail;
    if (checkFile(dbPath, detail)) return QString();

    LOG_CRITICAL("[DB] 数据库完整性检查失败: {} ({})", dbPath.toStdString(), detail.toStdString());
    const QString suffix = QStringLiteral(".corrupt-%1").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")));
    for (const QString &ext : {QString(), QStringLiteral("-wal"), QStringLiteral("-shm")}) {
        if (QFileInfo::exists(dbPath + ext) && !QFile::rename(dbPath + ext, dbPath + suffix + ext)) {
            return QStringLiteral("数据库已损坏，且无法改名保留原文件 %1，请人工处理").arg(dbPath + ext);
        }
    }

    for (const QString &candidate : backups(backupDir)) {
        QString backupDetail;
        if (!checkFile(candidate, backupDetail)) {
            LOG_ERROR("[DB] 备份不可用，跳过: {} ({})", candidate.toStdString(), backupDetail.toStdString());
            continue;
        }
        if (QFile::copy(candidate, dbPath)) {
            const QString message = QStringLiteral("数据库已损坏，已从备份 %1 恢复；原文件保留为 %2。备份之后写入的数据已丢失。")
                                        .arg(QFileInfo(candidate).fileName(), QFileInfo(dbPath + suffix).fileName());
            LOG_CRITICAL("[DB] {}", message.toStdString());
            return message;
        }
    }
    const QString message = QStringLiteral("数据库已损坏且没有可用备份，已以新数据库启动；原文件保留为 %1。")
                                .arg(QFileInfo(dbPath + suffix).fileName());
    LOG_CRITICAL("[DB] {}", message.toStdString());
    return message;
}

QString runningMarkerPath(const QString &dbPath)
{
    return QFileInfo(dbPath).absolutePath() + QStringLiteral("/.running");
}

QString corruptMarkerPath(const QString &dbPath)
{
    return QFileInfo(dbPath).absolutePath() + QStringLiteral("/.db-check-required");
}

} // namespace DatabaseGuard
