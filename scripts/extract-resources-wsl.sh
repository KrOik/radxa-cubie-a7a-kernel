#!/bin/bash
# Extract A7Z resources using WSL docker-desktop distribution
# Optimized for Windows environment with existing stock image

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STOCK_IMG="$PROJECT_ROOT/extracted_a7z/a7z-stock.img"
OUTPUT_DIR="$PROJECT_ROOT/extracted_a7z"

echo "=== A7Z Resource Extraction (WSL) ==="
echo "Stock image: $STOCK_IMG"
echo "Output: $OUTPUT_DIR/"
echo ""

# Check if stock image exists
if [ ! -f "$STOCK_IMG" ]; then
    echo "Error: Stock image not found at: $STOCK_IMG"
    echo "Expected: extracted_a7z/a7z-stock.img (10 GB decompressed)"
    exit 1
fi

echo "Stock image size: $(du -h "$STOCK_IMG" | cut -f1)"

# Step 1: Analyze partition layout
echo ""
echo "[1/7] Analyzing partition layout..."
parted -s "$STOCK_IMG" print > "$OUTPUT_DIR/partition-layout.txt" 2>&1 || true
fdisk -l "$STOCK_IMG" >> "$OUTPUT_DIR/partition-layout.txt" 2>&1 || true

echo "Partition layout:"
cat "$OUTPUT_DIR/partition-layout.txt" | grep -E "^(Disk|Number|/dev)"

# Step 2: Extract boot sectors (no mounting needed)
echo ""
echo "[2/7] Extracting boot sectors..."
if [ ! -f "$OUTPUT_DIR/boot-sectors.img" ]; then
    dd if="$STOCK_IMG" of="$OUTPUT_DIR/boot-sectors.img" bs=1M count=16 status=progress 2>/dev/null
    echo "✓ Extracted 16 MB boot sectors"
else
    echo "✓ Boot sectors already extracted"
fi

# Step 3: Setup loop device
echo ""
echo "[3/7] Setting up loop device..."
LOOP_DEV=$(sudo losetup -f --show "$STOCK_IMG")
sudo partprobe "$LOOP_DEV"
sleep 2
echo "✓ Loop device: $LOOP_DEV"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    sudo umount "$OUTPUT_DIR/mnt_boot" 2>/dev/null || true
    sudo umount "$OUTPUT_DIR/mnt_root" 2>/dev/null || true
    if [ -n "${LOOP_DEV:-}" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    sudo rm -rf "$OUTPUT_DIR/mnt_boot" "$OUTPUT_DIR/mnt_root"
}
trap cleanup EXIT

# Step 4: Mount boot partition
echo ""
echo "[4/7] Mounting boot partition (p2)..."
mkdir -p "$OUTPUT_DIR/mnt_boot"
if sudo mount "${LOOP_DEV}p2" "$OUTPUT_DIR/mnt_boot"; then
    echo "✓ Mounted boot partition"

    # Extract DTB
    if [ -f "$OUTPUT_DIR/mnt_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" ]; then
        sudo cp "$OUTPUT_DIR/mnt_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb" \
            "$OUTPUT_DIR/stock-a7z.dtb"
        sudo chown $(whoami) "$OUTPUT_DIR/stock-a7z.dtb"

        # Decompile to DTS
        dtc -I dtb -O dts -o "$OUTPUT_DIR/stock-a7z.dts" \
            "$OUTPUT_DIR/stock-a7z.dtb" 2>/dev/null || true
        echo "  ✓ Extracted DTB and decompiled to DTS"
    fi

    # Extract extlinux.conf
    if [ -f "$OUTPUT_DIR/mnt_boot/extlinux/extlinux.conf" ]; then
        sudo cp "$OUTPUT_DIR/mnt_boot/extlinux/extlinux.conf" \
            "$OUTPUT_DIR/stock-extlinux.conf"
        sudo chown $(whoami) "$OUTPUT_DIR/stock-extlinux.conf"
        echo "  ✓ Extracted extlinux.conf"
    fi

    # Extract kernel config
    sudo cp "$OUTPUT_DIR/mnt_boot"/config-* "$OUTPUT_DIR/stock-kernel.config" 2>/dev/null || true
    if [ -f "$OUTPUT_DIR/stock-kernel.config" ]; then
        sudo chown $(whoami) "$OUTPUT_DIR/stock-kernel.config"
        echo "  ✓ Extracted kernel config"
    fi

    # Extract kernel Image
    if [ -f "$OUTPUT_DIR/mnt_boot/Image" ]; then
        sudo cp "$OUTPUT_DIR/mnt_boot/Image" "$OUTPUT_DIR/stock-Image"
        sudo chown $(whoami) "$OUTPUT_DIR/stock-Image"
        echo "  ✓ Extracted kernel Image ($(du -h "$OUTPUT_DIR/stock-Image" | cut -f1))"
    fi
