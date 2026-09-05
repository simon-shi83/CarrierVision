#!/usr/bin/env python3
# ==============================================================================
# CarrierVision 独立完整依赖精简部署打包脚本 (Linux)
# ==============================================================================
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

NEEDED_PATTERN = re.compile(r'NEEDED\s+(\S+)')

def get_needed_libraries(binary_path):
    """使用 objdump 解析 ELF 文件的直接依赖 (DT_NEEDED)"""
    try:
        res = subprocess.run(
            ['objdump', '-p', str(binary_path)],
            capture_output=True,
            text=True,
            check=True
        )
        return NEEDED_PATTERN.findall(res.stdout)
    except Exception as error:
        raise RuntimeError(f"Cannot inspect ELF dependency: {binary_path}") from error

def copy_with_symlinks(src_path, dst_dir):
    """
    拷贝动态库并保留/重建相关软链接。
    例如：src_path 为 libQt6Core.so.6，真实文件为 libQt6Core.so.6.11.2，
    则将 libQt6Core.so.6.11.2 复制到 dst_dir，并在 dst_dir 中创建指向它的软链接。
    """
    src = Path(src_path)
    dst_dir = Path(dst_dir)
    dst_dir.mkdir(parents=True, exist_ok=True)

    if src.is_symlink():
        real_file = src.resolve()
        target_real = dst_dir / real_file.name
        if not target_real.exists() or target_real.stat().st_size != real_file.stat().st_size:
            shutil.copy2(real_file, target_real)

        symlink_name = dst_dir / src.name
        if symlink_name.exists() or symlink_name.is_symlink():
            symlink_name.unlink()
        symlink_name.symlink_to(real_file.name)
        return target_real
    else:
        target = dst_dir / src.name
        if not target.exists() or target.stat().st_size != src.stat().st_size:
            shutil.copy2(src, target)
        return target

def copy_qml_tree(src_dir, dst_dir, include_subdirs=None, exclude_subdirs=None):
    """精简拷贝 QML 模块目录，支持白名单与黑名单过滤子目录"""
    src_dir = Path(src_dir)
    dst_dir = Path(dst_dir)
    dst_dir.mkdir(parents=True, exist_ok=True)

    include_subdirs = set(include_subdirs) if include_subdirs else None
    exclude_subdirs = set(exclude_subdirs) if exclude_subdirs else set()

    for item in src_dir.iterdir():
        if item.is_file():
            shutil.copy2(item, dst_dir / item.name)
        elif item.is_dir():
            if item.name in exclude_subdirs:
                continue
            if include_subdirs is not None and item.name not in include_subdirs:
                continue
            dst_sub = dst_dir / item.name
            if dst_sub.exists():
                shutil.rmtree(dst_sub)
            shutil.copytree(item, dst_sub, symlinks=True)

