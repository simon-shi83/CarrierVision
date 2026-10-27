# CarrierVision 载具视觉检测系统

CarrierVision 是专为工业自动化生产线设计的载具轮位视觉检测上位机系统，基于 Qt 6 (C++ / QML) 开发。通过内置的 FTP 服务与 TCP 数据服务，接收各工位相机的拍摄图像与算法测量数据，实现多视角实时监控、公差超差报警与历史追溯。

---

## 通信机制说明

系统采用 **“图像走 FTP + 数据走 TCP”** 的双通道机制：
- **FTP**：客户端将检测图像上传至服务端归档目录。
- **TCP**：客户端以 **NDJSON（每条 JSON 报文以 `\n` 换行符结尾）** 格式推送批次测量数据。
- **关联规则**：FTP 图像文件名与 TCP 数据中的 `imageName` 保持一致即可完成自动绑定。两者上传先后顺序不限（服务端支持自动缓存与异步匹配）。

---

## TCP 数据通信协议

### 1. 传输规范
- **协议**：TCP 长连接，UTF-8 编码。
- **分包机制**：**每条 JSON 报文末尾必须以换行符 `\n` 结尾**。
- **端口**：默认为 `9000`（可在系统配置中自定义）。

### 2. 请求报文格式 (Client -> Server)

```json
{
  "requestId": "52fa1f4e-59e8-4cb8-813c-cd315f26fc49",
  "carrierId": 3,
  "timestamp": "20260912_143005",
  "wheels": [
    {
      "wheelId": 1,
      "cameraId": 1,
      "actualDistance": 125.4,
      "baseDistance": 120.0,
      "lowerTolerance": -2.0,
      "result": "OK",
      "imageName": "CARRIER_3_20260912_143005_cam01.png"
    },
    {
      "wheelId": 2,
      "cameraId": 1,
      "actualDistance": 117.8,
      "baseDistance": 120.0,
      "lowerTolerance": -2.0,
      "result": "NG",
      "imageName": "CARRIER_3_20260912_143005_cam01.png"
    }
  ]
}
```
*(注：网络发送时必须压缩为单行，并在末尾附加 `\n` 换行符)*

#### 字段说明

**根对象：**
| 字段 | 类型 | 必填 | 范围 / 格式 | 说明 |
| :--- | :--- | :---: | :--- | :--- |
| `carrierId` | int | 是 | `1 ~ 50` | 载具编号 |
| `wheels` | array | 是 | 长度 `1 ~ 32` | 轮测量数据列表（包含驱动轮和走行轮） |
| `timestamp` | string | 否 | `yyyyMMdd_HHmmss` 或 ISO 8601 | 测量时间（缺省时为当前系统时间）；不得晚于服务器时间 10 分钟，也不得早于数据保留天数，否则拒收 |
| `requestId` | string | 否 | 最长 128 字符 | 幂等请求唯一标识 |

**`wheels` 数组项：**
| 字段 | 类型 | 必填 | 范围 / 格式 | 说明 |
| :--- | :--- | :---: | :--- | :--- |
| `wheelId` | int | 是 | `1 ~ 16` | 轮位，1～8 为走行轮，9～16 为驱动轮；界面按同一轮位显示，见下表 |
| `cameraId` | int | 否 | `1 ~ 12`（默认 1） | 对应工位相机号（同一批次内 `cameraId:wheelId` 唯一） |
| `actualDistance` | double | 是 | 有限数值 | 实测轮间距 (mm) |
| `baseDistance` | double | 是 | 有限数值 | 基准理论间距 (mm) |
| `lowerTolerance` | double | 是 | 有限数值 | 下公差 (mm)，如 `-2.0` |
| `result` | string / int | 是 | `"OK"`/`"NG"` 或 `1`/`0` | 检测判定结果（任一轮 NG 即触发报警） |
| `imageName` | string | 是 | 最长 512 字符，图片扩展名 | 关联的图像文件名（须与 FTP 上传文件名一致）。只应填写文件名；若带路径（如 `D:\cam\a.png`），服务端只取文件名并记录告警；为空、以 `.` 开头或不是图片扩展名时拒收 |

