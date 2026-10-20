#pragma once

#include <QString>

// 崩溃现场记录：Linux 下把致命信号与调用栈追加到 <dir>/crash.log 后交还默认处理（照常生成 core）；
// Windows 下在 <dir> 生成 crash_<时间>.dmp 小型转储。应在日志初始化后尽早调用一次。
namespace CrashHandler {

void install(const QString &dir);

} // namespace CrashHandler