else
    echo "⚠ Failed to mount boot partition"
fi

# Step 5: Mount rootfs partition
echo ""
echo "[5/7] Mounting rootfs partition (p3)..."
mkdir -p "$OUTPUT_DIR/mnt_root"
if sudo mount "${LOOP_DEV}p3" "$OUTPUT_DIR/mnt_root"; then
    echo "✓ Mounted rootfs partition"

    # Extract fstab
    if [ -f "$OUTPUT_DIR/mnt_root/etc/fstab" ]; then
        sudo cp "$OUTPUT_DIR/mnt_root/etc/fstab" "$OUTPUT_DIR/stock-fstab"
        sudo chown $(whoami) "$OUTPUT_DIR/stock-fstab"
        echo "  ✓ Extracted fstab"
    fi
else
    echo "⚠ Failed to mount rootfs partition"
fi

# Step 6: Compare with our configs
echo ""
echo "[6/7] Comparing with project configurations..."

if [ -f "$OUTPUT_DIR/stock-a7z.dts" ]; then
    echo ""
    echo "=== DTS Comparison ==="
    diff -u "$PROJECT_ROOT/configs/a7z/board.dts" "$OUTPUT_DIR/stock-a7z.dts" \
        > "$OUTPUT_DIR/dts-diff.patch" 2>&1 || true

    DIFF_LINES=$(wc -l < "$OUTPUT_DIR/dts-diff.patch")
    if [ "$DIFF_LINES" -gt 10 ]; then
        echo "⚠ Found $DIFF_LINES lines of differences"
        echo "First 30 lines:"
        head -30 "$OUTPUT_DIR/dts-diff.patch"
    else
        echo "✓ DTB files are very similar (only $DIFF_LINES differences)"
    fi
fi

if [ -f "$OUTPUT_DIR/stock-kernel.config" ]; then
    echo ""
    echo "=== Kernel Config Comparison ==="
    diff "$PROJECT_ROOT/configs/a7z/cubie_a7z_defconfig" "$OUTPUT_DIR/stock-kernel.config" \
        > "$OUTPUT_DIR/config-diff.txt" 2>&1 || true
    echo "Differences: $(wc -l < "$OUTPUT_DIR/config-diff.txt") lines"

    echo ""
    echo "UFS-related configs in stock:"
    grep -E "UFS|SCSI.*UFS" "$OUTPUT_DIR/stock-kernel.config" | head -10
fi

if [ -f "$OUTPUT_DIR/stock-extlinux.conf" ]; then
    echo ""
    echo "=== Boot Config (stock) ==="
    cat "$OUTPUT_DIR/stock-extlinux.conf"
fi

if [ -f "$OUTPUT_DIR/stock-fstab" ]; then
    echo ""
    echo "=== fstab (stock) ==="
    cat "$OUTPUT_DIR/stock-fstab"
fi

# Step 7: Summary
echo ""
echo "[7/7] Extraction Summary"
echo "================================"
echo "Extracted files in $OUTPUT_DIR/:"
ls -lh "$OUTPUT_DIR" | grep -E "stock-|boot-sectors|partition" | awk '{print $9, $5}'

echo ""
echo "✅ Extraction complete!"
echo ""
echo "Key files:"
echo "  - stock-a7z.dtb / .dts : Device tree"
echo "  - stock-kernel.config  : Kernel configuration"
echo "  - stock-extlinux.conf  : Boot configuration"
echo "  - stock-fstab          : Filesystem table"
echo "  - boot-sectors.img     : Boot0 + U-Boot (16 MB)"
echo ""
echo "Comparison files:"
echo "  - dts-diff.patch       : DTS differences"
echo "  - config-diff.txt      : Kernel config differences"
echo ""
