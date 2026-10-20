# 优化方案（2026-10-20）

## 背景

当前版本的网络层防护已较完善：FTP/TCP 缓冲与连接数受限，密码加盐哈希，SQLite 使用 WAL。剩余问题主要集中在三方面：

1. **主线程负载**：统计查询、清理、FTP 上传处理（含图片解码）都在 GUI 线程执行。`RELEASE_FIXES.md` 中已记录“图片解码与业务数据库操作仍在控制器线程”，数据量增长后会直接表现为界面卡顿。
2. **代码结构**：`AppController.cpp` 3100 余行，承担几乎所有职责，部分查询逻辑重复。
3. **工程化**：CI 只编译不跑测试，部分测试未注册。

本方案按“先消除现场风险，再重构，最后完善工程化”的顺序分四个阶段，每个阶段可独立合入、独立验收。

## 执行进度

| 阶段 | 状态 | 说明 |
| :--- | :--- | :--- |
| 0 测试兜底 | 已完成 | CI 工作流已修改，尚未在 GitHub 上实际运行 |
| 1 消除主线程阻塞 | 已完成 | 1.4 压测结果见附录 A |
| 2 查询性能 | 已完成（按实测调整） | 2.2～2.4 经实测取消，原因见附录 A |
| 3 代码结构重构 | C++ 部分完成 | 见附录 B；QML 拆分（3.3）暂缓 |
| 4 安全与工程细节 | 已完成 | 4.1 按方案 B 实施，见附录 B |

---

## 阶段 0：测试兜底（先做，0.5 天）

后续改动涉及线程模型和大范围重构，必须先让现有测试在 CI 上生效。

| 编号 | 内容 | 位置 |
| :--- | :--- | :--- |
| 0.1 | CI 构建后执行 `ctest --output-on-failure` | `.github/workflows/build-windows.yml` |
| 0.2 | 新增 Linux 构建 + 测试任务（Qt 6.11、GCC） | `.github/workflows/` |
| 0.3 | `CarrierVisionQmlSmoke` 补 `add_test`，失败时返回非零退出码 | `CMakeLists.txt`、`tests/QmlDeploymentSmoke.cpp` |

**验收**：PR 上能看到 `CarrierVisionBoundaryTests`、`CarrierVisionReleaseTests`、`CarrierVisionQmlSmoke` 三项结果；人为制造一条失败断言时 CI 变红。

---

## 阶段 1：消除主线程阻塞（优先级最高，3～4 天）

### 1.1 统计/监控查询异步化

以下 `Q_INVOKABLE` 函数由 QML 同步调用，使用主线程连接 `QSqlDatabase::database()`：

| 函数 | 位置 | 调用方 |
| :--- | :--- | :--- |
| `driveWheelRackStats` / `walkingWheelRackStats` | `AppController.cpp:693` / `:749` | 统计页 |
| `rackWheelMonitorStatus` / `rackPhotoCounts` | `:794` / `:839` | 监控页（定时刷新） |
| `homepageCurrentDetection` | `:876` | 首页 |
| `latestRackWheelMonitorImage` | `:1033` | 监控页 |
| `wheelRackResultStats` / `rackWheelResultStats` | `:1070` / `:1117` | 统计页、报警统计 |
| `weeklyReports` | `:675` | 周报页 |
| `queryLogs` / `getLogStats` | `:3032` / `:3057` | 日志页 |

**做法**：沿用 `searchPaged` 已验证的模式——

- 在 `m_searchPool`（或新建 `m_statsPool`，最大线程数 1～2）中执行，使用 `getThreadDatabase()` 获取线程专属连接；
- 每类请求维护一个 generation 计数，结果返回时丢弃过时请求；
- 新增 `requestXxx(...)` 接口返回 requestId，结果通过 `xxxReady(requestId, result)` 信号回到 QML；
- 保留旧同步接口一个版本并标记废弃，QML 逐页迁移，避免一次性大改。

**迁移顺序**：监控页（定时刷新，影响最大）→ 首页 → 统计页 → 报警统计 → 周报/日志。

### 1.2 归档清理移出主线程

