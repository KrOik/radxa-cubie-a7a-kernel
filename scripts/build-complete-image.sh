#!/bin/bash
# Build complete A7Z bootable image from kernel build artifacts
# Usage: ./build-complete-image.sh <kernel-tarball> <output-image>

set -uo pipefail

KERNEL_TARBALL="${1:-}"
OUTPUT_IMAGE="${2:-radxa-cubie-a7z.img}"
WORK_DIR="$(pwd)/image_build_work"

# Image configuration
IMAGE_SIZE="4096"  # 4GB in MB
PARTITION_1_SIZE="16"    # 16 MB - config partition
PARTITION_2_SIZE="300"   # 300 MB - EFI/boot partition
# Partition 3 gets remaining space - rootfs

usage() {
    echo "Usage: $0 <kernel-tarball.tar.gz> [output-image.img]"
    echo ""
    echo "Example:"
    echo "  $0 release-tarball-a7z.tar.gz radxa-cubie-a7z.img"
    echo ""
    echo "Requirements:"
    echo "  - Linux environment (native or WSL)"
    echo "  - sudo privileges for loop device mounting"
    echo "  - parted, mkfs.vfat, mkfs.ext4, sfdisk"
    exit 1
}

if [ -z "$KERNEL_TARBALL" ] || [ ! -f "$KERNEL_TARBALL" ]; then
    echo "Error: Kernel tarball not found: $KERNEL_TARBALL"
    usage
fi

echo "=== Radxa Cubie A7Z Complete Image Builder ==="
echo "Kernel source: $KERNEL_TARBALL"
echo "Output image: $OUTPUT_IMAGE"
echo "Image size: ${IMAGE_SIZE} MB"
echo ""

# Check dependencies
for cmd in parted mkfs.vfat mkfs.ext4 dd tar partx; do
    if ! command -v $cmd &>/dev/null; then
        echo "Error: Required command '$cmd' not found"
        exit 1
    fi
done

# Cleanup old work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Step 1: Create empty image file
echo "[1/9] Creating ${IMAGE_SIZE}MB image file..."
dd if=/dev/zero of="$OUTPUT_IMAGE" bs=1M count="$IMAGE_SIZE" status=progress
echo "✓ Image file created"

# Step 2: Create GPT partition table
echo ""
echo "[2/9] Creating GPT partition table..."
parted -s "$OUTPUT_IMAGE" mklabel gpt

# Calculate partition boundaries (in MB)
START_1=1
END_1=$((START_1 + PARTITION_1_SIZE))

START_2=$END_1
END_2=$((START_2 + PARTITION_2_SIZE))

START_3=$END_2
END_3=$((IMAGE_SIZE - 1))  # Leave 1MB at end

# Create partitions
parted -s "$OUTPUT_IMAGE" mkpart primary ext4 "${START_1}MB" "${END_1}MB"
parted -s "$OUTPUT_IMAGE" mkpart primary fat32 "${START_2}MB" "${END_2}MB"
parted -s "$OUTPUT_IMAGE" mkpart primary ext4 "${START_3}MB" "${END_3}MB"

# Set partition types
parted -s "$OUTPUT_IMAGE" set 2 esp on  # Mark partition 2 as EFI System Partition
parted -s "$OUTPUT_IMAGE" name 1 config
parted -s "$OUTPUT_IMAGE" name 2 boot
parted -s "$OUTPUT_IMAGE" name 3 rootfs

# Set partition type GUIDs using sfdisk
sfdisk --part-type "$OUTPUT_IMAGE" 1 8300  # Linux filesystem
sfdisk --part-type "$OUTPUT_IMAGE" 2 EF00  # EFI System
sfdisk --part-type "$OUTPUT_IMAGE" 3 8300  # Linux filesystem

echo "✓ Partition table created"
parted -s "$OUTPUT_IMAGE" print

