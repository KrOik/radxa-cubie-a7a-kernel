# Radxa Cubie A7Z Configuration Files

This directory contains A7Z-specific configuration files for UFS-based storage.

## Files

- `board.dts` - A7Z device tree source (modified from A7A with A7Z board ID)
- `cubie_a7z_defconfig` - A7Z kernel configuration (UFS-optimized)
- `extlinux.conf.template` - Boot configuration template for UFS partitions

## Key Differences from A7A

### Storage
- **Device path**: `/dev/sda` (UFS) instead of `/dev/mmcblk0` (SD/eMMC)
- **Root partition**: `/dev/sda3` instead of `/dev/mmcblk0p3`
- **U-Boot scan**: `sunxi_flash_ufs 0:2` instead of `mmc 0:3`

### Partition Layout
A7Z requires 3 partitions:
1. `/dev/sda1` - 16 MB config partition (optional)
2. `/dev/sda2` - 300 MB EFI System Partition (type EF00, contains /boot)
3. `/dev/sda3` - Remaining space for rootfs

### Device Tree
- Board ID: `"A733-CUBIE-A7Z-AXP318"`
- Compatible: `"radxa,cubie-a7z"`
- UFS controller enabled (same as A7A overclocked DTS)

## Usage

These files are automatically used when building with `BOARD=a7z`:

```bash
./scripts/setup-kernel.sh a7z
cd kernel-6.6
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ cubie_a7z_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ -j$(nproc) Image dtbs modules
```

Or via GitHub Actions:
```bash
git push origin main  # Automatically builds both A7A and A7Z
```
