#include "ImageListModel.h"
#include "AppLogger.h"

#include "AgcUtils.h"
#include "ImageItemObject.h"

#include <QFileInfo>
#include <QUrl>

namespace {

bool imageItemEquals(const ImageItem &a, const ImageItem &b)
{
    return a.batchId == b.batchId
           && a.roundNumber == b.roundNumber
           && a.carrierId == b.carrierId
           && a.cameraId == b.cameraId
           && a.wheelId == b.wheelId
           && a.serial == b.serial
           && a.fileName == b.fileName
           && a.filePath == b.filePath
           && a.fileUrl == b.fileUrl
           && a.receivedAt == b.receivedAt
           && a.result == b.result
           && qFuzzyCompare(a.distance, b.distance)
           && qFuzzyCompare(a.dist_norm, b.dist_norm)
           && qFuzzyCompare(a.lower_tolerance, b.lower_tolerance)
           && a.wheelsInfo == b.wheelsInfo;
}

void syncObjectFromItem(ImageItemObject *o, const ImageItem &it)
{
    if (!o) return;
    o->setBatchId(it.batchId);
    o->setRoundNumber(it.roundNumber);
    o->setCarrierId(it.carrierId > 0 ? it.carrierId : it.rack);
    o->setCameraId(it.cameraId > 0 ? it.cameraId : it.slot);
    o->setWheelId(it.wheelId);
    o->setFileName(it.fileName);
    o->setFilePath(it.filePath);
    o->setFileUrl(it.fileUrl.isEmpty() ? QUrl::fromLocalFile(it.filePath).toString() : it.fileUrl);
    o->setReceivedAtText(AgcUtils::formatDateTime(it.receivedAt));
    o->setSerial(it.serial);
    o->setResult(it.result);
    o->setDistance(it.distance);
    o->setDistNorm(it.dist_norm);
    o->setLowerTolerance(it.lower_tolerance);
    o->setWheelsInfo(it.wheelsInfo);
}

}

ImageListModel::ImageListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ImageListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }

    return m_items.size();
}

QVariant ImageListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }

    const ImageItem &item = m_items.at(index.row());

    switch (role) {
    case BatchIdRole:
        return item.batchId;
    case RoundNumberRole:
        return item.roundNumber;
    case SlotRole:
    case CameraIdRole:
        return item.cameraId > 0 ? item.cameraId : item.slot;
    case RackRole:
    case CarrierIdRole:
        return item.carrierId > 0 ? item.carrierId : item.rack;
    case WheelIdRole:
        return item.wheelId;
    case SerialRole:
        return item.serial;
    case FileNameRole:
        return item.fileName;
    case FilePathRole:
        return item.filePath;
    case FileUrlRole:
        return item.fileUrl.isEmpty() ? QUrl::fromLocalFile(item.filePath) : QUrl(item.fileUrl);
    case ItemObjectRole: {
        if (index.row() < 0 || index.row() >= m_itemObjects.size()) return {};
        ImageItemObject *obj = m_itemObjects.at(index.row());
        return QVariant::fromValue(static_cast<QObject*>(obj));
    }
    case ResultRole:
        return item.result;
    case DistanceRole:
        return item.distance;
    case DistMaxRole:
        return item.dist_max;
    case DistNormRole:
        return item.dist_norm;
    case LowerToleranceRole:
        return item.lower_tolerance;
    case WheelsInfoRole:
        return item.wheelsInfo;
    case ReceivedAtRole:
        return item.receivedAt.toString(Qt::ISODateWithMs);
    case ReceivedAtTextRole:
        return AgcUtils::formatDateTime(item.receivedAt);
    default:
        return {};
    }
}

QHash<int, QByteArray> ImageListModel::roleNames() const
{
    return {
        {BatchIdRole, "batchId"},
        {RoundNumberRole, "roundNumber"},
        {SlotRole, "slot"},
        {RackRole, "rack"},
        {CarrierIdRole, "carrierId"},
        {CameraIdRole, "cameraId"},
        {WheelIdRole, "wheelId"},
        {SerialRole, "serial"},
        {FileNameRole, "fileName"},
        {FilePathRole, "filePath"},
        {FileUrlRole, "fileUrl"},
        {DistMaxRole, "dist_max"},
        {DistNormRole, "dist_norm"},
        {LowerToleranceRole, "lowerTolerance"},
        {WheelsInfoRole, "wheelsInfo"},
        {ItemObjectRole, "itemObject"},
        {ReceivedAtRole, "receivedAt"},
        {ResultRole, "result"},
        {DistanceRole, "distance"},
        {ReceivedAtTextRole, "receivedAtText"}
    };
}

int ImageListModel::count() const
{
    return m_items.size();
}

