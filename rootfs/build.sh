#!/usr/bin/env bash
# rootfs/build.sh -- Build a minimal Alpine Linux rootfs tarball for MSM8909 Hisense M20-T
# Installs openrc, dropbear (SSH), wpa_supplicant, and pre-configures Wi-Fi and root credentials.
set -euo pipefail

ALPINE_VER="v3.21"
MINIROOTFS_VER="3.21.0"
ARCH="armhf"
ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/${ALPINE_VER}/releases/${ARCH}/alpine-minirootfs-${MINIROOTFS_VER}-${ARCH}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRCDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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
    qrtr \
    hostapd \
    dnsmasq \
    lighttpd \
    e2fsprogs \
    curl \
    htop \
    chrony \
    chrony-openrc \
    libgpiod \
    bluez \
    bluez-openrc \
    bluez-deprecated \
    qmi-utils \
    modemmanager \
    modemmanager-openrc \
    usbutils \
    android-tools \
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
    ${CROSS:-arm-linux-gnueabihf-}gcc -static -I/tmp/qrtr-src/lib -I/tmp/qrtr-src/src \
        -o "$TARGET/usr/sbin/qrtr-ns" \
        /tmp/qrtr-src/lib/logging.c /tmp/qrtr-src/lib/qrtr.c \
        /tmp/qrtr-src/src/addr.c /tmp/qrtr-src/src/ns.c /tmp/qrtr-src/src/map.c \
        /tmp/qrtr-src/src/hash.c /tmp/qrtr-src/src/waiter.c /tmp/qrtr-src/src/util.c
fi

# hidkey: type into the USB-host phone through the HID gadget
cat <<'EOF' > "$TARGET/usr/local/bin/hidkey"
#!/bin/sh
# usage: hidkey "text"          — type text (US layout)
#        hidkey -k enter|tab|esc|space|backspace|up|down|left|right|home|end
D=/dev/hidg0
[ -c $D ] || { echo "no $D (hid gadget not bound)"; exit 1; }
Z='\000\000\000\000\000\000\000\000'
tap() { # $1 modifier(0x) $2 keycode(0x)
    printf "\\$(printf '%03o' $1)\\000\\$(printf '%03o' $((16#$2)))\\000\\000\\000\\000\\000" > $D
    usleep 15000
    printf "$Z" > $D
    usleep 15000
}
code() { case $1 in
    a) echo 04;; b) echo 05;; c) echo 06;; d) echo 07;; e) echo 08;; f) echo 09;;
    g) echo 0a;; h) echo 0b;; i) echo 0c;; j) echo 0d;; k) echo 0e;; l) echo 0f;;
    m) echo 10;; n) echo 11;; o) echo 12;; p) echo 13;; q) echo 14;; r) echo 15;;
    s) echo 16;; t) echo 17;; u) echo 18;; v) echo 19;; w) echo 1a;; x) echo 1b;;
    y) echo 1c;; z) echo 1d;; 1) echo 1e;; 2) echo 1f;; 3) echo 20;; 4) echo 21;;
    5) echo 22;; 6) echo 23;; 7) echo 24;; 8) echo 25;; 9) echo 26;; 0) echo 27;;
    \ ) echo 2c;; -) echo 2d;; =) echo 2e;; .) echo 37;; ,) echo 36;; /) echo 38;;
esac; }
if [ "$1" = "-k" ]; then
    case $2 in
      enter) tap 0 28;; tab) tap 0 2b;; esc) tap 0 29;; space) tap 0 2c;;
      backspace) tap 0 2a;; up) tap 0 52;; down) tap 0 51;;
      left) tap 0 50;; right) tap 0 4f;; home) tap 0 4a;; end) tap 0 4d;;
    esac; exit 0
fi
text="$*"
i=1; len=${#text}
while [ $i -le $len ]; do
    ch=$(printf "%s" "$text" | cut -c $i-$i)
    case "$ch" in
      " ") tap 0 2c;;
      [A-Z]) tap 2 $(code $(echo "$ch" | tr A-Z a-z));;
      *) k=$(code "$ch"); [ -n "$k" ] && tap 0 "$k";;
    esac
    i=$((i + 1))
