#pragma once

#include <QString>
#include <QVariant>
#include <cmath>

// 协议口径（2026-10-22 确认）：TCP wheelId 就是轮位，1～8 为走行轮、9～16 为驱动轮。
// 原始轮号与显示轮位相同；position/rawId 仅保留为统一入口，不做偏移。
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
    return raw;
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
    return raw == 0 ? QString() : (raw <= 8 ? QStringLiteral("走行轮") : QStringLiteral("驱动轮"));
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
                     .arg(raw <= 8 ? QStringLiteral("walk") : QStringLiteral("drive")).arg(typeIndex(raw))
               : QStringLiteral(",,,");
}

} // namespace WheelIdentity
