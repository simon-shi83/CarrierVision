#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>

namespace AgcUtils {

QStringList splitSerials(const QString &rawText);
QString normalizedPath(const QString &path);
QString formatDateTime(const QDateTime &dateTime);
QDateTime parseFlexibleDateTime(const QString &text, bool endOfDay = false);
bool isImageFile(const QString &fileName);
QString makeBatchId(int roundNumber, const QDateTime &receivedAt);
QString safeNamePart(const QString &input);

} // namespace AgcUtils
