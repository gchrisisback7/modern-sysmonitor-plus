#!/usr/bin/env python3
"""System stats collector for the Modern SysMonitor AMD plasmoid.

Prints one JSON object with CPU, RAM, network and GPU statistics.
GPU data comes from /sys (amdgpu driver) with an nvidia-smi fallback.
"""
import sys
import os
import re
import json
import time
import subprocess

STATE_FILE = "/tmp/sysmonitor_state.json"
DRM_PATH = "/sys/class/drm"
HWMON_PATH = "/sys/class/hwmon"
BLOCK_PATH = "/sys/class/block"
MOUNTS_PATH = "/proc/mounts"
# Disk information changes slowly (and SMART reads are not free), so it is
# refreshed only every few seconds and cached in the state file in between.
DISK_REFRESH_SECONDS = 10


def read_cpu_ticks():
    try:
        with open("/proc/stat", "r") as f:
            for line in f:
                if line.startswith("cpu "):
                    parts = [float(x) for x in line.split()[1:]]
                    idle = parts[3] + parts[4]
                    total = sum(parts)
                    return total, idle
    except Exception:
        pass
    return 0.0, 0.0


def read_cpu_temp():
    try:
        for hwmon_dir in os.listdir("/sys/class/hwmon"):
            path = os.path.join("/sys/class/hwmon", hwmon_dir)
            name_file = os.path.join(path, "name")
            if os.path.exists(name_file):
                with open(name_file, "r") as f:
                    if f.read().strip() == "coretemp":
                        temp_file = os.path.join(path, "temp1_input")
                        if os.path.exists(temp_file):
                            with open(temp_file, "r") as tf:
                                return float(tf.read().strip()) / 1000.0
    except Exception:
        pass
    try:
        for hwmon_dir in os.listdir("/sys/class/hwmon"):
            path = os.path.join("/sys/class/hwmon", hwmon_dir)
            temp_file = os.path.join(path, "temp1_input")
            if os.path.exists(temp_file):
                with open(temp_file, "r") as tf:
                    return float(tf.read().strip()) / 1000.0
    except Exception:
        pass
    return 0.0


def read_ram():
    try:
        meminfo = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split(":")
                if len(parts) == 2:
                    key = parts[0].strip()
                    val = parts[1].strip().split()[0]
                    meminfo[key] = float(val)

        total_kb = meminfo.get("MemTotal", 0.0)
        available_kb = meminfo.get("MemAvailable", 0.0)
        used_kb = total_kb - available_kb

        total_gb = total_kb / (1024.0 * 1024.0)
        used_gb = used_kb / (1024.0 * 1024.0)
        pct = (used_kb / total_kb * 100.0) if total_kb > 0 else 0.0
        return used_gb, total_gb, pct
    except Exception:
        pass
    return 0.0, 0.0, 0.0


def read_net_bytes():
    total_rx = 0
    total_tx = 0
    try:
        with open("/proc/net/dev", "r") as f:
            for line in f:
                if ":" in line:
                    parts = line.split(":")
                    if len(parts) == 2:
                        ifparts = parts[0].strip()
                        if ifparts == "lo":
                            continue
                        stats = parts[1].strip().split()
                        if len(stats) >= 8:
                            total_rx += int(stats[0])
                            total_tx += int(stats[8])
    except Exception:
        pass
    return total_rx, total_tx


# ---------------------------------------------------------------- GPU

def _read_text(path):
    with open(path, "r") as f:
        return f.read().strip()


def _read_num(path):
    """Return the number stored in a sysfs file, or None if unavailable."""
    try:
        return float(_read_text(path))
    except Exception:
        return None


def _empty_gpu():
    return {
        "usage": 0.0,
        "temp": 0.0,
        "vram_used_gb": 0.0,
        "vram_total_gb": 0.0,
        "vram_pct": 0.0,
        # Extra details (None = not available on this GPU)
        "temp_junction": None,
        "temp_mem": None,
        "clock_mhz": None,
        "mem_clock_mhz": None,
        "fan_rpm": None,
        "fan_pct": None,
        "power_w": None,
        "power_cap_w": None,
    }