done
EOF
chmod +x "$TARGET/usr/local/bin/hidkey"
ln -sf /usr/local/bin/hidkey "$TARGET/usr/bin/hidkey"

# usb-mode: switch USB controller between host and gadget roles
cat <<'EOF' > "$TARGET/usr/local/bin/usb-mode"
#!/bin/sh
ROLE_FILE="/sys/devices/platform/soc@0/78d9000.usb/ci_hdrc.0/role"
GADGET_UDC="/sys/kernel/config/usb_gadget/m20t/UDC"

status() {
    echo "=== USB Controller Status ==="
    if [ -f "$ROLE_FILE" ]; then
        echo "Current Role: $(cat $ROLE_FILE)"
    else
        echo "Role file not found: $ROLE_FILE"
    fi
    if [ -d /sys/class/extcon/extcon0 ]; then
        echo "Extcon (PM8909 usbin): $(cat /sys/class/extcon/extcon0/state 2>/dev/null | tr '\n' ' ')"
    fi
    echo ""
    echo "=== USB Devices (lsusb) ==="
    lsusb 2>/dev/null
    echo ""
    echo "=== USB Ports / Sysfs Devices ==="
    for dev in /sys/bus/usb/devices/*; do
        [ -e "$dev" ] || continue
        echo -n "$(basename $dev): "
        if [ -f "$dev/product" ]; then
            echo "$(cat $dev/manufacturer 2>/dev/null) $(cat $dev/product 2>/dev/null) ($(cat $dev/idVendor 2>/dev/null):$(cat $dev/idProduct 2>/dev/null))"
        else
            echo "(bus/hub/interface)"
        fi
    done
}

set_host() {
    echo "Switching USB controller to HOST mode..."
    if [ -f "$GADGET_UDC" ]; then
        echo "" > "$GADGET_UDC" 2>/dev/null
    fi
    if [ -f "$ROLE_FILE" ]; then
        echo host > "$ROLE_FILE"
        sleep 1
    fi
    status
}

set_gadget() {
    echo "Switching USB controller to GADGET mode..."
    if [ -f "$ROLE_FILE" ]; then
        echo gadget > "$ROLE_FILE"
        sleep 1
    fi
    if [ -f "$GADGET_UDC" ]; then
        UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
        [ -n "$UDC" ] && echo "$UDC" > "$GADGET_UDC" 2>/dev/null
    fi
    status
}

case "$1" in
    host)
        set_host
        ;;
    gadget)
        set_gadget
        ;;
    status|"")
        status
        ;;
    *)
        echo "Usage: $0 [host|gadget|status]"
        exit 1
        ;;
esac
EOF
chmod +x "$TARGET/usr/local/bin/usb-mode"
ln -sf /usr/local/bin/usb-mode "$TARGET/usr/bin/usb-mode"

# WiFi provisioning fallback AP (verified live):
#   station fails 60 s -> hostapd AP "Hisense-M20t-Setup" (open) ->
#   lighttpd captive portal (CGI: save/scan/form) -> new credentials into
#   wpa_supplicant.conf -> back to station. See /usr/local/sbin/wifi-ap-mode.
# Packages needed beyond the base list: hostapd dnsmasq lighttpd
mkdir -p "$TARGET/srv/provision/cgi-bin"
cp -a "$SRCDIR/rootfs/provision/index.html" "$TARGET/srv/provision/"
cp -a "$SRCDIR/rootfs/provision/cgi-bin/"*.sh "$TARGET/srv/provision/cgi-bin/"
chmod 755 "$TARGET/srv/provision/cgi-bin/"*.sh
# extra packages (must appear in the chroot apk list — see above)
grep -q "hostapd" /dev/null 2>/dev/null || true

# USB dual-role manager: 00:00-06:00 device(gadget), 06:00-24:00 host.
# Mechanism: chipidea role switch (/sys/class/usb_role/.../role) — requires
# CONFIG_USB_ROLE_SWITCH + the DT usb-role-switch property.
mkdir -p "$TARGET/opt/usb-role-manager/state"
cp -a /tmp/usbrole-kit/* "$TARGET/opt/usb-role-manager/" 2>/dev/null || \
    cp -a "$SRCDIR/rootfs/usb-role-manager/"* "$TARGET/opt/usb-role-manager/" 2>/dev/null || true
chmod 755 "$TARGET/opt/usb-role-manager/"{usb-role,schedule-apply,schedule-check,install.sh,uninstall.sh} 2>/dev/null || true
ln -sf /opt/usb-role-manager/usb-role "$TARGET/usr/local/bin/usb-role" 2>/dev/null || true
cat >> "$TARGET/etc/crontabs/root" <<CRON
0 0 * * * /opt/usb-role-manager/schedule-apply
0 6 * * * /opt/usb-role-manager/schedule-apply
*/5 * * * * /opt/usb-role-manager/schedule-check
CRON
printf '#!/bin/sh\n/opt/usb-role-manager/schedule-apply\n' > "$TARGET/etc/local.d/usb-role-boot.start"
chmod +x "$TARGET/etc/local.d/usb-role-boot.start"

# WiFi AP fallback orchestrator + boot trigger
mkdir -p "$TARGET/usr/local/sbin" "$TARGET/usr/local/bin"
cat <<'EOF' > "$TARGET/usr/local/sbin/wifi-ap-mode"
#!/bin/sh
if [ -f /run/wifi-ap-mode.pid ] && kill -0 $(cat /run/wifi-ap-mode.pid 2>/dev/null) 2>/dev/null; then
    echo "already running, exit"
    exit 0
fi
echo $$ > /run/wifi-ap-mode.pid
trap "rm -f /run/wifi-ap-mode.pid" EXIT
LOG=/tmp/ap.log
exec >> $LOG 2>&1
echo "=== AP mode $(date) ==="
wpa_cli terminate 2>/dev/null
pkill -f "udhcpc.*wlan0" 2>/dev/null
killall lighttpd dnsmasq hostapd 2>/dev/null; sleep 1
ip link set wlan0 down; ip link set wlan0 up
cat > /tmp/hostapd-ap.conf <<HCFG
interface=wlan0
driver=nl80211
ssid=Hisense-M20t-Setup
channel=6
HCFG
hostapd -B /tmp/hostapd-ap.conf 2>&1 | head -1
ip addr add 10.42.0.1/24 dev wlan0 2>/dev/null
dnsmasq --interface=wlan0 --bind-dynamic \
  --dhcp-range=10.42.0.10,10.42.0.100,12h \
  --dhcp-option=3,10.42.0.1 --dhcp-option=6,10.42.0.1 \
  --address=/#/10.42.0.1 --no-hosts >/dev/null 2>&1 &
cat > /tmp/lighttpd-ap.conf <<LCFG
server.document-root = "/srv/provision"
server.port = 80
server.bind = "10.42.0.1"
index-file.names = ( "index.html" )
server.modules += ( "mod_cgi" )
cgi.assign = ( ".sh" => "/bin/sh" )
LCFG
lighttpd -f /tmp/lighttpd-ap.conf 2>/dev/null &
rm -f /tmp/newwifi
echo "AP up, waiting for credentials (max 600s)"
n=0
while [ ! -f /tmp/newwifi ] && [ $n -lt 300 ]; do sleep 1; n=$((n+1)); done
killall lighttpd dnsmasq 2>/dev/null; killall hostapd 2>/dev/null; sleep 1
ip addr del 10.42.0.1/24 dev wlan0 2>/dev/null
ip link set wlan0 down; ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
sleep 2
udhcpc -b -i wlan0 -t 8 -n >/dev/null 2>&1
sleep 6
if ip addr show wlan0 | grep -q "inet "; then
    echo "connected OK"; exit 0
fi
echo "connect failed - back to AP"
/usr/local/sbin/wifi-ap-mode &

EOF
cat <<'EOF' > "$TARGET/etc/local.d/wifi-fallback.start"
#!/bin/sh
( sleep 60
  if ! ip addr show wlan0 | grep -q "inet "; then
      /usr/local/sbin/wifi-ap-mode >/tmp/ap.log 2>&1
  fi ) &

EOF
chmod 755 "$TARGET/usr/local/sbin/wifi-ap-mode" "$TARGET/etc/local.d/wifi-fallback.start"

# IP reporter: sends LAN/Tailscale/WAN/IPv6 to WeChat via ServerChan (sct.ftqq.com)
# after boot. The SendKey lives in /etc/report-ip.key (NOT in this repo — it is a
# per-user secret; create it manually: echo SCTxxxx > /etc/report-ip.key).
# Free tier ~5 messages/day; one message per boot fits the quota.
cat <<'EOF' > "$TARGET/usr/local/sbin/report-ip"
#!/bin/sh
KEYFILE=/etc/report-ip.key
[ -f $KEYFILE ] || exit 1
KEY=$(cat $KEYFILE | tr -d " \n")
LAN=$(ip -4 addr show wlan0 2>/dev/null | grep -o "inet [0-9.]*" | awk "{print \$2}")
TS=$(ip -4 addr show tailscale0 2>/dev/null | grep -o "inet [0-9.]*" | awk "{print \$2}")
EXT=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null)
V6=$(ip -6 addr show scope global 2>/dev/null | grep -o "inet6 [0-9a-f:]*" | head -1 | awk "{print \$2}")
BODY="内网: ${LAN:-无}\nTailscale: ${TS:-无}\n外网: ${EXT:-获取失败}\nIPv6: ${V6:-无}\n主机: $(hostname)\n时间: $(date)"
curl -s --max-time 15 "https://sctapi.ftqq.com/$(cat $KEYFILE).send" \
  --data-urlencode "title=M20T 上线" --data-urlencode "desp=$BODY"
