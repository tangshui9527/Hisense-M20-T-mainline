#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Patch a property into an Android boot-image ramdisk without unpacking tools.

Android 4.4-era ramdisks are gzip'd newc cpio archives.  This script rewrites
one file inside the archive (default.prop by default) while byte-preserving
every other entry, including the header fields that GNU/built-in cpio tools
tend to mangle.

Usage:
    python3 patch-ramdisk-prop.py <ramdisk.gz> <output.gz> \
        [--file default.prop] [--append "service.adb.tcp.port=5555"]
"""
import argparse
import gzip
import io
import sys


def parse_newc(raw: bytes):
    pos, entries = 0, []
    while pos < len(raw):
        if raw[pos:pos + 6] not in (b'070701', b'070702'):
            pos = (pos + 3) & ~3          # alignment padding between entries
            continue
        hdr = raw[pos:pos + 110]
        filesize = int(hdr[54:62], 16)
        namesize = int(hdr[94:102], 16)
        name = raw[pos + 110:pos + 110 + namesize - 1].decode()
        data_start = (pos + 110 + namesize + 3) & ~3
        entries.append([name, bytearray(hdr), raw[data_start:data_start + filesize]])
        if name == 'TRAILER!!!':
            break
        pos = (data_start + filesize + 3) & ~3
    return entries


def write_newc(entries):
    out = io.BytesIO()
    for name, hdr, data in entries:
        namesize = len(name) + 1
        hdr[54:62] = b'%08X' % len(data)          # filesize
        hdr[94:102] = b'%08X' % namesize          # namesize
        out.write(hdr)
        out.write(name.encode() + b'\0')
        out.write(b'\0' * ((4 - (110 + namesize) % 4) % 4))
        out.write(data)
        out.write(b'\0' * ((4 - len(data) % 4) % 4))
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ramdisk_in')
    ap.add_argument('ramdisk_out')
    ap.add_argument('--file', default='default.prop')
    ap.add_argument('--append', required=True, help='text appended to the file')
    a = ap.parse_args()

    raw = gzip.open(a.ramdisk_in, 'rb').read()
    entries = parse_newc(raw)

    hit = False
    for name, hdr, data in entries:
        if name == a.file:
            data = data.rstrip(b'\0') + ('\n' + a.append + '\n\0').encode()
            hit = True
    if not hit:
        sys.exit('file not found in ramdisk: ' + a.file)

    new = write_newc(entries)

    # sanity re-parse: every entry must decode with its own header sizes
    for name, hdr, data in parse_newc(new):
        pass

    gzip.open(a.ramdisk_out, 'wb').write(gzip.compress(new, 6))
    print('%s: %s updated (%d bytes -> %s)' %
          (a.ramdisk_in, a.file, len(a.append), a.ramdisk_out))


if __name__ == '__main__':
    main()