def _find_amd_card():
    """Return the sysfs device dir of the AMD GPU with the most VRAM.

    Picking the largest VRAM makes sure a discrete card wins over the
    integrated GPU of an AMD APU.
    """
    best = None
    best_vram = -1.0
    try:
        names = sorted(os.listdir(DRM_PATH))
    except Exception:
        return None
    for name in names:
        if not re.match(r"^card\d+$", name):
            continue
        dev = os.path.join(DRM_PATH, name, "device")
        try:
            if _read_text(os.path.join(dev, "vendor")) != "0x1002":
                continue
        except Exception:
            continue
        vram = _read_num(os.path.join(dev, "mem_info_vram_total"))
        if vram is None or _read_num(os.path.join(dev, "gpu_busy_percent")) is None:
            continue
        if vram > best_vram:
            best = dev
            best_vram = vram
    return best


def read_gpu_amd():
    dev = _find_amd_card()
    if dev is None:
        return None

    gpu = _empty_gpu()
    total = _read_num(os.path.join(dev, "mem_info_vram_total")) or 0.0
    used = _read_num(os.path.join(dev, "mem_info_vram_used")) or 0.0
    gpu["usage"] = _read_num(os.path.join(dev, "gpu_busy_percent")) or 0.0
    gpu["vram_used_gb"] = used / (1024.0 ** 3)
    gpu["vram_total_gb"] = total / (1024.0 ** 3)
    gpu["vram_pct"] = (used / total * 100.0) if total > 0 else 0.0

    # hwmon: temperatures, clocks, fan, power
    hwmon = None
    try:
        hwmon_root = os.path.join(dev, "hwmon")
        for entry in sorted(os.listdir(hwmon_root)):
            if entry.startswith("hwmon"):
                hwmon = os.path.join(hwmon_root, entry)
                break
    except Exception:
        hwmon = None
    if hwmon is None:
        return gpu

    # Temperatures, mapped by their label (edge / junction / mem)
    temps = {}
    for i in range(1, 6):
        value = _read_num(os.path.join(hwmon, "temp%d_input" % i))
        if value is None:
            continue
        try:
            label = _read_text(os.path.join(hwmon, "temp%d_label" % i)).lower()
        except Exception:
            label = "temp%d" % i
        temps[label] = value / 1000.0
    gpu["temp_junction"] = temps.get("junction")
    gpu["temp_mem"] = temps.get("mem")
    if "edge" in temps:
        gpu["temp"] = temps["edge"]
    elif "junction" in temps:
        gpu["temp"] = temps["junction"]
    elif temps:
        gpu["temp"] = list(temps.values())[0]

    # Clocks (sysfs reports Hz): sclk = core, mclk = memory
    for i in range(1, 4):
        value = _read_num(os.path.join(hwmon, "freq%d_input" % i))
        if value is None:
            continue
        try:
            label = _read_text(os.path.join(hwmon, "freq%d_label" % i)).lower()
        except Exception:
            label = ""
        mhz = value / 1e6
        if label == "sclk" or (not label and i == 1):
            gpu["clock_mhz"] = mhz
        elif label == "mclk" or (not label and i == 2):
            gpu["mem_clock_mhz"] = mhz

    # Fan
    fan = _read_num(os.path.join(hwmon, "fan1_input"))
    if fan is not None:
        gpu["fan_rpm"] = fan
    pwm = _read_num(os.path.join(hwmon, "pwm1"))
    pwm_max = _read_num(os.path.join(hwmon, "pwm1_max")) or 255.0
    if pwm is not None and pwm_max > 0:
        gpu["fan_pct"] = pwm / pwm_max * 100.0

    # Power (sysfs reports microwatts)
    power = _read_num(os.path.join(hwmon, "power1_average"))
    if power is None:
        power = _read_num(os.path.join(hwmon, "power1_input"))
    if power is not None:
        gpu["power_w"] = power / 1e6
    cap = _read_num(os.path.join(hwmon, "power1_cap"))
    if cap is not None and cap > 0:
        gpu["power_cap_w"] = cap / 1e6

    return gpu


def _to_float(text):
    try:
        return float(text)
    except Exception:
        return None


