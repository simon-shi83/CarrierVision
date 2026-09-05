@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ======================================================================
echo           CarrierVision Windows 环境变量清理/注销工具
echo ======================================================================
echo.

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "LIB_DIR=%APP_DIR%\lib"

echo 正在清理当前用户的 CarrierVision 环境变量配置...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$userPath = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
    "$libDir = '%LIB_DIR%';" ^
    "if ($userPath) {" ^
    "    $paths = $userPath.Split(';') | Where-Object { $_ -ne $libDir -and $_ -ne '' };" ^
    "    $newPath = $paths -join ';';" ^
    "    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User');" ^
    "};" ^
    "[Environment]::SetEnvironmentVariable('QT_PLUGIN_PATH', $null, 'User');" ^
    "[Environment]::SetEnvironmentVariable('QML2_IMPORT_PATH', $null, 'User');" ^
    "Write-Host '[成功] 已成功从用户环境变量中移除 CarrierVision 相关配置！' -ForegroundColor Green;"

echo.
echo ======================================================================
echo  清理完成！
echo ======================================================================
echo.
pause
