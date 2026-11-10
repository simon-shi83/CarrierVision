@echo off
rem ============================================================================
rem CarrierVision Windows 发布打包脚本
rem
rem 用法:
rem   scripts\install.cmd [目录] [--no-test] [--clean]
rem
rem 以 Release 构建并运行测试，然后 cmake --install 并执行 cmake/DeployWindows.cmake（调用 windeployqt），
rem 生成可直接拷贝到工控机运行的目录（lib\、plugins\、qml\、fonts\、qt.conf、CarrierVision.bat）。
rem 不给目录时输出到 install\CarrierVision_windows_<版本>。
rem
rem 需要: Visual Studio / Build Tools（C++ x64）、Qt 6 MSVC 64 位套件。
rem 现场升级时只替换程序文件，data\、images\、logs\ 保持不动（见 AGENTS.md 第 7 节）。
rem ============================================================================
setlocal EnableExtensions
rem shift 会连同 %0 一起移位，先保存脚本目录
set "SCRIPT_DIR=%~dp0"

set "PREFIX_ARG="
set "EXTRA_ARGS="

:parse_args
if "%~1"=="" goto args_done
set "_arg=%~1"
if "%_arg:~0,2%"=="--" (
    set "EXTRA_ARGS=%EXTRA_ARGS% %1"
) else if /i "%_arg%"=="-h" (
    goto usage
) else (
    set "PREFIX_ARG=%~f1"
)
shift
goto parse_args

:args_done
if defined PREFIX_ARG (
    call "%SCRIPT_DIR%build.cmd" Release --install "%PREFIX_ARG%" %EXTRA_ARGS%
) else (
    call "%SCRIPT_DIR%build.cmd" Release --install %EXTRA_ARGS%
)
exit /b %errorlevel%

:usage
echo 用法: scripts\install.cmd [目录] [--no-test] [--clean]
exit /b 0
