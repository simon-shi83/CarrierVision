#pragma once

#include <QString>
#include <QVariant>
#include <cmath>

// 原始轮号始终是 TCP/数据库查询键；显示轮位只用于界面与导出。
namespace WheelIdentity {

inline int validId(const QVariant &value)
{
    if (!value.isValid() || value.isNull() || value.metaType().id() == QMetaType::Bool)
        return 0;
    bool ok = false;
    const double number = value.toDouble(&ok);
    return ok && std::isfinite(number) && number >= 1 && number <= 16
            && std::floor(number) == number ? static_cast<int>(number) : 0;
}

inline int position(const QVariant &rawWheelId)
{
    const int raw = validId(rawWheelId);
    return raw == 0 ? 0 : (raw <= 8 ? raw + 8 : raw - 8);
}

inline int rawId(const QVariant &positionNo) { return position(positionNo); }

inline int typeIndex(const QVariant &rawWheelId)
{
    const int raw = validId(rawWheelId);
    return raw == 0 ? 0 : (raw <= 8 ? raw : raw - 8);
}

inline QString typeName(const QVariant &rawWheelId)
{
    const int raw = validId(rawWheelId);
    return raw == 0 ? QString() : (raw <= 8 ? QStringLiteral("驱动轮") : QStringLiteral("走行轮"));
}

inline QString tagName(const QVariant &rawWheelId)
{
    return validId(rawWheelId) ? typeName(rawWheelId) + QString::number(typeIndex(rawWheelId)) : QString();
}

inline int rawForTag(const QString &name)
{
    for (int raw = 1; raw <= 16; ++raw)
        if (tagName(raw) == name) return raw;
    return 0;
}

inline QString label(const QVariant &rawWheelId)
{
    return validId(rawWheelId)
            ? QStringLiteral("轮位%1/%2").arg(position(rawWheelId)).arg(tagName(rawWheelId))
            : QStringLiteral("—");
}

inline QString csvIdentity(const QVariant &rawWheelId)
{
    const int raw = validId(rawWheelId);
    return raw ? QStringLiteral("%1,%2,%3,%4").arg(raw).arg(position(raw))
                     .arg(raw <= 8 ? QStringLiteral("drive") : QStringLiteral("walk")).arg(typeIndex(raw))
               : QStringLiteral(",,,");
}

} // namespace WheelIdentity
