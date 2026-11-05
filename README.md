# Hisense-M20-T-mainline

[![CI Build](https://github.com/tangshui9527/Hisense-M20-T-mainline/actions/workflows/build.yml/badge.svg?branch=lk2nd-m20t)](https://github.com/tangshui9527/Hisense-M20-T-mainline/actions/workflows/build.yml)
[![Kernel](https://img.shields.io/badge/Linux-7.0.0--msm8909+-blue.svg)](https://github.com/weikaizhi4/linux)
[![Distro](https://img.shields.io/badge/Alpine%20Linux-3.21%20armhf-teal.svg)](https://alpinelinux.org/)
[![License](https://img.shields.io/badge/License-GPL--2.0-yellow.svg)](LICENSE)

Mainline Linux port for the **Hisense M20-T** (Uniscope ODM, **Qualcomm MSM8909 / Snapdragon 210**, `soc_id 245 / 0xf5`).

This project transforms the old smartphone into an ultra-low-power, dedicated **headless Linux mini-server**. Android has been completely removed in favor of a single-system Alpine Linux distribution running directly on the internal eMMC.

---

## 🌟 Highlights & Features

- **⚡ Ultra-Low Power Consumption (<0.5W)**: Screen backlights, touch panels, cameras, and audio codecs are unpowered. Idle draw is ~0.2W to 0.5W, costing almost nothing (~$0.20/year) in continuous 24/7 operation.
- **🔋 Built-In Natural UPS**: The phone's internal lithium-ion battery functions as an uninterruptible power supply. In the event of a power outage, the server continues running for hours without losing data.
- **🪶 Featherweight Footprint**: Alpine Linux 3.21 with OpenRC consumes only **~34 MB of RAM** at idle out of 895 MB, leaving >840 MB of RAM free for user applications, containers, or services.
- **💾 Full Persistence**: Persistent ext4 root filesystem on internal eMMC `userdata` (`/dev/mmcblk0p29`) with ~4.9 GB free storage.
- **📶 Wireless Auto-Connect**: Automatic connection to configured Wi-Fi on boot via `wcn36xx` driver and Qualcomm PIL firmware.
- **🔄 Cable-Free OTA Firmware Updates**: Flash new kernel and device tree images wirelessly over the local network without needing a USB cable.
- **🛡️ Disaster-Proof Dual-Console**: Primary control via Dropbear SSH over Wi-Fi, with a zero-configuration USB CDC-ACM serial console (`/dev/ttyGS0`) as a plug-and-play offline fallback.

---

## 📊 Hardware Support Matrix

| Peripheral / Component | Subsystem / Driver | Status | Notes |
| :--- | :--- | :---: | :--- |
| **CPU** | 4× Cortex-A7 @ 1.1 GHz | ✅ Working | Full SMP multi-core scaling with `schedutil` |
| **RAM** | 1GB LPDDR3 (`0x80000000`) | ✅ Working | Dynamically mapped via stock aboot `/memory` node |
| **Storage (eMMC)** | SDHC1 (`sdhci-msm-v4`) | ✅ Working | HS200 mode, persistent ext4 rootfs on `/dev/mmcblk0p29` |
| **Wi-Fi** | WCN3620 (`wcn36xx` + PIL) | ✅ Working | Auto-connects on boot with fixed MAC |
| **Bluetooth** | WCN3620 (`btqcomsmd` over SMD) | ✅ Working | BD_ADDR derived, BlueZ 5.79, BLE + BR/EDR discovery & gateway verified |
| **USB Console** | ChipIdea USB2 (`ci_hdrc_msm`) | ✅ Working | CDC-ACM serial gadget on `/dev/ttyGS0` (root shell) |
| **Timekeeping** | PM8909 RTC + `chrony` | ✅ Working | Sub-second NTP synchronization on boot; SSL certs verified |
| **Battery & Power** | PM8909 Autonomous Charger | ✅ Working | Hardware automatically regulates charging when 5V USB is connected |
| **MicroSD Slot** | SDHC2 (`sdhci-msm-v4`) | ⚠️ Partial | Functional in 1-bit mode @ 25MHz; 4-bit bus pending hardware pin cleanup |
| **Cellular Modem** | Hexagon QDSP6 PIL (`qcom_q6v5_mss` + `rmtfs`) | ✅ Working | Firmware loaded, EFS served via qrtr, ModemManager + qmi-utils ready |
| **Display / Audio** | DSI / Codec / Touch | ❌ Omitted | Intentionally disabled to minimize memory and power draw |

---

## 📐 Boot Chain Architecture

```
[Power On]
  │
  ▼
[PBL / SBL1 / RPM / TZ] (Qualcomm factory firmware)
  │
  ▼
[Stock aboot] (Bootloader at /dev/mmcblk0p4)
  │  └─ Validates QCDT table header (magic 0x54444351)
  │
  ▼
[boot partition @ Offset 0]: lk2nd 23.1 (lk2nd-msm8909)
  │  └─ Provides fastboot menu, watchdog reset recovery, chainloads slot
  │
  ▼
[boot partition @ Offset +512 KiB]: Mainline Boot Package
  │  ├─ Linux Kernel 7.0 zImage
  │  ├─ Device Tree Blob (wrapped in QCDT table: soc=0xf5, board=0x1000b)
  │  └─ Stage-1 Initramfs (CPIO)
  │
  ▼
[Stage-1 Initramfs]
  │  ├─ Clears lk2nd boot watchdog retry counter
  │  ├─ Mounts virtual filesystems & spawns USB CDC-ACM console (/dev/ttyGS0)
  │  ├─ Locates persistent partition (/dev/mmcblk0p29)
  │  └─ Executes: switch_root /newroot /sbin/init
  │
  ▼
[Stage-2 Alpine Linux (OpenRC)]
  ├─ modules: Loads qcom_wcnss_pil and wcn36xx
  ├─ local.d/wifi.start: Sets MAC address, runs wpa_supplicant & udhcpc
  ├─ chronyd: Syncs clock over NTP
  └─ dropbear: SSH server listening on port 22
```

---

## 📖 Installation & Flashing Guide

To flash the phone from factory stock Android to Mainline Linux, follow our step-by-step installation guide:  
👉 **[From Stock Android to Mainline Linux (Complete Flashing Guide)](docs/install.md)**

The guide covers:
- Taking a full partition backup before making any changes
- Formatting and deploying the Alpine Linux rootfs onto internal eMMC (`userdata`)
- Flashing the Mainline Linux kernel + QCDT boot package via `root + dd`
- First boot, SSH setup, and disaster recovery via Qualcomm 9008 EDL mode

---

## 🚀 Quick Access

### SSH Login (Over Wi-Fi)
Once the server is booted, log in directly from your computer:
```bash
ssh root@<DEVICE_IP>
# Default password: toor
```

### USB Serial Console (Emergency Fallback)
If Wi-Fi is disconnected or misconfigured, connect a USB cable to a host computer:
- **macOS**: `screen /dev/cu.usbmodem* 115200`
- **Linux**: `screen /dev/ttyACM0 115200`

Press Enter to get an interactive, passwordless root shell directly into the system.

---

## 🔄 Firmware Updates: Cable-Free OTA vs. Fastboot

### Option 1: Wireless Over-The-Air (OTA) Update (Recommended)
When you have a new `m20t-boot.img` generated from CI, you can flash it completely wirelessly:

```bash
# 1. Upload image to the device over Wi-Fi
scp m20t-boot.img root@<DEVICE_IP>:/tmp/

# 2. Flash to the kernel slot (boot partition mmcblk0p20 at +512KiB offset) and reboot
ssh root@<DEVICE_IP> "dd if=/tmp/m20t-boot.img of=/dev/mmcblk0p20 seek=1024 bs=512 conv=notrunc && reboot"
```
The device will reboot and come back online with the updated kernel within ~15 seconds.

### Option 2: Wired Fastboot Flashing (Recovery / Fallback)
If the kernel fails to boot and Wi-Fi is unreachable:
1. Hold **Volume Down** on boot to enter the lk2nd fastboot menu.
2. Flash over USB:
   ```bash
   fastboot flash boot m20t-boot.img
   fastboot reboot
   ```

---

## 📁 Repository Structure

```
├── .github/workflows/
│   └── build.yml               # GitHub Actions CI pipeline (Kernel + Rootfs + Packaging)
├── configs/
│   └── msm8909-reference.config # Reference Linux kernel config for MSM8909
├── device/
│   └── qcom-msm8909-hisense-m20t.dts # Hisense M20-T board device tree
├── initramfs/
│   └── init                    # Two-stage initramfs startup script
├── rootfs/
│   └── build.sh                # Alpine Linux armhf minirootfs build script
└── tools/
    ├── mkbootimg.py            # Android boot.img assembler
    └── wrap-dt-qcdt.py         # Wraps FDT blobs into Qualcomm QCDT v3 tables
```

---

## 🛠️ Building with GitHub Actions

The entire build process is containerized and automated in `.github/workflows/build.yml`.
Any push to the `lk2nd-m20t` branch triggers a workflow run that:
1. Clones the close-to-mainline Linux 7.0 kernel tree (`wip/msm8916/7.0`).
2. Compiles `zImage` and device tree blobs (`.dtb`).
3. Wraps the device tree into a Qualcomm QCDT v3 table.
4. Builds the two-stage initramfs and compiles kernel modules.
5. Assembles `m20t-qcom-msm8909-hisense-m20t.img` ready for flashing.

---

## 📜 License

This project is licensed under the **GNU General Public License v2.0** (`GPL-2.0-only`). See [LICENSE](LICENSE) for details.
