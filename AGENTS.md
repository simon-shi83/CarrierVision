# CarrierVision 开发准则

本文件适用于整个仓库。修改代码前先读 `README.md`（通信协议、FTP 规范、运行配置）和本文件。

## 1. 定位

- CarrierVision 是载具轮位点检的服务端上位机（Qt 6 / C++17 / QML），现场运行在 Windows 工控机上。
- 它只接收和展示数据：图像由客户端经内置 FTP 上传，测量结果由客户端经 TCP（NDJSON）推送。它不连接相机或 PLC，不做检测运算。
- 界面、统计和报警里的测量值、判定和图像只能来自客户端上报并入库的数据。禁止在 QML、C++ 或配置中硬编码、伪造、随机生成或推导检测数据；联调用的模拟数据只能由外部脚本经 FTP/TCP 发送。

## 2. 协议与入库

- TCP 报文格式、字段范围和错误应答以 `README.md` 为准；改协议必须同步更新 README 与 `tests/` 中的边界测试。
- 图像与测量记录只按文件名关联（`imageName` 与 FTP 文件名一致，不区分大小写）。两者到达顺序不限：图片先到进入待关联缓存（`IngestCoordinator::PendingImageCache`），记录先到则在图片到达时回填 `image_path`。改动关联逻辑时两种顺序都要验证。
- `requestId` 可选，只用于重发去重；不要把它改成必填。
- 一个载具分两次触发（每次 6 个相机）。首页 12 宫格对同一载具的后续批次只刷新本批相机，不得清掉前一批的卡片。
- 数据库结构变更写在 `DbSchema`，必须兼容已有现场库（加列、迁移旧值），不得要求现场删库。

## 3. 路径

- 所有相对路径一律按程序所在目录解析（`AgcUtils::resolveAppPath`），不得依赖启动时的工作目录。
- 程序目录内的路径保存为相对路径（`AgcUtils::toAppRelativePath`），安装目录整体搬迁后配置仍然有效。不要把规范化后的绝对路径写回数据库。
- 图像只有一个目录：FTP 上传目录就是图像存储目录（数据库键 `ftp/rootDirectory`，默认 `images`）。不要再引入第二个图像根目录。
- 程序目录布局：`data/`（数据库与备份）、`images/`、`logs/`、`fonts/`。FTP 日志已并入主日志，不要再单独写日志文件。升级只替换程序文件，不得覆盖或清理这些数据。

## 4. 线程与日志

- 主线程只做界面与轻量调度。FTP 服务在独立线程（`m_ftpThread`），统计、查询、维护和日志检索在各自的 `QThreadPool` 中用 `QtConcurrent::run` 执行。新的耗时操作照此处理，不得阻塞主事件循环。
- 访问主数据库连接要持有 `m_dbMutex`；后台线程通过 `getThreadDatabase()` 使用按线程区分的独立连接。
- C++ 用 `LOG_INFO` / `LOG_WARN` / `LOG_ERROR`（`common/AppLogger.h`）写日志，内容用中文，带上关键标识（载具号、文件名、端口）。日志每秒落盘，现场可直接查看 `logs/carrier_YYYY-MM-DD.log`。
- 关键路径要留下可核对的统计日志，例如 TCP 入库时记录"已关联图片的轮 / 待图片到达的轮"，联调时据此判断关联是否完整。

## 5. QML 视觉规范

所有取值来自 `qml/Theme.qml`，与 VisionStudio 的 AppTheme 是同一套体系。亮色和暗色两套必须同时成立。

**字体**

- 界面字体只用 `assets/fonts` 中随程序分发的字体：正文 `Theme.fontSans`（思源黑体 SC），等宽 `Theme.fontMono`（JetBrains Mono，缺中文时回退到思源黑体）。字体由 `main.cpp` 从程序旁的 `fonts/` 加载，不要引用系统字体名。
- 等宽字体只用于文件名、路径、日志正文和报文。普通数字（计数、百分比、时间、测量值）用 `fontSans` 加 `font.features: Theme.fontFeaturesTabular`。
- 字号只用 `Theme.fontDisplay`、`fontTitle`、`fontBody`、`fontCaption`、`fontMicro`，禁止写数字字号。`fontMicro` 只用于数字、单位和徽标，不用于中文句子。
- 字重只有三档：`Theme.fontRegular`、`fontMedium`、`fontBold`。页面大标题用 Bold，分区标题、按钮和强调项用 Medium，其余用 Regular。禁止写 `font.bold`。
- 文字颜色只用 `Theme.text`、`textSoft`、`muted`、`disabled`；强调色或状态色实底上的文字用 `textOnAccent`。
- 界面文字禁止使用 Emoji 和符号图标，图标一律用 `AppIcon` 加 `assets/icons/` 下的单色 SVG（新增图标要登记到 `CMakeLists.txt` 的资源列表）。

