// AppController：检测记录查询、报警操作、后台统计、热力图像与最新轮位图像、日志检索。
#include "app/AppController.h"
#include "app/AppControllerInternal.h"
#include "data/DbSchema.h"
#include "common/AppLogger.h"

#include "common/AgcUtils.h"
#include "ingest/ImageIngest.h"
#include "data/ArchiveMaintenance.h"
#include "data/StatsService.h"
#include "data/WeeklyReport.h"
#include "data/DatabaseGuard.h"
#include "data/SearchService.h"
#include "data/SettingsStore.h"
#include "ingest/IngestCoordinator.h"
#include "common/StorageMonitor.h"
#include "common/ImageExport.h"
#include <iostream>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QHostAddress>
#include <QCoreApplication>
#include <QDirIterator>
#include <QElapsedTimer>

#include <algorithm>
#include <utility>
#include <limits>

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QSettings>
#include <QTime>
#include <QStandardItemModel>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QClipboard>
#include <QUrl>
#include <QWindow>
#include <QImageReader>
#include <QStandardPaths>
#include <QUuid>
#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QtConcurrent/QtConcurrentRun>
#include <QThread>


using AppControllerInternal::getThreadDatabase;
using AppControllerInternal::kMaxPageSize;
using AppControllerInternal::legacyFtpLogPrefix;
using SearchService::RecordFilter;
using SearchService::buildRecordFilter;
using SearchService::parseResultFilter;
using SearchService::queryRecordPage;
using SearchService::resolveRecordImage;

QStringList AppController::alertHandlers() const
{
    QMutexLocker locker(&m_dbMutex);
    QSqlDatabase db = QSqlDatabase::database();
    return SettingsStore::loadAlertHandlers(db);
}

QString AppController::addAlertHandler(const QString &name)
{
    const QString clean = SettingsStore::normalizeAlertHandlerName(name);
    if (clean.isEmpty()) return QStringLiteral("请输入人员姓名");
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        QStringList names = SettingsStore::loadAlertHandlers(db);
        if (names.contains(clean, Qt::CaseInsensitive)) return QStringLiteral("该人员已在名单中");
        if (names.size() >= SettingsStore::kMaxAlertHandlers)
            return QStringLiteral("名单最多 %1 人").arg(SettingsStore::kMaxAlertHandlers);
        names.append(clean);
        if (!SettingsStore::saveAlertHandlers(db, names)) return QStringLiteral("保存失败，请查看日志");
    }
    LOG_INFO("添加报警处置人员：{}", clean.toStdString());
    emit alertHandlersChanged();
    return {};
}

bool AppController::removeAlertHandler(const QString &name)
{
    {
        QMutexLocker locker(&m_dbMutex);
        QSqlDatabase db = QSqlDatabase::database();
        QStringList names = SettingsStore::loadAlertHandlers(db);
        if (!names.removeOne(name)) return false;
        if (!SettingsStore::saveAlertHandlers(db, names)) return false;
    }
    LOG_INFO("移除报警处置人员：{}", name.toStdString());
    emit alertHandlersChanged();
    return true;
}

