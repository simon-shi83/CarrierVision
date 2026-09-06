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
    src/main.cpp
    src/AppController.cpp
    src/AppController.h
    src/TcpMessageServer.cpp
    src/TcpMessageServer.h
    src/FtpServer.cpp
    src/FtpServer.h
    src/ImageListModel.cpp
    src/ImageListModel.h
    src/ImageItemObject.cpp
    src/ImageItemObject.h
    src/BatchTypes.h
    src/WeeklyReport.cpp
    src/WeeklyReport.h
    src/ArchiveMaintenance.cpp
    src/ArchiveMaintenance.h
    src/ImageIngest.cpp
    src/ImageIngest.h
    src/DbSchema.cpp
    src/DbSchema.h
    src/AgcUtils.cpp
    src/AgcUtils.h
    src/AppLogger.cpp
    src/AppLogger.h
)

if(WIN32)
    # If a Windows .rc resource file exists (to embed .ico), add it to the target sources
    set(ICON_RC ${CMAKE_SOURCE_DIR}/resources/app_icon.rc)
    if(EXISTS ${ICON_RC})
        message(STATUS "Found app_icon.rc, adding to CarrierVision sources for embedding exe icon")
        target_sources(CarrierVision PRIVATE ${ICON_RC})
    else()
        message(STATUS "No app_icon.rc found; exe will not have embedded icon. To embed, add resources/app_icon.rc and icons/app_icon.ico")
    endif()
endif()

# ftpserver is built into the main CarrierVision executable (no separate ftpserver_qt target)

target_include_directories(CarrierVision PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

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

        # 首页与3D数字孪生视窗
        qml/home/HomeWorkspace.qml
        qml/home/DesignShow.qml
        qml/home/DesignShowCore.qml
        qml/home/DesignShowCache.qml
        qml/home/RealtimeStationImageView.qml

        # 全景监控
        qml/monitor/MonitorWorkspace.qml

        # 历史查询
        qml/search/SearchWorkspace.qml

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
        resources/icons.qrc
        icons/Assembly.glb
        icons/logo_agc.svg
        icons/nav_home.svg
        icons/nav_batch.svg
        icons/nav_monitor.svg
        icons/nav_search.svg
        icons/nav_stats.svg
        icons/nav_report.svg
        icons/nav_alert.svg
        icons/nav_log.svg
        icons/nav_settings.svg
        icons/icon_sun.svg
        icons/icon_moon.svg
        icons/icon_lock.svg
        icons/icon_win_min.svg
        icons/icon_win_max.svg
        icons/icon_win_restore.svg
        icons/icon_close.svg
        icons/icon_calendar.svg
        icons/icon_eye.svg
        icons/icon_3d.svg
        icons/icon_chart_bar.svg
        icons/icon_chart_line.svg
        icons/icon_file_text.svg
        icons/icon_camera.svg
        icons/icon_check_circle.svg
        icons/icon_user.svg
        icons/icon_arrow_down.svg
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

set_target_properties(CarrierVision PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    INSTALL_RPATH "$ORIGIN/lib"
)

include(GNUInstallDirs)
if(WIN32)
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/src/CarrierVision.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/CarrierVision.rc"
        @ONLY
    )
    target_sources(CarrierVision PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/CarrierVision.rc")
    set_target_properties(CarrierVision PROPERTIES
        OUTPUT_NAME "CarrierVision_app"
    )
    install(TARGETS CarrierVision
        BUNDLE DESTINATION .
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION lib
    )

    # 根目录放置零外部依赖的轻量 Win32 原生启动器 CarrierVision.exe (透明拉起 lib/CarrierVision_app.exe)
    add_executable(CarrierVisionLauncher WIN32
        src/launcher_win.cpp
        "${CMAKE_CURRENT_BINARY_DIR}/CarrierVision.rc"
    )
    set_target_properties(CarrierVisionLauncher PROPERTIES
        OUTPUT_NAME "CarrierVision"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    )
    install(TARGETS CarrierVisionLauncher
        RUNTIME DESTINATION .
    )

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/scripts/README.txt")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/scripts/README.txt" DESTINATION .)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo_agc.svg")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/icons/logo_agc.svg" DESTINATION . RENAME CarrierVision.svg)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/scripts/register_env.bat")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/scripts/register_env.bat" DESTINATION .)
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/scripts/unregister_env.bat")
        install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/scripts/unregister_env.bat" DESTINATION .)
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

# If a legacy standalone ftpserver_qt target exists in the build tree, exclude it
# from default builds and prevent installation (FTP is embedded into CarrierVision).
if(TARGET ftpserver_qt)
    set_target_properties(ftpserver_qt PROPERTIES EXCLUDE_FROM_ALL TRUE EXCLUDE_FROM_DEFAULT_BUILD TRUE)
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
        tests/CoreBoundaryTests.cpp
        src/ImageListModel.cpp
        src/ImageListModel.h
        src/ImageItemObject.cpp
        src/ImageItemObject.h
        src/AgcUtils.cpp
        src/AgcUtils.h
        src/DbSchema.cpp
        src/DbSchema.h
        src/AppLogger.cpp
        src/AppLogger.h
    )
    target_include_directories(CarrierVisionBoundaryTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(CarrierVisionBoundaryTests PRIVATE Qt6::Core Qt6::Sql Qt6::Test)
    add_test(NAME CarrierVisionBoundaryTests COMMAND CarrierVisionBoundaryTests)
endif()

if(BUILD_TESTING)
    qt_add_executable(CarrierVisionReleaseTests
        tests/ReleaseBoundaryTests.cpp
        src/ImageIngest.cpp src/ImageIngest.h
        src/ArchiveMaintenance.cpp src/ArchiveMaintenance.h
        src/FtpServer.cpp src/FtpServer.h
        src/DbSchema.cpp src/DbSchema.h
        src/AgcUtils.cpp src/AgcUtils.h
        src/AppLogger.cpp src/AppLogger.h)
    target_include_directories(CarrierVisionReleaseTests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(CarrierVisionReleaseTests PRIVATE Qt6::Gui Qt6::Network Qt6::Sql Qt6::Test)
    add_test(NAME CarrierVisionReleaseTests COMMAND CarrierVisionReleaseTests)
    set_tests_properties(CarrierVisionReleaseTests PROPERTIES TIMEOUT 60)
endif()
if(BUILD_TESTING)
    qt_add_executable(CarrierVisionQmlSmoke tests/QmlDeploymentSmoke.cpp)
    target_link_libraries(CarrierVisionQmlSmoke PRIVATE Qt6::Qml Qt6::Quick Qt6::QuickControls2)
endif()
