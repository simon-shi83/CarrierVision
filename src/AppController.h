#pragma once

#include "BatchTypes.h"
#include "ImageListModel.h"
#include "TcpMessageServer.h"
#include "FtpServer.h"

#include <QObject>
#include <QHash>
#include <QSet>
#include <QVariantList>
#include <QVector>
#include <QMutex>
#include <QTimer>
#include <QDirIterator>
#include <memory>
#include <QThreadPool>
#include <QFutureWatcher>
#include <nlohmann/json.hpp>

class AppController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString sourceDirectory READ sourceDirectory NOTIFY sourceDirectoryChanged)
    Q_PROPERTY(QString archiveDirectory READ archiveDirectory NOTIFY archiveDirectoryChanged)
    Q_PROPERTY(int listenPort READ listenPort NOTIFY listenPortChanged)
    Q_PROPERTY(bool serverRunning READ serverRunning NOTIFY serverRunningChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString currentSerialsRaw READ currentSerialsRaw NOTIFY currentBatchChanged)
    Q_PROPERTY(QString lastTcpMessage READ lastTcpMessage NOTIFY lastTcpMessageChanged)
    Q_PROPERTY(QString currentReceivedAtText READ currentReceivedAtText NOTIFY currentBatchChanged)
    Q_PROPERTY(int currentRoundNumber READ currentRoundNumber NOTIFY currentBatchChanged)
    Q_PROPERTY(int currentCopiedCount READ currentCopiedCount NOTIFY currentBatchChanged)
    Q_PROPERTY(int currentExpectedCount READ currentExpectedCount NOTIFY currentBatchChanged)
    Q_PROPERTY(QString searchSummary READ searchSummary NOTIFY searchSummaryChanged)
    Q_PROPERTY(QString defaultSearchStart READ defaultSearchStart NOTIFY defaultSearchRangeChanged)
    Q_PROPERTY(QString defaultSearchEnd READ defaultSearchEnd NOTIFY defaultSearchRangeChanged)
    Q_PROPERTY(QString homepageDescription READ homepageDescription NOTIFY homepageDescriptionChanged)
    Q_PROPERTY(bool isDark READ isDarkMode WRITE setDarkMode NOTIFY darkModeChanged)
    Q_PROPERTY(ImageListModel *currentImagesModel READ currentImagesModel CONSTANT)
    Q_PROPERTY(ImageListModel *searchImagesModel READ searchImagesModel CONSTANT)
    Q_PROPERTY(QString ftpUser READ ftpUser NOTIFY ftpSettingsChanged)
    Q_PROPERTY(QString ftpRoot READ ftpRoot NOTIFY ftpSettingsChanged)
    Q_PROPERTY(int ftpPort READ ftpPort NOTIFY ftpSettingsChanged)
    Q_PROPERTY(bool ftpRunning READ ftpRunning NOTIFY ftpServerStateChanged)
    Q_PROPERTY(int ftpClientCount READ ftpClientCount NOTIFY ftpServerStateChanged)
    Q_PROPERTY(QVariantList ftpAccounts READ ftpAccounts NOTIFY ftpSettingsChanged)
    Q_PROPERTY(QVariantList slotMapping READ slotMapping NOTIFY mappingChanged)
    Q_PROPERTY(QVariantList gearSumResult READ gearSumResult NOTIFY gearSumResultChanged)
    Q_PROPERTY(QString ftpLog READ ftpLog NOTIFY ftpLogChanged)
    Q_PROPERTY(QVariantList ftpLogLines READ ftpLogLines NOTIFY ftpLogChanged)

