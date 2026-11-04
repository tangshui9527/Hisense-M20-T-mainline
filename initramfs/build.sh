#!/usr/bin/env bash
# build.sh -- assemble the m20-t-prephase initramfs cpio (gzip).
#
# Produces: initramfs.cpio.gz
# Layout: /init, /etc/setup-ncm.sh, /busybox (static armhf from Alpine)
#
# busybox-static is fetched from the public Alpine mirror.  The version is
# pinned here; bump _BB_VER together with _BB_APK sha when upgrading.

set -euo pipefail
cd "$(dirname "$0")"

_ALPINE=v3.21
_BB_APK="busybox-static-1.37.0-r14.apk"       # armhf, alpine 3.21 main
# fallback lookup: if the pinned file 404s, resolve name from APKINDEX
_BASE=https://dl-cdn.alpinelinux.org/alpine/${_ALPINE}/main/armhf

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "[initramfs] fetching ${_BB_APK}"
if ! curl -fSL -o "$WORK/bb.apk" "${_BASE}/${_BB_APK}" 2>/dev/null; then
    echo "[initramfs] pinned version missing, resolving from APKINDEX"
    BBFILE=$(curl -fsSL "${_BASE}/APKINDEX.tar.gz" | tar -xzO APKINDEX \
        | awk '/^P:busybox-static$/{p=1} p && /^V:/{v=$2; p=0} END{print "busybox-static-" v ".apk"}')
    curl -fSL -o "$WORK/bb.apk" "${_BASE}/${BBFILE}"
fi

# apk files are (compressed) tar archives
mkdir -p "$WORK/fs"
if ! tar -xf "$WORK/bb.apk" -C "$WORK/fs" 2>/dev/null; then
    gzip -dc "$WORK/bb.apk" | tar -xf - -C "$WORK/fs"
fi
BB="$WORK/fs/bin/busybox.static"
[ -f "$BB" ] || { echo "busybox.static not found in apk"; exit 1; }

STAGE="$WORK/stage"
mkdir -p "$STAGE/bin" "$STAGE/sbin" "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" \
         "$STAGE/tmp" "$STAGE/config" "$STAGE/etc" "$STAGE/dev/pts" "$STAGE/run" \
         "$STAGE/lib/modules"
install -m 0755 "$BB" "$STAGE/busybox"
install -m 0755 "$BB" "$STAGE/bin/busybox"
ln -sf /busybox "$STAGE/bin/sh"
ln -sf /busybox "$STAGE/bin/ash"
ln -sf /busybox "$STAGE/sbin/init"
install -m 0755 init "$STAGE/init"
install -m 0755 setup-ncm.sh "$STAGE/etc/setup-ncm.sh"

if [ -f "../rootfs/alpine-rootfs.tar.gz" ]; then
    echo "[initramfs] embedding alpine-rootfs.tar.gz into initramfs..."
    cp "../rootfs/alpine-rootfs.tar.gz" "$STAGE/alpine-rootfs.tar.gz"
fi

if [ -d "../modout/lib/modules" ]; then
    echo "[initramfs] embedding kernel modules..."
    cp -a "../modout/lib/modules" "$STAGE/lib/"
elif [ -d "lib/modules" ]; then
    cp -a "lib/modules" "$STAGE/lib/"
fi

(cd "$STAGE" && find . | cpio -o -H newc --owner=0:0 2>/dev/null) | gzip -9 > initramfs.cpio.gz
ls -l initramfs.cpio.gz
echo "[initramfs] done"
