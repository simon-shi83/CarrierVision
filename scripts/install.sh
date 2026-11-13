#!/usr/bin/env bash
# ============================================================================
# CarrierVision Linux 发布打包脚本（只安装，不编译）
#
# 用法:
#   scripts/install.sh [目录] [--build-dir <构建目录>]
#
# 对已编译好的构建目录（默认 build/Release）执行 cmake --install，并由
# scripts/deploy_linux.py 收集 Qt 运行库、插件和 QML 模块，生成可直接拷贝运行的独立目录。
# 不给目录时输出到 install/CarrierVision_linux_<版本>。
#
# 先用 scripts/build.sh 编译。构建目录不是最新时脚本会拒绝安装，避免打出旧版本的包。
# 在 Windows 的 Git Bash / MSYS 中运行时，自动转交给同目录的 install.cmd。
# 现场升级时只替换程序文件，data/、images/、logs/ 保持不动（见 AGENTS.md 第 7 节）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        exec cmd.exe //c "$(cygpath -w "$SCRIPT_DIR/install.cmd")" "$@"
        ;;
esac

usage() { echo "用法: scripts/install.sh [目录] [--build-dir <构建目录>]"; }

BUILD_DIR="$SOURCE_DIR/build/Release"
PREFIX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --build-dir)
            [[ $# -gt 1 ]] || { usage; exit 2; }
            BUILD_DIR="$(realpath -m "$2")"; shift ;;
        --*) echo "[install] 未知参数: $1"; usage; exit 2 ;;
        *)   PREFIX="$(realpath -m "$1")" ;;
    esac
    shift
done

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "[install] 错误: 构建目录不存在或尚未配置: $BUILD_DIR"
    echo "          请先运行 scripts/build.sh"
    exit 1
fi
if ! grep -q '^ENABLE_LINUX_DEPLOY:BOOL=ON' "$BUILD_DIR/CMakeCache.txt"; then
    echo "[install] 错误: 该构建目录未开启依赖部署（ENABLE_LINUX_DEPLOY），需要 python3 后重新运行 scripts/build.sh"
    exit 1
fi

# 检查构建是否最新（Ninja 生成器）：试运行没有待执行的步骤才继续
if [[ -f "$BUILD_DIR/build.ninja" ]]; then
    echo "[install] 检查构建目录是否最新: $BUILD_DIR"
    if ! cmake --build "$BUILD_DIR" -- -n 2>&1 | grep -q "no work to do"; then
        echo "[install] 错误: 构建目录不是最新（源码或 git 提交有变化），安装会得到旧版本。"
        echo "          请先运行 scripts/build.sh 重新编译，再执行本脚本。"
        exit 1
    fi
fi

echo "[install] 安装并部署 Qt 依赖"
if [[ -n "$PREFIX" ]]; then
    cmake --install "$BUILD_DIR" --prefix "$PREFIX"
    echo "[install] 安装完成: $PREFIX"
else
    cmake --install "$BUILD_DIR"
    echo "[install] 安装完成: $(sed -n 's/^CMAKE_INSTALL_PREFIX:PATH=//p' "$BUILD_DIR/CMakeCache.txt")"
fi
