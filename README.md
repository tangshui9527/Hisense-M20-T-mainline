# m20-t-mainline

Mainline Linux for the **Hisense M20-T** (Uniscope ODM, **Qualcomm MSM8909 / Snapdragon 210**, soc_id 245/0xf5).

**Project Target:** A minimal, dedicated **headless Linux server** running Alpine Linux 3.21 on mainline Linux 7.0 with automatic Wi-Fi association and SSH remote access. Android has been completely removed.

---

## Current Status (2026-11-04)

- **System State**: Fully operational dedicated Linux server.
- **Kernel**: Close-to-mainline Linux `7.0.0-msm8909+` (`wip/msm8916/7.0` tree with Hisense M20-T board DTS).
- **Distribution**: Alpine Linux 3.21 (`armhf`, musl libc, OpenRC).
- **Rootfs Persistence**: Stored on internal eMMC `userdata` partition (`/dev/mmcblk0p29`, ext4, ~4.9 GB free).
- **Network**:
  - Wi-Fi (WCN3620 / `wcn36xx`) connects automatically on boot.
  - SSH service (Dropbear) active on port 22 (`root:toor`).
  - Network time sync managed by `chronyd`.
- **Hardware Console**:
  - USB CDC-ACM serial console active on `/dev/ttyGS0` (appears as `/dev/cu.usbmodem*` on macOS) with an interactive root shell for offline emergency access.
- **Bootloader**:
  - Stock `aboot` -> `lk2nd` 23.1 (`boot@0`) -> Mainline Linux package (`boot@+512KiB`).
  - Device Tree wrapped in Qualcomm QCDT v3 table matching board IDs (`0xf5`, `0x1000b`, subtype 0).

---

## Directory Structure

| Path | Description |
| :--- | :--- |
| `device/` | Device tree source (`qcom-msm8909-hisense-m20t.dts`) |
| `initramfs/` | Two-stage initramfs (clears watchdog, sets up USB CDC-ACM console, mounts userdata ext4 rootfs, `switch_root`) |
| `rootfs/` | Alpine Linux armhf rootfs builder (`build.sh`) |
| `configs/` | Kernel reference configurations |
| `tools/` | Image packaging scripts (`wrap-dt-qcdt.py`, `mkbootimg.py`, etc.) |
| `.github/workflows/` | Automated CI pipeline (`build.yml`) |

---

## Accessing the Live Device

- **SSH (over Wi-Fi)**:
  ```bash
  ssh root@192.168.31.167
  # Password: toor
  ```
- **USB Serial Console (Local Fallback)**:
  ```bash
  screen /dev/cu.usbmodem* 115200
  ```

---

## Building

The entire bootable image is built automatically via GitHub Actions:
- Push to branch `lk2nd-m20t`.
- Download artifact `m20t-qcom-msm8909-hisense-m20t.img`.
- Flash via fastboot:
  ```bash
  fastboot flash boot m20t-qcom-msm8909-hisense-m20t.img
  fastboot reboot
  ```

---

## License

GPL-2.0-only
