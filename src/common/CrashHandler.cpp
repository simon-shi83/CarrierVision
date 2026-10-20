#include "common/CrashHandler.h"

#include <QByteArray>
#include <QDir>

#if defined(Q_OS_WIN)
#include <windows.h>
#include <dbghelp.h>
#include <string>
#else
#include <csignal>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <unistd.h>
#if __has_include(<execinfo.h>)
#include <execinfo.h>
#define CARRIERVISION_HAS_BACKTRACE 1
#endif
#endif

namespace CrashHandler {

#if defined(Q_OS_WIN)

namespace {
std::wstring g_dumpDir;

LONG WINAPI writeMiniDump(EXCEPTION_POINTERS *info)
{
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t name[64];
    swprintf(name, 64, L"\\crash_%04d%02d%02d_%02d%02d%02d.dmp",
             now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);
    const std::wstring path = g_dumpDir + name;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        MINIDUMP_EXCEPTION_INFORMATION exception{};
        exception.ThreadId = GetCurrentThreadId();
        exception.ExceptionPointers = info;
        exception.ClientPointers = FALSE;
        MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file,
                          static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo | MiniDumpWithIndirectlyReferencedMemory),
                          &exception, nullptr, nullptr);
        CloseHandle(file);
    }
    return EXCEPTION_CONTINUE_SEARCH; // 继续交给系统处理（Windows 错误报告）
}
} // namespace

void install(const QString &dir)
{
    QDir().mkpath(dir);
    g_dumpDir = QDir::toNativeSeparators(QDir(dir).absolutePath()).toStdWString();
    SetUnhandledExceptionFilter(writeMiniDump);
}

#else

namespace {
char g_crashLog[4096] = {0};

void writeText(int fd, const char *text)
{
    const ssize_t ignored = ::write(fd, text, std::strlen(text));
    (void)ignored;
}

void writeNumber(int fd, long long value)
{
    char buffer[32];
    int pos = sizeof(buffer);
    const bool negative = value < 0;
    unsigned long long v = negative ? -value : value;
    do { buffer[--pos] = char('0' + v % 10); v /= 10; } while (v && pos > 1);
    if (negative) buffer[--pos] = '-';
    const ssize_t ignored = ::write(fd, buffer + pos, sizeof(buffer) - pos);
    (void)ignored;
}

// 只使用异步信号安全的调用（open/write/close、backtrace_symbols_fd）
void onFatalSignal(int signal)
{
    const int fd = ::open(g_crashLog, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        writeText(fd, "==== CarrierVision crash: signal ");
        writeNumber(fd, signal);
        writeText(fd, ", unix time ");
        writeNumber(fd, static_cast<long long>(::time(nullptr)));
        writeText(fd, ", pid ");
        writeNumber(fd, static_cast<long long>(::getpid()));
        writeText(fd, "\n");
#ifdef CARRIERVISION_HAS_BACKTRACE
        void *frames[64];
        const int count = ::backtrace(frames, 64);
        ::backtrace_symbols_fd(frames, count, fd);
#endif
        writeText(fd, "\n");
        ::close(fd);
    }
    // SA_RESETHAND 已恢复默认处理：重新发出信号，照常终止并生成 core
    ::raise(signal);
}
} // namespace

void install(const QString &dir)
{
    QDir().mkpath(dir);
    const QByteArray path = QDir(dir).absoluteFilePath(QStringLiteral("crash.log")).toLocal8Bit();
    std::strncpy(g_crashLog, path.constData(), sizeof(g_crashLog) - 1);
#ifdef CARRIERVISION_HAS_BACKTRACE
    // 预先调用一次，让 backtrace 在正常状态下完成动态库加载，避免在信号处理中首次加载
    void *warmup[1];
    ::backtrace(warmup, 1);
#endif
    struct sigaction action {};
    action.sa_handler = onFatalSignal;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND;
    for (const int signal : {SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL})
        ::sigaction(signal, &action, nullptr);
}

#endif

} // namespace CrashHandler
