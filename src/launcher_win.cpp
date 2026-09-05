// ==============================================================================
// CarrierVision Windows 原生无黑框快速启动器 (Native Win32 Root Launcher)
// 1. 纯 Win32 API 编写，无任何第三方或 Qt 动态库依赖，加载零时延且不弹黑框控制台
// 2. 运行时动态将同级 ./lib 目录添加至当前进程 PATH 环境变量最前列
// 3. 动态配置 QT_PLUGIN_PATH 与 QML2_IMPORT_PATH
// 4. 透明拉起 lib/CarrierVision_app.exe，完整透传命令行参数
// ==============================================================================
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow) {
    (void)hInstance;
    (void)hPrevInstance;

    // 1. 获取当前启动器程序所在根目录
    wchar_t exePath[MAX_PATH];
    if (GetModuleFileNameW(NULL, exePath, MAX_PATH) == 0) {
        return 1;
    }

    std::wstring pathStr(exePath);
    size_t lastSlash = pathStr.find_last_of(L"\\/");
    if (lastSlash == std::wstring::npos) {
        return 1;
    }
    std::wstring appDir = pathStr.substr(0, lastSlash);

    // 2. 构造依赖路径与目标主程序路径
    std::wstring libDir = appDir + L"\\lib";
    std::wstring pluginsDir = appDir + L"\\plugins";
    std::wstring qmlDir = appDir + L"\\qml";

    // 首选主程序为 lib\CarrierVision_app.exe
    std::wstring targetExe = libDir + L"\\CarrierVision_app.exe";
    DWORD fileAttr = GetFileAttributesW(targetExe.c_str());
    if (fileAttr == INVALID_FILE_ATTRIBUTES || (fileAttr & FILE_ATTRIBUTE_DIRECTORY)) {
        // 备选路径：lib\CarrierVision.exe
        targetExe = libDir + L"\\CarrierVision.exe";
        fileAttr = GetFileAttributesW(targetExe.c_str());
        if (fileAttr == INVALID_FILE_ATTRIBUTES || (fileAttr & FILE_ATTRIBUTE_DIRECTORY)) {
            MessageBoxW(NULL,
                L"未能找到应用程序本体 (lib\\CarrierVision_app.exe)。\n请确保安装包文件完整且解压无误。",
                L"CarrierVision 启动错误",
                MB_OK | MB_ICONERROR);
            return 1;
        }
    }

    // 3. 将 ./lib 目录加入到当前进程的 PATH 环境变量最前列
    std::vector<wchar_t> pathBuffer(32768);
    DWORD pathLen = GetEnvironmentVariableW(L"PATH", pathBuffer.data(), 32768);
    std::wstring newPath = libDir;
    if (pathLen > 0) {
        newPath += L";" + std::wstring(pathBuffer.data(), pathLen);
    }
    SetEnvironmentVariableW(L"PATH", newPath.c_str());

    // 4. 设置 Qt 插件与 QML 模块的搜索路径
    SetEnvironmentVariableW(L"QT_PLUGIN_PATH", pluginsDir.c_str());
    SetEnvironmentVariableW(L"QML2_IMPORT_PATH", qmlDir.c_str());

    // 5. 组装完整命令行并透明启动主程序
    std::wstring fullCommandLine = L"\"" + targetExe + L"\"";
    if (lpCmdLine && wcslen(lpCmdLine) > 0) {
        fullCommandLine += L" ";
        fullCommandLine += lpCmdLine;
    }

    STARTUPINFOW si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = (WORD)nCmdShow;

    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    BOOL success = CreateProcessW(
        NULL,
        &fullCommandLine[0],
        NULL,
        NULL,
        FALSE,
        0,
        NULL,
        appDir.c_str(),
        &si,
        &pi
    );

    if (!success) {
        wchar_t errorMsg[512];
        wsprintfW(errorMsg, L"启动主程序失败，系统错误代码: %lu", GetLastError());
        MessageBoxW(NULL, errorMsg, L"CarrierVision 启动错误", MB_OK | MB_ICONERROR);
        return 1;
    }

    // 释放进程句柄，启动器即刻安静退出，由主程序独立运行
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
