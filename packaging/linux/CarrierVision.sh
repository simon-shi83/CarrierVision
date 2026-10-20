#!/bin/bash
# ==============================================================================
# CarrierVision 独立便携式启动脚本
# ==============================================================================
set -e

# 获取脚本所在根目录（支持从任何工作目录调用或双击运行）
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
APP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# 环境变量配置：优先使用随包附带的 Qt 共享库、插件和 QML 模块
export LD_LIBRARY_PATH="$APP_DIR/lib:$APP_DIR:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$APP_DIR/plugins"
export QML2_IMPORT_PATH="$APP_DIR/qml"
export QT_QPA_PLATFORM_PLUGIN_PATH="$APP_DIR/plugins/platforms"

# 默认优先使用 xcb，若无法使用则尝试 wayland
if [ -z "$QT_QPA_PLATFORM" ]; then
    export QT_QPA_PLATFORM="xcb;wayland"
fi

# 启动可执行程序
exec "$APP_DIR/CarrierVision" "$@"

