#pragma once

#include <QDate>
#include <QString>

namespace WeeklyReport {

// Generate weekly reports for the week that contains `monday` (mon..sun).
// Output CSVs into applicationDir()/data/reports/weekly_<YYYYMMDD>_drivers.csv
// and weekly_<YYYYMMDD>_deformed.csv. Returns true on success.
bool generateForWeek(const QDate &monday);

// Schedule a recurring weekly report timer (runs at next Monday 00:10 then every 7 days).
void scheduleWeeklyReports();

} // namespace WeeklyReport
