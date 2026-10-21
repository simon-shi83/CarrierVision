cmake_minimum_required(VERSION 3.21)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/version.cmake")

project(CarrierVision VERSION ${PROJECT_VERSION} LANGUAGES CXX)

# 默认安装路径规范：
# Windows 下输出至 install/CarrierVision_windows_${VERSION_FULL}
# Linux 下输出至 install/CarrierVision_linux_${VERSION_FULL}
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT
   OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local"
   OR CMAKE_INSTALL_PREFIX STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}/install/Release"
   OR CMAKE_INSTALL_PREFIX MATCHES "^C:/Program Files")
    if(WIN32)
        set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/install/CarrierVision_windows_${VERSION_FULL}" CACHE PATH "Windows 安装输出目录" FORCE)
    else()
        set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/install/CarrierVision_linux_${VERSION_FULL}" CACHE PATH "Linux 安装输出目录" FORCE)
    endif()
endif()


set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(_qt_prefix_hints
    "/usr/lib/x86_64-linux-gnu/cmake"
    "/usr/lib64/cmake"
    "/usr/lib/cmake"
    "/usr/local/lib/cmake"
    "/opt/Qt/6.11.2/gcc_64"
    "/opt/Qt/6.11.2/gcc_64/lib/cmake"
    "/opt/Qt/6.11.0/gcc_64"
    "/opt/Qt/6.11.0/gcc_64/lib/cmake"
    "/opt/Qt/6.9.3/gcc_64"
    "/opt/Qt/6.9.3/gcc_64/lib/cmake"
)

foreach(_hint IN LISTS _qt_prefix_hints)
    if(EXISTS "${_hint}")
        list(APPEND CMAKE_PREFIX_PATH "${_hint}")
    endif()
endforeach()

find_package(Qt6 REQUIRED COMPONENTS Concurrent Quick Quick3D Quick3DAssetUtils QuickControls2 Qml Network Sql Svg)
find_package(Qt6 OPTIONAL_COMPONENTS QuickEffects)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)
endif()

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_executable(CarrierVision
    src/common/WheelIdentity.h
    src/main.cpp
    src/app/AppController.cpp
    src/app/AppController.h
    src/app/UiSnapshot.cpp
    src/app/UiSnapshot.h
    src/app/ThumbnailCache.cpp
    src/app/ThumbnailCache.h
    src/app/ThumbnailProvider.cpp
    src/app/ThumbnailProvider.h
    src/network/TcpDataReceiver.cpp
    src/network/TcpDataReceiver.h
    src/network/FtpServer.cpp
    src/network/FtpServer.h
    src/network/FtpIngestService.cpp
    src/network/FtpIngestService.h
    src/network/NetworkAccess.cpp
    src/network/NetworkAccess.h
    src/app/ImageListModel.cpp
    src/app/ImageListModel.h
    src/app/ImageItemObject.cpp
    src/app/ImageItemObject.h
    src/app/BatchTypes.h
    src/data/WeeklyReport.cpp
    src/data/WeeklyReport.h
    src/data/ArchiveMaintenance.cpp
    src/data/ArchiveMaintenance.h
    src/ingest/ImageIngest.cpp
    src/ingest/ImageIngest.h
    src/data/DbSchema.cpp
    src/data/DbSchema.h
    src/data/DatabaseGuard.cpp
    src/data/DatabaseGuard.h
    src/data/StatsService.cpp
    src/data/StatsService.h
    src/data/SearchService.cpp
    src/data/SearchService.h
    src/data/SettingsStore.cpp
    src/data/SettingsStore.h
    src/ingest/IngestCoordinator.cpp
    src/ingest/IngestCoordinator.h
    src/common/AgcUtils.cpp
    src/common/AgcUtils.h
    src/common/AppLogger.cpp
    src/common/AppLogger.h
    src/common/StorageMonitor.cpp
    src/common/StorageMonitor.h
    src/common/CrashHandler.cpp
    src/common/CrashHandler.h
)

if(WIN32)
    # If a Windows .rc resource file exists (to embed .ico), add it to the target sources
    set(ICON_RC ${CMAKE_SOURCE_DIR}/packaging/windows/app_icon.rc)
    if(EXISTS ${ICON_RC})
        message(STATUS "Found app_icon.rc, adding to CarrierVision sources for embedding exe icon")
        target_sources(CarrierVision PRIVATE ${ICON_RC})
    else()
        message(STATUS "No app_icon.rc found; exe will not have embedded icon. To embed, add packaging/windows/app_icon.rc and assets/icons/favicon.ico")
    endif()