# Step 3: Setup loop device with partx (GPT support)
echo ""
echo "[3/9] Setting up loop device..."
LOOP_BASE=$(sudo losetup -f --show "$OUTPUT_IMAGE")
echo "Loop device: $LOOP_BASE"

# Use partx to add GPT partitions
sudo partx -a "$LOOP_BASE" || true
sleep 2

# List partitions to verify
ls -la ${LOOP_BASE}* || true
echo "✓ Partitions registered"

# Step 4: Format partitions
echo ""
echo "[4/9] Formatting partitions..."
sudo mkfs.ext4 -F -L config "${LOOP_BASE}p1"
sudo mkfs.vfat -F 32 -n BOOT "${LOOP_BASE}p2"
sudo mkfs.ext4 -F -L rootfs "${LOOP_BASE}p3"
echo "✓ Partitions formatted"

# Step 5: Mount partitions
echo ""
echo "[5/9] Mounting partitions..."
sudo mkdir -p "$WORK_DIR/mnt/config"
sudo mkdir -p "$WORK_DIR/mnt/boot"
sudo mkdir -p "$WORK_DIR/mnt/rootfs"

sudo mount "${LOOP_BASE}p1" "$WORK_DIR/mnt/config"
sudo mount "${LOOP_BASE}p2" "$WORK_DIR/mnt/boot"
sudo mount "${LOOP_BASE}p3" "$WORK_DIR/mnt/rootfs"
echo "✓ Partitions mounted"

# Step 6: Extract kernel tarball
echo ""
echo "[6/9] Extracting kernel tarball..."
mkdir -p "$WORK_DIR/kernel_extract"
tar -xzf "$KERNEL_TARBALL" -C "$WORK_DIR/kernel_extract"
echo "✓ Kernel extracted"

# Step 7: Install kernel to boot partition
echo ""
echo "[7/9] Installing kernel to boot partition..."
sudo mkdir -p "$WORK_DIR/mnt/boot/extlinux"
sudo mkdir -p "$WORK_DIR/mnt/boot/dtb/allwinner"

# Copy kernel Image
if [ -f "$WORK_DIR/kernel_extract/boot/Image" ]; then
    sudo cp "$WORK_DIR/kernel_extract/boot/Image" "$WORK_DIR/mnt/boot/"
    echo "  ✓ Copied Image"
fi

# Copy DTB
if [ -f "$WORK_DIR/kernel_extract/boot/sun60i-a733-cubie-a7z.dtb" ]; then
    sudo cp "$WORK_DIR/kernel_extract/boot/sun60i-a733-cubie-a7z.dtb" \
        "$WORK_DIR/mnt/boot/dtb/allwinner/"
    echo "  ✓ Copied DTB"
fi

# Create extlinux.conf
sudo tee "$WORK_DIR/mnt/boot/extlinux/extlinux.conf" >/dev/null <<'EOF'
label Radxa Cubie A7Z (Custom 6.6.98+ Overclocked)
  kernel /Image
  fdt /dtb/allwinner/sun60i-a733-cubie-a7z.dtb
  append root=/dev/sda3 rw rootwait console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000

label recovery
  kernel /Image
  fdt /dtb/allwinner/sun60i-a733-cubie-a7z.dtb
  append root=/dev/sda3 ro rootwait console=ttyS0,115200 single
EOF
echo "  ✓ Created extlinux.conf"

# Step 8: Install kernel modules to rootfs
echo ""
echo "[8/9] Installing kernel modules to rootfs..."
if [ -d "$WORK_DIR/kernel_extract/lib/modules" ]; then
    sudo cp -r "$WORK_DIR/kernel_extract/lib/modules" "$WORK_DIR/mnt/rootfs/lib/"
    echo "  ✓ Copied kernel modules"
fi

