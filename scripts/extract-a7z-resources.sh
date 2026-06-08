#!/bin/bash
# Extract A7Z resources from official stock image
set -euo pipefail

IMG_XZ="${1:-temp_extract/a7z-stock.img.xz}"
OUTPUT_DIR="extracted_a7z"

if [ ! -f "$IMG_XZ" ]; then
    echo "Error: Image file not found: $IMG_XZ"
    echo "Usage: $0 <path-to-a7z-stock.img.xz>"
    exit 1
fi

echo "=== A7Z Resource Extraction Tool ==="
echo "Source: $IMG_XZ"
echo "Output: $OUTPUT_DIR/"
echo ""

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 1. Decompress image
echo "[1/9] Decompressing image (this may take 5-10 minutes)..."
if [ ! -f a7z-stock.img ]; then
    xz -dc "../$IMG_XZ" > a7z-stock.img
    echo "✓ Decompressed to $(du -h a7z-stock.img | cut -f1)"
else
    echo "✓ Already decompressed"
fi

# 2. Analyze partition layout
echo ""
echo "[2/9] Analyzing partition layout..."
fdisk -l a7z-stock.img > a7z-partition-layout.txt 2>&1 || true
parted a7z-stock.img print >> a7z-partition-layout.txt 2>&1 || true
echo "✓ Saved to a7z-partition-layout.txt"
cat a7z-partition-layout.txt

# 3. Mount partitions (Linux only)
if [ "$(uname)" = "Linux" ]; then
    echo ""
    echo "[3/9] Mounting partitions..."
    LOOP_DEV=$(sudo losetup -f --show a7z-stock.img)
    sudo partprobe "$LOOP_DEV"
    sudo mkdir -p /mnt/a7z_boot /mnt/a7z_rootfs

    # Mount EFI partition (partition 2)
    if sudo mount "${LOOP_DEV}p2" /mnt/a7z_boot 2>/dev/null; then
        echo "✓ Mounted EFI partition: /mnt/a7z_boot"
        BOOT_MOUNT="/mnt/a7z_boot"
    else
        echo "⚠ Failed to mount partition 2, trying partition 1..."
        sudo mount "${LOOP_DEV}p1" /mnt/a7z_boot 2>/dev/null || true
        BOOT_MOUNT="/mnt/a7z_boot"
    fi

    # Mount rootfs (partition 3)
    sudo mount "${LOOP_DEV}p3" /mnt/a7z_rootfs 2>/dev/null || true
    ROOTFS_MOUNT="/mnt/a7z_rootfs"

    # 4. Extract DTB
    echo ""
    echo "[4/9] Extracting device tree blob..."
    if [ -f "$BOOT_MOUNT/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" ]; then
        sudo cp "$BOOT_MOUNT/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" ./
        echo "✓ Copied from $BOOT_MOUNT/dtb/allwinner/"
    elif [ -f "$ROOTFS_MOUNT/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" ]; then
        sudo cp "$ROOTFS_MOUNT/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" ./
        echo "✓ Copied from rootfs /boot/dtb/allwinner/"
    else
        echo "⚠ DTB not found in expected locations"
        find "$BOOT_MOUNT" "$ROOTFS_MOUNT" -name "*.dtb" 2>/dev/null | head -10
    fi

    # Decompile DTB to DTS
    if [ -f sun60i-a733-cubie-a7z.dtb ]; then
        dtc -I dtb -O dts -o a7z-stock.dts sun60i-a733-cubie-a7z.dtb 2>/dev/null || true
        echo "✓ Decompiled to a7z-stock.dts"
    fi

    # 5. Extract kernel config
    echo ""
    echo "[5/9] Extracting kernel configuration..."
    sudo cp "$BOOT_MOUNT"/config-* ./a7z-stock.config 2>/dev/null || \
        sudo cp "$ROOTFS_MOUNT"/boot/config-* ./a7z-stock.config 2>/dev/null || \
        echo "⚠ Kernel config not found"

    if [ -f a7z-stock.config ]; then
        echo "✓ Saved kernel config ($(wc -l < a7z-stock.config) lines)"
    fi

    # 6. Extract extlinux.conf
    echo ""
    echo "[6/9] Extracting boot configuration..."
    sudo cp "$BOOT_MOUNT/extlinux/extlinux.conf" ./a7z-stock-extlinux.conf 2>/dev/null || \
        echo "⚠ extlinux.conf not found"

    if [ -f a7z-stock-extlinux.conf ]; then
        echo "✓ Saved boot config"
        cat a7z-stock-extlinux.conf
    fi

    # 7. Extract fstab
    echo ""
    echo "[7/9] Extracting fstab..."
    sudo cp "$ROOTFS_MOUNT/etc/fstab" ./a7z-stock-fstab 2>/dev/null || \
        echo "⚠ fstab not found"

    if [ -f a7z-stock-fstab ]; then
        echo "✓ Saved fstab"
        cat a7z-stock-fstab
    fi

    # 8. Extract kernel Image
    echo ""
    echo "[8/9] Extracting kernel Image..."
    sudo cp "$BOOT_MOUNT/Image" ./a7z-stock-Image 2>/dev/null || \
        sudo cp "$ROOTFS_MOUNT/boot/Image" ./a7z-stock-Image 2>/dev/null || \
        echo "⚠ Kernel Image not found"

    if [ -f a7z-stock-Image ]; then
        echo "✓ Saved kernel Image ($(du -h a7z-stock-Image | cut -f1))"
        strings a7z-stock-Image | grep "Linux version" | head -3
    fi

    # 9. Cleanup
    echo ""
    echo "[9/9] Cleaning up..."
    sudo umount /mnt/a7z_boot /mnt/a7z_rootfs 2>/dev/null || true
    sudo losetup -d "$LOOP_DEV"
    sudo rmdir /mnt/a7z_boot /mnt/a7z_rootfs 2>/dev/null || true
    echo "✓ Unmounted and cleaned up"
else
    echo ""
    echo "[3-9] Skipping extraction - Linux required for mounting"
    echo "⚠ Manual extraction needed on Windows/WSL"
fi

# Extract boot sectors (works on all platforms)
echo ""
echo "[Extra] Extracting boot sectors..."
dd if=a7z-stock.img of=a7z-boot-sectors.img bs=1M count=16 2>/dev/null || true
echo "✓ Saved boot sectors (16 MB)"

echo ""
echo "================================================"
echo "✅ Extraction complete!"
echo ""
echo "Extracted files:"
ls -lh | grep -v "^d" | grep -v "^total"
echo ""
echo "Next steps:"
echo "  1. Compare DTS:"
echo "     diff -u ../configs/a7z/board.dts a7z-stock.dts"
echo ""
echo "  2. Compare kernel config:"
echo "     diff ../configs/a7z/cubie_a7z_defconfig a7z-stock.config | head -50"
echo ""
echo "  3. Compare boot config:"
echo "     diff ../configs/a7z/extlinux.conf.template a7z-stock-extlinux.conf"
echo ""
