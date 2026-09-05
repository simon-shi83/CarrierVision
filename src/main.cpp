#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QSharedMemory>
#ifdef Q_OS_WIN
#include <windows.h>
#endif
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QWindow>
#include "WeeklyReport.h"
#include "DbSchema.h"
#include "AppLogger.h"
#include "version.h"
#include <nlohmann/json.hpp>

#include "AppController.h"
#include "ImageItemObject.h"
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QDir>
#include <QCoreApplication>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QStandardPaths>
#include <QSaveFile>
#include <QSettings>
#include <QMutex>
#include <QMutexLocker>

int main(int argc, char *argv[])
{
#if defined(Q_OS_WIN)
    // 确保从应用程序根目录下的 lib 子目录加载动态链接库
    wchar_t exePath[MAX_PATH];
    if (GetModuleFileNameW(nullptr, exePath, MAX_PATH)) {
        wchar_t *lastSlash = wcsrchr(exePath, L'\\');
        if (lastSlash) {
            *lastSlash = L'\0';
            std::wstring libPath = std::wstring(exePath) + L"\\lib";
            SetDllDirectoryW(libPath.c_str());
        }
    }
#endif

    // 单实例检查：避免同时启动多个程序实例（生命周期持续到 main 结束）
    static const char *singleKey = "CarrierVision_single_instance_key";
    QSharedMemory singleMem(QString::fromUtf8(singleKey));
#if !defined(Q_OS_WIN)
    // 在 Linux/Unix 下，若前次异常退出残留共享内存，先尝试 attach 并 detach 以释放无主共享内存
    if (singleMem.attach()) {
        singleMem.detach();
    }
#endif
    if (!singleMem.create(1)) {
        // 如果创建失败，说明已有实例在运行，提示并退出
        QFile startupLog("startup_log.txt");
        if (startupLog.open(QIODevice::Append|QIODevice::Text)) {
            QTextStream out(&startupLog);
            out << QDateTime::currentDateTime().toString(Qt::ISODate) << " another instance detected, exiting\n";
            startupLog.close();
        }
        // 使用原生 Windows 消息框提示，避免依赖 Widgets 模块
#if defined(Q_OS_WIN)
        MessageBoxW(nullptr, L"程序已在运行", L"AGC ImageViewer", MB_OK | MB_ICONINFORMATION);
#else
        qInfo() << "程序已在运行";
#endif
        return 0;
    }

    QQuickStyle::setStyle("Fusion");

    QGuiApplication app(argc, argv);
    app.setApplicationVersion(QString::fromUtf8(CARRIER_VISION_VERSION_FULL));
    // 初始化 spdlog 工业日志引擎
    AppLogger::init();
    LOG_INFO("CarrierVision 应用程序启动, 版本: {}", CARRIER_VISION_VERSION_FULL);

    // remove old debug log file to keep installation clean
    QFile oldDbg(QCoreApplication::applicationDirPath() + QDir::separator() + "run_debug_log.txt");
    if (oldDbg.exists()) oldDbg.remove();
    // Ensure app exits when the last top-level window closes.
    app.setQuitOnLastWindowClosed(true);
    // set application icon from resources
    app.setWindowIcon(QIcon("qrc:/icons/favicon.png"));

    // On Windows, set an explicit AppUserModelID so the taskbar groups and icon use our app identity
#ifdef Q_OS_WIN
    // Use a stable AppUserModelID for taskbar grouping; call dynamically to avoid compile-time header issues
    using SetAppIDFn = HRESULT (WINAPI *)(PCWSTR);
    HMODULE shell = LoadLibraryW(L"shell32.dll");
    if (shell) {
        auto fn = reinterpret_cast<SetAppIDFn>(GetProcAddress(shell, "SetCurrentProcessExplicitAppUserModelID"));
        if (fn) {
            fn(L"com.chaixy.CarrierVision");
        }
        FreeLibrary(shell);
    }
#endif

    // 初始化 SQLite 数据库 dataAgc（文件 dataAgc.db）并确保表 record 存在
    {
        QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE");
        QString dbPath = DBSchema::defaultDatabasePath();
        db.setDatabaseName(dbPath);
        if (!db.open()) {
            LOG_ERROR("无法打开主数据库 dataAgc: {}", db.lastError().text().toStdString());
            return 1;
        } else {
            // 启用 WAL 模式以支持高并发读写，并设置 5 秒 busy_timeout 防止锁库抛错
            QSqlQuery pragmaQuery(db);
            pragmaQuery.exec("PRAGMA journal_mode = WAL;");
            pragmaQuery.exec("PRAGMA busy_timeout = 5000;");
            pragmaQuery.exec("PRAGMA synchronous = NORMAL;");

            // 集中创建所有表结构
            if(!DBSchema::ensureAllTables(db)){
                LOG_ERROR("DBSchema: 核心表结构初始化校验失败");
                return 1;
            }
        }
    }

    // 生成上周汇总报告并启动每周调度（在程序常驻时生效）
    QDate today = QDate::currentDate();
    QDate thisMonday = today.addDays(-today.dayOfWeek()+1);
    QDate lastMonday = thisMonday.addDays(-7);
    WeeklyReport::generateForWeek(lastMonday);
    WeeklyReport::scheduleWeeklyReports();

    int exitCode = 0;
    {
        qRegisterMetaType<BatchRecord>("BatchRecord");
        qRegisterMetaType<CopyTask>("CopyTask");

        AppController controller;

        QObject::connect(&app, &QCoreApplication::aboutToQuit, [&controller]() {
            LOG_INFO("应用程序即将退出，停止后台服务");
            controller.stopFtpServer();
        });

        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("appController", &controller);

        QObject::connect(
            &engine,
            &QQmlApplicationEngine::objectCreationFailed,
            &app,
            []() { QCoreApplication::exit(-1); },
            Qt::QueuedConnection);
        QObject::connect(&engine, &QQmlEngine::warnings, [&](const QList<QQmlError> &warnings){
            for (const QQmlError &e : warnings) {
                LOG_WARN("QML 引擎警告: {}", e.toString().toStdString());
            }
        });

        // register ImageItemObject type for QML bindings (uncreatable from QML)
        qmlRegisterUncreatableType<ImageItemObject>("AGC", 1, 0, "ImageItemObject", "exposed for model only");
        engine.loadFromModule("CarrierVision", "MainFrame");
        if (!engine.rootObjects().isEmpty()) {
            QObject *rootObj = engine.rootObjects().first();
            if (QWindow *win = qobject_cast<QWindow*>(rootObj)) {
                // 确保清除可能将窗口当作工具窗口的标志，并强制设置为主窗口，保证任务栏图标显示
                Qt::WindowFlags flags = win->flags();
                // 清除 Tool 标志
                flags &= ~Qt::Tool;
                // 强制设置为 Window
                flags |= Qt::Window;
                win->setFlags(flags);
                // 设置窗口标题
                win->setTitle("AGC Ftp Viewer");
                // 确保窗口使用应用图标（某些平台/环境需要在窗口级别显式设置）
                win->setIcon(QIcon("qrc:/icons/favicon.png"));
                // 确保窗口可见并激活
                win->show();
                // 有时 Windows 会不在任务栏显示，使用最小化-还原技巧强制刷新任务栏图标
                win->showMinimized();
                win->showNormal();
                win->showMaximized();
                win->raise();
                // 请求激活窗口（在 Windows 上更可靠）
                win->requestActivate();
                // 如有需要可临时启用置顶以确保可见（默认注释）
                // flags |= Qt::WindowStaysOnTopHint; win->setFlags(flags);
            }
        }

        exitCode = app.exec();
    }
    AppLogger::shutdown();
    return exitCode;
}