def read_gpu_nvidia():
    fields = "utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.gr,clocks.mem,fan.speed,power.draw,power.limit"
    res = None
    for query in (fields, "utilization.gpu,temperature.gpu,memory.used,memory.total"):
        try:
            cmd = ["/usr/bin/nvidia-smi", "--query-gpu=" + query, "--format=csv,noheader,nounits"]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8").strip()
            break
        except Exception:
            res = None
    if not res:
        return None

    # First line = first GPU
    parts = [x.strip() for x in res.splitlines()[0].split(",")]
    if len(parts) < 4:
        return None
    usage = _to_float(parts[0])
    temp = _to_float(parts[1])
    used_mib = _to_float(parts[2])
    total_mib = _to_float(parts[3])
    if None in (usage, temp, used_mib, total_mib):
        return None

    gpu = _empty_gpu()
    gpu["usage"] = usage
    gpu["temp"] = temp
    gpu["vram_used_gb"] = used_mib / 1024.0
    gpu["vram_total_gb"] = total_mib / 1024.0
    gpu["vram_pct"] = (used_mib / total_mib * 100.0) if total_mib > 0 else 0.0
    if len(parts) >= 9:
        gpu["clock_mhz"] = _to_float(parts[4])
        gpu["mem_clock_mhz"] = _to_float(parts[5])
        gpu["fan_pct"] = _to_float(parts[6])
        gpu["power_w"] = _to_float(parts[7])
        gpu["power_cap_w"] = _to_float(parts[8])
    return gpu


def read_gpu():
    """AMD first (via /sys), then Nvidia (nvidia-smi), else zeros."""
    for reader in (read_gpu_amd, read_gpu_nvidia):
        try:
            gpu = reader()
        except Exception:
            gpu = None
        if gpu is not None:
            return gpu
    return _empty_gpu()


def _round(value, digits=1):
    return None if value is None else round(value, digits)


# --------------------------------------------------------------- Fans

GPU_DRIVER_NAMES = ("amdgpu", "radeon", "nouveau", "nvidia")
FAN_FILE = re.compile(r"^fan(\d+)_input$")


def _is_gpu_hwmon(path, name):
    """GPU fans are shown in the GPU card, not in the case fans list."""
    if name in GPU_DRIVER_NAMES:
        return True
    try:
        # PCI class 0x03xxxx = display controller
        return _read_text(os.path.join(path, "device", "class")).startswith("0x03")
    except Exception:
        return False


def read_fans(cpu_fan_number):
    """Find every fan the system reports, without any per-board setup.

    Returns (cpu_fan_rpm or None, [{"key", "name", "rpm"}, ...]).
    Only spinning fans are listed (an unplugged header reads 0 RPM).
    cpu_fan_number > 0 picks fan<N> of the main motherboard chip as the CPU fan;
    0 means automatic (a fan whose label contains "cpu").
    """
    chips = []
    try:
        entries = sorted(os.listdir(HWMON_PATH))
    except Exception:
        return None, []
    for entry in entries:
        path = os.path.join(HWMON_PATH, entry)
        try:
            name = _read_text(os.path.join(path, "name"))
            if _is_gpu_hwmon(path, name):
                continue
            numbers = []
            for f in os.listdir(path):
                m = FAN_FILE.match(f)
                if m:
                    numbers.append(int(m.group(1)))
        except Exception:
            continue
        if numbers:
            chips.append((entry, name, path, sorted(numbers)))
    if not chips:
        return None, []

    # The motherboard Super-I/O chip is the one with the most fan inputs
    main_path = max(chips, key=lambda c: len(c[3]))[2]

    fans = []
    cpu_rpm = None
    for entry, name, path, numbers in chips:
        for n in numbers:
            rpm = _read_num(os.path.join(path, "fan%d_input" % n))
            if rpm is None:
                continue
            try:
                label = _read_text(os.path.join(path, "fan%d_label" % n))
            except Exception:
                label = ""
            if cpu_fan_number > 0:
                is_cpu = (path == main_path and n == cpu_fan_number)
            else:
                is_cpu = "cpu" in label.lower()
            display = label or ("Fan %d" % n)
            if not label and path != main_path:
                display = "%s fan %d" % (name, n)
            if is_cpu:
                display = "CPU Fan"
                if cpu_rpm is None:
                    cpu_rpm = rpm
            if rpm > 0:
                fans.append({"key": "%s:%d" % (entry, n), "name": display, "rpm": round(rpm)})
    return cpu_rpm, fans


