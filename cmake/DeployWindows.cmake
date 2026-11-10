# ==============================================================================
# CarrierVision Windows 独立部署（cmake --install 阶段执行，不依赖 Python）
#
# 由 CMakeLists.txt 的 install(CODE) 引入，也可单独运行：
#   cmake -DCV_INSTALL_DIR=<安装目录> -DCV_QT_DIR=<Qt 套件根目录> -DCV_SOURCE_DIR=<源码根目录>
#         -P cmake/DeployWindows.cmake
#
# 输出目录结构：
# ├── CarrierVision.exe        主程序
# ├── CarrierVision.bat        便携启动脚本
# ├── CarrierVision_watchdog.bat
# ├── register_env.bat / unregister_env.bat
# ├── CarrierVision.svg、README.txt
# ├── qt.conf                  路径重定向
# ├── lib/                     全部 *.dll（Qt 与 VC 运行库）
# ├── plugins/                 Qt 插件目录
# ├── qml/                     QML 运行时模块
# └── assets/                  运行时资源：fonts/ 界面字体、models/ 首页三维模型
# ==============================================================================
cmake_minimum_required(VERSION 3.21)

if(NOT CV_INSTALL_DIR)
    set(CV_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}")
endif()
foreach(_var CV_INSTALL_DIR CV_QT_DIR CV_SOURCE_DIR)
    if(NOT ${_var})
        message(FATAL_ERROR "[Windows Deploy] 缺少参数 ${_var}")
    endif()
endforeach()

file(TO_CMAKE_PATH "${CV_INSTALL_DIR}" _install)
file(TO_CMAKE_PATH "${CV_QT_DIR}" _qt)
file(TO_CMAKE_PATH "${CV_SOURCE_DIR}" _src)

message(STATUS "[Windows Deploy] 安装目录: ${_install}")
message(STATUS "[Windows Deploy] Qt 根目录: ${_qt}")
message(STATUS "[Windows Deploy] 源码目录: ${_src}")

set(_lib_dir "${_install}/lib")
set(_plugins_dir "${_install}/plugins")
file(MAKE_DIRECTORY "${_lib_dir}" "${_plugins_dir}")

# 1. 定位主程序（兼容旧版安装到 bin/ 的布局）
set(_app_exe "${_install}/CarrierVision.exe")
if(NOT EXISTS "${_app_exe}")
    file(GLOB_RECURSE _candidates "${_install}/CarrierVision.exe")
    list(LENGTH _candidates _n)
    if(_n EQUAL 0)
        message(FATAL_ERROR "[Windows Deploy] 未找到 CarrierVision.exe: ${_install}")
    endif()
    list(GET _candidates 0 _found)
    file(RENAME "${_found}" "${_app_exe}")
endif()
if(IS_DIRECTORY "${_install}/bin")
    file(REMOVE_RECURSE "${_install}/bin")
endif()
message(STATUS "[Windows Deploy] 主程序: ${_app_exe}")

# 2. 定位 windeployqt
find_program(_windeployqt NAMES windeployqt windeployqt6
    HINTS "${_qt}/bin" NO_DEFAULT_PATH)
if(NOT _windeployqt)
    find_program(_windeployqt NAMES windeployqt windeployqt6)
endif()
if(NOT _windeployqt)
    message(FATAL_ERROR "[Windows Deploy] 未找到 windeployqt.exe（Qt 目录: ${_qt}）")
endif()
message(STATUS "[Windows Deploy] windeployqt: ${_windeployqt}")

# 3. 运行 windeployqt 收集直接与间接依赖
set(_path_env "${_qt}/bin;${_qt}/libexec;$ENV{PATH}")
string(REPLACE ";" "\\;" _path_env_escaped "${_path_env}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "PATH=${_path_env_escaped}"
            "${_windeployqt}"
            --qmldir "${_src}/qml"
            --compiler-runtime
            --force
            --verbose 1
            "${_app_exe}"
    RESULT_VARIABLE _wdq_res
)
if(NOT _wdq_res EQUAL 0)
    # 依赖收集失败时发布包不完整，现场会因缺 DLL 无法启动，直接终止
    message(FATAL_ERROR "[Windows Deploy] windeployqt 失败（返回 ${_wdq_res}），请检查上方输出；常见原因是 Qt 套件缺少某个模块")
