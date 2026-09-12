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
- **端口**：默认为 `8088`（可在系统配置中自定义）。

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
| `timestamp` | string | 否 | `yyyyMMdd_HHmmss` 或 ISO 8601 | 测量时间（缺省时为当前系统时间） |
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
| `imageName` | string | 是 | 最长 512 字符 | 关联的图像文件名（须与 FTP 上传文件名一致） |

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

---

## FTP 图像传输与命名规范

### 1. 传输要求
- **协议**：标准 FTP（支持主动模式 PORT 与被动模式 PASV），默认端口 21。
- **支持格式**：标准图片格式（`.png`、`.jpg`、`.jpeg`、`.bmp`、`.tiff` 等）。
- **文件校验**：单文件小于 512MB；同名且内容相同的文件视为幂等重传，同名但内容不同自动生成版本后缀（如 `_v2`）。

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
import socket, json, ftplib

HOST, FTP_PORT, TCP_PORT = "127.0.0.1", 21, 8088
IMAGE_NAME = "CARRIER_3_20260912_143005_cam01.png"

# 1. 上传图片至 FTP
ftp = ftplib.FTP()
ftp.connect(HOST, FTP_PORT)
ftp.login("admin", "admin")
ftp.set_pasv(True)
with open("local_cam01.png", "rb") as f:
    ftp.storbinary(f"STOR {IMAGE_NAME}", f)
ftp.quit()

# 2. 通过 TCP 发送测量数据 (末尾以 \n 结尾)
payload = {
    "carrierId": 3,
    "timestamp": "20260912_143005",
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
echo '{"carrierId":1,"wheels":[{"wheelId":1,"actualDistance":10.5,"baseDistance":10.0,"lowerTolerance":-2.0,"result":"OK","imageName":"sample.png"}]}' | nc -N 127.0.0.1 8088
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
