# Flashing / operating checklist — Hisense M20-T mainline boot

> **2026-10-31:** the primary boot route is now **lk2nd** (flashed at `boot`
> offset 0; kernel images go to `boot + 512 KiB` via `fastboot flash boot`).
> The root+dd flow below remains valid for the stock-aboot route and for
> recovery (EDL write of the stock `boot` backup). See the README for the
> current status.

Device facts proven on 2026-10-29 (serial `2f339cef`):

* `boot` partition = `/dev/block/bootdevice/by-name/boot`, **32 MiB**,
  original MD5 `0e5f1083a10c418c956de9d0c34f2a2d`
* stock bootloader accepts **unsigned / modified** boot images
  (verified: repacked stock image with cmdline marker `m20tlin=1` booted,
  marker visible in `/proc/cmdline`)
* root available on stock ROM: `adb shell "su -c <cmd>"` (no interactive prompt)
* fastboot has no flash/boot/unlock commands — never counts on fastboot

## Flash a CI artifact

Download `out/m20t-boot.img` from the Actions run, then:

```sh
adb push m20t-boot.img /data/local/tmp/
adb shell "su -c 'chmod 644 /data/local/tmp/m20t-boot.img'"
# write -- image is ~<10 MiB; partition is 32 MiB, trailing stock zeros untouched
adb shell "su -c 'dd if=/data/local/tmp/m20t-boot.img of=/dev/block/bootdevice/by-name/boot bs=4096 && sync'"
# verify back-read; md5 must match the local file
adb shell "su -c 'md5 <(dd if=/dev/block/bootdevice/by-name/boot bs=1 count=<size> 2>/dev/null)'"
```

Simpler on-device verify (no process substitution on this old toybox-less ROM):

```sh
adb shell "su -c 'dd if=/dev/block/bootdevice/by-name/boot of=/data/local/tmp/back.img bs=4096 count=\$(\"" \e"$(stat -c%s m20t-boot.img)/4096+1) && md5 /data/local/tmp/back.img'"
adb pull /data/local/tmp/back.img /tmp/ && head -c <size> /tmp/back.img | md5
```

## Expectations after flashing the phase-1 image

* phone boots the mainline kernel — screen stays black (no display driver work),
  no adb (no Android), WiFi not yet configured
* shell via USB: a Linux/macOS host gets an NCM interface; set host IP
  `172.16.42.2/24` and run `telnet 172.16.42.1` (user: none, shell directly)

```
sudo ip addr add 172.16.42.2/24 dev <usb-interface>
telnet 172.16.42.1
# -> /tmp/boot.log holds the bring-up evidence (UDC used, ifconfig, dmesg tail)
```

## Recovery

Stock lives in your backup of 2026-10-29 (`boot.img`, MD5 above). Restore:

```sh
adb push boot.img /data/local/tmp/stock-boot.img
adb shell "su -c 'dd if=/data/local/tmp/stock-boot.img of=/dev/block/bootdevice/by-name/boot bs=4096 && sync'"
adb reboot
```

Worst case (device will not boot at all, no adb): MSM8909 rescue only via
9008/EDL firehose (search ODM keyword `uniscope8909`) — keep the volume-down
(EDL entry) trick in mind; this path was NOT needed so far.

---

# Android slot image (lk2nd second stage) — recipe (2026-11-04)

The M20-T now boots via: PBL → stock aboot → **lk2nd-m20t** (boot @0) →
**Android slot** (boot +512 KiB). The slot image must be an Android boot
image that lk2nd accepts; the stock ODM image fails two checks:

1. **header**: the original header lies (`kernel_size` etc. do not match the
   payload) → repack with `tools/mkbootimg.py` (clean header, same page size
   2048, same cmdline).
2. **DT table**: the DT section must remain the **QCDT** table (lk2nd's
   `dev_tree_validate` requires the QCDT magic and matches entries against
   platform 0xf5 / board 0x1000b / **subtype 0** — the stock table carries
   that as entry #17). Do not replace it with a plain FDT.

### Build (all from the original boot backup)

```sh
# 1. split the original boot image (kernel / ramdisk / QCDT) — see header at
#    offset 8..40 (sizes), page size at 36; sections are page-aligned
# 2. repack:
python3 tools/mkbootimg.py \
  --kernel orig-kernel.bin --ramdisk orig-ramdisk.gz --dtb orig-dt.qcdt \
  --cmdline '<original cmdline from header offset 64>' \
  --bootimg stock-android-slot.img
# 3. optional: wireless-ADB auto start (patch default.prop inside the ramdisk)
python3 tools/patch-ramdisk-prop.py orig-ramdisk.gz ramdisk-adb-tcp.gz \
  --append "service.adb.tcp.port=5555"
#    … then rebuild with --ramdisk ramdisk-adb-tcp.gz
# 4. verify the QCDT table survives:
python3 tools/check-qcdt.py stock-android-slot.img
```

### Flash

Slot = `boot + 512 KiB`. From lk2nd fastboot:
`fastboot flash boot stock-android-slot.img` (lk2nd redirects `boot` to the
slot). From stock Android (root): `dd bs=2048 seek=256` onto the boot block
device. **boot is 31 MiB per GPT — do not write past its end** (the lk2nd
state block occupies the last sector).

### Current on-device build (2026-11-04)

* `boot @0`: lk2nd-m20t (lk2nd 23.1 + `patches/lk2nd-m20t-23.1.patch`, CI
  build of commit `0a2ce01`, md5 `66fd4eb4…`) — menu: Android / Recovery /
  Linux / Bootloader / EDL / Shutdown / Reboot, 30 s wall-clock auto-continue
* `boot +512K`: stock Android slot (original kernel+ramdisk+QCDT, clean
  header, wireless-ADB auto start, md5 `696429a9…`)
* boot failsafe: EDL-write of the original boot backup (`0e5f1083…`)
  restores the stock chain at any time
