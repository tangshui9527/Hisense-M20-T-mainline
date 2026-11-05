# Flashing Guide: From Stock Android to Mainline Linux

> **Target Device**: Hisense M20-T (Uniscope ODM, Qualcomm Snapdragon 210 / MSM8909, `soc_id 245 / 0xf5`)  
> **Target OS**: Mainline Linux 7.0 + Alpine Linux 3.21 (Headless Server)  
> **Author**: Hisense-M20-T-mainline Project Contributors  

---

## 📋 Overview

This guide walks you through migrating a factory Hisense M20-T smartphone running Android 4.4.4 (KitKat) to a single-system, headless Alpine Linux server running a close-to-mainline Linux 7.0 kernel on the internal eMMC.

### Key Hardware & Boot Facts
- **No Fastboot Flash/Boot/Unlock**: The stock bootloader (`aboot`) provides a stripped-down fastboot implementation that lacks `flash`, `boot`, and `oem unlock` commands.
- **No Signature Enforcement**: The bootloader does **not** enforce cryptographic signatures on the `boot` partition. Unsigned custom kernels boot directly without unlocking the bootloader.
- **Root Available by Default**: The factory Android firmware permits root execution via `adb shell "su -c '<command>'"` without any superuser prompt.
- **QCDT Header Requirement**: The bootloader strictly inspects the Device Tree table. The DT blob must be wrapped into a Qualcomm QCDT v3 table matching platform `0xf5` (245), board `0x1000b`, and subtype `0`.
- **Flashing Method**: Initial installation is performed directly from stock Android using `root` and `dd` to write the internal eMMC partitions.

---

## 🧰 Requirements & Artifacts

### 1. Host Machine
- Linux or macOS with `adb` installed (`android-tools` on Linux or `brew install android-platform-tools` on macOS).
- USB Type-A to Micro-USB data cable.

### 2. Build Artifacts
Download the latest build artifacts from the GitHub Actions CI (run from the `lk2nd-m20t` branch):
- **`m20t-qcom-msm8909-hisense-m20t.img`**: The complete Android boot image containing Linux 7.0 zImage, QCDT-wrapped Device Tree, and Stage-1 initramfs.
- **`alpine-rootfs.tar.gz`**: Pre-configured Alpine Linux 3.21 armhf root filesystem tarball (contains OpenRC, Dropbear SSH, WCN3620 Wi-Fi configuration, BlueZ Bluetooth, and ModemManager).

---

## 🛡️ Step 1: Prerequisites & Full Partition Backup

> [!CAUTION]
> Before modifying any partition on the device, create a full raw backup of your original Android partitions. This provides a guaranteed rollback path in case of any issue.

1. **Enable USB Debugging on Android**:
   - Power on the phone into factory Android.
   - Go to **Settings** → **About phone**, and tap **Build number** 7 times to enable Developer options.
   - Go to **Settings** → **Developer options**, and turn on **USB debugging**.
   - Connect the phone to your computer via USB.

2. **Verify ADB Connection and Root**:
   ```bash
   adb devices
   # Should report: 2f339cef    device

   # Test root access
   adb shell "su -c id"
   # Must return: uid=0(root) gid=0(root)
   ```

3. **Backup Critical Partitions**:
   ```bash
   mkdir -p m20t-backup
   cd m20t-backup

   # Back up the stock boot partition (32 MiB)
   adb shell "su -c 'dd if=/dev/block/bootdevice/by-name/boot of=/data/local/tmp/stock-boot.img bs=4096'"
   adb pull /data/local/tmp/stock-boot.img ./stock-boot.img
   adb shell "su -c 'rm -f /data/local/tmp/stock-boot.img'"

   # Verify original boot image MD5 (factory MD5 is 0e5f1083a10c418c956de9d0c34f2a2d)
   md5sum stock-boot.img || md5 stock-boot.img

   # (Recommended) Back up other firmware partitions
   for PART in aboot recovery sbl1 tz rpm modem; do
       echo "Backing up $PART..."
       adb shell "su -c 'dd if=/dev/block/bootdevice/by-name/$PART of=/data/local/tmp/$PART.img bs=4096'"
       adb pull /data/local/tmp/$PART.img ./$PART.img
       adb shell "su -c 'rm -f /data/local/tmp/$PART.img'"
   done
   ```

---

## 💾 Step 2: Install Alpine Linux Rootfs on `userdata`

The stock partition table reserves ~5.6 GB for `userdata` (`/dev/block/bootdevice/by-name/userdata` or `/dev/mmcblk0p29`). We will format this partition with `ext4` and extract the root filesystem onto it.

1. **Push the Rootfs Package**:
   ```bash
   adb push alpine-rootfs.tar.gz /data/local/tmp/
   ```

2. **Format and Extract via ADB Root Shell**:
   ```bash
   # Format userdata partition to ext4
   adb shell "su -c 'mke2fs -F -t ext4 /dev/block/bootdevice/by-name/userdata'"

   # Mount userdata temporarily
   adb shell "su -c 'mkdir -p /data/local/tmp/target_root && mount -t ext4 /dev/block/bootdevice/by-name/userdata /data/local/tmp/target_root'"

   # Extract rootfs
   echo "Extracting root filesystem (this takes ~1 minute)..."
   adb shell "su -c 'tar -xzf /data/local/tmp/alpine-rootfs.tar.gz -C /data/local/tmp/target_root'"

   # Clean up tarball
   adb shell "su -c 'rm -f /data/local/tmp/alpine-rootfs.tar.gz'"
   ```

