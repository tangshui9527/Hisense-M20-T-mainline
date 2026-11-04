# m20-t-mainline

Mainline Linux for the **Hisense M20-T** (Uniscope ODM, **MSM8909 / Snapdragon 210**,
stock Android 4.4.4, soc_id 245/0xf5). Target system: a minimal **headless Linux
server** (USB network + SSH, WiFi later) — no display / touch / audio work —
the phone acts as a boot-and-serve box.

## Status (2026-11-04)

**lk2nd boot menu + stock-Android slot fully working on device.**

* boot layout: **lk2nd 23.1 `lk2nd-msm8909` + M20-T patch** at `boot` offset 0;
  the stock-Android image lives at `boot + 512 KiB` (the "slot"); the boot
  menu auto-continues after **30 s** (wall clock — `thread_sleep(1)` costs
  ~10 ms on this platform, never use tick counters for timeouts)
* menu (volume keys navigate, long-press selects): **Android** (boots the
  slot), Recovery (stock recovery image), Linux (mainline test slot, boot
  attempts counted, fastboot fallback), Bootloader, EDL, Shutdown, Reboot
* the stock-Android slot image = the original (ADB-modified) boot image
  content repacked with `mkbootimg` (clean header) — **the original ODM
  header is rejected by lk2nd**; the DT section must stay **QCDT**
  (lk2nd's dev_tree code does not accept plain FDT in the slot)
* wireless adb auto-starts: the slot ramdisk's `default.prop` gained
  `service.adb.tcp.port=5555` (see `tools/patch-ramdisk-prop.py`)
* **boot partition is 31 MiB per the GPT** (not 32): never write past its
  end; the lk2nd-m20t state block lives in the partition's LAST sector
* mainline kernel status unchanged: the 7.0-based msm8909 kernel
  ([weikaizhi4/linux](https://github.com/weikaizhi4/linux) @ `410d5647` +
  [ufi210-debian](https://github.com/3899/ufi210-debian) reference config,
  validated on the same SoC soc_id 245) hangs in early boot; RAM-booted via
  `fastboot boot` for testing. A DEBUG_LL "RAM console" patch (earlyprintk →
  phys 0x8f001000) is in the build to capture the early boot log.

## Build

GitHub Actions on push — see `.github/workflows/build.yml`. Artifacts:
`m20t-boot.img` (lk2nd layout, raw zu02 DTB), `m20t-qcom-msm8909-nokia-leo.img`
(board-bisection variant), `zImage`, DTB, modules, initramfs.

## Boot chain notes (M20-T specific, reverse-engineered)

* stock `aboot` requires the DT segment of a boot image to be a **dtbTool
  "QCDT" table** (magic `0x54444351`); a bare FDT blob is rejected
  ("Bad magic in device tree table") and the device falls back to its own
  fastboot (USB `18d1:d00d`) without ever launching the kernel —
  `tools/wrap-dt-qcdt.py` wraps a DTB into a QCDT v3 single-entry table
  (`soc=0xf5, board=0x1000b, subtype=0`, the stock-selected dtb17 entry)
* the stock aboot injects `bootargs`/initrd and the **DDR size into a node
  named exactly `/memory`** (exact-path lookup; `memory@80000000` does not
  match) — keep that node name in any board DTS
* lk2nd occupies the first 512 KiB of `boot`; the real boot image is flashed
  at `boot + 512 KiB` (`fastboot flash boot` handles the offset)
* lk2nd needs the QCDT wrapper too (`fastboot boot` with a bare-DTB image is
  rejected with "dtb not found")
* the stock bootloader accepts unsigned boot images (no secboot fuse blown);
  no fastboot flash/boot commands exist in stock (getvar/download only)

## Repo layout

| path | content |
|---|---|
| `device/qcom-msm8909-hisense-m20t.dts` | board device tree (6.12-era; port to the 7.0 tree pending — see `patches-msm8909-zu02-dw01.patch` for the minimal-board pattern) |
| `configs/msm8909-reference.config` | kernel config proven on soc_id 245 by ufi210-debian |
| `patches-msm8909-zu02-dw01.patch` | minimal 8909 board dts + imem reboot-mode pattern (applies to the 7.0 tree) |
| `kernel-romconsole.patch` | DEBUG_LL → RAM console (early-hang post-mortem) |
| `tools/` | mkbootimg, QCDT wrapper |
| `initramfs/` | RAM-root initramfs: USB NCM gadget (builtin) + telnetd; host side `telnet 172.16.42.1` (host IP `172.16.42.2/24`) |
| `.github/workflows/build.yml` | CI: kernel+dtb+modules+initramfs+images |

## Installation / recovery

lk2nd route: flash `lk2nd-msm8909.img` (from
[msm8916-mainline/lk2nd releases](https://github.com/msm8916-mainline/lk2nd/releases))
to `boot`, then `fastboot flash boot m20t-boot.img` under lk2nd.
Stock route (root+dd) and full partition forensics: `docs/install.md`.
Recovery from any state: EDL (9008) firehose write of the stock `boot`
partition backup.

License: GPL-2.0-only (kernel-adjacent tooling; DTS via upstream).