endif()

# 第三方仅头文件库（版本见 third_party/README.md），作为 SYSTEM 目录避免其告警混入项目告警
set(CARRIERVISION_THIRD_PARTY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party")

target_include_directories(CarrierVision PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CARRIERVISION_GENERATED_DIR}"   # version.h，由 cmake/version.cmake 生成
)
target_include_directories(CarrierVision SYSTEM PRIVATE "${CARRIERVISION_THIRD_PARTY_DIR}")

set_source_files_properties(qml/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)
set_source_files_properties(qml/home/DesignShowCache.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(CarrierVision
    URI CarrierVision
    VERSION 1.0
    QML_FILES
        # 核心主框架与主题
        qml/Theme.qml
        qml/MainFrame.qml
        qml/HeadBar.qml
        qml/StatusBar.qml

        # 公共通用组件
        qml/common/AppIcon.qml
        qml/common/ActionButton.qml
        qml/common/ZoomOverlay.qml
        qml/common/DatePicker.qml
        qml/common/DateQueryBar.qml
        qml/common/NumPicker.qml
        qml/common/WheelSelector.qml
        qml/common/PageBar.qml
        qml/common/QueryConditionBar.qml
        qml/common/ImageGridView.qml
        qml/common/PasswordConfirmDialog.qml

        # 首页与3D数字孪生视窗
        qml/home/HomeWorkspace.qml
        qml/home/DesignShow.qml
        qml/home/DesignShowCore.qml
        qml/home/DesignShowCache.qml
        qml/home/RealtimeStationImageView.qml
        qml/home/RealtimeStationImageCard.qml
        qml/home/StationImageInspectDialog.qml

        # 全景监控
        qml/monitor/MonitorWorkspace.qml
        qml/monitor/HeatImageWorkspace.qml

        # 数据查询
        qml/query/DataQueryWorkspace.qml

        # 统计分析
        qml/stats/StatsWorkspace.qml
        qml/stats/WheelStatsPage.qml
        qml/stats/RackStatsPage.qml
        qml/stats/WeekReportPage.qml
        qml/stats/WheelQueryBar.qml
        qml/stats/DriveWheelRackDetail.qml
        qml/stats/RackWheelStats.qml

        # 报警中心
        qml/alert/AlertWorkspace.qml
        qml/alert/AlertRecordPage.qml
        qml/alert/AlertStatsPage.qml

        # 日志查询
        qml/log/LogWorkspace.qml

        # 系统设置
        qml/settings/SettingsWorkspace.qml
        qml/settings/CalibrationPage.qml
        qml/settings/SystemConfigPage.qml


    RESOURCES
        assets/models/Assembly.glb
        assets/icons/favicon.png
        assets/icons/logo_agc.svg
        assets/icons/icon_refresh.svg
        assets/icons/icon_pause.svg
        assets/icons/icon_play.svg
        assets/icons/icon_ruler.svg
        assets/icons/icon_tag.svg
        assets/icons/icon_folder.svg
        assets/icons/icon_copy.svg
        assets/icons/icon_check.svg
        assets/icons/icon_info.svg
        assets/icons/icon_warning.svg
        assets/icons/icon_square.svg
        assets/icons/icon_image.svg
        assets/icons/icon_error.svg
        assets/icons/icon_check_square.svg
        assets/icons/nav_home.svg
        assets/icons/nav_batch.svg
        assets/icons/nav_monitor.svg
        assets/icons/nav_search.svg
        assets/icons/nav_stats.svg
        assets/icons/nav_report.svg
        assets/icons/nav_alert.svg
        assets/icons/nav_log.svg
        assets/icons/nav_settings.svg
        assets/icons/icon_sun.svg
        assets/icons/icon_moon.svg
        assets/icons/icon_lock.svg
        assets/icons/icon_win_min.svg
        assets/icons/icon_win_max.svg
        assets/icons/icon_win_restore.svg
        assets/icons/icon_close.svg
        assets/icons/icon_calendar.svg
        assets/icons/icon_eye.svg
        assets/icons/icon_3d.svg
        assets/icons/icon_chart_bar.svg
        assets/icons/icon_chart_line.svg
        assets/icons/icon_file_text.svg
        assets/icons/icon_camera.svg
        assets/icons/icon_check_circle.svg
        assets/icons/icon_user.svg
        assets/icons/icon_arrow_down.svg
)

target_link_libraries(CarrierVision PRIVATE
    Qt6::Concurrent
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    Qt6::Quick3D
    Qt6::Quick3DAssetUtils
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::Sql
)
if(TARGET Qt6::QuickEffects)
    target_link_libraries(CarrierVision PRIVATE Qt6::QuickEffects)
endif()
if(WIN32)
    target_link_libraries(CarrierVision PRIVATE Dbghelp)   # CrashHandler 写 minidump
else()
    # 导出符号，使 crash.log 中的调用栈能显示函数名（strip --strip-unneeded 会保留动态符号表）
    set_target_properties(CarrierVision PROPERTIES ENABLE_EXPORTS ON)
endif()

set_target_properties(CarrierVision PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    INSTALL_RPATH "$ORIGIN/lib"
)

include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_supported OUTPUT ipo_output)
if(ipo_supported)
    message(STATUS "IPO / LTO supported, enabling for CarrierVision in Release builds")
    set_property(TARGET CarrierVision PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
else()
    message(STATUS "IPO / LTO not supported: ${ipo_output}")
endif()

# 界面字体（assets/fonts）放在可执行文件旁的 fonts/ 目录，启动时由 main.cpp 加载；
# 不编进资源，避免 25 MB 字体数据进入 rcc 生成的源文件
set(CARRIERVISION_FONT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/assets/fonts")
add_custom_command(TARGET CarrierVision POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CARRIERVISION_FONT_DIR}" "$<TARGET_FILE_DIR:CarrierVision>/fonts"
    COMMENT "Staging bundled fonts")
install(DIRECTORY "${CARRIERVISION_FONT_DIR}/" DESTINATION fonts
        FILES_MATCHING PATTERN "*.otf" PATTERN "*.ttf" PATTERN "LICENSE-*.txt")

include(GNUInstallDirs)
if(WIN32)
    install(TARGETS CarrierVision
        BUNDLE DESTINATION .
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION .
    )

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/packaging/README.txt")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/packaging/README.txt" DESTINATION .)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/logo_agc.svg")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/logo_agc.svg" DESTINATION . RENAME CarrierVision.svg)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/packaging/windows/register_env.bat")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/packaging/windows/register_env.bat" DESTINATION .)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/packaging/windows/unregister_env.bat")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/packaging/windows/unregister_env.bat" DESTINATION .)
    endif()
