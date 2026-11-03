#!/usr/bin/env python3
# Verify the QCDT table inside an lk2nd boot image.
#
# The Hisense M20-T reports qcom,msm-id = 245 (0xf5) and
# qcom,board-id = 0x1000b with subtype 0. The stock image only had subtype 8,
# which is why the old image needed a one-byte binary patch.

import struct
import sys

QCDT_MAGIC = 0x54444351  # "QCDT"
EXPECT_SOC = 245
EXPECT_VARIANT = 0x1000B
EXPECT_SUBTYPE = 0

def find_qcdt(data):
    for off in range(0, len(data) - 12, 4):
        if data[off:off + 4] == b"QCDT":
            magic, version, count = struct.unpack_from("<III", data, off)
            if magic == QCDT_MAGIC and 0 < count < 200:
                return off, version, count
    return None, None, None

def main(path):
    with open(path, "rb") as f:
        data = f.read()

    off, version, count = find_qcdt(data)
    if off is None:
        print("FAIL: no QCDT table found")
        return 1

    print(f"QCDT at 0x{off:x}, version {version}, {count} entries")
    match = False
    for i in range(count):
        e = off + 12 + i * 40
        (platform, variant, subtype, soc_rev,
         pmic0, pmic1, pmic2, pmic3, dtb_off, dtb_size) = struct.unpack_from(
             "<10I", data, e)
        ok = platform == EXPECT_SOC and variant == EXPECT_VARIANT and subtype == EXPECT_SUBTYPE
        match |= ok
        print(f"  [{i:2d}] soc=0x{platform:02x} variant=0x{variant:06x} "
              f"subtype=0x{subtype:02x} pmic=({pmic0:08x},{pmic1:08x}) "
              f"dtb=0x{dtb_off:x}+0x{dtb_size:x}"
              f"{'  <== M20-T' if ok else ''}")

    if not match:
        print("FAIL: no entry for (245, 0x1000b, subtype 0)")
        return 1

    print("OK: M20-T board id present")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} lk2nd.img")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