`triggerCleanup`（`AppController.cpp:268`）在主线程调用 `ArchiveMaintenance::cleanup`，同时执行数据库删除与文件删除。

- 改为在后台线程使用独立数据库连接执行，完成后回主线程更新状态与续批（替代当前 `QTimer::singleShot(50, ...)` 的续批方式）；
- 保持现有“先提交删除队列、再删文件、失败保留队列”的语义不变，`ReleaseBoundaryTests` 中的清理用例必须全部通过。

### 1.3 FTP 服务独立线程

`FtpServer.cpp:872` 将每个连接 `moveToThread(this->thread())`，即全部运行在主线程；上传落盘、同名内容比对、`ImageIngest` 图片解码都会占用 GUI 事件循环。

- 将 `FtpServer` 整体移入独立 `QThread`，`uploadHandler` 回调中的数据库写入改用该线程的专属连接；
- 与 `AppController` 之间只通过排队信号通信（`imageStored`、`logMessage`、`clientCountChanged`）；
- 账户/根目录变更通过 `QMetaObject::invokeMethod(..., Qt::QueuedConnection)` 下发，保留“账户变更立即关闭旧凭据会话”行为；
- `TcpDataReceiver` 负载较轻，本阶段暂不迁移，视 1.4 压测结果再定。

### 1.4 验收

- 构造 50 万条 `record`、5 万条 `alertrecord` 的测试库；
- 监控页、统计页切换与定时刷新期间，主线程单次事件处理阻塞 < 50 ms（可用 `QElapsedTimer` 埋点或 `QT_LOGGING_RULES` 观察）；
- 12 路相机并发上传 5 MB 图片时，界面拖动、翻页无明显卡顿；
- 全部现有测试通过，ASan/UBSan 构建无报告。

---

## 阶段 2：查询性能（1～2 天）

| 编号 | 问题 | 方案 |
| :--- | :--- | :--- |
| 2.1 | 搜索结果逐行 `resolveImagePath` + `QFile::exists`，图片在机械盘/网络盘时很慢 | 列表只保存相对路径，存在性检查延迟到 delegate 可见时执行（或在 `ImageListModel::data` 首次访问时缓存结果） |
| 2.2 | `LIMIT … OFFSET` 深分页随页数线性变慢 | 改为基于 `(createtime, rowid)` 的游标分页；保留“跳转到第 N 页”时回退到 OFFSET |
| 2.3 | `imagename LIKE '%x%'` 无法使用 `idx_record_image` | 默认按前缀匹配 `LIKE 'x%'`，界面提供“包含”选项时才走全扫描 |
| 2.4 | `alertrecord` 仅有时间索引，按载具筛选需全表扫 | 新增 `idx_alertrecord_carrier_time ON alertrecord(carrier_id, createtime DESC)`，在 `DbSchema.cpp` 中按现有 `CREATE INDEX IF NOT EXISTS` 方式添加 |
| 2.5 | 统计查询未验证执行计划 | 对 1.1 列出的每条 SQL 执行 `EXPLAIN QUERY PLAN`，确认无 `SCAN record`，结果记入本文档附录 |

**验收**：在阶段 1 的测试库上，搜索第 1 页与第 500 页耗时差距 < 2 倍；报警按载具筛选 < 100 ms。

---

## 阶段 3：代码结构重构（3～5 天，可分多次合入）

### 3.1 拆分 `AppController`

按职责拆成独立类，`AppController` 只保留对 QML 暴露的属性与转发：

| 新模块 | 承接内容 |
| :--- | :--- |
| `SearchService` | `search`、`searchPaged`、`alertSearchPaged`、最新架轮图片分页 |
| `StatsService` | 1.1 中所有统计/监控查询、`gearSumQuery`、周报列表 |
| `SettingsStore` | 系统配置、FTP 账户、槽位映射、设置密码、清理参数 |
| `IngestCoordinator` | FTP/TCP 时序匹配缓存、`RackSession` 会话管理、超时收尾、待处理图片恢复 |

每拆出一个模块即补对应单元测试（`SearchService`、`StatsService` 可直接用内存 SQLite 测试，无需 QML）。