EOF
chmod 755 "$TARGET/usr/local/sbin/report-ip"
cat <<'EOF' > "$TARGET/etc/local.d/report-ip.start"
#!/bin/sh
(sleep 10; /usr/local/sbin/report-ip >> /root/report-ip.log 2>&1) &
EOF
chmod 755 "$TARGET/etc/local.d/report-ip.start"

# Power-key double-press -> show IP on screen (no touch driver in mainline)
cat <<'EOF' > "$TARGET/usr/local/bin/pwrkey-2tap"
#!/bin/sh
EV=/dev/input/event0
t1=0
while true; do
  ev=$(dd if=$EV bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d " \n")
  [ -z "$ev" ] && continue
  t=${ev:16:4}; c=${ev:20:4}; v=${ev:24:2}
  if [ "$t" = "0100" ] && [ "$c" = "7400" ] && [ "$v" = "01" ]; then
    now=$(date +%s)
    if [ $t1 -gt 0 ] && [ $((now - t1)) -le 2 ]; then
      /usr/local/bin/show-ip
      t1=0
    else
      t1=$now
    fi
  fi
done
EOF
chmod 755 "$TARGET/usr/local/bin/pwrkey-2tap"
cat <<'EOF' > "$TARGET/etc/local.d/pwrkey2tap.start"
#!/bin/sh
/usr/local/bin/pwrkey-2tap >/dev/null 2>&1 &
EOF
chmod 755 "$TARGET/etc/local.d/pwrkey2tap.start"