public:
    explicit AppController(QObject *parent = nullptr);
    ~AppController() override;

    QString sourceDirectory() const;
    QString archiveDirectory() const;
    int listenPort() const;
    bool serverRunning() const;
    QString statusMessage() const;
    QString currentSerialsRaw() const;
    QString lastTcpMessage() const;
    QString currentReceivedAtText() const;
    int currentRoundNumber() const;
    int currentCopiedCount() const;
    int currentExpectedCount() const;
    QString searchSummary() const;
    QString defaultSearchStart() const;
    QString defaultSearchEnd() const;
    QString homepageDescription() const;
    ImageListModel *currentImagesModel();
    ImageListModel *searchImagesModel();

    Q_INVOKABLE void search(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter);
    Q_INVOKABLE void searchPaged(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter, int page, int pageSize);
    Q_INVOKABLE void alertSearchPaged(const QString &startText, const QString &endText,
                                      int rackNumber, const QString &wheelNo,
                                      int page, int pageSize);
    Q_INVOKABLE int latestRackWheelImageRack() const;
    Q_INVOKABLE void loadLatestRackWheelImages(int rackNumber);
    Q_INVOKABLE void loadLatestRackWheelImagesPage(int rackNumber, int page);
    Q_INVOKABLE int latestRackWheelTotalPages(int rackNumber) const;
    Q_SIGNAL void latestRackLoadFinished(int count, const QString &dbPath);
    Q_INVOKABLE void clearSearch();
    Q_INVOKABLE void startFtpServer();
    Q_INVOKABLE void stopFtpServer();
    Q_SLOT void onFtpImageStored(const QString &filePath);
    Q_INVOKABLE QString ftpUser() const;
    Q_INVOKABLE QString ftpRoot() const;
    Q_INVOKABLE int ftpPort() const;
    Q_INVOKABLE bool ftpRunning() const;
    Q_INVOKABLE int ftpClientCount() const;
    Q_INVOKABLE void setFtpUser(const QString &user);
    Q_INVOKABLE void setFtpPass(const QString &pass);
    Q_INVOKABLE void setFtpRoot(const QString &root);
    Q_INVOKABLE void setFtpPort(int port);
    Q_INVOKABLE QVariantList ftpAccounts() const;
    Q_INVOKABLE QString ftpAccountsDebug() const;
    Q_INVOKABLE void addFtpAccount(const QString &user, const QString &pass);
    Q_INVOKABLE void removeFtpAccount(const QString &user);
    Q_INVOKABLE QVariantList slotMapping() const;
    Q_INVOKABLE void setSlotMapping(int sourceOneBased, int targetValue);
    Q_INVOKABLE QVariantList rackWheelDistances(int rackNumber) const;
    Q_INVOKABLE QVariantList driveWheelRackStats(const QString &startDate, const QString &endDate);
    Q_INVOKABLE QVariantList walkingWheelRackStats(const QString &startDate, const QString &endDate);
    Q_INVOKABLE QVariantList rackWheelMonitorStatus() const;
	Q_INVOKABLE QVariantList rackPhotoCounts() const;
    Q_INVOKABLE QVariantMap latestRackWheelMonitorImage(int rackNumber, int wheelNumber) const;
	Q_INVOKABLE QVariantMap homepageCurrentDetection() const;
    Q_INVOKABLE QVariantList wheelRackResultStats(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType);
    Q_INVOKABLE QVariantList rackWheelResultStats(const QString &startDate, const QString &endDate,
                                                  int rackNumber, const QString &resultType,
                                                  int wheelType) const;
    Q_INVOKABLE bool saveRackWheelDistances(int rackNumber, const QVariantList &distances);
    Q_INVOKABLE QVariantList weeklyReports();
    Q_INVOKABLE void openReportFile(const QString &fileName);
    Q_INVOKABLE void rowSelected(int index);
    Q_INVOKABLE void gearSumQuery(const QString &startDate, const QString &endDate, const QString &rackno, const QVariant &selectedTurns);
    Q_INVOKABLE void openGenericSearch(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType);
    Q_INVOKABLE bool saveCsv(const QString &filePath, const QString &content);
    Q_INVOKABLE void triggerCleanup();
    Q_INVOKABLE int cleanupKeepDays() const;
    Q_INVOKABLE int cleanupLogKeepDays() const;
    Q_INVOKABLE int cleanupRunHour() const;
    Q_INVOKABLE void setCleanupKeepDays(int days);
    Q_INVOKABLE void setCleanupLogKeepDays(int days);
    Q_INVOKABLE void setCleanupRunHour(int hour);
    Q_INVOKABLE bool saveHomepageDescription(const QString &description);
    Q_INVOKABLE bool isDarkMode() const;
    Q_INVOKABLE void setDarkMode(bool dark);
    Q_INVOKABLE bool verifySettingsPassword(const QString &password) const;
    Q_INVOKABLE bool changeSettingsPassword(const QString &currentPassword,
                                            const QString &newPassword);
    Q_INVOKABLE bool resetSettingsPassword();
    Q_INVOKABLE void activateEnglishInputMethod();
    Q_INVOKABLE QString ftpLog() const;
    Q_INVOKABLE QVariantList ftpLogLines() const;
    Q_INVOKABLE void loadFtpLogs();
    Q_INVOKABLE void clearFtpLogs();
    Q_INVOKABLE void debugLog(const QString &text);

    // 日志查询与统计接口
    Q_INVOKABLE QStringList getAvailableLogDates();
    Q_INVOKABLE QVariantMap queryLogs(const QString &dateStr, const QString &level, const QString &keyword, int page, int pageSize);
    Q_INVOKABLE QVariantMap getLogStats();
    Q_INVOKABLE int requestLogs(const QString &date, const QString &level, const QString &keyword, int page, int pageSize);
    Q_INVOKABLE void openLogDirectory();
    Q_INVOKABLE void copyToClipboard(const QString &text);

    // TCP 服务与槽位映射管理接口
    Q_INVOKABLE void startTcpServer();
    Q_INVOKABLE void stopTcpServer();
    Q_INVOKABLE void setListenPort(int port);
    Q_INVOKABLE void resetSlotMapping();
    Q_INVOKABLE void openArchiveDirectory();
    Q_INVOKABLE void openFtpRootDirectory();

    QVariantList gearSumResult() const;

