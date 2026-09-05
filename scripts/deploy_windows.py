#!/usr/bin/env python3
# ==============================================================================
# CarrierVision 独立完整依赖精简部署打包脚本 (Windows)
# 规范化输出目录结构，完全对齐 Linux 独立发布包规范：
# ├── CarrierVision.exe      (无黑框原生 GUI 快速启动器，可直接双击运行)
# ├── CarrierVision.bat      (便携启动脚本备用)
# ├── register_env.bat       (一键注册当前用户环境变量工具)
# ├── unregister_env.bat     (一键清理环境变量工具)
# ├── CarrierVision.svg      (应用矢量图标)
# ├── README.txt             (发布说明文档)
# ├── qt.conf                (根目录路径重定向配置)
# ├── lib/                   (真实应用 CarrierVision_app.exe、lib/qt.conf 及所有核心 DLL)
# ├── plugins/               (所有 Qt 平台、图像、数据库、网络等插件目录)
# └── qml/                   (所有 QML 运行时组件目录)
# ==============================================================================
import argparse
import io
import os
import shutil
import subprocess
import sys
from pathlib import Path

# 确保在 Windows 控制台环境下输出不会因为编码崩溃
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

def deploy_windows(install_dir_str, qt_dir_str, source_dir_str):
    install_path = Path(install_dir_str).resolve()
    qt_path = Path(qt_dir_str).resolve()
    source_path = Path(source_dir_str).resolve()

    print(f"[Windows Deploy] Target install directory: {install_path}")
    print(f"[Windows Deploy] Qt root path: {qt_path}")
    print(f"[Windows Deploy] Source root path: {source_path}")

    lib_dir = install_path / "lib"
    lib_dir.mkdir(parents=True, exist_ok=True)

    # 1. 定位真实 Qt 应用程序本体 (CarrierVision_app.exe)
    app_exe = lib_dir / "CarrierVision_app.exe"
    if not app_exe.is_file():
        alt_app = install_path / "CarrierVision_app.exe"
        if alt_app.is_file():
            shutil.move(str(alt_app), str(app_exe))
        else:
            candidates = list(install_path.glob("**/CarrierVision_app.exe"))
            if candidates:
                shutil.move(str(candidates[0]), str(app_exe))
            else:
                # 兼容处理：如果没有独立编译 Launcher，则保留根目录的 CarrierVision.exe
                fallback = install_path / "CarrierVision.exe"
                if fallback.is_file():
                    app_exe = fallback
                else:
                    alt_bin = install_path / "bin" / "CarrierVision.exe"
                    if alt_bin.is_file():
                        shutil.move(str(alt_bin), str(fallback))
                        app_exe = fallback
                    else:
                        raise FileNotFoundError(f"Target executable not found in: {install_path}")

    print(f"[Windows Deploy] Located application executable for dependency scan: {app_exe}")

    # 清理残留的 bin/ 目录（如果存在）
    bin_dir = install_path / "bin"
    if bin_dir.is_dir():
        shutil.rmtree(bin_dir, ignore_errors=True)

    # 2. 定位 windeployqt
    windeployqt = qt_path / "bin" / "windeployqt.exe"
    if not windeployqt.is_file():
        which_res = shutil.which("windeployqt")
        if which_res:
            windeployqt = Path(which_res)
        else:
            candidates = list(qt_path.glob("**/windeployqt.exe"))
            if candidates:
                windeployqt = candidates[0]
            else:
                raise FileNotFoundError(f"windeployqt.exe not found in: {qt_path}")

    print(f"[Windows Deploy] Using windeployqt at: {windeployqt}")

    # 3. 运行 windeployqt 自动收集所有直接与间接依赖
    qml_dir = source_path / "qml"
    deploy_env = os.environ.copy()
    deploy_env["PATH"] = f"{qt_path / 'bin'}{os.pathsep}{qt_path / 'libexec'}{os.pathsep}{deploy_env.get('PATH', '')}"

    cmd = [
        str(windeployqt),
        "--qmldir", str(qml_dir),
        "--compiler-runtime",
        "--force",
        "--verbose", "1",
        str(app_exe)
    ]
    print(f"[Windows Deploy] Running windeployqt: {' '.join(cmd)}")
    res = subprocess.run(cmd, env=deploy_env)
    print(f"[Windows Deploy] windeployqt exited with return code: {res.returncode}")

    # 4. 规范化重组目录结构
    # 4.1 归拢所有根目录下多余的动态库 (*.dll) 到 lib/ 目录
    moved_dlls = 0
    for item in list(install_path.glob("*.dll")):
        target = lib_dir / item.name
        if target.resolve() == item.resolve():
            continue
        if target.exists():
            try:
                target.unlink()
            except Exception:
                pass
        try:
            shutil.move(str(item), str(target))
            moved_dlls += 1
        except Exception as e:
            print(f"[Windows Deploy] Retrying DLL move via copy: {item.name} ({e})")
            try:
                shutil.copy2(str(item), str(target))
                item.unlink(missing_ok=True)
                moved_dlls += 1
            except Exception as e2:
                print(f"[Windows Deploy] Warning: failed to move {item.name}: {e2}")

    print(f"[Windows Deploy] Relocated {moved_dlls} root DLL(s) to lib/ directory.")

    # 4.2 归拢所有插件子目录（检查 install_path 和 lib_dir）到 plugins/ 目录
    plugins_dir = install_path / "plugins"
    plugins_dir.mkdir(parents=True, exist_ok=True)

    known_plugin_names = {
        "platforms", "styles", "imageformats", "iconengines",
        "sqldrivers", "tls", "networkinformation", "assetimporters",
        "qmltooling", "generic", "multimedia", "position", "sensors"
    }

    moved_plugins = 0
    # 检查 install_path 根目录下的插件目录
    for item in list(install_path.iterdir()):
        if not item.is_dir():
            continue
        if item.name.lower() in {"lib", "plugins", "qml", "data", "bin", "translations"}:
            continue
        is_plugin = item.name.lower() in known_plugin_names or any(item.glob("*.dll"))
        if is_plugin:
            target = plugins_dir / item.name
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
            try:
                shutil.move(str(item), str(target))
                moved_plugins += 1
            except Exception as e:
                print(f"[Windows Deploy] Retrying plugin move via copytree: {item.name} ({e})")
                try:
                    shutil.copytree(str(item), str(target), dirs_exist_ok=True)
                    shutil.rmtree(str(item), ignore_errors=True)
                    moved_plugins += 1
                except Exception as e2:
                    print(f"[Windows Deploy] Warning: failed to move plugin {item.name}: {e2}")

    # 检查 lib/ 目录下被 windeployqt 直接生成的插件子目录（如 lib/platforms）
    for item in list(lib_dir.iterdir()):
        if not item.is_dir():
            continue
        if item.name.lower() in known_plugin_names:
            target = plugins_dir / item.name
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
            try:
                shutil.move(str(item), str(target))
                moved_plugins += 1
            except Exception as e:
                print(f"[Windows Deploy] Retrying lib plugin move: {item.name} ({e})")
                try:
                    shutil.copytree(str(item), str(target), dirs_exist_ok=True)
                    shutil.rmtree(str(item), ignore_errors=True)
                    moved_plugins += 1
                except Exception as e2:
                    print(f"[Windows Deploy] Warning: failed to move lib plugin {item.name}: {e2}")

    # 检查是否有误放在 lib/ 内部的 qml/ 目录
    if (lib_dir / "qml").is_dir():
        target_qml = install_path / "qml"
        shutil.copytree(str(lib_dir / "qml"), str(target_qml), dirs_exist_ok=True)
        shutil.rmtree(str(lib_dir / "qml"), ignore_errors=True)

    print(f"[Windows Deploy] Relocated {moved_plugins} plugin directories to plugins/ directory.")

    # 4.3 生成双层标准 qt.conf（重定向 Libraries, Plugins, Qml2Imports）
    # 根目录 qt.conf
    qt_conf_path = install_path / "qt.conf"
    qt_conf_content = """[Paths]
Prefix = .
Libraries = lib
Plugins = plugins
Qml2Imports = qml
"""
    qt_conf_path.write_text(qt_conf_content, encoding="utf-8")
    print(f"[Windows Deploy] Generated root runtime config: {qt_conf_path}")

    # lib/ 目录内部 qt.conf (以 lib 为基准，Prefix 指向上一级 ..)
    lib_qt_conf_path = lib_dir / "qt.conf"
    lib_qt_conf_content = """[Paths]
Prefix = ..
Libraries = lib
Plugins = plugins
Qml2Imports = qml
"""
    lib_qt_conf_path.write_text(lib_qt_conf_content, encoding="utf-8")
    print(f"[Windows Deploy] Generated lib runtime config: {lib_qt_conf_path}")

    # 4.4 生成 Windows 便携启动脚本 CarrierVision.bat
    bat_path = install_path / "CarrierVision.bat"
    bat_content = """@echo off
setlocal
set "APP_DIR=%~dp0"
set "PATH=%APP_DIR%lib;%PATH%"
set "QT_PLUGIN_PATH=%APP_DIR%plugins"
set "QML2_IMPORT_PATH=%APP_DIR%qml"
if exist "%APP_DIR%lib\\CarrierVision_app.exe" (
    start "" "%APP_DIR%lib\\CarrierVision_app.exe" %*
) else (
    start "" "%APP_DIR%CarrierVision.exe" %*
)
"""
    bat_path.write_text(bat_content, encoding="utf-8")
    print(f"[Windows Deploy] Generated portable startup batch script: {bat_path}")

    # 4.5 复制环境变量注册与注销批处理脚本
    reg_src = source_path / "scripts" / "register_env.bat"
    reg_dst = install_path / "register_env.bat"
    if reg_src.is_file() and not reg_dst.is_file():
        shutil.copy2(reg_src, reg_dst)
        print(f"[Windows Deploy] Copied {reg_src.name} to package root.")

    unreg_src = source_path / "scripts" / "unregister_env.bat"
    unreg_dst = install_path / "unregister_env.bat"
    if unreg_src.is_file() and not unreg_dst.is_file():
        shutil.copy2(unreg_src, unreg_dst)
        print(f"[Windows Deploy] Copied {unreg_src.name} to package root.")

    # 4.6 部署说明文件与图标（清理多余的原始 logo_agc.svg，确保仅保留 CarrierVision.svg）
    legacy_logo = install_path / "logo_agc.svg"
    if legacy_logo.is_file():
        try:
            legacy_logo.unlink()
            print(f"[Windows Deploy] Removed redundant logo: {legacy_logo}")
        except Exception as e:
            print(f"[Windows Deploy] Warning removing {legacy_logo}: {e}")

    readme_src = source_path / "scripts" / "README.txt"
    readme_dst = install_path / "README.txt"
    if readme_src.is_file() and not readme_dst.is_file():
        shutil.copy2(readme_src, readme_dst)

    icon_dst = install_path / "CarrierVision.svg"
    if not icon_dst.is_file():
        icon_src = source_path / "icons" / "logo_agc.svg"
        if icon_src.is_file():
            shutil.copy2(icon_src, icon_dst)

    print("=" * 60)
    print("[Windows Deploy] Deployment finished successfully!")
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
