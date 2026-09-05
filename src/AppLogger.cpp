#include "AppLogger.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileInfoList>
#include <QRegularExpression>
#include <QTextStream>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <limits>

#include "spdlog/sinks/base_sink.h"
#include "spdlog/sinks/stdout_color_sinks.h"

namespace {

// 单文件大小上限：50MB
constexpr uint64_t MAX_SINGLE_FILE_SIZE = 50 * 1024 * 1024ULL;
// 总日志大小上限：1GB
constexpr uint64_t MAX_TOTAL_LOGS_SIZE = 1024 * 1024 * 1024ULL;

class DailyRollingSizeRetentionSink final : public spdlog::sinks::base_sink<std::mutex>
{
public:
    DailyRollingSizeRetentionSink(std::string logDir, std::string filePrefix)
        : logDir_(std::move(logDir)), filePrefix_(std::move(filePrefix))
    {
        ensureLogDirExists();
        openCurrentLogFile(std::chrono::system_clock::now());
        cleanOldLogsIfNeeded();
    }

    ~DailyRollingSizeRetentionSink() override
    {
        closeFile();
    }

protected:
    void sink_it_(const spdlog::details::log_msg &msg) override
    {
        auto now = msg.time;
        std::string msgDate = formatDate(now);

        // 1. 跨天检查：若进入新的一天，切换新日期文件
        if (msgDate != currentDate_) {
            closeFile();
            currentDate_ = msgDate;
            currentIndex_ = 0;
            openCurrentLogFile(now);
            cleanOldLogsIfNeeded();
        }

        // 2. 格式化日志
        spdlog::memory_buf_t formatted;
        base_sink<std::mutex>::formatter_->format(msg, formatted);
        size_t writeBytes = formatted.size();

        // 3. 单文件 50MB 大小检查：若写入后将超过 50MB，切分到下一个分卷
        if (currentFileSize_ + writeBytes > MAX_SINGLE_FILE_SIZE) {
            closeFile();
            currentIndex_++;
            openCurrentLogFile(now);
            cleanOldLogsIfNeeded();
        }

        // 4. 写入日志
        if (fileStream_ && fileStream_->is_open()) {
            fileStream_->write(formatted.data(), formatted.size());
            fileStream_->flush();
            currentFileSize_ += writeBytes;
            totalBytesWrittenSinceClean_ += writeBytes;
        }

        // 每写入约 10MB 或分卷时进行一次整体容量检查
        if (totalBytesWrittenSinceClean_ >= 10 * 1024 * 1024ULL) {
            cleanOldLogsIfNeeded();
            totalBytesWrittenSinceClean_ = 0;
        }
    }

    void flush_() override
    {
        if (fileStream_ && fileStream_->is_open()) {
            fileStream_->flush();
        }
    }

private:
    void ensureLogDirExists()
    {
        std::error_code ec;
        std::filesystem::create_directories(logDir_, ec);
    }

    std::string formatDate(const std::chrono::system_clock::time_point &tp)
    {
        auto time_t_val = std::chrono::system_clock::to_time_t(tp);
        std::tm tm_buf{};
#if defined(_WIN32)
        localtime_s(&tm_buf, &time_t_val);
#else
        localtime_r(&time_t_val, &tm_buf);
#endif
        char buf[32];
        std::snprintf(buf, sizeof(buf), "%04d-%02d-%02d",
                      tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday);
        return std::string(buf);
    }

    std::string buildFilePath(const std::string &dateStr, int index)
    {
        std::string filename;
        if (index <= 0) {
            filename = filePrefix_ + "_" + dateStr + ".log";
        } else {
            filename = filePrefix_ + "_" + dateStr + "." + std::to_string(index) + ".log";
        }
        std::filesystem::path p(logDir_);
        p /= filename;
        return p.string();
    }

