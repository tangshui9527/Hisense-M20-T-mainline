#!/usr/bin/env bash
# rootfs/build.sh -- Build a minimal Alpine Linux rootfs tarball for MSM8909 Hisense M20-T
# Installs openrc, dropbear (SSH), wpa_supplicant, and pre-configures Wi-Fi and root credentials.
set -euo pipefail

ALPINE_VER="v3.21"
MINIROOTFS_VER="3.21.0"
ARCH="armhf"
ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/releases/${ARCH}/alpine-minirootfs-${MINIROOTFS_VER}-${ARCH}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[rootfs] Downloading Alpine minirootfs ${MINIROOTFS_VER} (${ARCH})..."
curl -fSL -o "$WORK/minirootfs.tar.gz" "$ROOTFS_URL"

TARGET="$WORK/rootfs"
mkdir -p "$TARGET"
tar -xzf "$WORK/minirootfs.tar.gz" -C "$TARGET"

# Locate and configure QEMU user-static for armhf chroot emulation
QEMU_BIN=""
for candidate in /usr/bin/qemu-arm-static /usr/bin/qemu-arm /usr/libexec/qemu-binfmt/arm-binfmt-P; do
    if [ -f "$candidate" ]; then
        QEMU_BIN="$candidate"
        break
    fi
done

if [ -n "$QEMU_BIN" ]; then
    echo "[rootfs] Using QEMU binary: $QEMU_BIN"
    mkdir -p "$TARGET/usr/bin"
    cp "$QEMU_BIN" "$TARGET/usr/bin/qemu-arm-static"
    chmod +x "$TARGET/usr/bin/qemu-arm-static"
fi

# DNS configuration for chroot
mkdir -p "$TARGET/etc"
echo "nameserver 1.1.1.1" > "$TARGET/etc/resolv.conf"
echo "nameserver 8.8.8.8" >> "$TARGET/etc/resolv.conf"

# Alpine repositories
cat <<'EOF' > "$TARGET/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/v3.21/main
https://dl-cdn.alpinelinux.org/alpine/v3.21/community
EOF

# Install essential services via QEMU
echo "[rootfs] Installing packages via chroot..."
chroot "$TARGET" /sbin/apk update
chroot "$TARGET" /sbin/apk add --no-cache \
    openrc \
    dropbear \
    dropbear-openrc \
    wpa_supplicant \
    wpa_supplicant-openrc \
    wireless-tools \
    iproute2 \
    dhcpcd \
    util-linux-misc \
    e2fsprogs \
    curl \
    htop \
    chrony \
    chrony-openrc \
    libgpiod \
    bluez \
    bluez-openrc \
    bluez-deprecated \
    ca-certificates

# Clean up QEMU binary from target
rm -f "$TARGET/usr/bin/qemu-arm-static"

# Set root password to 'toor'
echo "root:toor" | chroot "$TARGET" /usr/sbin/chpasswd

# Configure hostname
echo "m20t-server" > "$TARGET/etc/hostname"

cat <<'EOF' > "$TARGET/etc/hosts"
127.0.0.1   localhost m20t-server
::1         localhost m20t-server
EOF

# Automatic kernel module loading
mkdir -p "$TARGET/etc"
cat <<'EOF' > "$TARGET/etc/modules"
af_packet
ipv6
qcom_wcnss_pil
wcn36xx
btqcomsmd
EOF

