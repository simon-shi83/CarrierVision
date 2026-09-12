#pragma once

#include <QObject>
#include <QDateTime>

class ImageItemObject : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString batchId READ batchId WRITE setBatchId NOTIFY batchIdChanged)
    Q_PROPERTY(int roundNumber READ roundNumber WRITE setRoundNumber NOTIFY roundNumberChanged)
    Q_PROPERTY(int carrierId READ carrierId WRITE setCarrierId NOTIFY carrierIdChanged)
    Q_PROPERTY(int rack READ carrierId WRITE setCarrierId NOTIFY carrierIdChanged)
    Q_PROPERTY(int cameraId READ cameraId WRITE setCameraId NOTIFY cameraIdChanged)
    Q_PROPERTY(int slot READ cameraId WRITE setCameraId NOTIFY cameraIdChanged)
    Q_PROPERTY(int wheelId READ wheelId WRITE setWheelId NOTIFY wheelIdChanged)
    Q_PROPERTY(QString serial READ serial WRITE setSerial NOTIFY serialChanged)
    Q_PROPERTY(QString fileName READ fileName WRITE setFileName NOTIFY fileNameChanged)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)
    Q_PROPERTY(QString fileUrl READ fileUrl WRITE setFileUrl NOTIFY fileUrlChanged)
    Q_PROPERTY(QString receivedAtText READ receivedAtText WRITE setReceivedAtText NOTIFY receivedAtTextChanged)
    Q_PROPERTY(int result READ result WRITE setResult NOTIFY resultChanged)
    Q_PROPERTY(double distance READ distance WRITE setDistance NOTIFY distanceChanged)
    Q_PROPERTY(double distNorm READ distNorm WRITE setDistNorm NOTIFY distNormChanged)
    Q_PROPERTY(double lowerTolerance READ lowerTolerance WRITE setLowerTolerance NOTIFY lowerToleranceChanged)
    Q_PROPERTY(QString wheelsInfo READ wheelsInfo WRITE setWheelsInfo NOTIFY wheelsInfoChanged)

public:
    explicit ImageItemObject(QObject *parent = nullptr) : QObject(parent) {}

    QString batchId() const { return m_batchId; }
    void setBatchId(const QString &v) { if (m_batchId == v) return; m_batchId = v; emit batchIdChanged(); }

    int roundNumber() const { return m_roundNumber; }
    void setRoundNumber(int v) { if (m_roundNumber == v) return; m_roundNumber = v; emit roundNumberChanged(); }

    int carrierId() const { return m_carrierId; }
    void setCarrierId(int v) { if (m_carrierId == v) return; m_carrierId = v; emit carrierIdChanged(); }

    int cameraId() const { return m_cameraId; }
    void setCameraId(int v) { if (m_cameraId == v) return; m_cameraId = v; emit cameraIdChanged(); }

    int wheelId() const { return m_wheelId; }
    void setWheelId(int v) { if (m_wheelId == v) return; m_wheelId = v; emit wheelIdChanged(); }

    // 兼容旧接口
    int slot() const { return m_cameraId; }
    void setSlot(int v) { setCameraId(v); }
    int rack() const { return m_carrierId; }
    void setRack(int v) { setCarrierId(v); }

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

    double distance() const { return m_distance; }
    void setDistance(double v) { if (qFuzzyCompare(m_distance, v)) return; m_distance = v; emit distanceChanged(); }

    double distNorm() const { return m_distNorm; }
    void setDistNorm(double v) { if (qFuzzyCompare(m_distNorm, v)) return; m_distNorm = v; emit distNormChanged(); }

    double lowerTolerance() const { return m_lowerTolerance; }
    void setLowerTolerance(double v) { if (qFuzzyCompare(m_lowerTolerance, v)) return; m_lowerTolerance = v; emit lowerToleranceChanged(); }

    QString wheelsInfo() const { return m_wheelsInfo; }
    void setWheelsInfo(const QString &v) { if (m_wheelsInfo == v) return; m_wheelsInfo = v; emit wheelsInfoChanged(); }

signals:
    void batchIdChanged();
    void roundNumberChanged();
    void carrierIdChanged();
    void cameraIdChanged();
    void wheelIdChanged();
    void serialChanged();
    void fileNameChanged();
    void filePathChanged();
    void fileUrlChanged();
    void receivedAtTextChanged();
    void resultChanged();
    void distanceChanged();
    void distNormChanged();
    void lowerToleranceChanged();
    void wheelsInfoChanged();

private:
    QString m_batchId;
    int m_roundNumber = 0;
    int m_carrierId = 0;
    int m_cameraId = 0;
    int m_wheelId = -1;
    QString m_serial;
    QString m_fileName;
    QString m_filePath;
    QString m_fileUrl;
    QString m_receivedAtText;
    int m_result = 1;
    double m_distance = 0.0;
    double m_distNorm = 0.0;
    double m_lowerTolerance = 0.0;
    QString m_wheelsInfo;
};