    void closeFile()
    {
        if (fileStream_) {
            if (fileStream_->is_open()) {
                fileStream_->flush();
                fileStream_->close();
            }
            fileStream_.reset();
        }
    }

    void openCurrentLogFile(const std::chrono::system_clock::time_point &now)
    {
        if (currentDate_.empty()) {
            currentDate_ = formatDate(now);
        }

        // 寻找当前日期未达到 50MB 的最新文件
        std::string path;
        while (true) {
            path = buildFilePath(currentDate_, currentIndex_);
            std::error_code ec;
            if (std::filesystem::exists(path, ec)) {
                auto sz = std::filesystem::file_size(path, ec);
                if (!ec && sz < MAX_SINGLE_FILE_SIZE) {
                    currentFileSize_ = sz;
                    break;
                }
                currentIndex_++;
            } else {
                currentFileSize_ = 0;
                break;
            }
        }

        currentFilePath_ = path;
        fileStream_ = std::make_unique<std::ofstream>(currentFilePath_, std::ios::app | std::ios::binary);
    }

public:
    void cleanOldLogsIfNeeded()
    {
        std::error_code ec;
        if (!std::filesystem::exists(logDir_, ec)) return;

        struct FileEntry {
            std::filesystem::path path;
            uint64_t size{0};
            std::filesystem::file_time_type lastWriteTime;
        };

        std::vector<FileEntry> entries;
        uint64_t totalSize = 0;

        for (const auto &item : std::filesystem::directory_iterator(logDir_, ec)) {
            if (item.is_regular_file(ec)) {
                std::string fname = item.path().filename().string();
                if (fname.rfind(filePrefix_, 0) == 0 && item.path().extension() == ".log") {
                    uint64_t sz = item.file_size(ec);
                    auto lwt = item.last_write_time(ec);
                    entries.push_back({item.path(), sz, lwt});
                    totalSize += sz;
                }
            }
        }

        // 如果总大小超过 1GB，按时间从旧到新排序，依次删除最老的日志文件
        if (totalSize > MAX_TOTAL_LOGS_SIZE) {
            std::sort(entries.begin(), entries.end(), [](const FileEntry &a, const FileEntry &b) {
                return a.lastWriteTime < b.lastWriteTime;
            });

            for (const auto &entry : entries) {
                if (totalSize <= MAX_TOTAL_LOGS_SIZE) break;

                // 避免删除当前正在写入的文件
                if (entry.path.string() == currentFilePath_) {
                    continue;
                }

                std::error_code rmEc;
                if (std::filesystem::remove(entry.path, rmEc)) {
                    totalSize -= (totalSize >= entry.size ? entry.size : totalSize);
                }
            }
        }
    }

private:
    std::string logDir_;
    std::string filePrefix_;
    std::string currentDate_;
    int currentIndex_{0};
    std::string currentFilePath_;
    uint64_t currentFileSize_{0};
    uint64_t totalBytesWrittenSinceClean_{0};
    std::unique_ptr<std::ofstream> fileStream_;
};

static std::shared_ptr<DailyRollingSizeRetentionSink> s_retentionSink;

void qtMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    auto lg = AppLogger::logger();
    if (!lg) return;

    std::string text = msg.toStdString();
    switch (type) {
    case QtDebugMsg:
        lg->debug(text);
        break;
    case QtInfoMsg:
        lg->info(text);
        break;
    case QtWarningMsg:
        lg->warn(text);
        break;
    case QtCriticalMsg:
        lg->error(text);
        break;
    case QtFatalMsg:
        lg->critical(text);
        break;
    }
}

} // namespace

std::shared_ptr<spdlog::logger> AppLogger::s_logger = nullptr;
QString AppLogger::s_logDir = QString();
static std::atomic<bool> s_isShuttingDown{false};