**颜色**

- 禁止在 QML 中硬编码颜色。需要新颜色时先在 `Theme.qml` 增加令牌，同时给出亮色和暗色两个值。
- 强调色 `accent` 只用于当前选中项、页面主操作和焦点框。悬停用中性色（`hover`、`pressed`、`borderStrong`、`text`），不用强调色；标题前的竖条、表头和普通标签也不用强调色。
- 状态色 `ok`、`warn`、`danger` 只表达状态，不用于标题、普通标签和装饰。`danger` 只用于 NG、故障报警和不可撤销操作的确认；关闭按钮、普通删除入口的悬停不用红色。
- 轮类别色 `driveWheel`、`walkWheel` 只用于区分驱动轮和走行轮；三维视图中的相机标记用 `cameraMarker`（紫色），不要用红色，以免和 NG 混淆。
- 表面层级用 `window` → `surface` → `surfaceAlt` → `surfaceFloating`，层级靠明度和留白表达，不要层层描边。表格斑马纹用 `subtleFill`，压在图像上的标签用 `overlayFill`，图像遮罩用 `imageScrim`。
- 例外：`qml/home/DesignShowCore.qml` 的三维场景可以独立切换明暗，场景底色、灯光和材质集中定义在其 `styleThemes` 中；其中的界面色（文字、强调、卡片、分割线）必须与 `Theme` 同值。新增的场景颜色也放进 `styleThemes`，不要散落在场景代码里。

**布局**

- 圆角用 `Theme.radiusMicro`、`radiusSmall`、`radiusMedium`、`radiusLarge`、`radiusPill`；间距优先用 `Theme.space1` 到 `space6`；动画时长用 `animFast`、`animNormal`、`animSlow`。

## 6. 构建与验证

- 构建并行度固定为 `-j8`：`cmake --build build/Debug -j8`。同一时间只运行一个构建，`ctest` 不与构建并行。
- 修改后至少执行 `cmake --build build/Debug -j8` 和 `ctest --test-dir build/Debug --output-on-failure`；无法执行时说明原因。
- 界面改动要截图确认亮色和暗色两套效果。设置 `CV_UI_SNAPSHOT_DIR=<目录>` 启动程序会依次截取每个导航页后退出，可选 `CV_UI_SNAPSHOT_THEME=light|dark`、`CV_UI_SNAPSHOT_SIZE`、`CV_UI_SNAPSHOT_DELAY_MS`、`CV_UI_SNAPSHOT_SETTLE_MS`。截图模式不参与单实例检查，请把程序拷到独立目录运行，避免改动开发库。`QT_QPA_PLATFORM=offscreen` 下没有 GPU，三维视图和 `AppIcon`（依赖 MultiEffect）不会显示，需要看这两类内容时在真实显示环境下运行。
- Windows 安装包由 GitHub Actions（`.github/workflows/build-windows.yml`）构建。推送 `main` 自动触发；其他分支用 `gh workflow run build-windows.yml --ref <分支>` 手动触发。CI 在 Windows 上跑全部测试，路径相关的测试要考虑盘符。
- 新代码不得引入编译告警（含 qmlcachegen 的 QML 告警）。

## 7. 现场部署注意

- Windows 防火墙按程序路径放行。安装目录变更后，首次启动弹出的提示若只勾选"专用网络"，而现场网络是"公用"，会生成"公用 = 阻止"的规则，导致客户端连不上 9000/21 端口。排查连通性时先检查 `Get-NetFirewallApplicationFilter` 中当前 exe 路径的规则。
- 升级时先备份旧程序目录，再解压新包覆盖；`data/`、`images/`、`logs/` 保持不动。

## 8. 提交

- 提交信息用中文，格式 `类型(范围): 摘要`，类型取 `feat`、`fix`、`refactor`、`test`、`docs`、`perf`、`chore`。
- 不要直接在 `main` 上开发；功能分支验证通过（含 Windows CI）后再合并。
