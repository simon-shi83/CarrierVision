@echo off
rem ============================================================================
rem CarrierVision Windows 发布打包脚本（只安装，不编译）
rem
rem 用法:
rem   scripts\install.cmd [目录] [--build-dir <构建目录>]
rem
rem 对已编译好的构建目录（默认 build\Release）执行 cmake --install，并由
rem cmake\DeployWindows.cmake 调用 windeployqt 收集依赖，生成可直接拷贝到工控机运行的目录
rem （lib\、plugins\、qml\、assets\、qt.conf、CarrierVision.bat）。
rem 不给目录时输出到 install\CarrierVision_windows_<版本>。
rem
rem 先用 scripts\build.cmd 编译。构建目录不是最新（源码或 git 提交有变化）时脚本会拒绝安装，
rem 避免打出旧版本的包。
rem 现场升级时只替换程序文件，data\、images\、logs\ 保持不动（见 AGENTS.md 第 7 节）。
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

rem shift 会连同 %0 一起移位，先保存脚本目录
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "SOURCE_DIR=%%~fI"
set "BUILD_DIR=%SOURCE_DIR%\build\Release"
set "PREFIX_ARG="

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="-h"     goto usage
if /i "%~1"=="--help" goto usage
if /i "%~1"=="--build-dir" (
    if "%~2"=="" goto usage_error
    set "BUILD_DIR=%~f2"
    shift & shift & goto parse_args
)
set "_arg=%~1"
if "!_arg:~0,2!"=="--" (
    echo [install] 未知参数: %~1
    goto usage_error
)
set "PREFIX_ARG=%~f1"
shift
goto parse_args

:args_done
if not exist "%BUILD_DIR%\CMakeCache.txt" (
    echo [install] 错误: 构建目录不存在或尚未配置: %BUILD_DIR%
    echo           请先运行 scripts\build.cmd
    exit /b 1
)

rem cmake.exe：优先 PATH，其次 Visual Studio / Build Tools 自带的 CMake
where cmake.exe >nul 2>&1
if errorlevel 1 (
    set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    if exist "!VSWHERE!" (
        for /f "usebackq delims=" %%P in (`"!VSWHERE!" -latest -products * -property installationPath`) do (
            set "PATH=!PATH!;%%P\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
        )
    )
)
where cmake.exe >nul 2>&1 || ( echo [install] 错误: 未找到 cmake.exe。& exit /b 1 )

findstr /b /c:"ENABLE_WINDEPLOYQT:BOOL=ON" "%BUILD_DIR%\CMakeCache.txt" >nul
if errorlevel 1 (
    echo [install] 错误: 该构建目录未开启依赖部署（ENABLE_WINDEPLOYQT），请重新运行 scripts\build.cmd
    exit /b 1
)

rem 检查构建是否最新：ninja 试运行（-n）没有待执行的步骤才继续
echo [install] 检查构建目录是否最新: %BUILD_DIR%
set "UP_TO_DATE=0"
for /f "usebackq delims=" %%L in (`cmake --build "%BUILD_DIR%" -- -n 2^>^&1`) do (
    echo %%L | findstr /c:"no work to do" >nul && set "UP_TO_DATE=1"
)
if "%UP_TO_DATE%"=="0" (
    echo [install] 错误: 构建目录不是最新（源码或 git 提交有变化），安装会得到旧版本。
    echo           请先运行 scripts\build.cmd 重新编译，再执行本脚本。
    exit /b 1
)

echo [install] 安装并部署 Qt 依赖
if defined PREFIX_ARG (
    cmake --install "%BUILD_DIR%" --prefix "%PREFIX_ARG%"
) else (
    cmake --install "%BUILD_DIR%"
)
if errorlevel 1 ( echo [install] 错误: 安装失败。& exit /b 1 )

if defined PREFIX_ARG (
    echo [install] 安装完成: %PREFIX_ARG%
) else (
    for /f "tokens=2 delims==" %%P in ('findstr /b /c:"CMAKE_INSTALL_PREFIX:PATH=" "%BUILD_DIR%\CMakeCache.txt"') do echo [install] 安装完成: %%P
)
exit /b 0

:usage
echo 用法: scripts\install.cmd [目录] [--build-dir ^<构建目录^>]
exit /b 0

:usage_error
echo 用法: scripts\install.cmd [目录] [--build-dir ^<构建目录^>]
exit /b 2