3. **(Optional) Customize Wi-Fi Credentials Before Boot**:
   If you want the phone to connect to your local Wi-Fi immediately upon boot, edit the configuration:
   ```bash
   # Replace SSID and password with your Wi-Fi credentials
   adb shell "su -c 'cat << \"EOF\" > /data/local/tmp/target_root/etc/wpa_supplicant/wpa_supplicant.conf
   ctrl_interface=/var/run/wpa_supplicant
   update_config=1

   network={
       ssid=\"Your-WiFi-SSID\"
       psk=\"Your-WiFi-Password\"
   }
   EOF'"
   ```

4. **Sync and Unmount**:
   ```bash
   adb shell "su -c 'sync && umount /data/local/tmp/target_root'"
   ```

---

## 🚀 Step 3: Flash the Mainline Boot Image

Now write the Linux kernel boot package to the `boot` partition (`/dev/block/bootdevice/by-name/boot`).

1. **Push the Boot Image**:
   ```bash
   adb push m20t-qcom-msm8909-hisense-m20t.img /data/local/tmp/m20t-boot.img
   ```

2. **Flash with `dd` and Verify**:
   ```bash
   # Flash image directly to boot partition
   adb shell "su -c 'dd if=/data/local/tmp/m20t-boot.img of=/dev/block/bootdevice/by-name/boot bs=4096 && sync'"

   # Clean up temporary file
   adb shell "su -c 'rm -f /data/local/tmp/m20t-boot.img'"
   ```

3. **Reboot into Linux**:
   ```bash
   adb shell "su -c 'reboot'"
   ```

---

## 🖥️ Step 4: First Boot & Access

When the phone restarts:
1. The screen will display the boot logo and may turn off (power management intentionally shuts down the backlight and panel to save power).
2. The phone initializes the SoC, mounts the `userdata` partition as `/`, and launches OpenRC services.

### Option A: SSH Over Wi-Fi (Primary Interface)
If your Wi-Fi credentials were set up in Step 2:
- Check your Wi-Fi router's DHCP client table for a new device named `m20t-server` (or IP assigned to MAC `00:0a:f5:2f:33:9c`).
- Connect via SSH:
  ```bash
  ssh root@<PHONE_IP>
  # Default password: toor
  ```

### Option B: USB CDC-ACM Serial Console (Offline Fallback)
If Wi-Fi fails to connect or you need an offline shell, connect the phone to your computer with a USB cable. The Stage-1 initramfs and OpenRC automatically configure a USB CDC-ACM serial gadget (`/dev/ttyGS0`).

- **On macOS**:
  ```bash
  screen /dev/cu.usbmodem* 115200
  ```
- **On Linux**:
  ```bash
  screen /dev/ttyACM0 115200
  ```
- Press **Enter** to open an interactive, passwordless root shell.
- (To exit `screen`, press `Ctrl+A` followed by `\`).

---

## 📶 Step 5: Post-Install Verification & Hardware Status

Once logged in, verify your hardware:

```bash
# Check uptime, kernel version, and memory usage (~34MB idle!)
uname -a
free -m
htop

# Check OpenRC services
rc-status

# Verify Bluetooth (scan for nearby BLE / smart home devices)
bluetoothctl --timeout 8 scan on

# Check cellular modem / IMEI (if SIM card is inserted)
qmicli -d qrtr://0 --dms-get-ids
```

---

## 🔄 Wireless Over-The-Air (OTA) Updates

Once Linux is running, you never need to connect a USB cable to update the kernel:

```bash
# 1. Transfer updated boot image over Wi-Fi
scp m20t-qcom-msm8909-hisense-m20t.img root@<PHONE_IP>:/tmp/m20t-boot.img

# 2. Write to boot partition directly and reboot
ssh root@<PHONE_IP> "dd if=/tmp/m20t-boot.img of=/dev/mmcblk0p20 bs=4096 && sync && reboot"
```

---

## 🛟 Disaster Recovery: Qualcomm 9008 EDL Mode

If an invalid image is flashed and the device enters a boot loop or cannot reach Linux:

1. **Enter EDL 9008 Mode**:
   - Unplug the USB cable.
   - Remove and reinsert the battery (or hold Power + Vol Up + Vol Down until power cycles).
   - Press and **hold both Volume Up and Volume Down** simultaneously.
   - While holding both buttons, plug the USB cable into your computer.
   - Check device manager / terminal:
     - macOS: `system_profiler SPUSBDataType | grep 05c6`
     - Linux: `lsusb | grep 05c6:9008`
2. **Flash Factory Boot Backup**:
   Use Qualcomm open-source EDL tools (e.g. `edl` / `bkerler/edl`):
   ```bash
   edl wl stock-boot.img --loader=tools/msm8909_ul40.mbn --partition=boot
   edl reset
   ```
   The phone will reboot back into factory Android immediately.