# qrtr-ns: static cross-build (kernel QRTR_SMD is built-in; the nameserver
# is required so the modem can discover the host rmtfs service)
if [ ! -f "$TARGET/usr/sbin/qrtr-ns" ]; then
    echo "[rootfs] cross-building qrtr-ns..."
    git clone -q https://github.com/linux-msm/qrtr /tmp/qrtr-src
    git -C /tmp/qrtr-src checkout -q 9dc7a88548c2
    mkdir -p "$TARGET/usr/sbin"
    ${CROSS}gcc -static -I/tmp/qrtr-src/lib -o "$TARGET/usr/sbin/qrtr-ns" \
        /tmp/qrtr-src/src/ns.c /tmp/qrtr-src/lib/qrtr.c /tmp/qrtr-src/src/addr.c \
        /tmp/qrtr-src/src/hash.c /tmp/qrtr-src/src/map.c 2>/dev/null \
    || ${CROSS}gcc -static -I/tmp/qrtr-src -I/tmp/qrtr-src/lib \
        -o "$TARGET/usr/sbin/qrtr-ns" /tmp/qrtr-src/src/*.c /tmp/qrtr-src/lib/*.c
fi

# bluetoothd must start AFTER dbus (parallel start races -> daemon exits ->
# OpenRC marks it crashed and it never comes back)
mkdir -p "$TARGET/etc/conf.d"
echo 'rc_need="dbus"' > "$TARGET/etc/conf.d/bluetooth"

# Local startup script for guaranteed Wi-Fi connection
mkdir -p "$TARGET/etc/local.d"
cat <<'EOF' > "$TARGET/etc/local.d/wifi.start"
#!/bin/sh
ip link set wlan0 address 00:0a:f5:2f:33:9c 2>/dev/null || true
ip link set wlan0 up 2>/dev/null || true
if ! pidof wpa_supplicant >/dev/null; then
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || true
fi
if ! ip addr show wlan0 | grep -q "inet 192"; then
    udhcpc -b -i wlan0 2>/dev/null || true
fi
sleep 2
chronyc makestep 2>/dev/null || true
EOF
chmod +x "$TARGET/etc/local.d/wifi.start"

# Local startup script to turn off display & backlight for headless operation
cat <<'EOF' > "$TARGET/etc/local.d/screen-off.start"
#!/bin/sh
# Turn off display backlight and panel to save power on headless server
# GPIO 37 = Backlight Enable (MSM TLMM)
# GPIO 25 = Display Panel Reset (MSM TLMM)
# MPP 2 (offset 1) = Backlight PWM (PM8909)
if which gpioset >/dev/null 2>&1; then
    gpioset -c gpiochip0 -z 37=0 >/dev/null 2>&1 &
    gpioset -c gpiochip0 -z 25=0 >/dev/null 2>&1 &
    gpioset -c gpiochip1 -z 1=0 >/dev/null 2>&1 &
fi
EOF
chmod +x "$TARGET/etc/local.d/screen-off.start"

# Local startup script to bring up Bluetooth adapter
cat <<'EOF' > "$TARGET/etc/local.d/bluetooth.start"
#!/bin/sh
if ! hciconfig hci0 2>/dev/null | grep -q 'UP RUNNING'; then
    hciconfig hci0 reset 2>/dev/null || true
    hciconfig hci0 up 2>/dev/null || true
fi
EOF
chmod +x "$TARGET/etc/local.d/bluetooth.start"

# zram swap (512M) — 895 MB RAM is tight for a server
cat <<'EOF' > "$TARGET/etc/local.d/zram.start"
#!/bin/sh
modprobe zram 2>/dev/null || true
[ -b /dev/zram0 ] || exit 0
[ "$(cat /proc/swaps | grep -c zram)" = "0" ] || exit 0
echo 512M > /sys/block/zram0/disksize
mkswap /dev/zram0 >/dev/null 2>&1 && swapon /dev/zram0
EOF
chmod +x "$TARGET/etc/local.d/zram.start"

# Hardware watchdog feeder (PM8916 PON WDT, 60 s) — auto-reboot on hang
cat <<'EOF' > "$TARGET/etc/local.d/watchdog.start"
#!/bin/sh
[ -c /dev/watchdog ] || exit 0
busybox watchdog -t 10 /dev/watchdog &
EOF
chmod +x "$TARGET/etc/local.d/watchdog.start"

# Clear the lk2nd boot-attempt counter (state block = last sector of boot);
# Linux reaching this point means the boot succeeded.
cat <<'EOF' > "$TARGET/etc/local.d/lk2nd-clear.start"
#!/bin/sh
B=/dev/mmcblk0p20
SZ=$(cat /sys/block/mmcblk0/mmcblk0p20/size 2>/dev/null) || exit 0
dd if=$B of=/tmp/m20t-state.bin bs=512 skip=$((SZ - 1)) count=1 2>/dev/null || exit 0
[ "$(xxd -p -l 4 /tmp/m20t-state.bin)" = "5430324d" ] || exit 0
printf "\000" | dd of=$B bs=1 seek=$(((SZ - 1) * 512 + 4)) conv=notrunc 2>/dev/null
sync
EOF
chmod +x "$TARGET/etc/local.d/lk2nd-clear.start"

# USB composite gadget: serial console (ttyGS0/ACM) + NCM network together
cat <<'EOF' > "$TARGET/etc/local.d/usb-gadget.start"
#!/bin/sh
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config 2>/dev/null || exit 0
# remove the initramfs g1 gadget (ACM only) if it holds the UDC
G1=/sys/kernel/config/usb_gadget/g1
if [ -d $G1 ]; then
    echo "" > $G1/UDC 2>/dev/null
    rm -f $G1/configs/c.1/f1 2>/dev/null
    rmdir $G1/configs/c.1/strings/0x409 $G1/configs/c.1/strings $G1/configs/c.1 \
          $G1/functions/acm.usb0 $G1/strings/0x409 $G1/strings $G1 2>/dev/null
fi
G=/sys/kernel/config/usb_gadget/m20t
mkdir -p $G/functions/acm.0 $G/functions/ncm.0 $G/configs/c.1 2>/dev/null || exit 0
echo 0x05c6 > $G/idVendor 2>/dev/null
echo 0x9025 > $G/idProduct 2>/dev/null
ln -sf $G/functions/acm.0 $G/configs/c.1/f1 2>/dev/null || true
ln -sf $G/functions/ncm.0 $G/configs/c.1/f2 2>/dev/null || true
n=0
while [ $n -lt 20 ]; do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    [ -n "$UDC" ] && break
    sleep 1; n=$((n + 1))
done
[ -n "$UDC" ] && echo $UDC > $G/UDC 2>/dev/null
EOF
chmod +x "$TARGET/etc/local.d/usb-gadget.start"

# Cellular modem autostart: firmware lives on the modem partition (vfat);
# mss PIL (qcom_q6v5_mss) loads mba.mbn + modem.mdt/bXX from /lib/firmware.
cat <<'EOF' > "$TARGET/etc/local.d/modem.start"
#!/bin/sh
[ -d /sys/class/remoteproc/remoteproc1 ] || { modprobe qcom_q6v5_mss 2>/dev/null; sleep 1; }
R=/sys/class/remoteproc/remoteproc1
[ -d $R ] || exit 0
[ "$(cat $R/state)" = "running" ] && exit 0
FW=/lib/firmware
if [ ! -f $FW/modem.mdt ] || [ ! -f $FW/modem.b22 ]; then
    mkdir -p /mnt/modem
    mount -t vfat -o ro /dev/mmcblk0p1 /mnt/modem 2>/dev/null && \
        cp /mnt/modem/image/mba.mbn /mnt/modem/image/modem.* $FW/ 2>/dev/null
    umount /mnt/modem 2>/dev/null
fi
echo start > $R/state 2>/dev/null
EOF
chmod +x "$TARGET/etc/local.d/modem.start"

# eMMC longevity: noatime root + weekly fstrim
echo "/dev/mmcblk0p29	/	ext4	defaults,noatime	0 1" > "$TARGET/etc/fstab"
mkdir -p "$TARGET/etc/periodic/weekly"
printf "#!/bin/sh\n/sbin/fstrim -v /\n" > "$TARGET/etc/periodic/weekly/fstrim"
chmod +x "$TARGET/etc/periodic/weekly/fstrim"

# Configure chrony NTP to always step time on boot (preventing SSL errors)
mkdir -p "$TARGET/etc/chrony"
cat <<'EOF' > "$TARGET/etc/chrony/chrony.conf"
pool pool.ntp.org iburst
makestep 1 -1
driftfile /var/lib/chrony/chrony.drift
rtcsync
EOF

# Configure OpenRC runlevels
chroot "$TARGET" /sbin/rc-update add devfs sysinit || true
chroot "$TARGET" /sbin/rc-update add dmesg sysinit || true
chroot "$TARGET" /sbin/rc-update add bootmisc boot || true
chroot "$TARGET" /sbin/rc-update add modules boot || true
chroot "$TARGET" /sbin/rc-update add hostname boot || true
chroot "$TARGET" /sbin/rc-update add networking boot || true
chroot "$TARGET" /sbin/rc-update add local default || true
chroot "$TARGET" /sbin/rc-update add chronyd default || true
chroot "$TARGET" /sbin/rc-update add dropbear default || true

# Wi-Fi: wpa_supplicant configuration
mkdir -p "$TARGET/etc/wpa_supplicant"
cat <<'EOF' > "$TARGET/etc/wpa_supplicant/wpa_supplicant.conf"
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="yyds"
    psk="goodnight"
    key_mgmt=WPA-PSK
}
EOF
chmod 600 "$TARGET/etc/wpa_supplicant/wpa_supplicant.conf"

# Network interfaces
cat <<'EOF' > "$TARGET/etc/network/interfaces"
auto lo
iface lo inet loopback

auto wlan0
iface wlan0 inet dhcp
    pre-up ip link set wlan0 address 00:0a:f5:2f:33:9c
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF

# Dropbear configuration: enable password auth, allow root
mkdir -p "$TARGET/etc/dropbear"
mkdir -p "$TARGET/etc/conf.d"
echo 'DROPBEAR_OPTS="-R"' > "$TARGET/etc/conf.d/dropbear"

# Enable USB serial console on ttyGS0 and UART console on ttyMSM0
cat <<'EOF' >> "$TARGET/etc/inittab"

# Serial consoles for M20-T
ttyGS0::respawn:/sbin/getty -L 115200 ttyGS0 vt100
ttyMSM0::respawn:/sbin/getty -L 115200 ttyMSM0 vt100
EOF

# Ensure firmware directory exists
mkdir -p "$TARGET/lib/firmware/wlan/prima"

# Pack rootfs tarball
echo "[rootfs] Packaging alpine-rootfs.tar.gz..."
tar -czf "$SCRIPT_DIR/alpine-rootfs.tar.gz" -C "$TARGET" .
chmod 0644 "$SCRIPT_DIR/alpine-rootfs.tar.gz"
ls -lh "$SCRIPT_DIR/alpine-rootfs.tar.gz"
echo "[rootfs] Alpine rootfs package successfully built!"