#### 轮位与轮系

`wheelId` 就是现场轮位，界面、数据库 `wheel_id`、查询键、统计分组和导出全部直接使用它，不做任何偏移换算。轮位 1～8 为走行轮，9～16 为驱动轮；界面名称为“轮位N/走行轮N”或“轮位N/驱动轮(N-8)”。

| TCP `wheelId` / 数据库 `wheel_id` / 轮位 | 物理轮 | 界面名称 |
| :--- | :--- | :--- |
| 1 | 走行轮1 | 轮位1/走行轮1 |
| 2 | 走行轮2 | 轮位2/走行轮2 |
| 3 | 走行轮3 | 轮位3/走行轮3 |
| 4 | 走行轮4 | 轮位4/走行轮4 |
| 5 | 走行轮5 | 轮位5/走行轮5 |
| 6 | 走行轮6 | 轮位6/走行轮6 |
| 7 | 走行轮7 | 轮位7/走行轮7 |
| 8 | 走行轮8 | 轮位8/走行轮8 |
| 9 | 驱动轮1 | 轮位9/驱动轮1 |
| 10 | 驱动轮2 | 轮位10/驱动轮2 |
| 11 | 驱动轮3 | 轮位11/驱动轮3 |
| 12 | 驱动轮4 | 轮位12/驱动轮4 |
| 13 | 驱动轮5 | 轮位13/驱动轮5 |
| 14 | 驱动轮6 | 轮位14/驱动轮6 |
| 15 | 驱动轮7 | 轮位15/驱动轮7 |
| 16 | 驱动轮8 | 轮位16/驱动轮8 |

例如：上报 `wheelId: 1` 是走行轮1，显示“轮位1/走行轮1”；上报 `wheelId: 9` 是驱动轮1，显示“轮位9/驱动轮1”。两种轮系的报文结构相同。相机号由客户端独立上报；一张图可关联多个轮，不能根据相机号推导轮位。

查询选择器、快捷搜索“轮位1”直接查询轮位 1；“驱动轮1”查询轮位 9，“走行轮1”查询轮位 1。内部跨页跳转传轮位，0 表示不筛选轮位。客户端负责保存并使用测量基准，本软件不提供基准标定或远程下发入口。旧版本保存在 `carrier_wheel_norm` 中的本地基准配置保留，不参与检测判定。

### 3. 响应报文格式 (Server -> Client)

服务端处理完每条报文后均返回单行响应（以 `\n` 结尾）：
- **成功**：
  ```json
  {"status":"OK","carrierId":3,"wheelCount":2}
  ```
- **失败**：
  ```json
  {"status":"ERROR","message":"错误原因说明"}
  ```

### 4. 连接约束
- 单条报文最长 64 KB，超过即断开连接；
- 连接 5 分钟内无任何数据即被服务端断开（客户端可按需重连，或定期发送报文）；
- 客户端须读取响应：未读取的响应积压超过 1 MB 时断开连接；
- 服务器存储空间低于停止阈值时，返回 `服务器存储空间不足，暂停接收数据`，客户端应稍后重发（建议携带 `requestId`，重发不会重复入库）。

---

## FTP 图像传输与命名规范

### 1. 传输要求
- **协议**：标准 FTP（支持主动模式 PORT 与被动模式 PASV/EPSV），默认端口 21。
- **被动端口**：默认 `50000 ~ 50100`，现场防火墙需放行控制端口与该范围（可通过 `ftp/passivePortMin`、`ftp/passivePortMax` 修改）。
- **登录保护**：同一来源 IP 10 分钟内登录失败 10 次，封禁 15 分钟（新连接返回 `421`）。
- **存储保护**：服务器存储空间低于拒收阈值时，`STOR` 返回 `452 Insufficient storage space`，客户端应稍后重传。
- **支持格式**：标准图片格式（`.png`、`.jpg`、`.jpeg`、`.bmp`、`.tiff` 等）。
- **文件校验**：单文件小于 512MB；JPEG/PNG/BMP 会检查文件是否完整（截断的文件返回 `451` 拒收）；同名且内容相同的文件视为幂等重传，同名但内容不同自动保存为带版本后缀的文件（如 `_v2`），并关联到随后引用该文件名的批次。
- **目录**：建议直接上传到 FTP 根目录；上传到子目录同样可以被正确关联与清理。