endif()

# 4.1 根目录下的 *.dll 归拢到 lib/
file(GLOB _dlls LIST_DIRECTORIES false "${_install}/*.dll")
list(LENGTH _dlls _dll_count)
foreach(_dll IN LISTS _dlls)
    get_filename_component(_name "${_dll}" NAME)
    file(REMOVE "${_lib_dir}/${_name}")
    file(RENAME "${_dll}" "${_lib_dir}/${_name}")
endforeach()
message(STATUS "[Windows Deploy] 已移动 ${_dll_count} 个 DLL 到 lib/")

# 4.2 插件目录归拢到 plugins/
set(_known_plugins platforms styles imageformats iconengines sqldrivers tls
    networkinformation assetimporters qmltooling generic multimedia position sensors)
set(_reserved lib plugins qml data bin translations assets fonts images logs)
file(GLOB _entries LIST_DIRECTORIES true "${_install}/*")
set(_plugin_count 0)
foreach(_entry IN LISTS _entries)
    if(NOT IS_DIRECTORY "${_entry}")
        continue()
    endif()
    get_filename_component(_name "${_entry}" NAME)
    string(TOLOWER "${_name}" _lname)
    if(_lname IN_LIST _reserved)
        continue()
    endif()
    file(GLOB _inner_dlls "${_entry}/*.dll")
    if(_lname IN_LIST _known_plugins OR _inner_dlls)
        file(REMOVE_RECURSE "${_plugins_dir}/${_name}")
        file(RENAME "${_entry}" "${_plugins_dir}/${_name}")
        math(EXPR _plugin_count "${_plugin_count} + 1")
    endif()
endforeach()
message(STATUS "[Windows Deploy] 已移动 ${_plugin_count} 个插件目录到 plugins/")

# 4.3 qt.conf
# Windows 上 file(WRITE) 按文本方式写入，\n 会自动转成 CRLF
file(WRITE "${_install}/qt.conf"
"[Paths]\nPrefix = .\nLibraries = lib\nPlugins = plugins\nQml2Imports = qml\n")

# 4.4 便携启动脚本（DLL 在 lib/，需要通过 PATH 让系统加载器找到）
file(WRITE "${_install}/CarrierVision.bat"
"@echo off\n\
setlocal\n\
set \"APP_DIR=%~dp0\"\n\
set \"PATH=%APP_DIR%lib;%PATH%\"\n\
set \"QT_PLUGIN_PATH=%APP_DIR%plugins\"\n\
set \"QML2_IMPORT_PATH=%APP_DIR%qml\"\n\
start \"\" \"%APP_DIR%CarrierVision.exe\" %*\n")
message(STATUS "[Windows Deploy] 已生成 qt.conf 与 CarrierVision.bat")

# 4.5 附带的批处理与说明文件
set(_pkg "${_src}/packaging")
foreach(_f register_env.bat unregister_env.bat)
    if(EXISTS "${_pkg}/windows/${_f}" AND NOT EXISTS "${_install}/${_f}")
        file(COPY "${_pkg}/windows/${_f}" DESTINATION "${_install}")
    endif()
endforeach()
if(EXISTS "${_pkg}/windows/CarrierVision_watchdog.bat")
    file(COPY "${_pkg}/windows/CarrierVision_watchdog.bat" DESTINATION "${_install}")
endif()
if(EXISTS "${_pkg}/README.txt" AND NOT EXISTS "${_install}/README.txt")
    file(COPY "${_pkg}/README.txt" DESTINATION "${_install}")
endif()

# 4.6 图标只保留 CarrierVision.svg
file(REMOVE "${_install}/logo_agc.svg")
if(NOT EXISTS "${_install}/CarrierVision.svg" AND EXISTS "${_src}/assets/icons/logo_agc.svg")
    file(COPY_FILE "${_src}/assets/icons/logo_agc.svg" "${_install}/CarrierVision.svg")
endif()

message(STATUS "[Windows Deploy] 部署完成")
