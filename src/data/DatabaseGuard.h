#pragma once

#include <QSqlDatabase>
#include <QString>
#include <QStringList>

// 数据库完整性检查、在线备份与损坏恢复。
namespace DatabaseGuard {

// PRAGMA quick_check；不通过时 detail 给出前几条问题
bool quickCheck(QSqlDatabase &db, QString &detail);

// 用 VACUUM INTO 在 backupDir 下生成 dataAgc-yyyyMMdd-HHmmss.db，只保留最近 keep 份
bool backup(QSqlDatabase &db, const QString &backupDir, int keep, QString &error, QString *createdPath = nullptr);

// backupDir 中的备份，按时间从新到旧
QStringList backups(const QString &backupDir);

// 在打开主连接之前调用：检查 dbPath，损坏时把原库（含 -wal/-shm）改名保留，
// 再用最近一份通过检查的备份恢复；没有可用备份时让程序以新库启动。
// 返回给用户的说明；数据库正常时返回空串。
QString recoverIfCorrupt(const QString &dbPath, const QString &backupDir);

// 运行标记：启动时创建、正常退出时删除；启动时仍存在说明上次异常退出
QString runningMarkerPath(const QString &dbPath);
// 日常检查发现损坏时创建，下次启动强制检查并恢复
QString corruptMarkerPath(const QString &dbPath);

} // namespace DatabaseGuard
