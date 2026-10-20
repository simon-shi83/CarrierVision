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
| `wheels` | array | 是 | 长度 `1 ~ 32` | 驱动轮测量数据列表 |
| `timestamp` | string | 否 | `yyyyMMdd_HHmmss` 或 ISO 8601 | 测量时间（缺省时为当前系统时间）；不得晚于服务器时间 10 分钟，也不得早于数据保留天数，否则拒收 |
| `requestId` | string | 否 | 最长 128 字符 | 幂等请求唯一标识 |

**`wheels` 数组项：**
| 字段 | 类型 | 必填 | 范围 / 格式 | 说明 |
| :--- | :--- | :---: | :--- | :--- |
| `wheelId` | int | 是 | `1 ~ 16` | 驱动轮编号 |
| `cameraId` | int | 否 | `1 ~ 12`（默认 1） | 对应工位相机号（同一批次内 `cameraId:wheelId` 唯一） |
| `actualDistance` | double | 是 | 有限数值 | 实测轮间距 (mm) |
| `baseDistance` | double | 是 | 有限数值 | 基准理论间距 (mm) |
| `lowerTolerance` | double | 是 | 有限数值 | 下公差 (mm)，如 `-2.0` |
| `result` | string / int | 是 | `"OK"`/`"NG"` 或 `1`/`0` | 检测判定结果（任一轮 NG 即触发报警） |
| `imageName` | string | 是 | 最长 512 字符，图片扩展名 | 关联的图像文件名（须与 FTP 上传文件名一致）。只应填写文件名；若带路径（如 `D:\cam\a.png`），服务端只取文件名并记录告警；为空、以 `.` 开头或不是图片扩展名时拒收 |

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
- 程序崩溃时，Linux 在 `logs/crash.log` 记录调用栈，Windows 在 `logs/` 下生成 `crash_时间.dmp`；
- FTP / TCP 服务因端口占用等原因启动失败后，每 30 秒自动重试；
- 自动重启：Linux 使用发布包中的 `carriervision.service`（systemd 用户服务，文件内有安装说明）；Windows 使用 `CarrierVision_watchdog.bat` 启动，异常退出后 5 秒自动重启。

### 5. 联调与长时间运行测试
`scripts/simulator.py` 按节拍模拟 12 路相机的 FTP 上传与 TCP 报文，可注入异常数据并采样进程资源：

```bash
python3 scripts/simulator.py --interval 5 --duration 72h --fault-rate 0.05 --pid $(pgrep -x CarrierVision)
```

---

## 目录结构

```text
CarrierVision/
├── CMakeLists.txt
├── cmake/               版本号计算（version.cmake），生成 version.h 到构建目录
├── src/
│   ├── main.cpp         程序入口、单实例保护、主数据库初始化
│   ├── app/             AppController（QML 门面）、图像列表模型、批次类型
│   ├── network/         内置 FTP 服务（独立线程）、TCP 数据接收
│   ├── ingest/          图像校验提交、TCP 批次解析入库、FTP/TCP 关联
│   ├── data/            表结构、统计/搜索查询、持久化配置、归档清理、周报
│   └── common/          通用工具、日志、version.h.in
├── qml/                 界面（按功能页分子目录，common/ 为公共组件）
├── assets/
│   ├── icons/           SVG 图标与程序图标，编译进程序资源
│   └── models/          首页 3D 装配体模型
├── packaging/           随安装包分发的文件
│   ├── README.txt       发布说明
│   ├── linux/           启动脚本、桌面快捷方式
│   └── windows/         exe 图标资源、环境变量注册脚本
├── scripts/             安装时调用的依赖部署脚本（Linux / Windows）
├── tests/               QtTest 单元测试与集成测试
├── third_party/         仅头文件的第三方库（版本见其中 README.md）
└── docs/                发布记录、优化方案
```

源码以 `src/` 为头文件根目录，包含时写子目录路径，例如 `#include "data/DbSchema.h"`。
