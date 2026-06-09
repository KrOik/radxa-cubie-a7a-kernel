#!/bin/bash
# Create bootable A7Z image using stock image as base
# This preserves the working boot sectors + GPT structure
set -eo pipefail

STOCK_IMAGE="${1:-radxa-a733_bullseye_kde_r6.output_4096.img.xz}"
CUSTOM_KERNEL_TARBALL="${2}"
OUTPUT_IMAGE="radxa-cubie-a7z-bootable-final.img"

echo "=== Radxa Cubie A7Z Bootable Image Creator (Stock Base) ==="
echo "Stock image: $STOCK_IMAGE"
echo "Custom kernel: $CUSTOM_KERNEL_TARBALL"
echo "Output: $OUTPUT_IMAGE"
echo ""

# Check files
if [ ! -f "$STOCK_IMAGE" ]; then
    echo "ERROR: Stock image not found: $STOCK_IMAGE"
    exit 1
fi

if [ -n "$CUSTOM_KERNEL_TARBALL" ] && [ ! -f "$CUSTOM_KERNEL_TARBALL" ]; then
    echo "ERROR: Custom kernel tarball not found: $CUSTOM_KERNEL_TARBALL"
    exit 1
fi

# Step 1: Decompress stock image (this is the base)
echo "[1/5] Decompressing stock image as base..."
if [ -f "$OUTPUT_IMAGE" ]; then
    echo "  ✓ Using existing $OUTPUT_IMAGE"
else
    echo "  This will take 3-5 minutes for 4GB image..."
    xz -d -c "$STOCK_IMAGE" > "$OUTPUT_IMAGE"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_IMAGE" 2>/dev/null || stat -f%z "$OUTPUT_IMAGE" 2>/dev/null)
    echo "  ✓ Stock image decompressed: $((OUTPUT_SIZE / 1024 / 1024)) MB"
fi

# Step 2: Verify GPT structure
echo ""
echo "[2/5] Verifying GPT structure..."
# Check GPT header at sector 1
GPT_SIG=$(dd if="$OUTPUT_IMAGE" bs=512 skip=1 count=1 2>/dev/null | xxd -p -l 8)
if [ "$GPT_SIG" = "45464920504152540000" ] || [ "${GPT_SIG:0:16}" = "4546492050415254" ]; then
    echo "  ✓ GPT header valid: EFI PART"
else
    echo "  ✗ WARNING: GPT header not found at sector 1"
    echo "  Got: $GPT_SIG"
fi

# Check boot0 at 8KB offset
BOOT0_SIG=$(dd if="$OUTPUT_IMAGE" bs=1K skip=8 count=4 2>/dev/null | xxd -p -l 8)
echo "  Boot0 signature at 8KB: $BOOT0_SIG"
if [ "$BOOT0_SIG" != "0000000000000000" ]; then
    echo "  ✓ boot0 present"
else
    echo "  ✗ WARNING: boot0 appears to be missing"
fi

# Exit if no custom kernel (just wanted to decompress stock)
if [ -z "$CUSTOM_KERNEL_TARBALL" ] || [ ! -f "$CUSTOM_KERNEL_TARBALL" ]; then
    echo ""
    echo "✓ Stock image prepared (no custom kernel to install)"
    echo "Output: $OUTPUT_IMAGE"
    exit 0
fi

# Step 3: Mount and replace kernel/modules
echo ""
echo "[3/5] Replacing kernel and modules..."

# Extract custom kernel
KERNEL_STAGING="kernel_staging_$$"
mkdir -p "$KERNEL_STAGING"
tar -xzf "$CUSTOM_KERNEL_TARBALL" -C "$KERNEL_STAGING/"
echo "  ✓ Custom kernel extracted"

# Setup loop device with partitions
LOOP_DEV=$(sudo losetup -f --show "$OUTPUT_IMAGE")
sudo partx -a "$LOOP_DEV" || true
sleep 2

# List partitions
echo "  Available partitions:"
lsblk "$LOOP_DEV" | grep -E "NAME|part"

# Mount boot partition (sda2)
BOOT_PART="${LOOP_DEV}p2"
BOOT_MNT="/mnt/a7z_boot_$$"
sudo mkdir -p "$BOOT_MNT"

