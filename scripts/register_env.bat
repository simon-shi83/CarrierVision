@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================================
echo           CarrierVision Windows 环境变量一键注册工具
echo ======================================================================
echo.

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

set "LIB_DIR=%APP_DIR%\lib"
set "PLUGIN_DIR=%APP_DIR%\plugins"
set "QML_DIR=%APP_DIR%\qml"

if not exist "%LIB_DIR%" (
    echo [错误] 未在当前目录下检测到 lib 目录：%LIB_DIR%
    echo 请确保本批处理文件位于 CarrierVision 安装根目录中。
    echo.
    pause
    exit /b 1
)

echo 正在将 CarrierVision 运行环境写入当前用户环境变量...
echo 应用程序目录: %APP_DIR%
echo 动态库路径  : %LIB_DIR%
echo 插件路径    : %PLUGIN_DIR%
echo QML组件路径 : %QML_DIR%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$userPath = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
    "$libDir = '%LIB_DIR%';" ^
    "if (-not $userPath) { $userPath = '' };" ^
    "$paths = $userPath.Split(';') | Where-Object { $_ -ne '' };" ^
    "if ($paths -notcontains $libDir) {" ^
    "    $newPath = if ($userPath) { $userPath + ';' + $libDir } else { $libDir };" ^
    "    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User');" ^
    "    Write-Host '[成功] 已将 lib 目录添加至当前用户 PATH 环境变量！' -ForegroundColor Green;" ^
    "} else {" ^
    "    Write-Host '[提示] lib 目录已存在于用户 PATH 中，无需重复添加。' -ForegroundColor Yellow;" ^
    "};" ^
    "[Environment]::SetEnvironmentVariable('QT_PLUGIN_PATH', '%PLUGIN_DIR%', 'User');" ^
    "[Environment]::SetEnvironmentVariable('QML2_IMPORT_PATH', '%QML_DIR%', 'User');" ^
    "Write-Host '[成功] 已配置 QT_PLUGIN_PATH 与 QML2_IMPORT_PATH 环境变量！' -ForegroundColor Green;"

echo.
echo ======================================================================
echo  注册完成！
echo  现在您可以：
echo    1. 在根目录下直接双击 CarrierVision.exe 启动（原生支持，无需黑框）
echo    2. 在任何命令行终端中直接调用 CarrierVision 相关命令
echo ======================================================================
echo.
pause
