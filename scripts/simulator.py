#!/usr/bin/env python3
"""CarrierVision 产线模拟器：按节拍模拟 12 路相机的 FTP 上传与 TCP 测量报文，可注入异常输入，
并采样被测进程的资源占用，用于联调与长时间运行测试。只依赖 Python 标准库。

示例：
  # 每 5 秒一架载具，运行 72 小时，5% 的批次注入异常，每分钟采样一次进程资源
  python3 scripts/simulator.py --interval 5 --duration 72h --fault-rate 0.05 --pid $(pgrep -x CarrierVision)

  # 快速冒烟：10 架载具后结束
  python3 scripts/simulator.py --batches 10

退出码：发生非预期结果（正常批次被拒、异常批次被接受等）时为 1。
"""
import argparse
import datetime
import ftplib
import io
import json
import os
import random
import socket
import struct
import sys
import threading
import time
import zlib


def parse_duration(text):
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    if text[-1] in units:
        return float(text[:-1]) * units[text[-1]]
    return float(text)


def make_png(width, height, seed):
    """生成内容随 seed 变化的 PNG（每张都不同，避免被当作幂等重传）。"""
    rng = random.Random(seed)
    row_noise = bytes(rng.getrandbits(8) for _ in range(width * 3))
    raw = b"".join(b"\x00" + bytes((b + y) & 0xFF for b in row_noise) for y in range(height))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b""))


class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.counts = {}
        self.unexpected = []

    def add(self, key, n=1):
        with self.lock:
            self.counts[key] = self.counts.get(key, 0) + n

    def fail(self, message):
        with self.lock:
            self.unexpected.append(f"{datetime.datetime.now():%H:%M:%S} {message}")
            self.counts["unexpected"] = self.counts.get("unexpected", 0) + 1


