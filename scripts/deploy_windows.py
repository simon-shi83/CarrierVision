#!/usr/bin/env python3
# ==============================================================================
# CarrierVision 独立完整依赖精简部署打包脚本 (Windows)
# 规范化输出目录结构，完全对齐 Linux 独立发布包结构：
# ├── CarrierVision.exe
# ├── CarrierVision.bat
# ├── CarrierVision.svg
# ├── README.txt
# ├── qt.conf
# ├── lib/       (所有核心 DLL 及 C/C++ 运行时)
# ├── plugins/   (所有 Qt 平台、图像、数据库、网络等插件目录)
# └── qml/       (所有 QML 运行时组件目录)
# ==============================================================================
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

def deploy_windows(install_dir_str, qt_dir_str, source_dir_str):
    install_path = Path(install_dir_str).resolve()
    qt_path = Path(qt_dir_str).resolve()
    source_path = Path(source_dir_str).resolve()

    app_exe = install_path / "CarrierVision.exe"
    if not app_exe.is_file():
        raise FileNotFoundError(f"CarrierVision.exe not found in install dir: {app_exe}")

    print(f"[Windows Deploy] 开始针对目标执行部署: {app_exe}")
    print(f"[Windows Deploy] Qt 安装路径: {qt_path}")

    windeployqt = qt_path / "bin" / "windeployqt.exe"
    if not windeployqt.is_file():
        # 尝试从系统 PATH 中寻找 windeployqt
        which_res = shutil.which("windeployqt")
        if which_res:
            windeployqt = Path(which_res)
        else:
            raise FileNotFoundError(f"windeployqt.exe not found at: {windeployqt}")

    # 1. 执行 windeployqt 自动收集所有直接与间接依赖
    qml_dir = source_path / "qml"
    cmd = [
        str(windeployqt),
        str(app_exe),
        "--qmldir", str(qml_dir),
        "--compiler-runtime",
        "--force"
    ]
    print(f"[Windows Deploy] 执行 windeployqt: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[Warning] windeployqt stderr:\n{res.stderr}")
    else:
        print("[Windows Deploy] windeployqt 完成依赖收集。")

    # 2. 规范化重组目录结构
    # 2.1 归拢所有动态库 (*.dll) 到 lib/ 目录
    lib_dir = install_path / "lib"
    lib_dir.mkdir(parents=True, exist_ok=True)

    moved_dlls = 0
    for item in list(install_path.glob("*.dll")):
        target = lib_dir / item.name
        if target.exists():
            target.unlink()
        shutil.move(str(item), str(target))
        moved_dlls += 1
    print(f"[Windows Deploy] 已归拢 {moved_dlls} 个核心动态链接库到 lib/ 目录。")

    # 2.2 归拢所有插件子目录到 plugins/ 目录
    plugins_dir = install_path / "plugins"
    plugins_dir.mkdir(parents=True, exist_ok=True)

    # 常见的 Qt 插件子目录列表
    known_plugin_names = {
        "platforms", "styles", "imageformats", "iconengines",
        "sqldrivers", "tls", "networkinformation", "assetimporters",
        "qmltooling", "generic", "multimedia", "position", "sensors"
    }

    moved_plugins = 0
    for item in list(install_path.iterdir()):
        if item.is_dir() and item.name not in {"lib", "plugins", "qml", "data"}:
            if item.name in known_plugin_names or any(item.glob("*.dll")):
                target = plugins_dir / item.name
                if target.exists():
                    shutil.rmtree(target)
                shutil.move(str(item), str(target))
                moved_plugins += 1
    print(f"[Windows Deploy] 已归拢 {moved_plugins} 个插件目录到 plugins/ 目录。")

    # 2.3 生成标准 qt.conf（重定向 Libraries, Plugins, Qml2Imports）
    qt_conf_path = install_path / "qt.conf"
    qt_conf_content = """[Paths]
Prefix = .
Libraries = lib
Plugins = plugins
Qml2Imports = qml
"""
    qt_conf_path.write_text(qt_conf_content, encoding="utf-8")
    print(f"[Windows Deploy] 已生成标准运行时配置: {qt_conf_path}")

    # 2.4 生成 Windows 便携启动脚本 CarrierVision.bat (类似 CarrierVision.sh)
    bat_path = install_path / "CarrierVision.bat"
    bat_content = """@echo off
setlocal
set "APP_DIR=%~dp0"
set "PATH=%APP_DIR%lib;%PATH%"
set "QT_PLUGIN_PATH=%APP_DIR%plugins"
set "QML2_IMPORT_PATH=%APP_DIR%qml"
start "" "%APP_DIR%CarrierVision.exe" %*
"""
    bat_path.write_text(bat_content, encoding="utf-8")
    print(f"[Windows Deploy] 已生成便携启动脚本: {bat_path}")

    # 2.5 部署说明文件与图标
    readme_src = source_path / "scripts" / "README.txt"
    if readme_src.is_file():
        shutil.copy2(readme_src, install_path / "README.txt")

    icon_src = source_path / "icons" / "logo_agc.svg"
    if icon_src.is_file():
        shutil.copy2(icon_src, install_path / "CarrierVision.svg")

    print("=" * 60)
    print("[Windows Deploy] 部署完成！结构已完全对齐独立发布包规范。")
    print("=" * 60)
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Deploy Windows standalone dependencies for CarrierVision")
    parser.add_argument("--install-dir", required=True, help="Installation output directory")
    parser.add_argument("--qt-dir", required=True, help="Qt installation root directory")
    parser.add_argument("--source-dir", required=True, help="Project source root directory")

    args = parser.parse_args()
    ret = deploy_windows(args.install_dir, args.qt_dir, args.source_dir)
    sys.exit(ret)
