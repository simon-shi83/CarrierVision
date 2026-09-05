#pragma once

#include <QSqlDatabase>

namespace DBSchema {

// Ensure all required tables and indices exist. Returns true on success.
bool ensureAllTables(QSqlDatabase &db);

}
