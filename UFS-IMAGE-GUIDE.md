# UFS Image Creation Guide for Radxa Cubie A7Z

## The Problem

Your A7Z board is failing to boot because of a **sector size mismatch**:

- **UFS storage uses 4096-byte logical sectors**
- **Standard images use 512-byte sectors**

When U-Boot tries to read the GPT partition table, it looks at offset 4096 (sector 1 in UFS), but finds nothing because the GPT was written at offset 512 (sector 1 in standard storage).

The error messages confirm this:
```
GUID Partition Table Header signature is wrong: 0x0 != 0x5452415020494645
part_get_info_efi: *** ERROR: Invalid GPT ***
```

## The Solution

Create a UFS-compatible image with 4096-byte sectors from the start.

### Requirements

- Linux system (WSL2, Ubuntu, Debian, etc.)
- Root access (sudo)
- Tools: `sgdisk` or `parted`, `debootstrap`, `mkfs.ext4`, `losetup`

Install required tools:
```bash
# Debian/Ubuntu
sudo apt install gdisk parted debootstrap qemu-user-static

# Arch
sudo pacman -S gptfdisk parted arch-install-scripts
```

### Step 1: Create UFS-Compatible Image

```bash
cd /path/to/radxa-cubie-a7a-kernel

# Create 4GB UFS image
sudo ./scripts/create-ufs-image.sh \
    radxa-a7z-ufs.img \
    kernel-a7z-*.tar.gz \
    radxa-a733_bullseye_kde_r6.output_4096.img.xz \
    4
```

**Parameters:**
1. Output image name
2. Kernel tarball (from your build)
3. Stock image (for U-Boot extraction)
4. Size in GB

This script:
- ✅ Creates image with 4096-byte sectors
- ✅ Creates GPT partition table aligned to 4K boundaries
- ✅ Extracts U-Boot from stock image
- ✅ Installs Debian 13 minimal base
- ✅ Installs your custom kernel
- ✅ Configures boot (extlinux.conf)
- ✅ Sets up networking (DHCP)

### Step 2: Flash to UFS Storage

**On Linux:**
```bash
# Find your UFS device
lsblk

# Flash with 4096-byte block size (IMPORTANT!)
sudo dd if=radxa-a7z-ufs.img of=/dev/sdX bs=4096 status=progress conv=fsync

# Verify
sudo sgdisk -p /dev/sdX
```

**On Windows (using WSL2):**
```bash
# Access Windows drive via WSL
# First, use Windows Disk Management to identify the disk number

# In WSL (careful with disk selection!):
sudo dd if=radxa-a7z-ufs.img of=/dev/sdX bs=4096 status=progress

# Alternative: Use Win32DiskImager or Rufus in DD mode
```

### Step 3: Boot

1. Insert UFS storage into A7Z
2. Power on
3. Connect serial console (115200 8N1)

You should see:
```
[04.644]flash init start
[04.646]workmode = 0,storage type = 8
[ufs]info:Driver version 0.0.24...
...
Found /boot/extlinux/extlinux.conf
Retrieving file: /boot/extlinux/extlinux.conf
...
Starting kernel...
```

## Verification

### Check Sector Size

```bash
# On the image file (before flashing)
sgdisk -p radxa-a7z-ufs.img | grep "sector size"

# Should show:
# Logical sector size: 4096 bytes

# On UFS device (after flashing)
sudo blockdev --getss /dev/sdX   # Should output: 4096
sudo blockdev --getpbsz /dev/sdX # Should output: 4096
```

### Check GPT Header

```bash
# UFS devices put GPT header at offset 4096, not 512
hexdump -C radxa-a7z-ufs.img -n 64 -s 4096 | head -5

# Should show "EFI PART" signature:
# 00001000  45 46 49 20 50 41 52 54  00 00 01 00 5c 00 00 00
```

## What's Different

| Feature | Standard Image | UFS Image |
|---------|---------------|-----------|
| Sector size | 512 bytes | 4096 bytes |
| GPT location | Offset 512 | Offset 4096 |
| Partition alignment | 1MB (2048×512) | 2MB (512×4096) |
| Filesystem block size | 4096 | 4096 |
| U-Boot location | 8KB offset | 8KB offset |

## Troubleshooting

### "sgdisk: command not found"

```bash
sudo apt install gdisk
```

### "debootstrap: command not found"

```bash
sudo apt install debootstrap
```

### Still getting GPT errors

Check that you used `bs=4096` when flashing:
```bash
# WRONG (will fail on UFS):
dd if=image.img of=/dev/sdX bs=1M

# CORRECT (for UFS):
dd if=image.img of=/dev/sdX bs=4096
```

### Can't mount partitions on host

UFS images with 4096-byte sectors may not mount on systems expecting 512-byte sectors. This is normal - they'll work fine on the A7Z hardware.

### U-Boot still can't find partitions

1. Verify the stock image has working U-Boot:
   ```bash
   dd if=radxa-a733_bullseye_kde_r6.output_4096.img bs=4096 count=4096 | hexdump -C | grep -A5 "boot0"
   ```

2. Check U-Boot was copied correctly:
   ```bash
   dd if=radxa-a7z-ufs.img bs=4096 skip=2 count=10 | strings | grep -i boot0
   ```

## Alternative: Convert Existing Image

If you already have a working 512-byte sector image, you **cannot** simply convert it. The GPT structures are fundamentally different. You must rebuild from scratch using the UFS script.

## References

- [Allwinner A733 Boot Process](https://linux-sunxi.org/A733)
- [GPT Specification](https://en.wikipedia.org/wiki/GUID_Partition_Table)
- [UFS vs eMMC Sector Sizes](https://www.kernel.org/doc/html/latest/block/blk-settings.html)

## Credits

This guide addresses the sector size mismatch causing:
```
GUID Partition Table Header signature is wrong: 0x0 != 0x5452415020494645
```

Root cause: UFS storage requires 4096-byte sector alignment for GPT, while standard tools default to 512-byte sectors.