### 3.2 消除重复

- `search()`（`AppController.cpp:1507` 起）与 `searchPaged()` 的 WHERE 拼接、参数绑定、行解析几乎相同，抽出 `RecordFilter` 结构及 `buildWhere()` / `bindValues()` / `readImageItem()` 三个函数；
- 搜索和报警搜索中的轮号解析（`DRIVE` / `WALK` / 逗号列表 / 单个数字）合并为一个工具函数，放入 `AgcUtils`。

### 3.3 QML 大文件拆分

| 文件 | 行数 | 方向 |
| :--- | ---: | :--- |
| `qml/home/DesignShowCore.qml` | 2149 | 拆出标签层、相机控制、模型加载三个组件；`:675-677` 三个一次性 Timer 改为在模型加载完成信号后刷新标签位置 |
| `qml/settings/SystemConfigPage.qml` | 1394 | 按 FTP / TCP / 清理 / 安全 分卡片组件 |
| `qml/HeadBar.qml` | 1272 | 导航、窗口控制、状态指示拆分 |

**验收**：行为不变（手工回归各页面 + 现有测试）；`AppController.cpp` < 1000 行。

---

## 阶段 4：安全与工程细节（1 天）

| 编号 | 内容 | 位置 |
| :--- | :--- | :--- |
| 4.1 | 设置密码重置后默认 `123456`，增加“首次使用须修改”标记，进入设置页时强制修改 | `AppController.cpp:513` |
| 4.2 | FTP 存量明文密码兼容分支：登录成功后自动升级为 `sha256$` 格式并落库，观察一个版本后移除明文分支 | `FtpServer.cpp:217` |
| 4.3 | spdlog、nlohmann/json 移至 `third_party/` 或改用 `FetchContent` 固定版本，`src/` 只保留业务代码 | `third_party/spdlog/`、`third_party/nlohmann/` |
| 4.4 | 清理 `CMakeLists.txt` 中已无意义的 `ftpserver_qt` 兼容段 | `CMakeLists.txt` |

---

## 排期与风险

| 阶段 | 工作量 | 依赖 | 主要风险 |
| :--- | :--- | :--- | :--- |
| 0 测试兜底 | 0.5 天 | 无 | Windows runner 缺少 Qt Test 组件 |
| 1 主线程 | 3～4 天 | 阶段 0 | 多线程访问 SQLite 的锁竞争；FTP 迁线程后信号时序变化影响 FTP/TCP 匹配 |
| 2 查询性能 | 1～2 天 | 阶段 1（异步后才能看清真实耗时） | 游标分页与“跳页”交互的兼容 |
| 3 重构 | 3～5 天 | 阶段 0、1 | 回归范围大，须分模块合入 |
| 4 细节 | 1 天 | 无 | 密码升级需兼容旧数据库 |

**风险控制**：

- 阶段 1 的每项改动都要跑 ASan/TSan 构建，重点关注 FTP/TCP 异步匹配缓存的并发访问；
- 数据库连接必须一线程一连接，禁止跨线程传递 `QSqlDatabase`/`QSqlQuery`；
- 所有改动只在临时目录与测试库上验证，不对现场生产数据库执行迁移；新增索引使用 `IF NOT EXISTS`，可在线追加。

## 现场验收（上线前）

沿用 `RELEASE_FIXES.md` 中尚未完成的项目，并补充：

- 真实 12 路相机峰值并发上传 + 连续 72 小时运行，记录内存与主线程延迟；
- 数据库达到半年数据量时，各页面打开与刷新耗时；
- 清理任务在业务高峰期执行时，对上传与界面无可感知影响。

---

## 附录 A：实测数据（阶段 1.4 / 2.5）

测试库：50 万条 `record`（50 架 × 16 轮，时间均匀分布在 180 天内，NG 率约 3%），由当前 `DBSchema` 建表（含触发器）后批量写入。生产库从未执行 `ANALYZE`，因此主要按“无统计信息”测量，并在执行 `ANALYZE` 后复测执行计划。耗时为 3 次取最小值，单线程 Python `sqlite3`，仅作量级参考。