# -------------------------------------------------------------- Disks

def _unescape_mount(text):
    """/proc/mounts escapes spaces and tabs as octal (\\040)."""
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), text)


def _parent_disk(name, depth=0):
    """Resolve sda1 / nvme0n1p2 / dm-0 to the physical disk (sda / nvme0n1)."""
    base = os.path.join(BLOCK_PATH, name)
    if not os.path.exists(base):
        return name
    slaves = os.path.join(base, "slaves")
    try:
        children = sorted(os.listdir(slaves)) if os.path.isdir(slaves) else []
    except Exception:
        children = []
    if children and depth < 5:
        return _parent_disk(children[0], depth + 1)
    if os.path.exists(os.path.join(base, "partition")):
        return os.path.basename(os.path.dirname(os.path.realpath(base)))
    return name


def _disk_model(disk):
    for rel in ("device/model", "device/name"):
        try:
            text = " ".join(_read_text(os.path.join(BLOCK_PATH, disk, rel)).split())
            if text:
                return text
        except Exception:
            pass
    return disk


def _disk_temps():
    """[(sysfs device path, temperature C)] for NVMe drives and drivetemp (SATA)."""
    temps = []
    try:
        entries = sorted(os.listdir(HWMON_PATH))
    except Exception:
        return temps
    for entry in entries:
        path = os.path.join(HWMON_PATH, entry)
        try:
            name = _read_text(os.path.join(path, "name"))
        except Exception:
            continue
        if name not in ("nvme", "drivetemp"):
            continue
        value = _read_num(os.path.join(path, "temp1_input"))
        if value is None:
            continue
        temps.append((os.path.realpath(os.path.join(path, "device")), value / 1000.0))
    return temps