if sudo mount "$BOOT_PART" "$BOOT_MNT" 2>/dev/null; then
    echo "  ✓ Mounted boot partition"

    # Replace kernel Image
    if [ -f "$KERNEL_STAGING/boot/Image" ]; then
        sudo cp "$KERNEL_STAGING/boot/Image" "$BOOT_MNT/"
        echo "    ✓ Updated kernel Image"
    fi

    # Replace DTBs
    if ls "$KERNEL_STAGING/boot/"*.dtb >/dev/null 2>&1; then
        sudo cp "$KERNEL_STAGING/boot/"*.dtb "$BOOT_MNT/" 2>/dev/null || true
        echo "    ✓ Updated device trees"
    fi

    sudo umount "$BOOT_MNT"
else
    echo "  ✗ Could not mount boot partition"
fi

# Mount rootfs partition (sda3)
ROOTFS_PART="${LOOP_DEV}p3"
ROOTFS_MNT="/mnt/a7z_rootfs_$$"
sudo mkdir -p "$ROOTFS_MNT"

if sudo mount "$ROOTFS_PART" "$ROOTFS_MNT" 2>/dev/null; then
    echo "  ✓ Mounted rootfs partition"

    # Replace kernel modules
    if [ -d "$KERNEL_STAGING/lib/modules" ]; then
        sudo rm -rf "$ROOTFS_MNT/lib/modules/"*
        sudo cp -r "$KERNEL_STAGING/lib/modules/"* "$ROOTFS_MNT/lib/modules/"
        echo "    ✓ Updated kernel modules"
    fi

    sudo umount "$ROOTFS_MNT"
else
    echo "  ✗ Could not mount rootfs partition"
fi

# Cleanup loop device
sudo partx -d "$LOOP_DEV" || true
sudo losetup -d "$LOOP_DEV" || true
sudo rmdir "$BOOT_MNT" "$ROOTFS_MNT" 2>/dev/null || true
rm -rf "$KERNEL_STAGING"

echo "  ✓ Partitions updated and unmounted"

# Step 4: Verify final image
echo ""
echo "[4/5] Verifying final image..."
FINAL_SIZE=$(stat -c%s "$OUTPUT_IMAGE" 2>/dev/null || stat -f%z "$OUTPUT_IMAGE" 2>/dev/null)
echo "  Image size: $((FINAL_SIZE / 1024 / 1024)) MB"

# Re-check GPT
GPT_CHECK=$(dd if="$OUTPUT_IMAGE" bs=512 skip=1 count=1 2>/dev/null | xxd -p -l 16)
if [ "${GPT_CHECK:0:16}" = "4546492050415254" ]; then
    echo "  ✓ GPT header still valid"
else
    echo "  ✗ ERROR: GPT header corrupted!"
    exit 1
fi

# Step 5: Compress
echo ""
echo "[5/5] Compressing final image..."
OUTPUT_XZ="${OUTPUT_IMAGE}.xz"
[ -f "$OUTPUT_XZ" ] && rm "$OUTPUT_XZ"

xz -9 -T0 -k "$OUTPUT_IMAGE"

FINAL_XZ_SIZE=$(stat -c%s "$OUTPUT_XZ" 2>/dev/null || stat -f%z "$OUTPUT_XZ" 2>/dev/null)
sha256sum "$OUTPUT_XZ" > "${OUTPUT_XZ}.sha256"

echo ""
echo "================================================"
echo "✅ Bootable A7Z image created!"
echo ""
echo "Output: $OUTPUT_XZ ($((FINAL_XZ_SIZE / 1024 / 1024)) MB)"
echo "SHA256: ${OUTPUT_XZ}.sha256"
echo ""
echo "This image contains:"
echo "  ✅ Stock boot0 + U-Boot (UFS 4K block aligned)"
echo "  ✅ Stock GPT partition table (U-Boot compatible)"
echo "  ✅ Custom kernel 6.6.98+ with overclock"
echo "  ✅ Custom kernel modules"
echo "  ✅ Stock Debian rootfs (preserved)"
echo ""
echo "Flash command:"
echo "  sudo ./flash-to-a7z.sh /dev/sdX"
echo ""
