#include "AgcUtils.h"

#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>

namespace AgcUtils {

QStringList splitSerials(const QString &rawText)
{
    QString normalized = rawText.trimmed();
    normalized.replace(u'，', u',');
    normalized.replace(u'；', u';');
    normalized.replace(u'｜', u'|');

    const QStringList rawParts = normalized.split(QRegularExpression(R"([\s,;|]+)"), Qt::SkipEmptyParts);
    QStringList result;
    QSet<QString> seen;

    for (const QString &part : rawParts) {
        const QString token = part.trimmed();
        if (token.isEmpty() || seen.contains(token)) {
            continue;
        }

        seen.insert(token);
        result.append(token);
    }

    return result;
}

QString normalizedPath(const QString &path)
{
    const QString trimmed = path.trimmed();
    if (trimmed.isEmpty()) {
        return {};
    }

    return QDir::cleanPath(QFileInfo(trimmed).absoluteFilePath());
}

QString formatDateTime(const QDateTime &dateTime)
{
    if (!dateTime.isValid()) {
        return QStringLiteral("--");
    }

    return dateTime.toLocalTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));
}

QDateTime parseFlexibleDateTime(const QString &text, bool endOfDay)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        return {};
    }

    const QList<QString> dateTimeFormats = {
        QStringLiteral("yyyy-MM-dd HH:mm:ss"),
        QStringLiteral("yyyy/MM/dd HH:mm:ss"),
        QStringLiteral("yyyy-MM-dd HH:mm"),
        QStringLiteral("yyyy/MM/dd HH:mm"),
        QStringLiteral("yyyyMMddHHmmss")
    };

    for (const QString &format : dateTimeFormats) {
        const QDateTime value = QDateTime::fromString(trimmed, format);
        if (value.isValid()) {
            return value;
        }
    }

    const QList<QString> dateFormats = {
        QStringLiteral("yyyy-MM-dd"),
        QStringLiteral("yyyy/MM/dd"),
        QStringLiteral("yyyyMMdd")
    };

    for (const QString &format : dateFormats) {
        const QDate date = QDate::fromString(trimmed, format);
        if (!date.isValid()) {
            continue;
        }

        return QDateTime(
            date,
            endOfDay ? QTime(23, 59, 59) : QTime(0, 0, 0));
    }

    QDateTime value = QDateTime::fromString(trimmed, Qt::ISODateWithMs);
    if (!value.isValid()) {
        value = QDateTime::fromString(trimmed, Qt::ISODate);
    }

    return value;
}

bool isImageFile(const QString &fileName)
{
    const QString suffix = QFileInfo(fileName).suffix().toLower();
    static const QSet<QString> supported = {
        QStringLiteral("bmp"),
        QStringLiteral("jpeg"),
        QStringLiteral("jpg"),
        QStringLiteral("png"),
        QStringLiteral("tif"),
        QStringLiteral("tiff"),
        QStringLiteral("webp")
    };

    return supported.contains(suffix);
}

QString makeBatchId(int roundNumber, const QDateTime &receivedAt)
{
    return QStringLiteral("R%1_%2")
        .arg(roundNumber, 4, 10, QChar(u'0'))
        .arg(receivedAt.toString(QStringLiteral("yyyyMMdd_HHmmss_zzz")));
}

QString safeNamePart(const QString &input)
{
    QString cleaned = input.trimmed();
    cleaned.replace(QRegularExpression(QStringLiteral(R"([^A-Za-z0-9_.-]+)")), QStringLiteral("_"));
    cleaned.remove(QRegularExpression(QStringLiteral(R"(^_+|_+$)")));

    if (cleaned.isEmpty()) {
        cleaned = QStringLiteral("image");
    }

    return cleaned;
}

} // namespace AgcUtils
