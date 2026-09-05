#pragma once
#include <QSqlDatabase>
#include <QStringList>
#include <QDateTime>
namespace ArchiveMaintenance {
// Deletes only DB-referenced, expired image files. Never deletes a directory.
bool cleanup(QSqlDatabase db, const QString &archiveRoot, const QStringList &managedRoots,
             const QDateTime &cutoff, int &removed, bool &more, QString &error);
}