void ImageListModel::setItems(const QVector<ImageItem> &items)
{
    const int oldCount = m_items.size();
    const int newCount = items.size();

    if (oldCount == 0 && newCount == 0) {
        return;
    }

    if (newCount < oldCount) {
        beginResetModel();
        m_items = items;
        while (m_itemObjects.size() > newCount) {
            delete m_itemObjects.takeLast();
        }
        for (int i = 0; i < newCount; ++i) {
            if (i < m_itemObjects.size()) {
                syncObjectFromItem(m_itemObjects.at(i), items.at(i));
            }
        }
        endResetModel();
        emit countChanged();
        return;
    }

    for (int i = 0; i < oldCount; ++i) {
        const ImageItem &oldItem = m_items.at(i);
        const ImageItem &newItem = items.at(i);
        if (!imageItemEquals(oldItem, newItem)) {
            m_items[i] = newItem;
            const QModelIndex idx = index(i, 0);
            if (i >= 0 && i < m_itemObjects.size()) {
                syncObjectFromItem(m_itemObjects.at(i), newItem);
            }
            emit dataChanged(idx, idx);
        }
    }

    if (newCount > oldCount) {
        beginInsertRows(QModelIndex(), oldCount, newCount - 1);
        for (int i = oldCount; i < newCount; ++i) {
            m_items.append(items.at(i));
            ImageItemObject *o = new ImageItemObject(this);
            syncObjectFromItem(o, items.at(i));
            m_itemObjects.append(o);
        }
        endInsertRows();
        emit countChanged();
    }

    while (m_itemObjects.size() > m_items.size()) {
        delete m_itemObjects.takeLast();
    }
}

bool ImageListModel::updateSlotItem(int index, const ImageItem &item)
{
    if (index < 0 || index >= 1000) {
        LOG_WARN("ImageListModel: 槽位更新索引 {} 超出安全有效范围 [0, 1000)", index);
        return false;
    }

    if (index >= m_items.size()) {
        beginInsertRows(QModelIndex(), m_items.size(), index);
        while (m_items.size() <= index) {
            m_items.append(ImageItem());
            ImageItemObject *o = new ImageItemObject(this);
            m_itemObjects.append(o);
        }
        endInsertRows();
        emit countChanged();
    }

    m_items[index] = item;
    if (index < m_itemObjects.size()) {
        syncObjectFromItem(m_itemObjects.at(index), item);
    }
    const QModelIndex idx = this->index(index, 0);
    emit dataChanged(idx, idx);
    return true;
}

void ImageListModel::clear()
{
    if (m_items.isEmpty() && m_itemObjects.isEmpty()) {
        return;
    }

    beginResetModel();
    m_items.clear();
    while (!m_itemObjects.isEmpty()) {
        delete m_itemObjects.takeLast();
    }
    endResetModel();
    emit countChanged();
}

QVariantMap ImageListModel::get(int index) const
{
    if (index < 0 || index >= m_items.size()) {
        return {};
    }

    const ImageItem &item = m_items.at(index);
    const int carrierId = item.carrierId > 0 ? item.carrierId : item.rack;
    const int cameraId = item.cameraId > 0 ? item.cameraId : item.slot;
    return {
        {QStringLiteral("batchId"), item.batchId},
        {QStringLiteral("roundNumber"), item.roundNumber},
        {QStringLiteral("carrierId"), carrierId},
        {QStringLiteral("rack"), carrierId},
        {QStringLiteral("cameraId"), cameraId},
        {QStringLiteral("slot"), cameraId},
        {QStringLiteral("wheelId"), item.wheelId},
        {QStringLiteral("serial"), item.serial},
        {QStringLiteral("fileName"), item.fileName},
        {QStringLiteral("filePath"), item.filePath},
        {QStringLiteral("fileUrl"), item.fileUrl.isEmpty() ? QUrl::fromLocalFile(item.filePath).toString() : item.fileUrl},
        {QStringLiteral("result"), item.result},
        {QStringLiteral("distance"), item.distance},
        {QStringLiteral("dist_norm"), item.dist_norm},
        {QStringLiteral("lowerTolerance"), item.lower_tolerance},
        {QStringLiteral("wheelsInfo"), item.wheelsInfo},
        {QStringLiteral("receivedAt"), item.receivedAt.toString(Qt::ISODateWithMs)},
        {QStringLiteral("receivedAtText"), AgcUtils::formatDateTime(item.receivedAt)}
    };
}

QObject* ImageListModel::itemObjectAt(int index) const
{
    if (index < 0 || index >= m_itemObjects.size()) return nullptr;
    return m_itemObjects.at(index);
}

ImageItem ImageListModel::itemAt(int index) const
{
    if (index < 0 || index >= m_items.size()) return ImageItem();
    return m_items.at(index);
}