void AppLogger::init(const QString &logDir)
{
    if (s_logger) return;
    s_isShuttingDown.store(false, std::memory_order_seq_cst);

    if (logDir.isEmpty()) {
        s_logDir = QCoreApplication::applicationDirPath() + QDir::separator() + QStringLiteral("logs");
    } else {
        s_logDir = logDir;
    }

    QDir dir(s_logDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    try {
        std::vector<spdlog::sink_ptr> sinks;

        // 1. 控制台彩色输出 Sink
        auto consoleSink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
        consoleSink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
        sinks.push_back(consoleSink);

        // 2. 日期滚动 + 50M 分卷 + 1G 自动淘汰 Sink
        s_retentionSink = std::make_shared<DailyRollingSizeRetentionSink>(
            s_logDir.toStdString(), "carrier");
        s_retentionSink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
        sinks.push_back(s_retentionSink);

        s_logger = std::make_shared<spdlog::logger>("carrier", sinks.begin(), sinks.end());
        s_logger->set_level(spdlog::level::trace);
        s_logger->flush_on(spdlog::level::info);

        spdlog::set_default_logger(s_logger);

        // 捕获并重定向 Qt 自带日志
        qInstallMessageHandler(qtMessageHandler);

        LOG_INFO("==================================================");
        LOG_INFO("CarrierVision 工业点检系统日志引擎初始化成功");
        LOG_INFO("日志目录: {}", s_logDir.toStdString());
        LOG_INFO("配置规则: 每日切分, 单文件上限50MB, 总日志上限1GB");
        LOG_INFO("==================================================");
    } catch (const std::exception &ex) {
        std::fprintf(stderr, "Failed to initialize AppLogger: %s\n", ex.what());
    }
}

void AppLogger::shutdown()
{
    s_isShuttingDown.store(true, std::memory_order_seq_cst);
    qInstallMessageHandler(nullptr);
    if (s_logger) {
        LOG_INFO("CarrierVision 系统日志引擎安全关闭");
        s_logger->flush();
        spdlog::shutdown();
        s_logger.reset();
        s_retentionSink.reset();
    }
}

std::shared_ptr<spdlog::logger> AppLogger::logger()
{
    if (s_isShuttingDown.load(std::memory_order_relaxed)) {
        return nullptr;
    }
    return s_logger;
}

QString AppLogger::getLogDirectory()
{
    return s_logDir;
}

void AppLogger::cleanupOldLogsIfNeeded()
{
    if (s_retentionSink) {
        s_retentionSink->cleanOldLogsIfNeeded();
    }
}

void AppLogger::cleanupLogsOlderThanDays(int days)
{
    if (days < 1) days = 1;
    QDir dir(s_logDir);
    if (!dir.exists()) return;

    const QDate cutoffDate = QDate::currentDate().addDays(-days);
    const QString todayStr = QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"));

    QStringList filters;
    filters << QStringLiteral("carrier_*.log");
    const QFileInfoList list = dir.entryInfoList(filters, QDir::Files);

    QRegularExpression re(QStringLiteral("carrier_(\\d{4}-\\d{2}-\\d{2})"));
    int deletedCount = 0;
    for (const QFileInfo &info : list) {
        QRegularExpressionMatch match = re.match(info.fileName());
        if (match.hasMatch()) {
            const QString dateStr = match.captured(1);
            if (dateStr == todayStr) continue;

            const QDate fileDate = QDate::fromString(dateStr, QStringLiteral("yyyy-MM-dd"));
            if (fileDate.isValid() && fileDate < cutoffDate) {
                if (QFile::remove(info.absoluteFilePath())) {
                    deletedCount++;
                    LOG_INFO("已自动删除超期日志文件: {}", info.fileName().toStdString());
                }
            }
        } else {
            if (info.lastModified().date() < cutoffDate) {
                if (QFile::remove(info.absoluteFilePath())) {
                    deletedCount++;
                    LOG_INFO("已自动删除超期日志文件: {}", info.fileName().toStdString());
                }
            }
        }
    }
    if (deletedCount > 0) {
        LOG_INFO("超期日志自动清理完成: 成功删除 {} 个文件 (保留期限={}天)", deletedCount, days);
    }
}

QStringList AppLogger::getAvailableDates()
{
    QStringList dates;
    QDir dir(s_logDir);
    if (!dir.exists()) return dates;

    QStringList filters;
    filters << QStringLiteral("carrier_*.log");
    QFileInfoList list = dir.entryInfoList(filters, QDir::Files, QDir::Time);

    QRegularExpression re(QStringLiteral("carrier_(\\d{4}-\\d{2}-\\d{2})"));
    for (const QFileInfo &info : list) {
        QRegularExpressionMatch match = re.match(info.fileName());
        if (match.hasMatch()) {
            QString d = match.captured(1);
            if (!dates.contains(d)) {
                dates.append(d);
            }
        }
    }
    dates.sort();
    // 逆序排序，最新日期在最前
    std::reverse(dates.begin(), dates.end());

    // 如果当天还没有生成文件，把当天加在首位
    QString today = QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"));
    if (!dates.contains(today)) {
        dates.prepend(today);
    }

    return dates;
}

QVariantMap AppLogger::getLogStats()
{
    QVariantMap stats;
    QDir dir(s_logDir);
    if (!dir.exists()) {
        stats[QStringLiteral("totalSizeBytes")] = 0;
        stats[QStringLiteral("totalSizeStr")] = QStringLiteral("0 B");
        stats[QStringLiteral("fileCount")] = 0;
        stats[QStringLiteral("todayTotal")] = 0;
        stats[QStringLiteral("todayWarn")] = 0;
        stats[QStringLiteral("todayError")] = 0;
        return stats;
    }

    QStringList filters;
    filters << QStringLiteral("carrier_*.log");
    QFileInfoList list = dir.entryInfoList(filters, QDir::Files);

    qint64 totalBytes = 0;
    for (const QFileInfo &fi : list) {
        totalBytes += fi.size();
    }

    stats[QStringLiteral("totalSizeBytes")] = totalBytes;
    stats[QStringLiteral("fileCount")] = list.size();

    // 格式化文件大小字符串
    if (totalBytes < 1024 * 1024) {
        stats[QStringLiteral("totalSizeStr")] = QStringLiteral("%1 KB").arg(QString::number(totalBytes / 1024.0, 'f', 1));
    } else if (totalBytes < 1024ULL * 1024 * 1024) {
        stats[QStringLiteral("totalSizeStr")] = QStringLiteral("%1 MB").arg(QString::number(totalBytes / (1024.0 * 1024.0), 'f', 2));
    } else {
        stats[QStringLiteral("totalSizeStr")] = QStringLiteral("%1 GB").arg(QString::number(totalBytes / (1024.0 * 1024.0 * 1024.0), 'f', 2));
    }

    // 统计今天的日志级别分布
    QString todayStr = QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd"));
    int todayTotal = 0;
    int todayWarn = 0;
    int todayError = 0;

    for (const QFileInfo &fi : list) {
        if (fi.fileName().contains(todayStr)) {
            QFile file(fi.absoluteFilePath());
            if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QTextStream in(&file);
                while (!in.atEnd()) {
                    QString line = in.readLine();
                    if (line.trimmed().isEmpty()) continue;
                    todayTotal++;
                    if (line.contains(QStringLiteral("[warning]")) || line.contains(QStringLiteral("[warn]"))) {
                        todayWarn++;
                    } else if (line.contains(QStringLiteral("[error]")) || line.contains(QStringLiteral("[critical]"))) {
                        todayError++;
                    }
                }
            }
        }
    }

    stats[QStringLiteral("todayTotal")] = todayTotal;
    stats[QStringLiteral("todayWarn")] = todayWarn;
    stats[QStringLiteral("todayError")] = todayError;

    return stats;
}