def deploy(install_dir, qt_dir, build_dir, source_dir):
    install_path = Path(install_dir).resolve()
    qt_path = Path(qt_dir).resolve()
    qt_lib_dir = qt_path / "lib"
    qt_plugins_dir = qt_path / "plugins"
    qt_qml_dir = qt_path / "qml"

    app_bin = install_path / "CarrierVision"
    if not app_bin.exists():
        legacy_bin = install_path / "bin" / "CarrierVision"
        if legacy_bin.exists():
            shutil.move(legacy_bin, app_bin)

    if not app_bin.exists():
        print(f"[ERROR] Target binary not found: {app_bin}", file=sys.stderr)
        return 1

    # 清理残留的 bin/ 目录（程序已直接放置在根目录下）
    legacy_bin_dir = install_path / "bin"
    if legacy_bin_dir.exists():
        shutil.rmtree(legacy_bin_dir, ignore_errors=True)

    target_lib_dir = install_path / "lib"
    target_plugins_dir = install_path / "plugins"
    target_qml_dir = install_path / "qml"

    # 部署前清理旧依赖目录，避免残留过往版本的无用库（例如 Widgets、Charts 等）
    if target_lib_dir.exists():
        shutil.rmtree(target_lib_dir)
    if target_plugins_dir.exists():
        shutil.rmtree(target_plugins_dir)
    if target_qml_dir.exists():
        shutil.rmtree(target_qml_dir)

    target_lib_dir.mkdir(parents=True, exist_ok=True)
    target_plugins_dir.mkdir(parents=True, exist_ok=True)
    target_qml_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("CarrierVision Linux 独立全依赖精简部署")
    print("=" * 60)
    print(f"安装目录: {install_path}")
    print(f"Qt 根目录: {qt_path}")

    # 1. 部署 Qt 精简核心插件 (Plugins)
    # 严格仅挑选桌面 GUI 运行所需插件，排除 embedded/framebuffer/vnc 等非必要插件
    plugin_specs = {
        "platforms": ["libqxcb.so", "libqwayland.so", "libqoffscreen.so"],
        "xcbglintegrations": ["libqxcb-glx-integration.so", "libqxcb-egl-integration.so"],
        "wayland-graphics-integration-client": ["libqt-plugin-wayland-egl.so"],
        "wayland-shell-integration": ["libxdg-shell.so", "libqt-shell.so"],
        "sqldrivers": ["libqsqlite.so"],
        "imageformats": ["libqsvg.so", "libqjpeg.so", "libqico.so", "libqtiff.so", "libqwebp.so"],
        "iconengines": ["libqsvgicon.so"],
        "tls": ["libqopensslbackend.so", "libqcertonlybackend.so"],
        "assetimporters": ["libuip.so", "libassimp.so"],
    }

    copied_plugins = []
    for group, plugin_names in plugin_specs.items():
        src_group_dir = qt_plugins_dir / group
        if not src_group_dir.exists():
            continue
        dst_group_dir = target_plugins_dir / group
        dst_group_dir.mkdir(parents=True, exist_ok=True)

        for p_name in plugin_names:
            src_p = src_group_dir / p_name
            if src_p.exists():
                dst_p = dst_group_dir / p_name
                shutil.copy2(src_p, dst_p)
                copied_plugins.append(dst_p)

    print(f"[OK] 已部署必要插件组 ({len(plugin_specs)} 组, 共 {len(copied_plugins)} 个插件)")

    # 2. 部署项目实际引用的 QML 模块（按需精简，去除未使用的 Dialogs、Imagine、Material、Particles3D、XR等）
    # 2.1 QtCore
    if (qt_qml_dir / "QtCore").exists():
        shutil.copytree(qt_qml_dir / "QtCore", target_qml_dir / "QtCore", symlinks=True)

    # 2.2 QtQml (仅保留 Models 和 WorkerScript)
    if (qt_qml_dir / "QtQml").exists():
        copy_qml_tree(qt_qml_dir / "QtQml", target_qml_dir / "QtQml", include_subdirs=["Models", "WorkerScript"])

    # 2.3 QtQuick (仅保留 Window, Layouts, Effects, Controls)
    if (qt_qml_dir / "QtQuick").exists():
        # 先拷贝顶层和基础子模块
        copy_qml_tree(
            qt_qml_dir / "QtQuick",
            target_qml_dir / "QtQuick",
            include_subdirs=["Window", "Layouts", "Effects", "Controls", "Templates"]
        )
        # 对 QtQuick/Controls 精简样式，仅保留基础 Basic 与项目设定的 Fusion
        src_controls = qt_qml_dir / "QtQuick" / "Controls"
        dst_controls = target_qml_dir / "QtQuick" / "Controls"
        if src_controls.exists():
            if dst_controls.exists():
                shutil.rmtree(dst_controls)
            copy_qml_tree(
                src_controls,
                dst_controls,
                include_subdirs=["Basic", "Fusion", "impl"]
            )

    # 2.4 QtQuick3D (仅保留主模块和 AssetUtils)
    if (qt_qml_dir / "QtQuick3D").exists():
        copy_qml_tree(
            qt_qml_dir / "QtQuick3D",
            target_qml_dir / "QtQuick3D",
            include_subdirs=["AssetUtils"]
        )

    for module in ["QtQuick/Templates", "QtQuick/Controls/impl", "QtQuick/Controls/Fusion"]:
        if not (target_qml_dir / module / "qmldir").is_file():
            raise RuntimeError(f"Required QML module missing: {module}")

    print("[OK] 已部署按需精简的 Qt QML 运行时模块 (QtCore, QtQml, QtQuick, QtQuick3D)")

    # 3. 递归解析并收集所有依赖的 Qt 共享库与 ICU 字符库
    to_scan = [app_bin]
    for p in copied_plugins:
        to_scan.append(p)
    for qml_so in target_qml_dir.rglob("*.so"):
        to_scan.append(qml_so)

    scanned_binaries = set()
    needed_qt_libs = set()

    available_qt_libs = {}
    for item in qt_lib_dir.iterdir():
        if item.is_file() or item.is_symlink():
            available_qt_libs[item.name] = item

    while to_scan:
        curr = to_scan.pop()
        real_curr = curr.resolve()
        if real_curr in scanned_binaries:
            continue
        scanned_binaries.add(real_curr)

        needed = get_needed_libraries(real_curr)
        for lib_name in needed:
            if lib_name in available_qt_libs:
                if lib_name not in needed_qt_libs:
                    needed_qt_libs.add(lib_name)
                    lib_file = available_qt_libs[lib_name]
                    to_scan.append(lib_file)

    # 关键基础 ICU 与平台动态库
    for icu_prefix in ["libicudata.so.73", "libicui18n.so.73", "libicuuc.so.73", "libQt6XcbQpa.so.6", "libQt6DBus.so.6"]:
        if icu_prefix in available_qt_libs:
            needed_qt_libs.add(icu_prefix)

    copied_lib_count = 0
    for lib_name in sorted(needed_qt_libs):
        src_file = available_qt_libs[lib_name]
        copy_with_symlinks(src_file, target_lib_dir)
        copied_lib_count += 1

    print(f"[OK] 已递归收集并部署 Qt/ICU 共享库 (共 {copied_lib_count} 个核心依赖库，无冗余库)")

    # 4. 生成 / 刷新 qt.conf（直接放置在安装根目录，与 CarrierVision 并在同一级）
    qt_conf_path = install_path / "qt.conf"
    qt_conf_content = """[Paths]
Prefix = .
Libraries = lib
Plugins = plugins
Qml2Imports = qml
"""
    qt_conf_path.write_text(qt_conf_content, encoding="utf-8")
    print(f"[OK] 已生成运行时配置: {qt_conf_path}")

    # 5. 安装便携启动脚本 CarrierVision.sh 与桌面快捷方式
    if source_dir:
        src_scripts = Path(source_dir) / "scripts"
        sh_script = src_scripts / "CarrierVision.sh"
        if sh_script.exists():
            dst_sh = install_path / "CarrierVision.sh"
            shutil.copy2(sh_script, dst_sh)
            os.chmod(dst_sh, 0o755)
            print(f"[OK] 已部署便携启动脚本: {dst_sh}")

        desktop_file = src_scripts / "CarrierVision.desktop"
        if desktop_file.exists():
            dst_desktop = install_path / "CarrierVision.desktop"
            shutil.copy2(desktop_file, dst_desktop)
            os.chmod(dst_desktop, 0o755)
            print(f"[OK] 已部署桌面快捷方式: {dst_desktop}")

        readme_file = src_scripts / "README.txt"
        if readme_file.exists():
            dst_readme = install_path / "README.txt"
            shutil.copy2(readme_file, dst_readme)
            print(f"[OK] 已部署使用说明: {dst_readme}")

        src_icon = Path(source_dir) / "icons" / "logo_agc.svg"
        if src_icon.exists():
            dst_icon = install_path / "CarrierVision.svg"
            shutil.copy2(src_icon, dst_icon)
            print(f"[OK] 已部署程序图标: {dst_icon}")

    # 6. 对 Release 可执行程序执行 strip，剥离非必要调试符号以节省体积
    try:
        subprocess.run(["strip", "--strip-unneeded", str(app_bin)], check=False)
        print(f"[OK] 已对可执行文件执行符号剥离优化 (strip)")
    except Exception:
        pass

    os.chmod(app_bin, 0o755)

    print("=" * 60)
    print("精简部署完成！已剔除全部系统自带库及非必要模块。")
    print("=" * 60)
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Deploy Qt dependencies for CarrierVision")
    parser.add_argument("--install-dir", required=True, help="Installation prefix directory")
    parser.add_argument("--qt-dir", required=True, help="Qt installation root directory")
    parser.add_argument("--build-dir", default="", help="Build directory")
    parser.add_argument("--source-dir", default="", help="Source directory")

    args = parser.parse_args()
    ret = deploy(args.install_dir, args.qt_dir, args.build_dir, args.source_dir)
    sys.exit(ret)
