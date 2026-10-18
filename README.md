# Modern SysMonitor Plus

A sleek, glassmorphic system monitor widget (plasmoid) for **KDE Plasma 6** featuring real-time resource tracking with a modern Cyberpunk theme.

This is a modified version of **Modern SysMonitor** by **Joao Gabriel Medeiros** (all credit for the original design and code goes to him). The original widget only supported Nvidia GPUs (through `nvidia-smi`). This version reads AMD GPUs directly from the kernel (`/sys`), keeps the Nvidia support, and adds disks, a CPU fan row, optional extra GPU details and a settings page.

## Features

- **Network Speed**: Live download/upload speed tracking visualized in smooth, responsive wave area charts.
- **CPU**: Real-time core load displayed in a glowing segmented bar, alongside CPU temperature using a smooth horizontal gradient bar. The CPU fan speed is shown too once the CPU fan is known (see below).
- **RAM**: Memory utilization (used vs total GB) shown with a 26-segment level bar.
- **GPU (AMD and Nvidia)**: Utilization and temperature.
  - **AMD**: read from `/sys` (amdgpu driver). No extra tools needed. If the system has more than one AMD GPU (for example an APU plus a discrete card), the one with the most VRAM is shown.
  - **Nvidia**: read through `nvidia-smi`, as in the original widget.
- **VRAM**: GPU memory consumption.
- **GPU details (More button)**: press **▾ More** in the GPU card to see junction and memory temperature, core and memory clock, fan speed and power draw. Values a GPU does not report are shown as `N/A`.
- **Disks**: one block per physical disk with a mounted filesystem (partitions, LUKS/LVM and btrfs subvolumes are grouped under their disk): model name, temperature and used/total space.
- **Settings**: choose which cards are shown, the update interval, and which fan is the CPU fan. If the widget is shorter than its cards, the content scrolls with the mouse wheel.
- **Glassmorphism Design**: Semi-transparent dark background with fine glowing borders, utilizing native Breeze system vector icons (`Kirigami.Icon`).

## Requirements

- **KDE Plasma**: Version 6.0 or higher.
- **AMD GPU**: the `amdgpu` kernel driver (the default on Linux). Nothing else to install.
- **Nvidia GPU** (optional): `nvidia-smi` must be installed.
- **lm_sensors**: Configured on the system for CPU temperatures.
- **Python 3**: For running the lightweight, non-blocking stats collection script.

### CPU fan and disk temperatures

Everything is read from the kernel's hwmon interface, so the sensors only show up if the kernel has a driver for them:

- **NVMe drives**: temperatures work out of the box.
- **SATA SSD/HDD temperatures**: load the `drivetemp` module once with `sudo modprobe drivetemp`, and to keep it after a reboot: `echo drivetemp | sudo tee /etc/modules-load.d/drivetemp.conf`.
- **CPU fan**: needs the driver of the motherboard's sensor chip (for example `nct6775` for many MSI/ASRock/Gigabyte boards, `it87` for some Gigabyte boards). Running `sudo sensors-detect` tells you which one; `sensors` should then list `fan1`, `fan2`, ...

Most boards do not name their fans, so open the widget settings and pick the CPU fan number (the numbers match `fan1`, `fan2`, ... in the output of `sensors`; an unplugged header reads 0 RPM). If the board does name it (a label containing "cpu"), the "Automatic" setting finds it.

## Installation

1. Download the `.plasmoid` file, or use the KDE Store / "Get New Widgets" dialog.
2. To install from a terminal:
   ```bash
   kpackagetool6 --type Plasma/Applet --install org.kde.plasma.sysmonitor.modern.plus.plasmoid
   ```
   To update an existing install, use `--upgrade` instead of `--install`.
3. Right-click on your Desktop/Panel -> **Add Widgets** -> Search for **Modern SysMonitor Plus** and add it.

## Packaging for KDE Store

To publish this widget on the [KDE Store (store.kde.org)](https://store.kde.org/), bundle it into a `.plasmoid` file (a standard ZIP file of the project folder):

```bash
zip -r org.kde.plasma.sysmonitor.modern.plus.plasmoid contents metadata.json README.md
```

Then upload the generated `.plasmoid` file under the **Plasma 6 Widgets** category.

## Changes compared to the original

- AMD GPU support through `/sys` (usage, VRAM, temperature), with automatic choice of the GPU with the most VRAM.
- Optional GPU details: junction/memory temperature, clocks, fan and power.
- New Disks card (temperature and usage) and an optional CPU fan row.
- New settings page: visible cards, update interval, CPU fan number. The cog icon in the header opens it.
- The content scrolls when the widget is shorter than the visible cards.
- The stats script is started through `python3`, so it does not depend on the executable bit.
- Nvidia support kept (with the same extra details where `nvidia-smi` provides them).

## Security & Best Practices

- **Zero hardcoded credentials**: The script reads only hardware stats and does not use or store any authentication tokens.
- **Local state**: The temporary state used to calculate delta network/CPU usage (and a short disk cache) is stored in `/tmp/sysmonitor_state.json`.
- **Privacy**: No telemetry, analytics, or external web requests are made.

## License

GPL-2.0-or-later. Based on Modern SysMonitor by Joao Gabriel Medeiros. Modified by UnsaidSpeech.