QVariantMap AppLogger::queryLogs(const QString &dateStr, const QString &level, const QString &keyword, int page, int pageSize)
{
    page = qMax(1, page);
    pageSize = qBound(1, pageSize <= 0 ? 50 : pageSize, 200);
    const QString targetDate = dateStr.trimmed().isEmpty() ? QDate::currentDate().toString(Qt::ISODate) : dateStr.trimmed();
    QVariantMap result{{"page",page},{"pageSize",pageSize},{"total",0},{"totalPages",1},{"items",QVariantList()}};
    if (!QDate::fromString(targetDate,Qt::ISODate).isValid()) {
        result["error"] = QStringLiteral("无效的日志日期"); return result;
    }
    struct Volume { QString path; qint64 size; int index; };
    QList<Volume> volumes;
    QRegularExpression volumeRe("^carrier_" + QRegularExpression::escape(targetDate) + "(?:\\.([0-9]+))?\\.log$");
    for (const auto &info : QDir(s_logDir).entryInfoList({"carrier_"+targetDate+"*.log"},QDir::Files)) {
        const auto match = volumeRe.match(info.fileName());
        if (match.hasMatch()) volumes.append({info.absoluteFilePath(), info.size(), match.captured(1).toInt()});
    }
    std::sort(volumes.begin(),volumes.end(),[](const auto &a,const auto &b){return a.index < b.index;});
    const QString filterLevel = level.trimmed().toLower(), filterKeyword = keyword.trimmed();
    const QRegularExpression lineRe(QStringLiteral("^\\[(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3})\\] \\[(\\w+)\\] (.*)$"));
    qint64 total = 0;
    QVariantList items;
    // Two streaming passes: keep only one requested page in memory. Snapshot file
    // lengths prevent concurrent appends from changing page boundaries mid-query.
    auto scan = [&](bool collect, qint64 first, qint64 last) {
        qint64 index = 0;
        for (const auto &volume : volumes) {
            QFile file(volume.path);
            if (!file.open(QIODevice::ReadOnly)) continue;
            while (!file.atEnd() && file.pos() < volume.size) {
                const QByteArray raw = file.readLine(qMin<qint64>(64*1024,volume.size-file.pos()+1));
                if (raw.isEmpty()) break;
                const QString line = QString::fromUtf8(raw).trimmed();
                if (line.isEmpty()) continue;
                const auto match = lineRe.match(line);
                const QString time = match.hasMatch() ? match.captured(1) : QString();
                const QString lvl = match.hasMatch() ? match.captured(2).toLower() : QStringLiteral("info");
                const QString message = match.hasMatch() ? match.captured(3) : line;
                if (!filterLevel.isEmpty() && filterLevel!="all") {
                    if (filterLevel=="warn" || filterLevel=="warning") { if(lvl!="warn" && lvl!="warning") continue; }
                    else if(filterLevel=="error" || filterLevel=="critical") { if(lvl!="error" && lvl!="critical") continue; }
                    else if(lvl!=filterLevel) continue;
                }
                if (!filterKeyword.isEmpty() && !message.contains(filterKeyword,Qt::CaseInsensitive)
                    && !time.contains(filterKeyword,Qt::CaseInsensitive)) continue;
                if (collect && index>=first && index<last) {
                    items.append(QVariantMap{{"time",time},{"level",lvl.toUpper()},{"message",message},{"raw",line}});
                }
                ++index;
                if (collect && index>=last) return index;
            }
        }
        return index;
    };
    total = scan(false,0,0);
    const qint64 offset = qint64(page-1)*pageSize;
    const qint64 last = qMax<qint64>(0,total-offset), first=qMax<qint64>(0,last-pageSize);
    if (last>first) scan(true,first,last);
    std::reverse(items.begin(),items.end());
    result["total"] = total;
    result["totalPages"] = qMax<qint64>(1,(total+pageSize-1)/pageSize);
    result["items"] = items;
    return result;
}
