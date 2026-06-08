#!/bin/bash
# Quick extraction script for Windows environment
# Extracts key A7Z resources and performs comparison

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMG_FILE="$PROJECT_ROOT/radxa-a733_bullseye_kde_r6.output_4096.img.xz"
OUTPUT_DIR="$PROJECT_ROOT/extracted_a7z"

echo "=== A7Z Resource Extraction and Comparison ==="
echo ""

# Check if image exists
if [ ! -f "$IMG_FILE" ]; then
    echo "Error: Image file not found: $IMG_FILE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Step 1: Decompress if not already done
if [ ! -f "a7z-stock.img" ]; then
    echo "[1/6] Decompressing image..."
    echo "This may take 5-10 minutes for 1.1 GB compressed → 4-6 GB raw"
    xz -dc "$IMG_FILE" > a7z-stock.img
    echo "✓ Decompressed: $(du -h a7z-stock.img | cut -f1)"
else
    echo "[1/6] Image already decompressed"
fi

# Step 2: Analyze partition layout
echo ""
echo "[2/6] Analyzing partition layout..."
if command -v fdisk &>/dev/null; then
    fdisk -l a7z-stock.img > partition-layout.txt 2>&1 || true
fi
if command -v parted &>/dev/null; then
    parted a7z-stock.img print >> partition-layout.txt 2>&1 || true
fi
echo "✓ Partition layout saved"

# Step 3: Extract boot sectors (works without mounting)
echo ""
echo "[3/6] Extracting boot sectors (boot0 + U-Boot)..."
dd if=a7z-stock.img of=boot-sectors.img bs=1M count=16 2>/dev/null
echo "✓ Extracted 16 MB boot sectors"

# Step 4: Try to extract using offset mounting (Linux/WSL only)
echo ""
echo "[4/6] Attempting to mount partitions..."

# Calculate offsets from partition table
# Typically: p1=32768 sectors, p2=~65536 sectors, p3=~655360 sectors
# Sector size = 512 bytes

OFFSET_P2=$((512 * 65536))   # ~32 MB, 300 MB EFI partition
OFFSET_P3=$((512 * 655360))  # ~320 MB, rootfs partition

mkdir -p mnt_boot mnt_root

# Try mounting partition 2 (boot)
if sudo mount -o loop,offset=$OFFSET_P2 a7z-stock.img mnt_boot 2>/dev/null; then
    echo "✓ Mounted partition 2 (boot) at offset $OFFSET_P2"

    # Extract DTB
    if [ -f mnt_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ]; then
        sudo cp mnt_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ./
        dtc -I dtb -O dts -o stock-a7z.dts sun60i-a733-cubie-a7z.dtb 2>/dev/null
        echo "  ✓ Extracted and decompiled DTB"
    fi

    # Extract extlinux.conf
    if [ -f mnt_boot/extlinux/extlinux.conf ]; then
        sudo cp mnt_boot/extlinux/extlinux.conf ./stock-extlinux.conf
        echo "  ✓ Extracted extlinux.conf"
    fi

    # Extract kernel config
    sudo cp mnt_boot/config-* ./stock-kernel.config 2>/dev/null || true

    # Extract Image
    sudo cp mnt_boot/Image ./stock-Image 2>/dev/null || true

    sudo umount mnt_boot
else
    echo "⚠ Cannot mount partition 2 (need Linux/WSL with sudo)"
fi

# Try mounting partition 3 (rootfs)
if sudo mount -o loop,offset=$OFFSET_P3 a7z-stock.img mnt_root 2>/dev/null; then
    echo "✓ Mounted partition 3 (rootfs)"

    # Extract fstab
    if [ -f mnt_root/etc/fstab ]; then
        sudo cp mnt_root/etc/fstab ./stock-fstab
        echo "  ✓ Extracted fstab"
    fi

    sudo umount mnt_root
else
    echo "⚠ Cannot mount partition 3"
fi

rmdir mnt_boot mnt_root 2>/dev/null || true

# Step 5: Compare with our configs
echo ""
echo "[5/6] Comparing with project configurations..."

if [ -f "stock-a7z.dts" ]; then
    echo ""
    echo "=== DTS Comparison ==="
    diff -u "$PROJECT_ROOT/configs/a7z/board.dts" stock-a7z.dts > dts-diff.patch || true
    DIFF_LINES=$(wc -l < dts-diff.patch)
    if [ "$DIFF_LINES" -gt 5 ]; then
        echo "⚠ Found $DIFF_LINES lines of differences"
        echo "Key differences:"
        head -50 dts-diff.patch
    else
        echo "✓ DTB files are very similar"
    fi
fi

if [ -f "stock-kernel.config" ]; then
    echo ""
    echo "=== Kernel Config Comparison ==="
    diff "$PROJECT_ROOT/configs/a7z/cubie_a7z_defconfig" stock-kernel.config > config-diff.txt 2>&1 || true
    echo "Differences: $(wc -l < config-diff.txt) lines"
    echo "UFS-related configs in stock:"
    grep -E "UFS|SCSI" stock-kernel.config | head -10
fi

if [ -f "stock-extlinux.conf" ]; then
    echo ""
    echo "=== Boot Config Comparison ==="
    echo "Stock extlinux.conf:"
    cat stock-extlinux.conf
fi

if [ -f "stock-fstab" ]; then
    echo ""
    echo "=== fstab Comparison ==="
    echo "Stock fstab:"
    cat stock-fstab
fi

# Step 6: Summary
echo ""
echo "[6/6] Summary"
echo "================================"
echo "Extracted files in: $OUTPUT_DIR/"
ls -lh | grep -v "^d" | grep -v "^total"

echo ""
echo "✅ Extraction complete!"
echo ""
echo "Next steps:"
echo "  1. Review dts-diff.patch to see device tree differences"
echo "  2. Review config-diff.txt for kernel config differences"
echo "  3. Update configs/a7z/* if stock version has critical fixes"
echo "  4. Re-run GitHub Actions build after updating configs"