class Simulator:
    def __init__(self, args):
        self.args = args
        self.stats = Stats()
        self.rng = random.Random(args.seed)

    # ---------- 通信 ----------
    def ftp_upload(self, name, data):
        ftp = ftplib.FTP()
        ftp.connect(self.args.host, self.args.ftp_port, timeout=30)
        try:
            ftp.login(self.args.user, self.args.password)
            return ftp.storbinary("STOR " + name, io.BytesIO(data))
        except ftplib.all_errors as error:
            return "ERR " + str(error)
        finally:
            try:
                ftp.quit()
            except Exception:
                ftp.close()

    def tcp_send(self, payload):
        with socket.create_connection((self.args.host, self.args.tcp_port), timeout=30) as sock:
            sock.sendall(payload)
            reply = b""
            while not reply.endswith(b"\n"):
                part = sock.recv(4096)
                if not part:
                    break
                reply += part
        return reply.decode("utf-8", "replace").strip()

    # ---------- 一架载具 ----------
    def batch(self, index):
        carrier = index % 50 + 1
        now = datetime.datetime.now()
        stamp = now.strftime("%Y%m%d_%H%M%S")
        fault = self.rng.random() < self.args.fault_rate
        kind = self.rng.choice(["bad_json", "future_ts", "path_name", "truncated", "idle_conn", "versioned"]) if fault else "normal"
        self.stats.add("batch." + kind)

        images = {cam: f"SIM_{carrier}_{stamp}_{index}_cam{cam:02d}.png" for cam in range(1, 13)}
        wheels = []
        for wheel in range(1, 17):
            cam = (wheel - 1) * 12 // 16 + 1
            ok = self.rng.random() > 0.03
            wheels.append({"wheelId": wheel, "cameraId": cam, "actualDistance": round(120 + self.rng.uniform(-3, 3), 2),
                           "baseDistance": 120.0, "lowerTolerance": -2.0, "result": "OK" if ok else "NG",
                           "imageName": images[cam]})
        message = {"requestId": f"sim-{os.getpid()}-{index}", "carrierId": carrier, "timestamp": stamp, "wheels": wheels}
        expect_tcp_ok = True

        if kind == "bad_json":
            payload = b'{"carrierId": 1, "wheels": [\n'
            expect_tcp_ok = False
        elif kind == "future_ts":
            message["timestamp"] = (now + datetime.timedelta(days=365)).strftime("%Y%m%d_%H%M%S")
            payload = (json.dumps(message) + "\n").encode()
            expect_tcp_ok = False
        elif kind == "path_name":
            for w in wheels:
                w["imageName"] = "D:\\camera\\output\\" + w["imageName"]
            payload = (json.dumps(message) + "\n").encode()
        else:
            payload = (json.dumps(message) + "\n").encode()

        def upload_all():
            for cam, name in images.items():
                data = make_png(self.args.width, self.args.height, hash((index, cam)))
                expect_ok = True
                if kind == "truncated" and cam == 1:
                    data = data[: len(data) * 2 // 3]
                    expect_ok = False
                result = self.ftp_upload(name, data)
                accepted = result.startswith("226")
                self.stats.add("ftp.accepted" if accepted else "ftp.rejected")
                if accepted != expect_ok:
                    self.stats.fail(f"FTP {name}: 预期{'接受' if expect_ok else '拒绝'}，实际 {result}")
                if kind == "versioned" and cam == 2:
                    # 同名不同内容重传：服务端应保存为 _v2，且新批次关联到新图
                    again = self.ftp_upload(name, make_png(self.args.width, self.args.height, hash((index, cam, "v2"))))
                    self.stats.add("ftp.versioned")
                    if not again.startswith("226"):
                        self.stats.fail(f"FTP 版本化重传被拒: {again}")

        def send_tcp():
            reply = self.tcp_send(payload)
            accepted = '"status":"OK"' in reply.replace(" ", "")
            self.stats.add("tcp.accepted" if accepted else "tcp.rejected")
            if accepted != expect_tcp_ok:
                self.stats.fail(f"TCP 载具 {carrier} ({kind}): 预期{'接受' if expect_tcp_ok else '拒绝'}，实际 {reply[:200]}")

        if kind == "idle_conn":
            # 只连接不发送：服务端应在空闲超时后回收，不占用连接名额
            idle = socket.create_connection((self.args.host, self.args.tcp_port), timeout=5)
            timer = threading.Timer(self.args.idle_hold, idle.close)
            timer.daemon = True  # 不阻止模拟器在结束时退出
            timer.start()

        try:
            if self.rng.random() < 0.5:
                upload_all()
                send_tcp()
            else:
                send_tcp()
                upload_all()
        except (OSError, ftplib.all_errors) as error:
            self.stats.fail(f"批次 {index} 通信异常: {error}")

    # ---------- 资源采样 ----------
    def sample(self, pid):
        try:
            with open(f"/proc/{pid}/status") as f:
                fields = dict(line.split(":", 1) for line in f if ":" in line)
            rss_mb = int(fields["VmRSS"].split()[0]) / 1024
            threads = int(fields["Threads"])
            fds = len(os.listdir(f"/proc/{pid}/fd"))
            return rss_mb, threads, fds
        except (OSError, KeyError, ValueError):
            return None

    def run(self):
        args = self.args
        deadline = time.time() + parse_duration(args.duration) if args.duration else None
        samples = []
        next_sample = time.time()
        index = 0
        print(f"开始模拟: 节拍 {args.interval}s, 异常比例 {args.fault_rate:.0%}, 图像 {args.width}x{args.height}", flush=True)
        while True:
            if args.batches and index >= args.batches:
                break
            if deadline and time.time() >= deadline:
                break
            started = time.time()
            self.batch(index)
            index += 1
            if args.pid and time.time() >= next_sample:
                sample = self.sample(args.pid)
                if sample is None:
                    self.stats.fail(f"被测进程 {args.pid} 已不存在")
                    break
                samples.append((time.time(), *sample))
                print(f"[{datetime.datetime.now():%H:%M:%S}] 批次 {index}: 内存 {sample[0]:.0f} MB, "
                      f"线程 {sample[1]}, 句柄 {sample[2]}, 非预期 {self.stats.counts.get('unexpected', 0)}", flush=True)
                next_sample = time.time() + args.sample_every
            time.sleep(max(0.0, args.interval - (time.time() - started)))

        print("\n==== 汇总 ====")
        for key in sorted(self.stats.counts):
            print(f"  {key}: {self.stats.counts[key]}")
        if samples:
            first, last = samples[0], samples[-1]
            peak = max(s[1] for s in samples)
            print(f"  内存: 起始 {first[1]:.0f} MB, 结束 {last[1]:.0f} MB, 峰值 {peak:.0f} MB")
            print(f"  线程: 起始 {first[2]}, 结束 {last[2]}; 句柄: 起始 {first[3]}, 结束 {last[3]}")
        for line in self.stats.unexpected[:50]:
            print("  非预期: " + line)
        return 1 if self.stats.unexpected else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--ftp-port", type=int, default=21)
    parser.add_argument("--tcp-port", type=int, default=9000)
    parser.add_argument("--user", default="agc")
    parser.add_argument("--password", default="123456")
    parser.add_argument("--interval", type=float, default=5.0, help="每架载具的节拍（秒）")
    parser.add_argument("--batches", type=int, default=0, help="模拟的载具数，0 表示不限")
    parser.add_argument("--duration", default="", help="运行时长，如 30m、72h；为空则由 --batches 决定")
    parser.add_argument("--fault-rate", type=float, default=0.0, help="注入异常的批次比例 0~1")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--idle-hold", type=float, default=600.0, help="空闲连接保持秒数（应大于服务端空闲超时）")
    parser.add_argument("--pid", type=int, default=0, help="被测进程号（Linux），用于采样内存/线程/句柄")
    parser.add_argument("--sample-every", type=float, default=60.0)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    if not args.batches and not args.duration:
        parser.error("需要指定 --batches 或 --duration")
    sys.exit(Simulator(args).run())


if __name__ == "__main__":
    main()
