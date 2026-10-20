#pragma once

#include "app/BatchTypes.h"
#include "app/ImageListModel.h"
#include "network/FtpIngestService.h"
#include "network/TcpDataReceiver.h"
#include "ingest/IngestCoordinator.h"
#include "common/StorageMonitor.h"

#include <QFile>
#include <QObject>
#include <QHash>
#include <QDateTime>
#include <QSet>
#include <QVariantList>
#include <QVector>
#include <QMutex>
#include <QTimer>
#include <memory>
#include <atomic>
#include <QThreadPool>
#include <QThread>
#include <QFutureWatcher>

class AppController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString sourceDirectory READ sourceDirectory NOTIFY sourceDirectoryChanged)
    Q_PROPERTY(QString archiveDirectory READ archiveDirectory NOTIFY archiveDirectoryChanged)
    Q_PROPERTY(QString imagesDirectory READ archiveDirectory NOTIFY archiveDirectoryChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    Q_PROPERTY(QString currentSerialsRaw READ currentSerialsRaw NOTIFY currentBatchChanged)
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
    Q_PROPERTY(bool tcpRunning READ tcpRunning NOTIFY tcpServerStateChanged)
    Q_PROPERTY(int tcpPort READ tcpPort WRITE setTcpPort NOTIFY tcpServerStateChanged)
    Q_PROPERTY(int tcpClientCount READ tcpClientCount NOTIFY tcpServerStateChanged)
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
    Q_PROPERTY(QVariantMap latestWarnOrError READ latestWarnOrError NOTIFY latestWarnOrErrorChanged)
    // {level: ok|warn|rejectUploads|rejectData, path, freeBytes, totalBytes, freePercent}
    Q_PROPERTY(QVariantMap storageStatus READ storageStatus NOTIFY storageStatusChanged)

public:
    explicit AppController(QObject *parent = nullptr);
    ~AppController() override;

    QString sourceDirectory() const;
    QString archiveDirectory() const;
    QString statusMessage() const;
    QString currentSerialsRaw() const;
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
    Q_INVOKABLE void startTcpServer();
    Q_INVOKABLE void stopTcpServer();
    Q_INVOKABLE void setTcpPort(int port);
    Q_INVOKABLE bool tcpRunning() const;
    Q_INVOKABLE int tcpPort() const;
    Q_INVOKABLE int tcpClientCount() const;
    Q_SLOT void onFtpImageStored(const QString &filePath, const QString &requestedPath);
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
    // 异步统计：kind 为下方同步统计函数名，args 与其参数顺序一致；结果经 statsReady 返回。
    // 页面应优先使用该接口，同步版本仅为兼容保留，会阻塞界面线程。
    Q_INVOKABLE int requestStats(const QString &kind, const QVariantList &args = {});
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
    // 命令面板等未授权入口使用：需当前设置密码或维护口令
    Q_INVOKABLE bool resetSettingsPasswordAuthorized(const QString &password);
    Q_INVOKABLE bool hasMaintenancePassword() const;
    Q_INVOKABLE bool setMaintenancePassword(const QString &currentSettingsPassword, const QString &newPassword);
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

    // 槽位映射与目录管理接口
    Q_INVOKABLE void resetSlotMapping();
    Q_INVOKABLE void openArchiveDirectory();
    Q_INVOKABLE void openImagesDirectory() { openArchiveDirectory(); }
    Q_INVOKABLE void openFtpRootDirectory();

    QVariantList gearSumResult() const;

    QVariantMap latestWarnOrError() const;
    QVariantMap storageStatus() const;
    Q_INVOKABLE void clearLatestWarnOrError();

signals:
    void logQueryFinished(int requestId, const QVariantMap &result);
    void statsReady(int requestId, const QString &kind, const QVariant &result);
    void latestWarnOrErrorChanged();
    void storageStatusChanged();
    void sourceDirectoryChanged();
    void archiveDirectoryChanged();
    void statusMessageChanged();
    void currentBatchChanged();
    void searchSummaryChanged();
    void defaultSearchRangeChanged();
    void homepageDescriptionChanged();
    void darkModeChanged(bool isDark);
    void ftpSettingsChanged();
    void ftpServerStateChanged();
    void tcpServerStateChanged();
    void ftpLogChanged();
    void mappingChanged();
    void gearSumResultChanged();
    void genericSearchRequested(const QString &startDate, const QString &endDate, int wheelNumber, const QString &resultType);
    void searchPagedResult(int totalCount);
    void slotUpdated(int index);
    void rackWheelMonitorUpdated();

private:
    void startLogQuery();
    int currentRackHint() const;
    void loadSettings();
    void ensureDirectories();
    void loadFtpSettingsFromFile();
    bool saveFtpSettingsToFile();
    bool applyFtpConfiguration(const QString &root, int port);
    bool ftpListen(int port, const QString &root);
    QList<NetworkAccess::Subnet> networkAllowList() const;
    void ftpStop();
    void ftpPushUsers();
    void ftpPushRoot();
    void setStatusMessage(const QString &message);
    void runScheduledTasks();
    void startMaintenance(bool emergency);
    void appendFtpLog(const QString &message);
    void checkStorage();
    QStringList storagePaths() const;
    bool processTcpBatch(const QJsonObject &batchData, QString &error);

    QString m_sourceDirectory;
    QString m_archiveDirectory;
    QString m_statusMessage;

    int m_currentCarrierId = 0;
    QString m_currentSerialsRaw;
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
    // 图像存储目录配置原值（FTP 上传与归档共用同一目录）；相对路径相对程序目录
    QString m_imageDirSetting = QStringLiteral("images");

    QMap<QString, QString> m_ftpUsers;
    bool m_ftpAllowAnonymous = false;

    QVector<int> m_slotMapping;

    // FTP 服务运行在 m_ftpThread 中，只能经 invokeMethod 访问；运行状态在主线程缓存
    QThread m_ftpThread;
    FtpIngestService *m_ftpService = nullptr;
    bool m_ftpRunning = false;
    int m_ftpClientCount = 0;
    TcpDataReceiver m_tcpReceiver;
    int m_tcpPort = 9000;

    QFile m_ftpLogFile;
    QVariantList m_ftpLogLines;
    QString m_ftpLogPath;

    ImageListModel m_currentImagesModel;
    ImageListModel m_searchImagesModel;
    IngestCoordinator::PendingImageCache m_pendingImages;
    QVariantList m_gearSumResult;
    mutable QMutex m_dbMutex;
    QThreadPool m_logPool;
    QThreadPool m_searchPool;
    QThreadPool m_statsPool;
    int m_statsRequestSeq = 0;
    int m_gearSumGeneration = 0;
    QThreadPool m_maintenancePool;
    bool m_cleanupRunning = false;
    QTimer m_storageTimer;
    StorageMonitor::Level m_storageLevel = StorageMonitor::Level::Ok;
    QVariantMap m_storageStatus;
    QDateTime m_lastEmergencyCleanup;
    QFutureWatcher<QVariantMap> m_logWatcher;
    QVariantList m_logRequest;
    int m_logGeneration = 0;
    int m_activeLogRequest = 0;
    bool m_logBusy = false;
    QTimer m_scheduleTimer;
    bool m_reportRunning = false;
    bool m_backupRunning = false;
    QTimer m_serviceRetryTimer;
    bool m_ftpStoppedByUser = false;
    bool m_tcpStoppedByUser = false;
    QTimer m_ftpLogThrottleTimer;
    std::atomic<int> m_searchGeneration{0};
    std::atomic<int> m_alertSearchGeneration{0};
};
