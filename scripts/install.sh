#!/usr/bin/env bash
# ============================================================================
# CarrierVision Linux 发布打包脚本
#
# 用法:
#   scripts/install.sh [目录] [--no-test] [--clean]
#
# 以 Release 构建并运行测试，然后 cmake --install 并执行 scripts/deploy_linux.py，
# 生成可直接拷贝运行的独立目录（Qt 运行库、插件、QML 模块、fonts/、启动脚本）。
# 不给目录时输出到 install/CarrierVision_linux_<版本>。
#
# 需要: cmake 3.21+、C++17 编译器、Qt 6、python3。
# 在 Windows 的 Git Bash / MSYS 中运行时，自动转交给同目录的 install.cmd。
# 现场升级时只替换程序文件，data/、images/、logs/ 保持不动（见 AGENTS.md 第 7 节）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        exec cmd.exe //c "$(cygpath -w "$SCRIPT_DIR/install.cmd")" "$@"
        ;;
esac

PREFIX=()
EXTRA=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) echo "用法: scripts/install.sh [目录] [--no-test] [--clean]"; exit 0 ;;
        --*) EXTRA+=("$arg") ;;
        *)   PREFIX=("$arg") ;;
    esac
done

exec "$SCRIPT_DIR/build.sh" Release ${EXTRA[@]+"${EXTRA[@]}"} --install ${PREFIX[@]+"${PREFIX[@]}"}