### 2. 文件命名规范
系统不从文件名解析业务数据，**仅依靠文件名与 TCP 数据中的 `imageName` 进行比对绑定**。

- **匹配原则**：FTP 上传的文件名必须与 TCP 报文中对应轮项的 `imageName` 完全一致（不区分大小写）。
- **多轮共图**：一个相机拍摄覆盖多个轮时，TCP 报文中的多个轮直接指定同一个 `imageName`，FTP 仅需上传一张图片。
- **推荐命名规范**：
  ```text
  CARRIER_{carrierId}_{timestamp}_cam{cameraId:02d}.png
  ```
  **示例**：
  - 载具 3、相机 1：`CARRIER_3_20260912_143005_cam01.png`
  - 载具 3、相机 2：`CARRIER_3_20260912_143005_cam02.png`

---

## 客户端对接示例

### Python 快速对接
```python
import socket, json, ftplib, time

HOST, FTP_PORT, TCP_PORT = "127.0.0.1", 21, 9000
TIMESTAMP = time.strftime("%Y%m%d_%H%M%S")  # 须接近服务器时间（不超前 10 分钟、不早于保留期）
IMAGE_NAME = f"CARRIER_3_{TIMESTAMP}_cam01.png"

# 1. 上传图片至 FTP
ftp = ftplib.FTP()
ftp.connect(HOST, FTP_PORT)
ftp.login("agc", "123456")  # 内置默认账户，现场请在系统设置中修改
ftp.set_pasv(True)
with open("local_cam01.png", "rb") as f:
    ftp.storbinary(f"STOR {IMAGE_NAME}", f)
ftp.quit()

# 2. 通过 TCP 发送测量数据 (末尾以 \n 结尾)
payload = {
    "carrierId": 3,
    "timestamp": TIMESTAMP,
    "wheels": [
        {"wheelId": 1, "cameraId": 1, "actualDistance": 125.4, "baseDistance": 120.0, "lowerTolerance": -2.0, "result": "OK", "imageName": IMAGE_NAME},
        {"wheelId": 2, "cameraId": 1, "actualDistance": 117.8, "baseDistance": 120.0, "lowerTolerance": -2.0, "result": "NG", "imageName": IMAGE_NAME}
    ]
}

with socket.create_connection((HOST, TCP_PORT), timeout=5) as s:
    s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    response = s.recv(1024).decode("utf-8").strip()
    print("服务端应答:", response)
```

### Netcat 命令行测试
```bash
echo '{"carrierId":1,"wheels":[{"wheelId":1,"actualDistance":10.5,"baseDistance":10.0,"lowerTolerance":-2.0,"result":"OK","imageName":"sample.png"}]}' | nc -N 127.0.0.1 9000
```

---

## 构建与运行

```bash
# 编译
cmake -B build/Debug -DCMAKE_BUILD_TYPE=Debug -G Ninja
cmake --build build/Debug -j8

# 运行测试
ctest --test-dir build/Debug --output-on-failure

# 启动系统
./build/Debug/bin/CarrierVision
```

发布版打包（安装时自动收集 Qt 运行库、插件与 QML 模块，生成可直接拷贝运行的目录）：

```bash
cmake -B build/Release -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build build/Release -j8
cmake --install build/Release      # 输出到 install/CarrierVision_linux_<版本>
```

持续集成：推送到 `main` 或向 `main` 发起 PR 时，GitHub Actions 自动执行 Windows 构建、全部测试并打包为 zip（在运行记录的 Artifacts 中下载，保留 14 天）。也可在 Actions 页面手动对任意分支运行。

---

## 运行配置与运维

### 1. 可调配置（`data/dataAgc.db` 的 `system_config` 表）

界面未提供入口的配置可直接修改该表（`key`、`value`），重启后生效：

