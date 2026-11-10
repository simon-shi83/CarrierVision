@echo off
rem ============================================================================
rem CarrierVision Windows 构建脚本
rem
rem 用法:
rem   scripts\build.cmd [Debug^|Release] [--no-test] [--clean] [--install [目录]]
rem
rem   Debug / Release   构建类型，默认 Debug，构建目录为 build\<类型>
rem   --no-test         跳过 ctest
rem   --clean           先删除对应构建目录再全量构建
rem   --install [目录]  构建后执行 cmake --install 并部署 Qt 依赖（windeployqt）；
rem                     不给目录时按 CMakeLists 默认输出到 install\CarrierVision_windows_<版本>
rem
rem 环境变量（均可选）:
rem   QT_DIR          Qt 套件根目录，例如 C:\Qt\6.11.2\msvc2022_64；
rem                   未设置时自动选择 C:\Qt 下版本最高的 msvc*_64 套件
rem   CV_CMAKE_ARGS   追加给 cmake 配置步骤的参数
rem
rem 并行度固定 -j8，测试在构建完成后串行执行（见 AGENTS.md 第 6 节）。
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "SOURCE_DIR=%%~fI"

set "BUILD_TYPE=Release"
set "RUN_TESTS=1"
set "CLEAN=0"
set "DO_INSTALL=0"
set "INSTALL_PREFIX="

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="Debug"     ( set "BUILD_TYPE=Debug"   & shift & goto parse_args )
if /i "%~1"=="Release"   ( set "BUILD_TYPE=Release" & shift & goto parse_args )
if /i "%~1"=="--no-test" ( set "RUN_TESTS=0"        & shift & goto parse_args )
if /i "%~1"=="--clean"   ( set "CLEAN=1"            & shift & goto parse_args )
if /i "%~1"=="--install" ( set "DO_INSTALL=1" & shift & goto parse_install_prefix )
if /i "%~1"=="-h"     goto usage
if /i "%~1"=="--help" goto usage
echo [build] 未知参数: %~1
goto usage_error

rem --install 后面可选跟一个目录（不能以 -- 开头，也不能是构建类型）
:parse_install_prefix
set "_next=%~1"
if not defined _next goto parse_args
if "%_next:~0,2%"=="--" goto parse_args
if /i "%_next%"=="Debug" goto parse_args
if /i "%_next%"=="Release" goto parse_args
set "INSTALL_PREFIX=%~f1"
shift
goto parse_args

:args_done
set "BUILD_DIR=%SOURCE_DIR%\build\%BUILD_TYPE%"

echo [build] 源码目录: %SOURCE_DIR%
echo [build] 构建目录: %BUILD_DIR%  (%BUILD_TYPE%)

rem ---------------------------------------------------------------------------
rem 1. MSVC 编译环境：cl.exe 不在 PATH 时通过 vswhere 定位并加载 vcvars64.bat
rem ---------------------------------------------------------------------------
where cl.exe >nul 2>&1
if errorlevel 1 (
    set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    if not exist "!VSWHERE!" (
        echo [build] 错误: 未找到 Visual Studio / Build Tools（缺少 vswhere.exe^)。
        exit /b 1
    )
    set "VS_PATH="
    for /f "usebackq delims=" %%P in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%P"
    if not defined VS_PATH (
        echo [build] 错误: 未找到带 C++ x64 工具集的 Visual Studio / Build Tools。
        exit /b 1
    )
    echo [build] 加载 MSVC 环境: !VS_PATH!
    rem vcvars 内部会调用 vswhere，需要它在 PATH 中，否则会打印 "vswhere.exe is not recognized"
    set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;!PATH!"
    call "!VS_PATH!\VC\Auxiliary\Build\vcvars64.bat" >nul
    if errorlevel 1 (
        echo [build] 错误: vcvars64.bat 执行失败。
        exit /b 1
    )
    rem VS 自带的 CMake 与 Ninja，vcvars 通常已加入 PATH，这里兜底
    set "PATH=!PATH!;!VS_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;!VS_PATH!\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
)