# bluetoothd must start AFTER dbus (parallel start races -> daemon exits ->
# OpenRC marks it crashed and it never comes back)
mkdir -p "$TARGET/etc/conf.d"
echo 'rc_need="dbus"' > "$TARGET/etc/conf.d/bluetooth"

# Hardened OpenRC init script for bluetoothd (waits for D-Bus socket to avoid startup race)
cat <<'EOF' > "$TARGET/etc/init.d/bluetooth"
#!/sbin/openrc-run

name="Bluetooth"
command="/usr/lib/bluetooth/bluetoothd"
pidfile="/run/bluetoothd.pid"
command_background=true

depend() {
	after coldplug udev-postmount
	need dbus localmount hostname
}

start_pre() {
	ebegin "Waiting for D-Bus system bus"
	local i
	for i in $(seq 1 20); do
		[ -S /run/dbus/system_bus_socket ] && break
		sleep 0.5
	done
	eend 0
}

start_post() {
	sleep 1
	if ! kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
		ewarn "bluetoothd exited immediately, retrying once"
		start-stop-daemon --start --background --make-pidfile \
			--pidfile "$pidfile" --exec "$command" >/dev/null 2>&1
	fi
	return 0
}
EOF
chmod +x "$TARGET/etc/init.d/bluetooth"

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
echo "" > $G/UDC 2>/dev/null
mkdir -p $G/functions/acm.0 $G/functions/ncm.0 $G/functions/hid.0 $G/configs/c.1 2>/dev/null || exit 0
echo 0x05c6 > $G/idVendor 2>/dev/null
echo 0x9025 > $G/idProduct 2>/dev/null
ln -sf $G/functions/acm.0 $G/configs/c.1/f1 2>/dev/null || true
ln -sf $G/functions/ncm.0 $G/configs/c.1/f2 2>/dev/null || true
# HID keyboard function: when a target phone hosts us (target = OTG adapter),
# /dev/hidg0 + tools/hidkey let this device type into the target phone.
mkdir -p $G/functions/hid.0 2>/dev/null && {
    echo 1 > $G/functions/hid.0/protocol
    echo 8 > $G/functions/hid.0/report_length
    printf '%s' '\005\001\011\006\241\001\005\007\031\340\051\347\025\000\045\001\165\001\225\010\201\002\225\001\165\010\201\001\225\005\165\001\005\010\031\001\051\005\221\002\225\001\165\003\221\001\225\006\165\010\025\000\045\145\005\007\031\000\051\145\201\000\300' > $G/functions/hid.0/report_desc
    ln -sf $G/functions/hid.0 $G/configs/c.1/f3 2>/dev/null || true
}
n=0
while [ $n -lt 20 ]; do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    [ -n "$UDC" ] && break
    sleep 1; n=$((n + 1))
