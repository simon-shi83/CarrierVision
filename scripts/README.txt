================================================================================
CarrierVision 工业巡检与视觉分析系统 - 独立便携发布包使用指南
================================================================================

本发布包为完全自包含的独立便携版本（Standalone Portable Package）。
已内置程序运行所需的 Qt 6 核心运行时、ICU 字符集库、QML 引擎模块以及平台与数据库插件。
直接解压并拷贝至任何兼容架构的 Linux x86_64 电脑即可直接运行，无需在目标系统上预装 Qt。

一、目录结构说明
--------------------------------------------------------------------------------
CarrierVision/
├── CarrierVision             # 主程序二进制（RPATH 已配置为当前目录下的 lib）
├── CarrierVision.sh          # 便携式启动脚本（推荐，自动注入环境变量以提高兼容性）
├── CarrierVision.desktop     # Linux 桌面快捷方式配置文件
├── CarrierVision.svg         # 应用程序矢量图标
├── qt.conf                   # Qt 运行时路径重定向配置（将前缀锁定为当前目录）
├── README.txt                # 本使用说明文件
├── lib/                      # Qt 6 核心共享库及 ICU 字符集支持库
├── plugins/                  # 平台显示(XCB/Wayland)、图片解码、SQLite 驱动、网络 TLS 等插件
└── qml/                      # 经深度精简的 Qt 官方 QML 核心运行时组件

注：CarrierVision 自身的所有业务 QML 界面源码、资源与图标已在构建期完全内联编译进
可执行文件内部，无需在外部散落部署源码文件。

二、启动运行方式
--------------------------------------------------------------------------------
方式 1：终端直接运行（最简便）
   打开终端，进入本程序目录后执行：
   ./CarrierVision

方式 2：使用便携启动脚本（最稳妥，推荐）
   启动脚本会自动检测当前物理路径并绑定专用运行库与环境变量：
   ./CarrierVision.sh

方式 3：图形桌面双击运行
   在系统文件管理器中直接双击 CarrierVision 或 CarrierVision.sh 即可启动。

方式 4：安装为桌面应用快捷方式（可选）
   若希望在操作系统的应用菜单或桌面上显示图标，可在本目录下执行：
   sed -i "s|Exec=.*|Exec=$(pwd)/CarrierVision.sh|" CarrierVision.desktop
   sed -i "s|Icon=.*|Icon=$(pwd)/CarrierVision.svg|" CarrierVision.desktop
   cp CarrierVision.desktop ~/.local/share/applications/

三、系统环境与依赖要求
--------------------------------------------------------------------------------
1. 操作系统：Linux x86_64（内核 4.15+，glibc 2.31+）
   已在 Ubuntu 20.04/22.04/24.04、Debian 11/12、CentOS 8/9、Fedora、openSUSE 等系统验证。
2. 显示环境：X11 或 Wayland 图形桌面环境。
3. 极简版 Linux 依赖补充：
   普通桌面版系统无需安装任何额外依赖。若在最小化安装或服务器版 Linux 运行，
   系统可能未预装基础的 X11/OpenGL 支持库，可执行以下命令快速安装：
   - Debian / Ubuntu 系统：
     sudo apt-get update
     sudo apt-get install -y libxcb-cursor0 libxkbcommon-x11-0 libgl1
   - RHEL / CentOS / Fedora 系统：
     sudo dnf install -y xcb-util-cursor libxkbcommon-x11 mesa-libGL

四、常见问题排查 (FAQ)
--------------------------------------------------------------------------------
1. 提示权限不足 (Permission denied)？
   从网络传输或解压时若未保留执行权限，请在终端中赋予执行权限：
   chmod +x CarrierVision CarrierVision.sh

2. 提示“程序已在运行”？
   CarrierVision 具备单实例防重入保护机制。
   - 若系统后台已有正在运行的实例，请先关闭已存在的程序。
   - 若程序曾异常终止导致共享内存残留，再次启动时程序会自动尝试清理并启动；
     如仍提示，可注销重新登录当前 Linux 用户会话。

3. Wayland 与 X11 显示切换？
   程序默认优先适配 X11(xcb)，并支持 Wayland。如需在特定桌面环境下强制指定：
   - 强制使用 X11 模式：
     QT_QPA_PLATFORM=xcb ./CarrierVision.sh
   - 强制使用 Wayland 模式：
     QT_QPA_PLATFORM=wayland ./CarrierVision.sh

4. 本地数据与日志存储位置？
   程序会在当前工作目录或程序所在目录下生成运行日志与数据库配置：
   - 应用程序运行日志：AppLogger 输出及 startup_log.txt
   - 数据存储目录：data/ (包含架轮标准配置及 SQLite 数据存储)
================================================================================