### 已移至工作线程的查询（不再阻塞界面）

| 查询 | 耗时 | 执行计划 |
| :--- | ---: | :--- |
| 搜索 COUNT，1 天 / 30 天 / 180 天 | 0.2 / 8.6 / 52 ms | `idx_record_createtime` 范围扫描 |
| 搜索第 1 页（任意范围） | < 0.1 ms | `idx_record_createtime` |
| 搜索 OFFSET 10 万 / 45 万 | 11 / 47 ms | `idx_record_createtime` |
| 搜索 30 天 + 文件名包含匹配 / 180 天 COUNT | 6.5 / 81 ms | 时间索引后逐行匹配 |
| 驱动轮架号统计 30 天 / 180 天 | 14 / 95 ms | 时间索引 + 临时 B 树分组 |
| 轮号-架号统计 30 天 | 8 ms | 时间索引 |
| 架号-轮号统计 30 天 | 0.4 ms | `idx_record_carrier_wheel` |
| 监控状态 / 各架照片数 | 0.3 / 22 ms | 状态缓存表 / 覆盖索引 |
| 首页：当日合格率 / 架累计 | 0.7 / 10 ms | `idx_record_carrier_wheel` |

### 仍在主线程同步执行的查询

| 查询 | 耗时 |
| :--- | ---: |
| 校准页总页数 `latestRackWheelTotalPages` | 10 ms |
| 校准页单轮翻页（共 16 次） | 0.14 ms / 次 |
| 最新单轮图片 `latestRackWheelMonitorImage` | 0.01 ms |
| TCP 16 轮批次写入（含触发器） | 0.3 ms |

均低于 50 ms 的界面阻塞指标。

### 已修复的慢查询

“取最新架号”原写法 `ORDER BY createtime DESC, rowid DESC LIMIT 1`：`rowid` 平局条件使规划器无法利用时间索引，改为整表排序。

| 查询 | 修改前 | 修改后 |
| :--- | ---: | ---: |
| 首页最新架号（`StatsService::homepageCurrentDetection`） | 45 ms | 0.04 ms |
| 校准页最新架号（`latestRackWheelImageRack`，主线程） | 88 ms（有统计信息时改写不当可达 559 ms） | 0.04 ms |

改为两步：子查询经时间索引取最新时间，外层在同一秒内按 `rowid DESC` 取最后写入的记录，语义与原写法一致（含同秒平局）。子查询的过滤列加一元 `+` 号，否则执行 `ANALYZE` 后规划器会改用 `idx_record_carrier_wheel` 的 skip-scan，反而更慢。

### 按实测取消的计划项

- **2.2 游标分页**：OFFSET 45 万条仅 47 ms，且已在工作线程执行，收益不足以抵消“跳页”交互的复杂度。
- **2.3 文件名前缀匹配**：搜索总带时间范围，包含匹配最坏 81 ms；改为前缀匹配会改变操作员的搜索习惯，不做。
- **2.4 报警表载具索引**：`alertrecord` 有 `UNIQUE(carrier_id, wheel_id)`，SQLite 已自动建立以 `carrier_id` 开头的索引，且表最多 800 行。
- **2.1 图片存在性懒加载**：搜索已在工作线程执行；改为懒加载会改变 QML 中缺图占位的行为。改为去掉重复的 `QFile::exists`（`resolveImagePath` 只返回已确认存在的路径），每行磁盘访问减半。

---

## 附录 B：阶段 3、4 执行记录

### 3.1 / 3.2 拆分与去重

`AppController.cpp` 由 3103 行降至约 1800 行，新增模块均有单元测试：

| 模块 | 内容 |
| :--- | :--- |
| `StatsService` | 统计与监控查询，供同步接口与 `requestStats` 异步接口共用 |
| `SearchService` | 记录过滤条件、分页查询、图片路径解析；`searchPaged` 与 `alertSearchPaged` 共用 |
| `SettingsStore` | FTP 账户/目录/端口/槽位映射、设置密码、标准轮距 |
| `IngestCoordinator` | FTP 图像待关联缓存、TCP 批次到 12 宫格卡片的映射 |
| `FtpIngestService` | FTP 服务、上传提交与恢复扫描（独立线程） |

