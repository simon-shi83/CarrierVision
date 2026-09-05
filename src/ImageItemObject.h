#pragma once

#include <QObject>
#include <QDateTime>

class ImageItemObject : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString batchId READ batchId WRITE setBatchId NOTIFY batchIdChanged)
    Q_PROPERTY(int roundNumber READ roundNumber WRITE setRoundNumber NOTIFY roundNumberChanged)
    Q_PROPERTY(int slot READ slot WRITE setSlot NOTIFY slotChanged)
    Q_PROPERTY(int rack READ rack WRITE setRack NOTIFY rackChanged)
    Q_PROPERTY(QString serial READ serial WRITE setSerial NOTIFY serialChanged)
    Q_PROPERTY(QString fileName READ fileName WRITE setFileName NOTIFY fileNameChanged)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)
    Q_PROPERTY(QString fileUrl READ fileUrl WRITE setFileUrl NOTIFY fileUrlChanged)
    Q_PROPERTY(QString receivedAtText READ receivedAtText WRITE setReceivedAtText NOTIFY receivedAtTextChanged)
    Q_PROPERTY(int result READ result WRITE setResult NOTIFY resultChanged)
    Q_PROPERTY(int distance READ distance WRITE setDistance NOTIFY distanceChanged)
    Q_PROPERTY(int distMax READ distMax WRITE setDistMax NOTIFY distMaxChanged)
    Q_PROPERTY(int distNorm READ distNorm WRITE setDistNorm NOTIFY distNormChanged)

public:
    explicit ImageItemObject(QObject *parent = nullptr) : QObject(parent) {}

    QString batchId() const { return m_batchId; }
    void setBatchId(const QString &v) { if (m_batchId == v) return; m_batchId = v; emit batchIdChanged(); }

    int roundNumber() const { return m_roundNumber; }
    void setRoundNumber(int v) { if (m_roundNumber == v) return; m_roundNumber = v; emit roundNumberChanged(); }

    int slot() const { return m_slot; }
    void setSlot(int v) { if (m_slot == v) return; m_slot = v; emit slotChanged(); }

    int rack() const { return m_rack; }
    void setRack(int v) { if (m_rack == v) return; m_rack = v; emit rackChanged(); }

    QString serial() const { return m_serial; }
    void setSerial(const QString &v) { if (m_serial == v) return; m_serial = v; emit serialChanged(); }

    QString fileName() const { return m_fileName; }
    void setFileName(const QString &v) { if (m_fileName == v) return; m_fileName = v; emit fileNameChanged(); }

    QString filePath() const { return m_filePath; }
    void setFilePath(const QString &v) { if (m_filePath == v) return; m_filePath = v; emit filePathChanged(); }

    QString fileUrl() const { return m_fileUrl; }
    void setFileUrl(const QString &v) { if (m_fileUrl == v) return; m_fileUrl = v; emit fileUrlChanged(); }

    QString receivedAtText() const { return m_receivedAtText; }
    void setReceivedAtText(const QString &v) { if (m_receivedAtText == v) return; m_receivedAtText = v; emit receivedAtTextChanged(); }

    int result() const { return m_result; }
    void setResult(int v) { if (m_result == v) return; m_result = v; emit resultChanged(); }
    int distance() const { return m_distance; }
    void setDistance(int v) { if (m_distance == v) return; m_distance = v; emit distanceChanged(); }
    int distMax() const { return m_distMax; }
    void setDistMax(int v) { if (m_distMax == v) return; m_distMax = v; emit distMaxChanged(); }
    int distNorm() const { return m_distNorm; }
    void setDistNorm(int v) { if (m_distNorm == v) return; m_distNorm = v; emit distNormChanged(); }

signals:
    void batchIdChanged();
    void roundNumberChanged();
    void slotChanged();
    void rackChanged();
    void serialChanged();
    void fileNameChanged();
    void filePathChanged();
    void fileUrlChanged();
    void receivedAtTextChanged();
    void resultChanged();
    void distanceChanged();
    void distMaxChanged();
    void distNormChanged();

private:
    QString m_batchId;
    int m_roundNumber = 0;
    int m_slot = 0;
    int m_rack = 0;
    QString m_serial;
    QString m_fileName;
    QString m_filePath;
    QString m_fileUrl;
    QString m_receivedAtText;
    int m_result = 1;
    int m_distance = 0;
    int m_distMax = 0;
    int m_distNorm = 0;
};