| key | 默认值 | 说明 |
| :--- | :--- | :--- |
| `log/level` | 发布版 `info`，调试版 `debug` | 日志级别：`trace` / `debug` / `info` / `warn` / `error` |
| `network/allowList` | 空（不限制） | FTP 与 TCP 的来源 IP 白名单，逗号分隔，支持 CIDR，如 `192.168.1.0/24,10.0.0.5` |
| `ftp/passivePortMin`、`ftp/passivePortMax` | `50000`、`50100` | FTP 被动模式端口范围 |
| `storage/warnPercent` | `10` | 剩余空间低于该百分比时告警 |
| `storage/rejectUploadsPercent` | `5` | 低于该百分比时 FTP 拒收新上传，并触发紧急清理 |
| `storage/rejectDataPercent` | `2` | 低于该百分比时 TCP 也停止入库 |

### 2. 数据保留与清理
- 每天在设定时刻清理超过保留天数的检测记录与图片；程序关闭期间错过的清理会在启动后补做；
- 没有任何记录引用的图片，超过保留期 7 天后删除；
- 存储空间不足时执行紧急清理：从最旧的数据开始，逐步缩短保留期，直到恢复到告警阈值以上，最少保留最近 7 天。

### 3. 数据库备份与恢复
- 每天在清理时刻做一次完整性检查，并在 `data/backup/` 下备份，保留最近 3 份；
- 程序异常退出后再次启动，或日常检查发现损坏时，启动前会自动检查数据库；损坏时把原库改名为 `dataAgc.db.corrupt-时间` 保留，并从最近一份可用备份恢复（备份之后写入的数据会丢失）。

### 4. 故障诊断与自动重启
- 运行日志统一写入 `logs/carrier_YYYY-MM-DD.log`（含 FTP、TCP 与入库日志，可在「日志查询」页检索）。INFO 保留服务启停、连接、每批 TCP 入库及已关联/待图片轮数；FTP 图片每分钟汇总接收张数、回填记录轮数、进入缓存张数和当前待关联缓存量，无图片时不输出，正常退出时补记不足一分钟的汇总。两种关联顺序均可核对：图先到由 TCP 入库日志统计，记录先到由 FTP 汇总统计（各汇总窗口独立，不保证同一分钟对齐）。逐条 FTP 命令、应答、目录确认、图片归档/关联明细和 TCP 接收明细为 DEBUG 级别，排查具体文件时将 `log/level` 设为 `debug` 并重启；告警和错误仍逐条记录，QML 警告统一经 Qt 消息处理器记录一次；
- 旧版本在程序目录单独写的 `ftp.log`、`ftp.log.1`，升级后首次启动时移入 `logs/ftp_legacy_时间.log`，按日志保留天数清理；
- 程序崩溃时，Linux 在 `logs/crash.log` 记录调用栈，Windows 在 `logs/` 下生成 `crash_时间.dmp`；
- FTP / TCP 服务因端口占用等原因启动失败后，每 30 秒自动重试；
- 自动重启：Linux 使用发布包中的 `carriervision.service`（systemd 用户服务，文件内有安装说明）；Windows 使用 `CarrierVision_watchdog.bat` 启动，异常退出后 5 秒自动重启。

### 5. 联调与长时间运行测试
`scripts/simulator.py` 按节拍模拟 12 路相机的 FTP 上传与 TCP 报文，可注入异常数据并采样进程资源：

```bash
python3 scripts/simulator.py --interval 5 --duration 72h --fault-rate 0.05 --pid $(pgrep -x CarrierVision)
```

默认使用 `agc` / `123456` 账户和 21、9000 端口，现场修改过时用 `--user`、`--password`、`--ftp-port`、`--tcp-port` 指定。出现非预期结果（正常数据被拒、异常数据被接受、被测进程退出）时退出码为 1。

---

## 报警统计与人工处置