# Create basic rootfs structure
sudo mkdir -p "$WORK_DIR/mnt/rootfs"/{bin,boot,dev,etc,home,lib,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
sudo mkdir -p "$WORK_DIR/mnt/rootfs/etc"

# Create fstab
sudo tee "$WORK_DIR/mnt/rootfs/etc/fstab" >/dev/null <<'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
/dev/sda3       /             ext4   defaults,noatime 0 1
/dev/sda2       /boot         vfat   defaults         0 2
/dev/sda1       /boot/config  ext4   defaults         0 2
EOF
echo "  ✓ Created fstab"

# Create hostname
echo "radxa-cubie-a7z" | sudo tee "$WORK_DIR/mnt/rootfs/etc/hostname" >/dev/null

echo "✓ Rootfs structure created"

# Step 9: Write boot sectors (boot0 + U-Boot)
echo ""
echo "[9/9] Writing boot sectors..."
# Check if we have extracted boot sectors from stock image
if [ -f "extracted_a7z/boot-sectors.img" ]; then
    echo "Using boot sectors from stock A7Z image..."
    sudo dd if="extracted_a7z/boot-sectors.img" of="$LOOP_BASE" bs=1K seek=8 conv=notrunc,fsync
    echo "  ✓ Wrote 16 MB boot sectors (boot0 + U-Boot)"
    BOOTABLE_STATUS="✅ BOOTABLE"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  CRITICAL: Boot sectors (boot0 + U-Boot) NOT included"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This image contains:"
    echo "  ✅ GPT partition table (sda1/sda2/sda3)"
    echo "  ✅ Custom kernel 6.6.98+ with overclock support"
    echo "  ✅ Kernel modules"
    echo "  ✅ Basic rootfs structure"
    echo ""
    echo "Missing (will NOT boot without this):"
    echo "  ❌ boot0 (Allwinner BROM first-stage bootloader)"
    echo "  ❌ U-Boot (second-stage bootloader)"
    echo ""
    echo "To make this image bootable, you need to:"
    echo "  1. Obtain A7Z boot sectors from stock image"
    echo "  2. Write them to offset 8KB:"
    echo "     dd if=boot-sectors.img of=$OUTPUT_IMAGE bs=1K seek=8 conv=notrunc"
    echo ""
    echo "Alternatively:"
    echo "  - Flash this image to A7Z UFS"
    echo "  - Boot from SD card with working U-Boot"
    echo "  - U-Boot will find kernel on UFS partition 2"
    echo ""
    BOOTABLE_STATUS="⚠️  NEEDS BOOT SECTORS"
fi

# Cleanup
echo ""
echo "Cleaning up..."
sudo umount "$WORK_DIR/mnt/config" "$WORK_DIR/mnt/boot" "$WORK_DIR/mnt/rootfs" 2>/dev/null || true
sudo losetup -d "$LOOP_BASE" || true
sudo rm -rf "$WORK_DIR"

echo ""
echo "================================================"
echo "${BOOTABLE_STATUS}: Image build complete"
echo ""
echo "Output: $OUTPUT_IMAGE (${IMAGE_SIZE} MB)"
echo ""
echo "Partition layout:"
echo "  - /dev/sda1 (16 MB)  - config partition (ext4)"
echo "  - /dev/sda2 (300 MB) - boot partition (vfat, EFI System)"
echo "  - /dev/sda3 (rest)   - rootfs partition (ext4)"
echo ""
echo "Next steps:"
echo "  1. Compress: xz -9 -T0 $OUTPUT_IMAGE"
echo "  2. Flash to A7Z device: dd if=${OUTPUT_IMAGE}.xz bs=4M status=progress | xz -d | dd of=/dev/sdX bs=4M"
echo ""
if [ "$BOOTABLE_STATUS" = "✅ BOOTABLE" ]; then
    echo "✅ This image is ready to boot on A7Z hardware"
else
    echo "⚠️  This image requires boot sectors to be added before it can boot"
    echo "   See warning message above for details"
fi
echo ""
