#pragma once
#include <QString>
#include <QVector>
#include <QDateTime>
#include <functional>
#include <QSqlDatabase>
#include <QVariantList>

namespace ImageIngest {
struct Wheel { int number = 0; int result = -1; };
struct Metadata {
    int rack = 0;
    int camera = 0;
    int distance = 0;
    int maximum = 0;
    int norm = 0;
    QVector<Wheel> wheels;
};
bool parse(const QString &path, Metadata &out, QString &error);
QDateTime parseTimestamp(const QString &path, const QDateTime &fallbackTime = QDateTime::currentDateTime());
bool record(QSqlDatabase db, const Metadata &metadata, const QString &imageName,
            const QString &time, const QVariantList &standards, bool &inserted, QString &error,
            const QString &batchId = QString(), int roundNo = 0);
bool validate(const QString &file, const QString &target, QString &error);
// Never replaces existing content. A durable sidecar allows retry after a DB failure/crash.
bool accept(const QString &staged, const QString &target,
            const std::function<bool(const QString &)> &ingest, QString &error);
}