报警统计默认查询含今天在内的近 7 天，重置恢复此范围，统一显示全部轮位（1～16），不再按驱动轮、走行轮筛选。左侧架号列表显示未处理频次和已处理频次，处置成功后重新查询并刷新计数，保留当前架号、轮位和原图选择。未处理仅统计尚未处置的 NG 记录，已处理仅统计已换轮记录，误报单独计数。轮位行显示 NG 总数、待处置、已处理及误报数量，并提供「已处理」「误报」操作；已处理表示现场已经换轮。

操作仅覆盖当前已查询日期范围内、相同架号和原始轮号的未处置 NG 记录。`record.is_handled` 和 `record.is_false_alarm` 为独立于检测结果的人工处置字段（默认 0），两种处置互斥且已处置记录不可重复修改。新收到的记录默认未处置。升级时自动为现有数据库加列，无需删库。人工处置不修改客户端的 `result`、测量值、图片或原有 NG 统计，也不更改最新检测报警缓存。

右侧异常原图按时间倒序逐张浏览，支持上一幅、下一幅及点击放大；同一落盘图片不区分大小写去重，同名的不同落盘版本分别展示。已处置记录仍可查看，图片尚未到达或文件缺失时显示提示。图像分页没有 200 条上限。

---

## 统计导出与周报编号

本次轮位展示升级后，新生成的轮级 CSV 增加 `position_no`、`wheel_type`、`type_index` 身份列：

- `wheel_id`：协议/数据库轮号，即轮位，含义不变。
- `position_no`：界面显示轮位1～16，与 `wheel_id` 相同，保留此列便于按表头识别格式。
- `wheel_type`：`drive` 为驱动轮，`walk` 为走行轮。
- `type_index`：本轮系内序号1～8。

轮位统计及日期栏兜底导出表头为 `wheel_id,position_no,wheel_type,type_index,ok数,ng数`；周报表头为 `carrier_id,wheel_id,position_no,wheel_type,type_index,ok_count,ng_count,total,loss_rate`。`loss_rate` 仍为0～1的比例。驱动/走行周报的物理分组与原有文件命名不变。

架号统计和报警统计导出的是整组汇总，不具备单轮身份，新增 `wheel_type,position_range` 说明轮系和轮位范围，不填造单轮编号。报警统计导出使用 `wheel_type=all`、`position_range=1～16`，并增加未处理频次、已处理频次列。旧版轮级导出中“轮号”与周报 `wheel_id` 都是轮位；历史已生成文件不改写，已经登记的周报不重复生成。读取 CSV 时应按表头识别格式，固定列号的外部程序需要适配新增列。

---

## 目录结构

```text
CarrierVision/
├── CMakeLists.txt
├── cmake/               版本号计算（version.cmake），生成 version.h 到构建目录
├── src/
│   ├── main.cpp         程序入口、单实例保护、数据库完整性检查与初始化
│   ├── app/             AppController（QML 门面）、图像列表模型、批次类型
│   ├── network/         内置 FTP 服务（独立线程）、TCP 数据接收、来源 IP 白名单与登录封禁
│   ├── ingest/          图像校验提交、TCP 批次解析入库、FTP/TCP 关联
│   ├── data/            表结构、统计/搜索查询、持久化配置、归档清理、周报、数据库备份与恢复
│   └── common/          通用工具、日志、磁盘空间监控、崩溃记录、version.h.in
├── qml/                 界面（按功能页分子目录，common/ 为公共组件）
├── assets/
│   ├── icons/           SVG 图标与程序图标，编译进程序资源
│   └── models/          首页 3D 装配体模型
├── packaging/           随安装包分发的文件
│   ├── README.txt       发布说明
│   ├── linux/           启动脚本、桌面快捷方式、systemd 守护服务
│   └── windows/         exe 图标资源、环境变量注册脚本、守护启动脚本
├── scripts/             安装时调用的依赖部署脚本（Linux / Windows）、产线模拟器 simulator.py
├── tests/               QtTest 单元测试与集成测试
├── third_party/         仅头文件的第三方库（版本见其中 README.md）
├── docs/                发布记录、两轮优化方案及实测数据
└── .github/workflows/   Windows 构建、测试与打包
```

源码以 `src/` 为头文件根目录，包含时写子目录路径，例如 `#include "data/DbSchema.h"`。
