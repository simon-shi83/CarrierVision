#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QSharedMemory>
#ifdef Q_OS_WIN
#include <windows.h>
#endif
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QWindow>
#include "data/DbSchema.h"
#include "data/DatabaseGuard.h"
#include "common/AppLogger.h"
#include "common/CrashHandler.h"
#include "version.h"
#include <nlohmann/json.hpp>

#include "app/AppController.h"
#include "app/ImageItemObject.h"
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

namespace {

// 启动阶段的致命错误：显示错误窗口（不依赖 Widgets 模块），关闭后程序退出
int showFatalError(QGuiApplication &app, const QString &title, const QString &detail)
{
    LOG_CRITICAL("{}: {}", title.toStdString(), detail.toStdString());
    const QString logDir = QDir::toNativeSeparators(AppLogger::getLogDirectory());
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(R"(
        import QtQuick
        import QtQuick.Controls
        import QtQuick.Layouts
        ApplicationWindow {
            property string titleText
            property string detailText
            width: 560; height: 260; visible: true
            title: "CarrierVision 启动失败"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 12
                Label { text: titleText; font.pixelSize: 18; font.bold: true; color: "#c62828" }
                Label { text: detailText; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.fillHeight: true }
                Button { text: "退出"; Layout.alignment: Qt.AlignRight; onClicked: Qt.quit() }
            }
        })", QUrl());
    QObject *window = component.createWithInitialProperties({
        {QStringLiteral("titleText"), title},
        {QStringLiteral("detailText"), detail + QStringLiteral("\n\n日志目录：") + logDir},
    });
    if (!window) {
        LOG_ERROR("无法显示启动错误窗口: {}", component.errorString().toStdString());
        return 1;
    }
    app.exec();
    delete window;
    AppLogger::shutdown();
    return 1;
}

} // namespace

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
    CrashHandler::install(AppLogger::getLogDirectory());
    LOG_INFO("CarrierVision 应用程序启动, 版本: {}", CARRIER_VISION_VERSION_FULL);

    // remove old debug log file to keep installation clean
    QFile oldDbg(QCoreApplication::applicationDirPath() + QDir::separator() + "run_debug_log.txt");
    if (oldDbg.exists()) oldDbg.remove();
    // Ensure app exits when the last top-level window closes.
    app.setQuitOnLastWindowClosed(true);
    // set application icon from resources
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/CarrierVision/assets/icons/favicon.png")));

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

    // 上次异常退出（运行标记仍在）或日常检查发现损坏时，打开数据库前先做完整性检查，损坏则从备份恢复
    const QString dbPath = DBSchema::defaultDatabasePath();
    const QString runningMarker = DatabaseGuard::runningMarkerPath(dbPath);
    const QString checkMarker = DatabaseGuard::corruptMarkerPath(dbPath);
    const bool uncleanExit = QFile::exists(runningMarker);
    if (uncleanExit)
        LOG_WARN("检测到上次程序未正常退出（崩溃、断电或被强制结束），启动前检查数据库完整性");
    if (uncleanExit || QFile::exists(checkMarker)) {
        const QString recovery = DatabaseGuard::recoverIfCorrupt(
            dbPath, QFileInfo(dbPath).absolutePath() + QStringLiteral("/backup"));
        if (!recovery.isEmpty()) LOG_CRITICAL("{}", recovery.toStdString());
        QFile::remove(checkMarker);
    }

    // 初始化 SQLite 数据库 dataAgc（文件 dataAgc.db）并确保表 record 存在
    {
        QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE");
        db.setDatabaseName(dbPath);
        if (!db.open()) {
            return showFatalError(app, QStringLiteral("无法打开主数据库"),
                                  QStringLiteral("数据库文件：%1\n错误：%2\n请检查磁盘空间、文件权限，或数据库是否被其他程序占用。")
                                      .arg(QDir::toNativeSeparators(dbPath), db.lastError().text()));
        } else {
            // 启用 WAL 模式以支持高并发读写，并设置 5 秒 busy_timeout 防止锁库抛错
            QSqlQuery pragmaQuery(db);
            pragmaQuery.exec("PRAGMA journal_mode = WAL;");
            pragmaQuery.exec("PRAGMA busy_timeout = 5000;");
            pragmaQuery.exec("PRAGMA synchronous = NORMAL;");

            // 日志级别：system_config 中的 log/level 优先；未配置时发布版 info、调试版 debug
#ifdef NDEBUG
            const QString defaultLevel = QStringLiteral("info");
#else
            const QString defaultLevel = QStringLiteral("debug");
#endif
            const QString configuredLevel = DBSchema::getConfig(db, QStringLiteral("log/level"), defaultLevel);
            if (!AppLogger::setLevel(configuredLevel)) {
                AppLogger::setLevel(defaultLevel);
                LOG_WARN("日志级别配置无效: '{}'，使用默认 {}", configuredLevel.toStdString(), defaultLevel.toStdString());
            }

            // 集中创建所有表结构
            if(!DBSchema::ensureAllTables(db)){
                return showFatalError(app, QStringLiteral("数据库表结构初始化失败"),
                                      QStringLiteral("数据库文件：%1\n请查看日志中 DBSchema 开头的错误；数据库可能已损坏或磁盘已满。")
                                          .arg(QDir::toNativeSeparators(dbPath)));
            }
        }
    }


    {
        QFile marker(runningMarker);
        if (marker.open(QIODevice::WriteOnly | QIODevice::Truncate))
            marker.write(QDateTime::currentDateTime().toString(Qt::ISODate).toUtf8());
    }

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
                win->setIcon(QIcon(QStringLiteral(":/qt/qml/CarrierVision/assets/icons/favicon.png")));
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
    QFile::remove(runningMarker); // 正常退出：下次启动无需检查数据库
    AppLogger::shutdown();
    return exitCode;
}
