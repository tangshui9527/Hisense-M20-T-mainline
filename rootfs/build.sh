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
    busybox-initscripts \
    dropbear \
    dropbear-openrc \
    wpa_supplicant \
    wpa_supplicant-openrc \
    wireless-tools \
    iproute2 \
    dhcpcd \
    e2fsprogs \
    curl \
    htop \
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

# Configure OpenRC runlevels
chroot "$TARGET" /sbin/rc-update add devfs sysinit
chroot "$TARGET" /sbin/rc-update add dmesg sysinit
chroot "$TARGET" /sbin/rc-update add mdev sysinit
chroot "$TARGET" /sbin/rc-update add hwdrivers sysinit

chroot "$TARGET" /sbin/rc-update add bootmisc boot
chroot "$TARGET" /sbin/rc-update add hostname boot
chroot "$TARGET" /sbin/rc-update add networking boot
chroot "$TARGET" /sbin/rc-update add dropbear default

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
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF

# Dropbear configuration: enable password auth, allow root
mkdir -p "$TARGET/etc/dropbear"
mkdir -p "$TARGET/etc/conf.d"
echo 'DROPBEAR_OPTS="-R -w -g"' > "$TARGET/etc/conf.d/dropbear"

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
ls -lh "$SCRIPT_DIR/alpine-rootfs.tar.gz"
echo "[rootfs] Alpine rootfs package successfully built!"
