#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <array>

struct CopyTask
{
    QString batchId;
    int roundNumber = 0;
    QString serialsRaw;
    QStringList serials;
    QDateTime receivedAt;
    QString sourceDirectory;
    QString archiveDirectory;
    int expectedImageCount = 12;
    QString rackNumber;
    int currentTotal = 0;
    bool rackMode = false;
    std::array<int, 14> slotMapping{};  // 固定长度快照，避免动态容器复制问题；目标可映射到 1..14
};

Q_DECLARE_METATYPE(CopyTask)

struct BatchRecord
{
    QString batchId;
    int roundNumber = 0;
    QString serialsRaw;
    QStringList serials;
    QDateTime receivedAt;
    QString targetDirectory;
    QStringList imageFiles;
    bool completed = false;
};

Q_DECLARE_METATYPE(BatchRecord)
