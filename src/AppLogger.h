#ifndef APPLOGGER_H
#define APPLOGGER_H

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVariantList>
#include <memory>
#include <string>

#include "spdlog/spdlog.h"

// 结构化日志输出宏（带安全空指针防护，防止析构或关闭阶段触发空指针解引用）
#define LOG_TRACE(...)    do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_TRACE(_lg, __VA_ARGS__); } while (0)
#define LOG_DEBUG(...)    do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_DEBUG(_lg, __VA_ARGS__); } while (0)
#define LOG_INFO(...)     do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_INFO(_lg, __VA_ARGS__); } while (0)
#define LOG_WARN(...)     do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_WARN(_lg, __VA_ARGS__); } while (0)
#define LOG_ERROR(...)    do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_ERROR(_lg, __VA_ARGS__); } while (0)
#define LOG_CRITICAL(...) do { if (auto _lg = AppLogger::logger()) SPDLOG_LOGGER_CRITICAL(_lg, __VA_ARGS__); } while (0)

class AppLogger
{
public:
    static void init(const QString &logDir = QString());
    static void shutdown();
    static std::shared_ptr<spdlog::logger> logger();
    static QString getLogDirectory();

    // 日志查询与统计接口（供前端及控制器使用）
    static QStringList getAvailableDates();
    static QVariantMap queryLogs(const QString &dateStr, const QString &level, const QString &keyword, int page, int pageSize);
    static QVariantMap getLogStats();

    // 实时日志监听回调（level: "INFO"/"WARN"/"ERROR"/"CRITICAL", message, time）
    using LogCallback = std::function<void(const QString &level, const QString &message, const QString &time)>;
    static void setLogCallback(LogCallback cb);
    static QVariantMap latestWarningOrError();
    static void clearLatestWarningOrError();

    // 手动触发容量检查与清理（通常会自动触发）
    static void cleanupOldLogsIfNeeded();
    // 根据保留期限清理超期日志（超过指定天数的日志文件自动删除）
    static void cleanupLogsOlderThanDays(int days);

private:
    static std::shared_ptr<spdlog::logger> s_logger;
    static QString s_logDir;
};

#endif // APPLOGGER_H
