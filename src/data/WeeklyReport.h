#pragma once

#include <QDate>
#include <QSqlDatabase>
#include <QString>

namespace WeeklyReport {

// 生成以 monday 开始的一周（周一至周日）的周报 CSV，输出到程序目录下的 data/。
// 可在任意线程调用，db 须为该线程自己的连接。已生成或该周无数据时也返回 true（无需重试）。
// 调度由 AppController 每分钟检查一次完成，不再依赖长时间单次定时器。
bool generateForWeek(QSqlDatabase db, const QDate &monday);

} // namespace WeeklyReport