done
[ -n "$UDC" ] && echo $UDC > $G/UDC 2>/dev/null
EOF
chmod +x "$TARGET/etc/local.d/usb-gadget.start"

# Cellular modem autostart (verified live on device):
#   qrtr-ns -> rmtfs -P (serves modemst1/2+fsg+fsc EFS via qrtr; WITHOUT it
#   the modem watchdog-crashes in a loop) -> mss remoteproc start.
# Alpine has no /dev/disk/by-partlabel (mdev) — symlinks are hardcoded to
# this device's GPT mapping (modemst1=p11 modemst2=p12 fsg=p18 fsc=p14).
# Firmware (mba.mbn, modem.*) is copied from the vfat modem partition (p1).
cat <<'EOF' > "$TARGET/etc/local.d/modem.start"
#!/bin/sh
[ -b /dev/mmcblk0p11 ] || exit 0
pgrep qrtr-ns >/dev/null || qrtr-ns &
mkdir -p /dev/disk/by-partlabel
ln -sf /dev/mmcblk0p11 /dev/disk/by-partlabel/modemst1
ln -sf /dev/mmcblk0p12 /dev/disk/by-partlabel/modemst2
ln -sf /dev/mmcblk0p18 /dev/disk/by-partlabel/fsg
ln -sf /dev/mmcblk0p14 /dev/disk/by-partlabel/fsc
pgrep rmtfs >/dev/null || (rmtfs -P -v > /tmp/rmtfs.log 2>&1 &)
sleep 1
[ -d /sys/class/remoteproc/remoteproc1 ] || { modprobe qcom_q6v5_mss 2>/dev/null; sleep 1; }
modprobe rpmsg_wwan_ctrl 2>/dev/null
R=/sys/class/remoteproc/remoteproc1
[ -d $R ] || exit 0
FW=/lib/firmware
if [ ! -f $FW/modem.mdt ] || [ ! -f $FW/modem.b22 ]; then
    mkdir -p /mnt/modem
    mount -t vfat -o ro /dev/mmcblk0p1 /mnt/modem 2>/dev/null && \
        cp /mnt/modem/image/mba.mbn /mnt/modem/image/modem.* $FW/ 2>/dev/null
    umount /mnt/modem 2>/dev/null
fi
[ "$(cat $R/state)" = "running" ] || echo start > $R/state 2>/dev/null
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
chroot "$TARGET" /sbin/rc-update add modemmanager default || true

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