def read_disks():
    """One entry per physical disk that has a mounted filesystem."""
    mounts = {}  # block device name -> mount point (first wins: skips btrfs subvolume duplicates)
    try:
        with open(MOUNTS_PATH, "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3 or not parts[0].startswith("/dev/"):
                    continue
                # Read-only images (always 100% full) are not interesting here
                if parts[2] in ("squashfs", "erofs", "iso9660", "udf"):
                    continue
                dev = os.path.basename(os.path.realpath(parts[0]))
                if re.match(r"^(loop|zram|ram|sr|fd)\d+$", dev):
                    continue
                mounts.setdefault(dev, _unescape_mount(parts[1]))
    except Exception:
        return []

    disks = {}
    for dev, mountpoint in mounts.items():
        try:
            st = os.statvfs(mountpoint)
        except Exception:
            continue
        total = st.f_blocks * st.f_frsize
        if total <= 0:
            continue
        used = (st.f_blocks - st.f_bfree) * st.f_frsize
        disk = _parent_disk(dev)
        entry = disks.setdefault(disk, {"used": 0.0, "total": 0.0})
        entry["used"] += used
        entry["total"] += total

    temps = _disk_temps()
    result = []
    for disk in sorted(disks):
        real = os.path.realpath(os.path.join(BLOCK_PATH, disk))
        temp = None
        for dev_path, value in temps:
            if real.startswith(dev_path + os.sep):
                temp = value
                break
        used = disks[disk]["used"]
        total = disks[disk]["total"]
        result.append({
            "key": disk,
            "name": _disk_model(disk),
            "temp": _round(temp),
            "used_gb": round(used / (1024.0 ** 3), 1),
            "total_gb": round(total / (1024.0 ** 3), 1),
            "pct": round(used / total * 100.0, 1) if total > 0 else 0.0,
        })
    return result


def parse_cpu_fan_arg():
    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--cpu-fan" and i + 1 < len(args):
            try:
                return max(0, int(args[i + 1]))
            except ValueError:
                return 0
    return 0


# --------------------------------------------------------------- main

def format_speed(speed_bytes):
    if speed_bytes < 1024:
        return f"{speed_bytes:.0f} B/s"
    elif speed_bytes < 1024 * 1024:
        return f"{speed_bytes / 1024.0:.1f} KB/s"
    else:
        return f"{speed_bytes / (1024.0 * 1024.0):.1f} MB/s"


def main():
    curr_time = time.time()
    curr_cpu_total, curr_cpu_idle = read_cpu_ticks()
    curr_rx, curr_tx = read_net_bytes()

    prev_state = {}
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                prev_state = json.load(f)
        except Exception:
            pass

    # Disks: reuse the cached values if they are fresh enough
    disks = None
    disks_ts = curr_time
    cached_ts = prev_state.get("disks_ts") if prev_state else None
    if isinstance(cached_ts, (int, float)) and prev_state.get("disks") is not None \
            and 0 <= curr_time - cached_ts < DISK_REFRESH_SECONDS:
        disks = prev_state["disks"]
        disks_ts = cached_ts
    if disks is None:
        try:
            disks = read_disks()
        except Exception:
            disks = []

    state_to_save = {
        "timestamp": curr_time,
        "cpu_total": curr_cpu_total,
        "cpu_idle": curr_cpu_idle,
        "net_rx": curr_rx,
        "net_tx": curr_tx,
        "disks_ts": disks_ts,
        "disks": disks
    }
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state_to_save, f)
    except Exception:
        pass

    cpu_usage = 0.0
    if prev_state:
        prev_total = prev_state.get("cpu_total", 0.0)
        prev_idle = prev_state.get("cpu_idle", 0.0)
        total_diff = curr_cpu_total - prev_total
        idle_diff = curr_cpu_idle - prev_idle
        if total_diff > 0:
            cpu_usage = (1.0 - (idle_diff / total_diff)) * 100.0

    net_down_speed = 0.0
    net_up_speed = 0.0
    if prev_state:
        prev_time = prev_state.get("timestamp", curr_time)
        prev_rx = prev_state.get("net_rx", curr_rx)
        prev_tx = prev_state.get("net_tx", curr_tx)
        dt = curr_time - prev_time
        if dt > 0:
            net_down_speed = (curr_rx - prev_rx) / dt
            net_up_speed = (curr_tx - prev_tx) / dt

    cpu_temp = read_cpu_temp()
    ram_used_gb, ram_total_gb, ram_pct = read_ram()
    gpu = read_gpu()
    try:
        cpu_fan_rpm, _unused = read_fans(parse_cpu_fan_arg())
    except Exception:
        cpu_fan_rpm = None

    result = {
        "cpu_usage": round(cpu_usage, 1),
        "cpu_temp": round(cpu_temp, 1),
        "ram_used_gb": round(ram_used_gb, 1),
        "ram_total_gb": round(ram_total_gb, 1),
        "ram_pct": round(ram_pct, 1),
        "gpu_usage": round(gpu["usage"], 1),
        "gpu_temp": round(gpu["temp"], 1),
        "vram_used_gb": round(gpu["vram_used_gb"], 1),
        "vram_total_gb": round(gpu["vram_total_gb"], 1),
        "vram_pct": round(gpu["vram_pct"], 1),
        "gpu_temp_junction": _round(gpu["temp_junction"]),
        "gpu_temp_mem": _round(gpu["temp_mem"]),
        "gpu_clock_mhz": _round(gpu["clock_mhz"], 0),
        "gpu_mem_clock_mhz": _round(gpu["mem_clock_mhz"], 0),
        "gpu_fan_rpm": _round(gpu["fan_rpm"], 0),
        "gpu_fan_pct": _round(gpu["fan_pct"], 0),
        "gpu_power_w": _round(gpu["power_w"]),
        "gpu_power_cap_w": _round(gpu["power_cap_w"], 0),
        "cpu_fan_rpm": _round(cpu_fan_rpm, 0),
        "disks": disks,
        "net_down_speed": round(net_down_speed, 1),
        "net_up_speed": round(net_up_speed, 1),
        "net_down_formatted": format_speed(net_down_speed),
        "net_up_formatted": format_speed(net_up_speed)
    }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
