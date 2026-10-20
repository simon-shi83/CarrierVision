@echo off
rem ============================================================================
rem CarrierVision 守护启动脚本：程序异常退出（崩溃）后 5 秒自动重启；
rem 在界面中正常退出（退出码 0）时守护随之结束。
rem 开机自启：将本脚本的快捷方式放入“启动”文件夹（Win+R 输入 shell:startup）。
rem 重启记录写入 logs\watchdog.log。
rem ============================================================================
setlocal
set "APP_DIR=%~dp0"
set "PATH=%APP_DIR%lib;%PATH%"
set "QT_PLUGIN_PATH=%APP_DIR%plugins"
set "QML2_IMPORT_PATH=%APP_DIR%qml"
if not exist "%APP_DIR%logs" mkdir "%APP_DIR%logs"

:run
"%APP_DIR%CarrierVision.exe" %*
set "CODE=%ERRORLEVEL%"
if "%CODE%"=="0" goto :eof
echo %DATE% %TIME% CarrierVision 异常退出 (退出码 %CODE%)，5 秒后重启>> "%APP_DIR%logs\watchdog.log"
timeout /t 5 /nobreak > nul
goto run
