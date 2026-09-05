#pragma once

#include <QSqlDatabase>
#include <QString>

namespace DBSchema {

// Returns the canonical database path (${AppDir}/data/dataAgc.db),
// and auto-relocates legacy ${AppDir}/dataAgc.db (plus -wal, -shm) if present.
QString defaultDatabasePath();

// Ensure all required tables and indices exist. Returns true on success.
bool ensureAllTables(QSqlDatabase &db);

// System configuration helper functions (system_config table)
QString getConfig(QSqlDatabase &db, const QString &key, const QString &defaultValue = QString());
int getConfigInt(QSqlDatabase &db, const QString &key, int defaultValue);
bool getConfigBool(QSqlDatabase &db, const QString &key, bool defaultValue);
bool setConfig(QSqlDatabase &db, const QString &key, const QString &value);

}