删除的死代码：无调用方的同步 `search()`；启动时加载却从不读取的 JSON 批次索引（`m_records` 及其读写函数，启动时最多读 50 MB 文件）；JSON 槽位映射函数；从未启用的离站/超时结案会话（`RackSession`、`m_safetyTimeoutTimer` 等）；未使用的 `onTcpBatchReceived` 槽与 `gearSumQuery` 中构建后未使用的 JSON 数组。

修复：首页“当前架号”原从显示文本 `载具 #3 (轮数=2)` 中解析数字，始终失败并退回“库中最新架号”；改为直接记录当前批次的载具号。

### 3.3 QML 拆分：暂缓

`DesignShowCore.qml` 中三个一次性 Timer 用于等待 View3D 首帧后刷新标签投影坐标，替换方案需在真实 3D 画面下验证；offscreen 环境下 Qt Quick 3D 不渲染，无法验证。几个大 QML 文件的拆分同理，待可目视回归时进行。

### 4.1 重置后强制修改密码：待定

发现更优先的问题：标题栏命令面板中的“重置安全管理密码为默认 (123456)”无需任何验证即可执行，任何人都可借此进入设置页，绕过设置密码。同一面板中的“恢复相机通道映射”“立即执行历史数据清理”也无需验证。该入口可能是有意保留的忘记密码后门，处理方式需产品确认：

- 方案 A：从命令面板移除重置密码，忘记密码时由维护人员处理；
- 方案 B：保留入口，但执行前要求验证当前设置密码（或独立的维护口令）；
- 方案 C：保留现状，重置后在下次进入设置页时强制修改密码（即原 4.1）。

**决定：方案 B（2026-10-20）。** 实现：

- 命令面板的“重置安全管理密码”改为弹出口令确认框（新组件 `qml/common/PasswordConfirmDialog.qml`），输入当前设置密码或维护口令验证通过后才重置；后端接口 `resetSettingsPasswordAuthorized` 再次校验，并记录授权方式。
- 维护口令默认未设置（不设公开默认值，避免形成新的后门），在设置页“维护口令”一栏设置，需填写当前设置密码；至少 6 位、不得与设置密码相同，仅接受哈希存储。未设置维护口令时，忘记设置密码将无法自助重置，需维护人员处理数据库。
- 设置页内的“重置初始”按钮位于已验证的设置页中，保持不变。
- 命令面板中的“恢复相机通道映射”“立即执行历史数据清理”同样改为先验证设置密码（不接受维护口令：维护口令只用于忘记密码时的重置）。

**修复：** 原“进入设置”“退出系统”两个密码弹窗通过 `Dialog.accept()` 提交；Qt 在发出 `accepted` 后总会关闭弹窗（已在 Qt 6.11 实测），因此输错密码时弹窗直接关闭，“密码错误，请重新输入”提示无法显示。现在 `MainFrame.qml` 中全部四个口令弹窗（进入设置、退出、重置密码、维护命令）都使用 `PasswordConfirmDialog`，以显式 `submit()` 提交，验证失败时保持打开并显示错误。组件行为已用替身环境实际驱动验证（输错保持打开、输对关闭并回调一次、重开清空、未提供验证函数一律拒绝）。

### 4.2 明文密码

所有写入路径均已哈希，历史 JSON 迁移也会哈希，明文只可能来自手工改库。改为：`SettingsStore::loadFtpSettings` 加载时把明文 FTP 密码转为哈希并写回；设置密码在校验成功时就地升级。`FtpServer` 内的明文比较分支保留（仅测试直接构造明文账户时使用，程序路径不会再传入明文）。

### 4.3 / 4.4

spdlog 1.16.0（内置 fmt 12.0.0）与 nlohmann/json 3.12.0 移至 `third_party/`，以 SYSTEM 头文件目录引入，版本记录在 `third_party/README.md`；删除 `CMakeLists.txt` 中已无意义的 `ftpserver_qt` 兼容段。

