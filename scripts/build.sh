#!/usr/bin/env bash
# ============================================================================
# CarrierVision Linux 构建脚本
#
# 用法:
#   scripts/build.sh [Debug|Release] [--no-test] [--clean] [--install [目录]]
#
#   Debug / Release   构建类型，默认 Debug，构建目录为 build/<类型>
#   --no-test         跳过 ctest
#   --clean           先删除对应构建目录再全量构建
#   --install [目录]  构建后执行 cmake --install 并部署 Qt 依赖（需要 python3）；
#                     不给目录时按 CMakeLists 默认输出到 install/CarrierVision_linux_<版本>
#
# 环境变量（均可选）:
#   QT_DIR          Qt 套件根目录，例如 /opt/Qt/6.11.2/gcc_64；
#                   未设置时使用 CMakeLists.txt 中的默认搜索路径（系统 Qt 与 /opt/Qt）
#   CV_CMAKE_ARGS   追加给 cmake 配置步骤的参数
#
# 在 Windows 的 Git Bash / MSYS 中运行时，自动转交给同目录的 build.cmd。
# 并行度固定 -j8，测试在构建完成后串行执行（见 AGENTS.md 第 6 节）。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        exec cmd.exe //c "$(cygpath -w "$SCRIPT_DIR/build.cmd")" "$@"
        ;;
esac

usage() {
    echo "用法: scripts/build.sh [Debug|Release] [--no-test] [--clean] [--install [目录]]"
}

BUILD_TYPE=Release
RUN_TESTS=1
CLEAN=0
DO_INSTALL=0
INSTALL_PREFIX=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        Debug|debug)     BUILD_TYPE=Debug ;;
        Release|release) BUILD_TYPE=Release ;;
        --no-test)       RUN_TESTS=0 ;;
        --clean)         CLEAN=1 ;;
        --install)
            DO_INSTALL=1
            if [[ $# -gt 1 && "$2" != --* && "$2" != Debug && "$2" != Release ]]; then
                INSTALL_PREFIX="$(realpath -m "$2")"
                shift
            fi
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[build] 未知参数: $1"; usage; exit 2 ;;
    esac
    shift
done

BUILD_DIR="$SOURCE_DIR/build/$BUILD_TYPE"
echo "[build] 源码目录: $SOURCE_DIR"
echo "[build] 构建目录: $BUILD_DIR  ($BUILD_TYPE)"

command -v cmake >/dev/null || { echo "[build] 错误: 未找到 cmake（需要 3.21 以上）。"; exit 1; }

GENERATOR_ARGS=()
if command -v ninja >/dev/null || command -v ninja-build >/dev/null; then
    GENERATOR_ARGS=(-G Ninja)
fi

CMAKE_ARGS=(
    -S "$SOURCE_DIR" -B "$BUILD_DIR"
    ${GENERATOR_ARGS[@]+"${GENERATOR_ARGS[@]}"}
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DBUILD_TESTING=ON
)

if [[ -n "${QT_DIR:-}" ]]; then
    if [[ ! -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]]; then
        echo "[build] 错误: QT_DIR 不是有效的 Qt 6 套件: $QT_DIR"
        exit 1
    fi
    echo "[build] Qt 套件: $QT_DIR"
    CMAKE_ARGS+=(-DCMAKE_PREFIX_PATH="$QT_DIR")
    export PATH="$QT_DIR/bin:$PATH"
fi

if [[ "$DO_INSTALL" == 1 ]]; then
    command -v python3 >/dev/null || { echo "[build] 错误: 安装部署需要 python3。"; exit 1; }
    CMAKE_ARGS+=(-DENABLE_LINUX_DEPLOY=ON -DPython3_EXECUTABLE="$(command -v python3)")
else
    CMAKE_ARGS+=(-DENABLE_LINUX_DEPLOY=OFF)
fi

if [[ -n "${CV_CMAKE_ARGS:-}" ]]; then
    # shellcheck disable=SC2206  # 有意按空格拆分
    CMAKE_ARGS+=($CV_CMAKE_ARGS)
fi

if [[ "$CLEAN" == 1 && -d "$BUILD_DIR" ]]; then
    echo "[build] 清理构建目录"
    rm -rf "$BUILD_DIR"
fi

echo "[build] 配置 CMake"
cmake "${CMAKE_ARGS[@]}"

echo "[build] 编译 (-j8)"
cmake --build "$BUILD_DIR" -j8

if [[ "$RUN_TESTS" == 1 ]]; then
    echo "[build] 运行测试"
    ctest --test-dir "$BUILD_DIR" --output-on-failure
fi

if [[ "$DO_INSTALL" == 1 ]]; then
    echo "[build] 安装并部署 Qt 依赖"
    if [[ -n "$INSTALL_PREFIX" ]]; then
        cmake --install "$BUILD_DIR" --prefix "$INSTALL_PREFIX"
        echo "[build] 安装完成: $INSTALL_PREFIX"
    else
        cmake --install "$BUILD_DIR"
        echo "[build] 安装完成，默认输出在 install/ 下"
    fi
fi

echo "[build] 完成"