signals:
    void logQueryFinished(int requestId, const QVariantMap &result);
    void sourceDirectoryChanged();
    void archiveDirectoryChanged();
    void listenPortChanged();
    void serverRunningChanged();
    void statusMessageChanged();
    void currentBatchChanged();
    void lastTcpMessageChanged();
    void searchSummaryChanged();
    void defaultSearchRangeChanged();
    void homepageDescriptionChanged();
    void darkModeChanged(bool isDark);
    void ftpSettingsChanged();
    void ftpServerStateChanged();
    void ftpLogChanged();
    void mappingChanged();
    void gearSumResultChanged();
    void genericSearchRequested(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType);
    void searchPagedResult(int totalCount);
    void slotUpdated(int index);
    void rackWheelMonitorUpdated();

private:
    static constexpr int kListenPort = 22345;

    void startLogQuery();
    bool ingestStoredImage(const QString &filePath);
    void recoverPendingUploads();
    void loadSettings();
    void ensureDirectories();
    void loadArchiveIndex();
    void saveArchiveIndex() const;
    void loadFtpSettingsFromFile();
    bool saveFtpSettingsToFile();
    bool applyFtpConfiguration(const QString &root, int port);
    void loadSlotMappingFromJson(const nlohmann::json &obj);
    void saveSlotMappingToJson(nlohmann::json &obj) const;
    QString archiveIndexPath() const;
    QVector<ImageItem> buildImageItems(const BatchRecord &record) const;
    void upsertRecord(const BatchRecord &record);
    void setStatusMessage(const QString &message);
    void scheduleCleanup();
    void closeoutPreviousSession(const QString &newRackNumber);
    void checkSessionTimeout();

    struct RackSession {
        QString rack;
        QString batchId;
        int roundNumber = 0;
        QSet<int> receivedSlots;
        QDateTime startedAt;
        bool completed = false;
    };

    QString m_sourceDirectory;
    QString m_archiveDirectory;
    int m_listenPort = kListenPort;
    bool m_serverRunning = false;
    QString m_statusMessage;

    QString m_currentBatchId;
    QString m_currentSerialsRaw;
    QString m_lastTcpMessage;
    QString m_currentReceivedAtText;
    int m_currentRoundNumber = 0;
    int m_currentCopiedCount = 0;
    int m_currentExpectedCount = 12;

    QString m_searchSummary;
    QString m_defaultSearchStart;
    QString m_defaultSearchEnd;

    QString m_ftpUser;
    QString m_ftpPass;
    int m_ftpPort = 21;
    QString m_ftpRoot;

    QMap<QString, QString> m_ftpUsers;
    bool m_ftpAllowAnonymous = false;

    QVector<int> m_slotMapping;

    FtpServer m_ftpServer;

    QString m_ftpLogBuffer;
    QVariantList m_ftpLogLines;
    QString m_ftpLogPath;

    QList<BatchRecord> m_records;
    ImageListModel m_currentImagesModel;
    ImageListModel m_searchImagesModel;
    TcpMessageServer m_tcpServer;
    // CopyWorker removed; file-moving/archiving handled by FtpServer and archive logic
    QVariantList m_gearSumResult;
    QHash<QString, int> m_lastTotalByRack;
    mutable QMutex m_dbMutex;
    QThreadPool m_logPool;
    QFutureWatcher<QVariantMap> m_logWatcher;
    QVariantList m_logRequest;
    int m_logGeneration = 0;
    int m_activeLogRequest = 0;
    bool m_logBusy = false;
    QTimer m_cleanupTimer;
    QTimer m_ingestRetryTimer;
    std::unique_ptr<QDirIterator> m_pendingScan;
    QHash<QString, RackSession> m_activeRackSessions;
    QString m_currentSessionRack;
    QTimer m_safetyTimeoutTimer;
};
