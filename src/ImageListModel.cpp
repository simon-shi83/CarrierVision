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
           && a.slot == b.slot
           && a.rack == b.rack
           && a.serial == b.serial
           && a.fileName == b.fileName
           && a.filePath == b.filePath
           && a.fileUrl == b.fileUrl
           && a.receivedAt == b.receivedAt
           && a.result == b.result
           && a.distance == b.distance
           && a.dist_max == b.dist_max
           && a.dist_norm == b.dist_norm;
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
        return item.slot;
    case RackRole:
        return item.rack;
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
        {SerialRole, "serial"},
        {FileNameRole, "fileName"},
        {FilePathRole, "filePath"},
        {FileUrlRole, "fileUrl"},
        {DistMaxRole, "dist_max"},
        {DistNormRole, "dist_norm"},
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
    if (items.size() > MaxItemCount) {
        LOG_WARN("ImageListModel: 拒绝导入 {} 条图片，超出最大限制 {}", items.size(), MaxItemCount);
        return;
    }
    const int oldCount = m_items.size();
    const int newCount = items.size();

    if (oldCount == 0 && newCount == 0) {
        return;
    }

    // 缩容或重排场景直接重置，保证模型状态正确。
    if (newCount < oldCount) {
        beginResetModel();
        m_items = items;
        // 同步释放并裁剪多余的 QObject，防止内存泄漏与脏数据
        while (m_itemObjects.size() > newCount) {
            delete m_itemObjects.takeLast();
        }
        for (int i = 0; i < newCount; ++i) {
            if (i < m_itemObjects.size()) {
                ImageItemObject *o = m_itemObjects.at(i);
                const ImageItem &it = items.at(i);
                o->setBatchId(it.batchId);
                o->setFileName(it.fileName);
                o->setFilePath(it.filePath);
                o->setFileUrl(it.fileUrl.isEmpty() ? QUrl::fromLocalFile(it.filePath).toString() : it.fileUrl);
                o->setReceivedAtText(AgcUtils::formatDateTime(it.receivedAt));
                o->setSerial(it.serial);
                o->setRoundNumber(it.roundNumber);
                o->setRack(it.rack);
                o->setSlot(it.slot);
                o->setResult(it.result);
                o->setDistance(it.distance);
                o->setDistMax(it.dist_max);
                o->setDistNorm(it.dist_norm);
            }
        }
        endResetModel();
        emit countChanged();
        return;
    }

    Q_UNUSED(oldCount);
    Q_UNUSED(newCount);

    // 先更新已有行，仅对变化行发 dataChanged，避免整页闪烁。
    for (int i = 0; i < oldCount; ++i) {
        const ImageItem &oldItem = m_items.at(i);
        const ImageItem &newItem = items.at(i);
        if (!imageItemEquals(oldItem, newItem)) {
            m_items[i] = newItem;
            const QModelIndex idx = index(i, 0);
            // update backing QObject fields if exists
            if (i >= 0 && i < m_itemObjects.size()) {
                ImageItemObject *o = m_itemObjects.at(i);
                o->setBatchId(newItem.batchId);
                o->setFileName(newItem.fileName);
                o->setFilePath(newItem.filePath);
                o->setFileUrl(newItem.fileUrl.isEmpty() ? QUrl::fromLocalFile(newItem.filePath).toString() : newItem.fileUrl);
                o->setReceivedAtText(AgcUtils::formatDateTime(newItem.receivedAt));
                o->setSerial(newItem.serial);
                o->setRoundNumber(newItem.roundNumber);
                o->setRack(newItem.rack);
                o->setSlot(newItem.slot);
                o->setResult(newItem.result);
                o->setDistance(newItem.distance);
                o->setDistMax(newItem.dist_max);
                o->setDistNorm(newItem.dist_norm);
            }
            emit dataChanged(idx, idx);
        }
    }

    // 新增行采用插入通知，不触发历史行重建。
    if (newCount > oldCount) {
        beginInsertRows(QModelIndex(), oldCount, newCount - 1);
        for (int i = oldCount; i < newCount; ++i) {
            m_items.append(items.at(i));
            ImageItemObject *o = new ImageItemObject(this);
            const ImageItem &it = items.at(i);
            o->setBatchId(it.batchId);
            o->setFileName(it.fileName);
            o->setFilePath(it.filePath);
            o->setFileUrl(it.fileUrl.isEmpty() ? QUrl::fromLocalFile(it.filePath).toString() : it.fileUrl);
            o->setReceivedAtText(AgcUtils::formatDateTime(it.receivedAt));
            o->setSerial(it.serial);
            o->setRoundNumber(it.roundNumber);
            o->setRack(it.rack);
            o->setSlot(it.slot);
            o->setResult(it.result);
            o->setDistance(it.distance);
            o->setDistMax(it.dist_max);
            o->setDistNorm(it.dist_norm);
            m_itemObjects.append(o);
        }
        endInsertRows();
        emit countChanged();
    }

    // ensure object pool size matches
    while (m_itemObjects.size() > m_items.size()) {
        delete m_itemObjects.takeLast();
    }
}

bool ImageListModel::updateSlotItem(int index, const ImageItem &item)
{
    if (index < 0 || index >= MaxItemCount) {
        LOG_WARN("ImageListModel: 槽位更新索引 {} 超出有效范围 [0, {})", index, MaxItemCount);
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
        ImageItemObject *o = m_itemObjects.at(index);
        o->setBatchId(item.batchId);
        o->setFileName(item.fileName);
        o->setFilePath(item.filePath);
        o->setFileUrl(item.fileUrl.isEmpty() ? QUrl::fromLocalFile(item.filePath).toString() : item.fileUrl);
        o->setReceivedAtText(AgcUtils::formatDateTime(item.receivedAt));
        o->setSerial(item.serial);
        o->setRoundNumber(item.roundNumber);
        o->setRack(item.rack);
        o->setSlot(item.slot);
        o->setResult(item.result);
        o->setDistance(item.distance);
        o->setDistMax(item.dist_max);
        o->setDistNorm(item.dist_norm);
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
    return {
        {QStringLiteral("batchId"), item.batchId},
        {QStringLiteral("roundNumber"), item.roundNumber},
        {QStringLiteral("serial"), item.serial},
        {QStringLiteral("slot"), item.slot},
        {QStringLiteral("fileName"), item.fileName},
        {QStringLiteral("filePath"), item.filePath},
        {QStringLiteral("fileUrl"), item.fileUrl.isEmpty() ? QUrl::fromLocalFile(item.filePath).toString() : item.fileUrl},
        {QStringLiteral("rack"), item.rack},
        {QStringLiteral("result"), item.result},
        {QStringLiteral("distance"), item.distance},
        {QStringLiteral("dist_max"), item.dist_max},
        {QStringLiteral("dist_norm"), item.dist_norm},
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
