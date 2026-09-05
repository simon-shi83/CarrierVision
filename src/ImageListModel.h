#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QString>
#include <QVector>

struct ImageItem
{
    QString batchId;
    int roundNumber = 0;
    int slot = 0;
    int rack = 0;
    QString serial;
    QString fileName;
    QString filePath;
    QString fileUrl;
    QDateTime receivedAt;
    int result = 1;
    int distance = 0;
    int dist_max=0;
    int dist_norm =0;
};

class ImageItemObject;

class ImageListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    static constexpr int MaxItemCount = 14;

    enum ImageRoles {
        BatchIdRole = Qt::UserRole + 1,
        RoundNumberRole,
        SlotRole,
        RackRole,
        SerialRole,
        FileNameRole,
        FilePathRole,
        FileUrlRole,
        ReceivedAtRole,
        ResultRole,
        DistanceRole,
        DistMaxRole,
        DistNormRole,
        ItemObjectRole,
        ReceivedAtTextRole
    };
    Q_ENUM(ImageRoles)

    explicit ImageListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    void setItems(const QVector<ImageItem> &items);
    bool updateSlotItem(int index, const ImageItem &item);
    void clear();

    Q_INVOKABLE QVariantMap get(int index) const;
    Q_INVOKABLE QObject* itemObjectAt(int index) const;
    ImageItem itemAt(int index) const;

signals:
    void countChanged();

private:
    QVector<ImageItem> m_items;
    QVector<class ImageItemObject*> m_itemObjects;
};