else()
    install(TARGETS CarrierVision
        BUNDLE DESTINATION .
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION .
    )
endif()

# Windows 独立依赖自动部署（收集全部 Qt 动态库至 lib/、插件至 plugins/、QML模块至 qml/、生成 qt.conf 及启动脚本）
option(ENABLE_WINDEPLOYQT "Run Windows standalone deployment on install" ON)

if(WIN32 AND ENABLE_WINDEPLOYQT)
    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    get_target_property(_qt_core_loc Qt6::Core LOCATION)
    get_filename_component(_qt_bin_dir "${_qt_core_loc}" DIRECTORY)
    get_filename_component(_qt_root_dir "${_qt_bin_dir}" DIRECTORY)

    install(CODE "
        message(STATUS \"CarrierVision Windows: Running standalone dependency deployment...\")
        execute_process(
            COMMAND \"${Python3_EXECUTABLE}\"
                    \"${CMAKE_CURRENT_SOURCE_DIR}/scripts/deploy_windows.py\"
                    --install-dir \"\${CMAKE_INSTALL_PREFIX}\"
                    --qt-dir \"${_qt_root_dir}\"
                    --source-dir \"${CMAKE_CURRENT_SOURCE_DIR}\"
            RESULT_VARIABLE _deploy_res
        )
        if(NOT _deploy_res EQUAL 0)
            message(FATAL_ERROR \"Windows standalone deployment failed with exit code: \${_deploy_res}\")
        endif()
    ")
endif()

# Linux 独立依赖自动部署（收集全部 Qt/ICU 动态库、插件、QML、配置和启动脚本）
option(ENABLE_LINUX_DEPLOY "Deploy all Qt dependencies, plugins, and QML on Linux install" ON)

if(UNIX AND NOT APPLE AND ENABLE_LINUX_DEPLOY)
    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    get_target_property(_qt_core_loc Qt6::Core LOCATION)
    get_filename_component(_qt_lib_dir "${_qt_core_loc}" DIRECTORY)
    get_filename_component(_qt_root_dir "${_qt_lib_dir}" DIRECTORY)

    install(CODE "
        message(STATUS \"CarrierVision Linux: Running standalone dependency deployment...\")
        execute_process(
            COMMAND \"${Python3_EXECUTABLE}\"
                    \"${CMAKE_CURRENT_SOURCE_DIR}/scripts/deploy_linux.py\"
                    --install-dir \"\${CMAKE_INSTALL_PREFIX}\"
                    --qt-dir \"${_qt_root_dir}\"
                    --build-dir \"${CMAKE_CURRENT_BINARY_DIR}\"
                    --source-dir \"${CMAKE_CURRENT_SOURCE_DIR}\"
            RESULT_VARIABLE _deploy_res
        )
        if(NOT _deploy_res EQUAL 0)
            message(FATAL_ERROR \"Linux standalone deployment failed with exit code: \${_deploy_res}\")
        endif()
    ")
endif()

if(QT_VERSION_MAJOR EQUAL 6)
    qt_finalize_executable(CarrierVision)
endif()

# CPack 打包配置 (支持一键生成 .tar.gz 和 .zip 绿色便携包)
set(CPACK_PACKAGE_NAME "CarrierVision")
set(CPACK_PACKAGE_VENDOR "VISIONGO")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "CarrierVision Standalone Portable Release")
set(CPACK_PACKAGE_VERSION_MAJOR ${PROJECT_VERSION_MAJOR})
set(CPACK_PACKAGE_VERSION_MINOR ${PROJECT_VERSION_MINOR})
set(CPACK_PACKAGE_VERSION_PATCH ${PROJECT_VERSION_PATCH})
if(WIN32)
    set(CPACK_PACKAGE_FILE_NAME "CarrierVision_windows_${VERSION_FULL}")
else()
    set(CPACK_PACKAGE_FILE_NAME "CarrierVision_linux_${VERSION_FULL}")
endif()
set(CPACK_GENERATOR "TGZ;ZIP")
set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
include(CPack)


if(BUILD_TESTING)
    qt_add_executable(CarrierVisionBoundaryTests
        src/common/WheelIdentity.h
        src/data/WeeklyReport.cpp
        tests/CoreBoundaryTests.cpp
        src/data/StatsService.cpp
        src/data/StatsService.h
        src/data/SearchService.cpp
        src/data/SearchService.h
        src/data/SettingsStore.cpp
        src/data/SettingsStore.h
        src/ingest/IngestCoordinator.cpp
        src/ingest/IngestCoordinator.h
        src/common/StorageMonitor.cpp
        src/common/StorageMonitor.h
        src/network/NetworkAccess.cpp
        src/network/NetworkAccess.h
        src/app/ImageListModel.cpp
        src/app/ImageListModel.h
        src/app/ImageItemObject.cpp
        src/app/ImageItemObject.h
        src/common/AgcUtils.cpp
        src/common/AgcUtils.h
        src/data/DbSchema.cpp
        src/data/DbSchema.h
        src/common/AppLogger.cpp
        src/common/AppLogger.h
    )
    target_include_directories(CarrierVisionBoundaryTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(CarrierVisionBoundaryTests SYSTEM PRIVATE "${CARRIERVISION_THIRD_PARTY_DIR}")
    target_link_libraries(CarrierVisionBoundaryTests PRIVATE Qt6::Core Qt6::Network Qt6::Sql Qt6::Test)
    add_test(NAME CarrierVisionBoundaryTests COMMAND CarrierVisionBoundaryTests)
endif()

if(BUILD_TESTING)
    qt_add_executable(CarrierVisionReleaseTests
        tests/ReleaseBoundaryTests.cpp
        src/app/ThumbnailCache.cpp src/app/ThumbnailCache.h
        src/network/TcpDataReceiver.cpp src/network/TcpDataReceiver.h
        src/ingest/ImageIngest.cpp src/ingest/ImageIngest.h
        src/data/ArchiveMaintenance.cpp src/data/ArchiveMaintenance.h
        src/network/FtpServer.cpp src/network/FtpServer.h
        src/network/FtpIngestService.cpp src/network/FtpIngestService.h
        src/network/NetworkAccess.cpp src/network/NetworkAccess.h
        src/data/DbSchema.cpp src/data/DbSchema.h
        src/data/DatabaseGuard.cpp src/data/DatabaseGuard.h
        src/common/AgcUtils.cpp src/common/AgcUtils.h
        src/common/AppLogger.cpp src/common/AppLogger.h)
    target_include_directories(CarrierVisionReleaseTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_include_directories(CarrierVisionReleaseTests SYSTEM PRIVATE "${CARRIERVISION_THIRD_PARTY_DIR}")
    target_link_libraries(CarrierVisionReleaseTests PRIVATE Qt6::Gui Qt6::Network Qt6::Sql Qt6::Test)
    add_test(NAME CarrierVisionReleaseTests COMMAND CarrierVisionReleaseTests)
    set_tests_properties(CarrierVisionReleaseTests PROPERTIES TIMEOUT 60)
endif()
if(BUILD_TESTING)
    qt_add_executable(CarrierVisionQmlSmoke tests/QmlDeploymentSmoke.cpp)
    target_link_libraries(CarrierVisionQmlSmoke PRIVATE Qt6::Qml Qt6::Quick Qt6::QuickControls2)
    # 构建树内使用 Qt 自带 QML 目录验证导入；打包后的验证仍由部署流程传入安装目录
    add_test(NAME CarrierVisionQmlSmoke
             COMMAND CarrierVisionQmlSmoke "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}")
endif()

if(BUILD_TESTING)
    qt_add_executable(CarrierVisionWheelSelectionTests
        tests/WheelSelectionTests.cpp src/common/WheelIdentity.h
        src/app/ImageListModel.cpp src/app/ImageListModel.h
        src/app/ImageItemObject.cpp src/app/ImageItemObject.h
        src/common/AgcUtils.cpp src/common/AgcUtils.h
        src/common/AppLogger.cpp src/common/AppLogger.h)
    target_include_directories(CarrierVisionWheelSelectionTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    # 交互测试通过 CTest 运行；Windows 上也保留控制台和文件日志。
    set_target_properties(CarrierVisionWheelSelectionTests PROPERTIES WIN32_EXECUTABLE FALSE)
    target_include_directories(CarrierVisionWheelSelectionTests SYSTEM PRIVATE "${CARRIERVISION_THIRD_PARTY_DIR}")
    target_link_libraries(CarrierVisionWheelSelectionTests PRIVATE Qt6::Test Qt6::Qml Qt6::Quick Qt6::QuickControls2)
    qt_add_qml_module(CarrierVisionWheelSelectionTests
        URI CarrierVisionWheelTests
        VERSION 1.0
        OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/wheel-tests/CarrierVisionWheelTests"
        NO_CACHEGEN
        NO_PLUGIN
        QML_FILES
            qml/Theme.qml
            qml/common/AppIcon.qml
            qml/common/ActionButton.qml
            qml/common/DatePicker.qml
            qml/common/NumPicker.qml
            qml/common/WheelSelector.qml
            qml/common/QueryConditionBar.qml
            qml/common/DateQueryBar.qml
            qml/stats/WheelQueryBar.qml
            qml/home/StationImageInspectDialog.qml
            qml/common/ZoomOverlay.qml
            qml/settings/CalibrationPage.qml)
    qt_add_resources(CarrierVisionWheelSelectionTests wheel_test_icons
        PREFIX "/qt/qml/CarrierVision"
        FILES
            assets/icons/icon_arrow_down.svg
            assets/icons/icon_calendar.svg
            assets/icons/icon_check_circle.svg
            assets/icons/icon_close.svg
            assets/icons/icon_camera.svg
            assets/icons/icon_eye.svg)
    add_test(NAME CarrierVisionWheelSelectionTests COMMAND CarrierVisionWheelSelectionTests
        -o -,txt -o "${CMAKE_CURRENT_BINARY_DIR}/WheelSelectionTests.txt,txt")
endif()

if(BUILD_TESTING)
    set_tests_properties(CarrierVisionBoundaryTests CarrierVisionReleaseTests CarrierVisionQmlSmoke CarrierVisionWheelSelectionTests
                         PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    # 此测试验证绑定/查询身份，不依赖 GPU；避免无显示设备的 CI 选择 D3D/OpenGL。
    set_property(TEST CarrierVisionWheelSelectionTests APPEND PROPERTY ENVIRONMENT "QT_QUICK_BACKEND=software")
endif()
