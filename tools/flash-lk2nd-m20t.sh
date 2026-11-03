#!/bin/sh
# Flash the M20-T lk2nd image and set up the Android slot.
#
# Run from the host with the device in Android (adb root available).
#
#   adb root
#   sh tools/flash-lk2nd-m20t.sh /path/to/lk2nd-m20t.img [/path/to/android-boot.img]
#
# What it does (all writes are dd on named partitions, no fastboot needed):
#   1. backs up the first 1 MiB of "boot" and the whole "recovery" partition
#      to /sdcard/m20t-backup-<timestamp>/
#   2. writes the new lk2nd image at offset 0 of "boot" (lk2nd lives in the
#      first 512 KiB; `fastboot flash boot` under lk2nd writes at +512 KiB)
#   3. optional: writes the stock Android boot image to "recovery"
#      (this is the "Android" slot used by the lk2nd menu)
#   4. verifies md5 of both partitions against what was written
#
# Recovery if the new lk2nd does not come up: EDL restore of the old boot
# partition (private/artifacts-20261031/lk2nd-msm8909-patched.img) or the
# stock boot.img dump.

set -eu

LK2ND_IMG=${1:?usage: flash-lk2nd-m20t.sh <lk2nd-m20t.img> [android-boot.img]}
ANDROID_IMG=${2:-}
TS=$(date +%Y%m%d-%H%M%S)
BACKUP=/sdcard/m20t-backup-$TS

sh_dev() {
	adb shell "$@"
}

part_dev() {
	# $1 = partition name -> prints /dev/block/<dev> on the device
	sh_dev "for u in /sys/class/block/mmcblk0p*/uevent; do
		grep -q '^PARTNAME=$1\$' \$u && echo /dev/\$(basename \$(dirname \$u)) && break
	done"
}

echo "== device =="
adb wait-for-device
sh_dev id
sh_dev "mount | grep -q ' /sdcard ' && echo sdcard-ok || echo sdcard-missing"

BOOT=$(part_dev boot)
RECOVERY=$(part_dev recovery)
[ -n "$BOOT" ] || { echo "FATAL: boot partition not found"; exit 1; }
echo "boot=$BOOT recovery=${RECOVERY:-none}"

echo "== backup =="
sh_dev "mkdir -p $BACKUP"
sh_dev "dd if=$BOOT of=$BACKUP/boot-head-1MiB.bin bs=1024 count=1024 2>/dev/null"
if [ -n "$RECOVERY" ]; then
	sh_dev "dd if=$RECOVERY of=$BACKUP/recovery.bin bs=1024 2>/dev/null"
fi
sh_dev "ls -l $BACKUP"

echo "== push =="
adb push "$LK2ND_IMG" /data/local/tmp/lk2nd-m20t.img
LK2ND_MD5=$(md5sum "$LK2ND_IMG" | cut -d' ' -f1)
sh_dev "[ \"\$(md5sum /data/local/tmp/lk2nd-m20t.img | cut -d' ' -f1)\" = \"$LK2ND_MD5\" ] \
	&& echo 'push md5 ok' || { echo 'FATAL: push md5 mismatch'; exit 1; }"

if [ -n "$ANDROID_IMG" ] && [ -n "$RECOVERY" ]; then
	adb push "$ANDROID_IMG" /data/local/tmp/android-boot.img
	ANDROID_MD5=$(md5sum "$ANDROID_IMG" | cut -d' ' -f1)
	sh_dev "[ \"\$(md5sum /data/local/tmp/android-boot.img | cut -d' ' -f1)\" = \"$ANDROID_MD5\" ] \
		&& echo 'android push md5 ok' || { echo 'FATAL: push md5 mismatch'; exit 1; }"
fi

echo "== write lk2nd (boot offset 0) =="
sh_dev "dd if=/data/local/tmp/lk2nd-m20t.img of=$BOOT bs=2048 conv=notrunc 2>/dev/null"
sh_dev "sync"
sh_dev "[ \"\$(dd if=$BOOT bs=2048 count=$(( ($(stat -c%s "$LK2ND_IMG" 2>/dev/null || wc -c < "$LK2ND_IMG") + 2047) / 2048 )) 2>/dev/null | md5sum | cut -d' ' -f1)\" = \"\$(dd if=/data/local/tmp/lk2nd-m20t.img bs=2048 2>/dev/null | md5sum | cut -d' ' -f1)\" ] \
	&& echo 'boot write verify ok' || echo 'WARN: boot write verify differs'"

if [ -n "$ANDROID_IMG" ] && [ -n "$RECOVERY" ]; then
	echo "== write Android slot (recovery) =="
	sh_dev "dd if=/data/local/tmp/android-boot.img of=$RECOVERY bs=2048 conv=notrunc 2>/dev/null"
	sh_dev "sync"
	sh_dev "echo recovery written"
fi

echo "== done =="
echo "reboot now:        adb reboot"
echo "expected:          lk2nd menu with Reboot / Android / Linux / Bootloader / EDL / Shutdown"
echo "check state block: lk2nd fastboot: fastboot oem m20t-state"