where cmake.exe >nul 2>&1 || ( echo [build] 错误: 未找到 cmake.exe。& exit /b 1 )
where ninja.exe >nul 2>&1 || ( echo [build] 错误: 未找到 ninja.exe。& exit /b 1 )

rem ---------------------------------------------------------------------------
rem 2. Qt 套件
rem ---------------------------------------------------------------------------
if not defined QT_DIR (
    for /f "usebackq delims=" %%Q in (`powershell -NoProfile -Command "$k = Get-ChildItem 'C:\Qt' -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } | Sort-Object { [version]$_.Name } -Descending | ForEach-Object { Get-ChildItem $_.FullName -Directory | Where-Object { $_.Name -like 'msvc*_64' } } | Select-Object -First 1; if ($k) { $k.FullName }"`) do set "QT_DIR=%%Q"
)
if not defined QT_DIR (
    echo [build] 错误: 未找到 Qt。请安装 Qt 6 MSVC 64 位套件，或设置 QT_DIR，例如:
    echo         set QT_DIR=C:\Qt\6.11.2\msvc2022_64
    exit /b 1
)
if not exist "%QT_DIR%\lib\cmake\Qt6\Qt6Config.cmake" (
    echo [build] 错误: QT_DIR 不是有效的 Qt 6 套件: %QT_DIR%
    exit /b 1
)
set "PATH=%QT_DIR%\bin;%PATH%"
echo [build] Qt 套件: %QT_DIR%

rem ---------------------------------------------------------------------------
rem 3. 只有安装时才打开依赖部署（cmake\DeployWindows.cmake，调用 windeployqt）
rem ---------------------------------------------------------------------------
set "DEPLOY_ARGS=-DENABLE_WINDEPLOYQT=OFF"
if "%DO_INSTALL%"=="1" set "DEPLOY_ARGS=-DENABLE_WINDEPLOYQT=ON"

rem ---------------------------------------------------------------------------
rem 4. 配置、构建、测试
rem ---------------------------------------------------------------------------
if "%CLEAN%"=="1" if exist "%BUILD_DIR%" (
    echo [build] 清理构建目录
    rmdir /s /q "%BUILD_DIR%"
)

set "QT_DIR_CMAKE=%QT_DIR:\=/%"
echo [build] 配置 CMake
cmake -S "%SOURCE_DIR%" -B "%BUILD_DIR%" -G Ninja ^
    -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
    "-DCMAKE_PREFIX_PATH=%QT_DIR_CMAKE%" ^
    -DBUILD_TESTING=ON ^
    %DEPLOY_ARGS% %CV_CMAKE_ARGS%
if errorlevel 1 ( echo [build] 错误: CMake 配置失败。& exit /b 1 )

echo [build] 编译 (-j8)
cmake --build "%BUILD_DIR%" -j8
if errorlevel 1 ( echo [build] 错误: 编译失败。& exit /b 1 )

if "%RUN_TESTS%"=="1" (
    echo [build] 运行测试
    ctest --test-dir "%BUILD_DIR%" --output-on-failure
    if errorlevel 1 ( echo [build] 错误: 测试失败。& exit /b 1 )
)

if "%DO_INSTALL%"=="1" (
    echo [build] 安装并部署 Qt 依赖
    if defined INSTALL_PREFIX (
        cmake --install "%BUILD_DIR%" --prefix "%INSTALL_PREFIX%"
    ) else (
        cmake --install "%BUILD_DIR%"
    )
    if errorlevel 1 ( echo [build] 错误: 安装失败。& exit /b 1 )
    if defined INSTALL_PREFIX (
        echo [build] 安装完成: %INSTALL_PREFIX%
    ) else (
        echo [build] 安装完成，输出目录见上方 "Target install directory"（默认在 install\ 下）
    )
)

echo [build] 完成
exit /b 0

:usage
echo 用法: scripts\build.cmd [Debug^|Release] [--no-test] [--clean] [--install [目录]]
exit /b 0

:usage_error
echo 用法: scripts\build.cmd [Debug^|Release] [--no-test] [--clean] [--install [目录]]
exit /b 2
