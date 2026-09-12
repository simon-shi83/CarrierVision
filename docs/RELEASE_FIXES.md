# 发布前修复记录（2026-09-05）

## 本轮变更

- FTP：空闲超时/主动关闭统一回收连接计数；控制输出和数据读取缓冲受限；PORT/EPRT、LIST、RETR 改为异步；空闲与整体传输超时；ABOR 清除临时上传；数据来源验证兼容 IPv4-mapped IPv6；PASV 使用控制连接的本地接口；账户变更立即关闭旧凭据会话。
- 上传：新 `ImageIngest` 模块严格校验图片类型、大小与解码结果；同名不同内容拒绝覆盖，同内容重传幂等；上传失败返回 451；`.cv-pending` 恢复记录在文件提交前落盘，数据库失败或进程重启后可重试。
- 入库：同图多轮记录与标准间距记录使用同一事务；只有提交成功才更新监控；添加图片名/轮号去重查询索引，不删除既有重复历史记录。
- 清理：新 `ArchiveMaintenance` 模块只删除数据库引用且已过期的图片，不按父目录时间递归删除；时间比较兼容 ISO/空格分隔；提交删除队列后删除图片，失败时保留队列；重试前检查新引用与待处理标记。旧隔离目录只恢复，不直接清空。
- 报警：事务替换既有触发器，迟到旧 NG 不再覆盖更新的 OK；监控同秒记录使用 rowid 决胜。
- 日志：流式两遍读取，只保留一页；分页参数限制与 64 位偏移；数字分卷排序；界面通过单工作线程异步查询，合并未完成请求并丢弃过时结果。
- 配置：FTP 根目录/端口切换失败恢复旧配置，验证目录可写；账户和槽位配置保存失败回滚内存；限制 JSON 数值转换和账户数量；主数据库初始化失败停止启动，避免继续接受上传。
- 部署：补充 QtQuick/Templates、Controls/impl、TIFF/WebP 插件；必需 QML 模块缺失或 ELF 依赖解析失败时中止部署。
- 冗余：删除不可达的旧架轮查询、手工拼接 COUNT 回退和启动调试搜索。

## 已执行验证

环境：Linux x86_64、Qt 6.11.2、GCC 11、Debug。

- `cmake --build build/Debug --target CarrierVision CarrierVisionBoundaryTests CarrierVisionReleaseTests CarrierVisionQmlSmoke -j 2` 通过。
- `ctest --test-dir build/Debug --output-on-failure`：2/2 测试套件通过，16 个业务测试场景通过（QtTest 另计每套 init/cleanup）。
- 独立 `/tmp/carriervision-sanitized` 构建，启用 `-fsanitize=address,undefined -fno-omit-frame-pointer`；两组测试通过，没有 sanitizer 报告。
- `cmake --install build/Debug --prefix /tmp/carriervision-fixed-package` 通过。
- `CarrierVisionQmlSmoke` 将 QML 导入路径限定为安装目录与 Qt 资源路径，使用安装目录的动态库和插件；QtQuick、Controls、Layouts、Effects、Quick3D、AssetUtils 与 Fusion Button 创建通过。

网络测试仅绑定回环随机端口，数据测试只使用临时目录与内存 SQLite；没有对工作目录中的生产数据库执行迁移或清理。临时安装目录来自 Debug 构建，是验证产物，不是正式 Release 发布包。

## 兼容性与现场验收

图片的载具、相机、轮位、检测结果和测量数据由 TCP JSON 提供。FTP 文件名仅用于唯一标识和与 TCP `imageName` 关联，不解析文件名中的业务元数据。

上线前仍需：正式 Release 构建及目标 Windows/Linux 机器验收、真实相机上传/重试联调、峰值并发和长时间运行、真实磁盘满/断电测试。图片解码与业务数据库操作仍在控制器线程，本轮消除了网络同步等待，但尚未证明峰值负载下的界面延迟指标。

清理只处理可安全识别且由数据库引用的过期图片。未入库旧文件、历史孤儿数据、旧隔离目录冲突不会被擅自删除，需要核查后单独处理。
