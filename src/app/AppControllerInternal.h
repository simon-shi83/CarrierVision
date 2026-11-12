#pragma once

// AppController 各实现文件（AppController*.cpp）共用的内部工具，不对外公开。

#include <QSqlDatabase>
#include <QString>

namespace AppControllerInternal {

// 后台线程使用按线程命名的独立数据库连接（WAL、busy_timeout 5s）
QSqlDatabase getThreadDatabase();

constexpr int kMaxPageSize = 200;

// 旧版本在程序目录单独写 ftp.log / ftp.log.1；现已并入主日志。
// 启动时把残留文件移入 logs/（不删除内容），之后随日志保留天数清理
inline QString legacyFtpLogPrefix() { return QStringLiteral("ftp_legacy_"); }

} // namespace AppControllerInternal