int AppController::requestAlertOperation(const QString &kind, const QString &start, const QString &end,
                                         int rack, int wheel, int page, const QString &operatorName)
{
    const int requestId = ++m_statsRequestSeq;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;
    const QString operatorText = SettingsStore::normalizeAlertHandlerName(operatorName);
    const bool disposition = kind == QLatin1String("handled") || kind == QLatin1String("falseAlarm");
    if (disposition) {
        // 处置人必须来自系统设置中的预设名单
        QString error;
        if (operatorText.isEmpty())
            error = QStringLiteral("请选择处置人员");
        else if (!alertHandlers().contains(operatorText, Qt::CaseInsensitive))
            error = QStringLiteral("处置人员不在系统设置的名单中，请重新选择");
        if (!error.isEmpty()) {
            LOG_WARN("报警处置被拒绝，架号={}，轮位={}：{}", rack, wheel, error.toStdString());
            QMetaObject::invokeMethod(this, [this, requestId, error]() {
                emit alertOperationFinished(requestId, {{QStringLiteral("ok"), false},
                                                        {QStringLiteral("error"), error}});
            }, Qt::QueuedConnection);
            return requestId;
        }
    }
    (void)QtConcurrent::run(&m_statsPool, [this, requestId, kind, start, end, rack, wheel, page, archiveDir, sourceDir, operatorText]() {
        const QVariantMap result = SearchService::alertOperation(getThreadDatabase(), kind, start, end,
                                                                 rack, wheel, page, archiveDir, sourceDir,
                                                                 operatorText);
        QMetaObject::invokeMethod(this, [this, requestId, result]() {
            emit alertOperationFinished(requestId, result);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

int AppController::currentRackHint() const
{
    return m_currentCarrierId >= 1 && m_currentCarrierId <= 50 ? m_currentCarrierId : 0;
}

int AppController::requestStats(const QString &kind, const QVariantList &args)
{
    const int requestId = ++m_statsRequestSeq;
    // 首页概览依赖主线程状态，在投递前取出
    const QVariantList effectiveArgs = kind == QLatin1String("homepageCurrentDetection")
        ? QVariantList{currentRackHint()} : args;

    (void)QtConcurrent::run(&m_statsPool, [this, requestId, kind, effectiveArgs]() {
        bool known = false;
        const QVariant result = StatsService::run(getThreadDatabase(), kind, effectiveArgs, &known);
        if (!known) LOG_WARN("未知统计请求或参数不足: {}", kind.toStdString());
        QMetaObject::invokeMethod(this, [this, requestId, kind, result]() {
            emit statsReady(requestId, kind, result);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

int AppController::requestLatestWheelImage(int rackNumber, int wheelNumber)
{
    const int requestId = ++m_latestWheelImageSeq;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;
    // 查库并在磁盘上定位图片，库大、图片目录大时耗时明显，放到查询线程执行
    (void)QtConcurrent::run(&m_searchPool, [this, requestId, rackNumber, wheelNumber, archiveDir, sourceDir]() {
        const QVariantMap image = SearchService::latestWheelImage(getThreadDatabase(), rackNumber, wheelNumber,
                                                                  archiveDir, sourceDir);
        QMetaObject::invokeMethod(this, [this, requestId, image]() {
            emit latestWheelImageReady(requestId, image);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

int AppController::requestRoundImages()
{
    const int requestId = ++m_roundImagesRequestSeq;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;
    (void)QtConcurrent::run(&m_searchPool, [this, requestId, archiveDir, sourceDir]() {
        QElapsedTimer timer;
        timer.start();
        const QVariantList racks = SearchService::latestRoundImages(getThreadDatabase(), archiveDir, sourceDir);
        int rackCount = 0;
        int imageCount = 0;
        int missingCount = 0;
        for (const QVariant &value : racks) {
            const QVariantMap rack = value.toMap();
            const int cameras = rack.value(QStringLiteral("cameraCount")).toInt();
            const int images = rack.value(QStringLiteral("imageCount")).toInt();
            if (cameras > 0) ++rackCount;
            imageCount += images;
            missingCount += cameras - images;
        }
        LOG_INFO("热力图像：本轮汇总完成，有记录的架={}，可显示图像={}，有记录缺图像={}，耗时={}ms",
                 rackCount, imageCount, missingCount, timer.elapsed());
        QMetaObject::invokeMethod(this, [this, requestId, racks]() {
            emit roundImagesReady(requestId, racks);
        }, Qt::QueuedConnection);
    });
    return requestId;
}

void AppController::searchPaged(const QString &startText, const QString &endText, const QString &serialKeyword, int rackNumber, const QString &wheelNo, const QString &resultFilter, int page, int pageSize)
{
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const int gen = ++m_searchGeneration;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;

    (void)QtConcurrent::run(&m_searchPool, [this, gen, startText, endText, serialKeyword, rackNumber, wheelNo, resultFilter, page, pageSize, archiveDir, sourceDir]() {
        RecordFilter filter = buildRecordFilter(startText, endText, rackNumber, wheelNo);
        const QString serialToken = serialKeyword.trimmed();
        if (!serialToken.isEmpty()) {
            filter.where << QStringLiteral("imagename LIKE :filename");
            filter.binds.append({QStringLiteral(":filename"),
                                 serialToken.contains('%') ? serialToken : QStringLiteral("%") + serialToken + QStringLiteral("%")});
        }
        int parsedResult = 0;
        if (parseResultFilter(resultFilter, parsedResult)) {
            filter.where << QStringLiteral("result = :res");
            filter.binds.append({QStringLiteral(":res"), parsedResult});
        }

        QSqlDatabase db = getThreadDatabase();
        if (!db.isValid() || !db.isOpen()) {
            LOG_ERROR("分页搜索失败，后台数据库无法打开");
            return;
        }

        int totalCount = 0;
        QVector<ImageItem> items;
        if (!queryRecordPage(db, QStringLiteral("record"), filter, page, pageSize, archiveDir, sourceDir, totalCount, items))
            return;
        for (const ImageItem &item : std::as_const(items)) {
            if (item.filePath.isEmpty())
                LOG_WARN("分页搜索结果中图片文件缺失: {}", item.fileName.toStdString());
        }

        LOG_DEBUG("searchPaged: start={} end={} serial={} rack={} wheel={} res={} page={} pageSize={} count={}",
                  startText.toStdString(), endText.toStdString(), serialToken.toStdString(),
                  rackNumber, wheelNo.toStdString(), resultFilter.toStdString(), page, pageSize, totalCount);

        if (m_searchGeneration.load() != gen) return;
        QMetaObject::invokeMethod(this, [this, gen, items, totalCount]() {
            if (m_searchGeneration.load() != gen) return;
            m_searchImagesModel.clear();
            m_searchImagesModel.setItems(items);
            m_searchSummary = QStringLiteral("取得 %1 条记录").arg(totalCount);
            emit searchSummaryChanged();
            emit searchPagedResult(totalCount);
        }, Qt::QueuedConnection);
    });
}

void AppController::alertSearchPaged(const QString &startText, const QString &endText,
                                     int rackNumber, const QString &wheelNo,
                                     int page, int pageSize)
{
    if (page < 1) page = 1;
    pageSize = qBound(1, pageSize <= 0 ? 10 : pageSize, kMaxPageSize);

    const int gen = ++m_alertSearchGeneration;
    const QString archiveDir = m_archiveDirectory;
    const QString sourceDir = m_sourceDirectory;

    (void)QtConcurrent::run(&m_searchPool, [this, gen, startText, endText, rackNumber, wheelNo, page, pageSize, archiveDir, sourceDir]() {
        const RecordFilter filter = buildRecordFilter(startText, endText, rackNumber, wheelNo);

        QSqlDatabase db = getThreadDatabase();
        if (!db.isValid() || !db.isOpen()) return;

        int totalCount = 0;
        QVector<ImageItem> items;
        if (!queryRecordPage(db, QStringLiteral("alertrecord"), filter, page, pageSize, archiveDir, sourceDir, totalCount, items))
            return;

        if (m_alertSearchGeneration.load() != gen) return;
        QMetaObject::invokeMethod(this, [this, gen, items, totalCount]() {
            if (m_alertSearchGeneration.load() != gen) return;
            m_searchImagesModel.clear();
            m_searchImagesModel.setItems(items);
            m_searchSummary = QStringLiteral("取得 %1 条报警记录").arg(totalCount);
            emit searchSummaryChanged();
            emit searchPagedResult(totalCount);
        }, Qt::QueuedConnection);
    });
}

void AppController::clearSearch()
{
    m_searchImagesModel.clear();
    m_searchSummary = QStringLiteral("(debug) search cleared");
    emit searchSummaryChanged();
}

QVariantList AppController::gearSumResult() const {
    return m_gearSumResult;
}

void AppController::gearSumQuery(const QString &startDate, const QString &endDate, const QString &rackno, const QVariant &selectedTurns) {
    // 按日期范围对全部架号分组统计，在统计线程执行；只采用最后一次请求的结果
    const int generation = ++m_gearSumGeneration;
    const QVariantList turns = selectedTurns.isValid() ? selectedTurns.toList() : QVariantList();
    (void)QtConcurrent::run(&m_statsPool, [this, generation, startDate, endDate, rackno, turns]() {
        const QVariantList out = StatsService::gearSum(getThreadDatabase(), startDate, endDate, rackno, turns);
        QMetaObject::invokeMethod(this, [this, generation, out]() {
            if (generation != m_gearSumGeneration) return;
            m_gearSumResult = out;
            LOG_DEBUG("gearSum 汇总统计计算完成，已触发更新");
            emit gearSumResultChanged();
        }, Qt::QueuedConnection);
    });
}

int AppController::requestLogs(const QString &startDate, const QString &endDate, const QString &level, const QString &keyword,
                               int page, int pageSize, const QString &category)
{
    m_logRequest = {startDate,endDate,level,keyword,page,pageSize,category};
    ++m_logGeneration;
    if (!m_logBusy) startLogQuery();
    return m_logGeneration;
}

void AppController::startLogQuery()
{
    m_logBusy = true;
    const auto request = m_logRequest;
    m_activeLogRequest = m_logGeneration;
    m_logWatcher.setFuture(QtConcurrent::run(&m_logPool, [request]() {
        auto result = AppLogger::queryLogRange(request[0].toString(), request[1].toString(), request[2].toString(),
                                               request[3].toString(), request[4].toInt(), request[5].toInt(),
                                               request[6].toString());
        result["stats"] = AppLogger::getLogStats();
        return result;
    }));
}

void AppController::openLogDirectory()
{
    const QString dirPath = AppLogger::getLogDirectory();
    QDesktopServices::openUrl(QUrl::fromLocalFile(dirPath));
    LOG_INFO("在系统管理器中打开日志目录: {}", dirPath.toStdString());
}
