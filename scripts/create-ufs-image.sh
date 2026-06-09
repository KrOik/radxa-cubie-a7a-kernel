#!/bin/bash
# Create UFS-compatible A7Z image with 4096-byte sectors
# UFS devices use 4096-byte logical sectors, not 512-byte
set -eo pipefail

IMAGE_FILE="${1:-radxa-cubie-a7z-ufs.img}"
KERNEL_TARBALL="${2}"
STOCK_BOOT="${3:-radxa-a733_bullseye_kde_r6.output_4096.img.xz}"
IMAGE_SIZE_GB="${4:-4}"

if [ -z "$KERNEL_TARBALL" ]; then
    echo "Usage: $0 <output-image> <kernel-tarball> [stock-boot-image] [size-in-gb]"
    echo ""
    echo "This script creates a UFS-compatible image with 4096-byte sectors"
    echo "Regular images use 512-byte sectors and won't boot on UFS storage"
    exit 1
fi

if [ ! -f "$KERNEL_TARBALL" ]; then
    echo "ERROR: Kernel tarball not found: $KERNEL_TARBALL"
    exit 1
fi

echo "=== Creating UFS-Compatible A7Z Image (4096-byte sectors) ==="
echo "Output: $IMAGE_FILE"
echo "Kernel: $KERNEL_TARBALL"
echo "Boot sectors: $STOCK_BOOT"
echo "Size: ${IMAGE_SIZE_GB}GB"
echo ""

# Extract kernel files
KERNEL_STAGING="kernel_staging_$$"
mkdir -p "$KERNEL_STAGING"
echo "Extracting kernel tarball..."
tar -xzf "$KERNEL_TARBALL" -C "$KERNEL_STAGING/"
echo "✓ Kernel extracted"

# Calculate image size in 4096-byte blocks
BLOCK_SIZE=4096
BLOCKS_PER_GB=$((1024 * 1024 * 1024 / BLOCK_SIZE))
TOTAL_BLOCKS=$((IMAGE_SIZE_GB * BLOCKS_PER_GB))

# Step 1: Create sparse image with 4096-byte blocks
echo ""
echo "[1/9] Creating ${IMAGE_SIZE_GB}GB image with 4096-byte sectors..."
dd if=/dev/zero of="$IMAGE_FILE" bs=$BLOCK_SIZE count=$TOTAL_BLOCKS status=progress
echo "✓ Image created ($TOTAL_BLOCKS blocks × 4096 bytes)"

# Step 2: Create GPT with 4096-byte sector size
echo ""
echo "[2/9] Creating GPT partition table (4096-byte sectors)..."

# Use sgdisk which supports non-512 sector sizes better
# Alternative: use parted with sector size specification
cat > /tmp/parted_script_$$.txt <<EOF
unit s
mklabel gpt
mkpart primary 512 4095
name 1 uboot
mkpart primary ext4 4096 36863
name 2 boot
set 2 boot on
mkpart primary ext4 36864 100%
name 3 rootfs
quit
EOF

# Apply partition table (parted will auto-detect or we force with environment)
PARTED_SECTOR_SIZE=4096 parted ---pretend-input-tty "$IMAGE_FILE" < /tmp/parted_script_$$.txt 2>&1 || {
    echo "Regular parted doesn't support 4096 sectors, trying sgdisk..."

    # Fallback: use sgdisk
    sgdisk -Z "$IMAGE_FILE"  # Zap existing
    sgdisk -o "$IMAGE_FILE"  # Create new GPT

    # Partition 1: U-Boot (2MB-16MB = sectors 512-4095 in 4K blocks)
    sgdisk -n 1:512:4095 -t 1:8300 -c 1:uboot "$IMAGE_FILE"

    # Partition 2: Boot (16MB-144MB = sectors 4096-36863)
    sgdisk -n 2:4096:36863 -t 2:8300 -c 2:boot "$IMAGE_FILE"
    sgdisk -A 2:set:2 "$IMAGE_FILE"  # Set legacy boot flag

    # Partition 3: Root (144MB-end)
    sgdisk -n 3:36864:0 -t 3:8300 -c 3:rootfs "$IMAGE_FILE"
}

rm -f /tmp/parted_script_$$.txt

echo "✓ GPT created with 4096-byte sectors"
sgdisk -p "$IMAGE_FILE" 2>&1 || parted -s "$IMAGE_FILE" print

# Step 3: Extract boot sectors from stock image
echo ""
echo "[3/9] Extracting U-Boot from stock image..."
BOOT_SECTORS="boot-ufs-4k.img"

if [ -f "$STOCK_BOOT" ]; then
    echo "  Extracting first 16MB (4096 blocks × 4096 bytes)..."
    xz -d -c "$STOCK_BOOT" 2>/dev/null | dd bs=$BLOCK_SIZE count=4096 of="$BOOT_SECTORS" status=none
    echo "  ✓ U-Boot extracted (16MB)"
else
    echo "  WARNING: Stock boot image not found"
    echo "  You'll need to install U-Boot separately"
    touch "$BOOT_SECTORS"
fi

# Step 4: Write boot sectors at 8KB offset (preserving GPT)
echo ""
echo "[4/9] Installing U-Boot at 8KB offset..."
if [ -s "$BOOT_SECTORS" ]; then
    # Write starting at block 2 (8KB offset)
    dd if="$BOOT_SECTORS" of="$IMAGE_FILE" bs=$BLOCK_SIZE seek=2 conv=notrunc,fsync status=none
    echo "✓ U-Boot installed"
else
    echo "⚠ Skipped (no boot sectors)"
fi

# Step 5: Setup loop devices
echo ""
echo "[5/9] Setting up loop devices..."

# Get partition info (in 4K blocks)
PART_INFO=$(sgdisk -i 2 "$IMAGE_FILE" 2>&1 || parted -s "$IMAGE_FILE" unit s print)
BOOT_START=$(echo "$PART_INFO" | grep -oP '(?<=First sector: )\d+' || echo "4096")
BOOT_END=$(echo "$PART_INFO" | grep -oP '(?<=Last sector: )\d+' || echo "36863")

PART_INFO=$(sgdisk -i 3 "$IMAGE_FILE" 2>&1 || parted -s "$IMAGE_FILE" unit s print)
ROOTFS_START=$(echo "$PART_INFO" | grep -oP '(?<=First sector: )\d+' || echo "36864")

# Calculate offsets and sizes in bytes
BOOT_OFFSET=$((BOOT_START * BLOCK_SIZE))
BOOT_SIZE=$(( (BOOT_END - BOOT_START + 1) * BLOCK_SIZE ))
ROOTFS_OFFSET=$((ROOTFS_START * BLOCK_SIZE))

# Setup loop devices with proper offsets
BOOT_LOOP=$(sudo losetup -f --show -o $BOOT_OFFSET --sizelimit $BOOT_SIZE "$IMAGE_FILE")
ROOTFS_LOOP=$(sudo losetup -f --show -o $ROOTFS_OFFSET "$IMAGE_FILE")

echo "✓ Boot: $BOOT_LOOP (offset $BOOT_OFFSET, size $BOOT_SIZE)"
echo "✓ Root: $ROOTFS_LOOP (offset $ROOTFS_OFFSET)"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    sudo umount "$ROOTFS_MNT/boot" 2>/dev/null || true
    sudo umount "$ROOTFS_MNT" 2>/dev/null || true
    sudo losetup -d "$BOOT_LOOP" 2>/dev/null || true
    sudo losetup -d "$ROOTFS_LOOP" 2>/dev/null || true
    sudo rmdir "$ROOTFS_MNT" 2>/dev/null || true
    rm -rf "$KERNEL_STAGING" "$BOOT_SECTORS"
}
trap cleanup EXIT

# Step 6: Format partitions
echo ""
echo "[6/9] Formatting partitions..."
sudo mkfs.ext4 -L boot -b 4096 -F "$BOOT_LOOP"
sudo mkfs.ext4 -L rootfs -b 4096 -F "$ROOTFS_LOOP"
echo "✓ Formatted with 4096-byte blocks"

# Step 7: Mount and install base system
echo ""
echo "[7/9] Mounting partitions..."
ROOTFS_MNT="/mnt/a7z_ufs_$$"
sudo mkdir -p "$ROOTFS_MNT"
sudo mount "$ROOTFS_LOOP" "$ROOTFS_MNT"
sudo mkdir -p "$ROOTFS_MNT/boot"
sudo mount "$BOOT_LOOP" "$ROOTFS_MNT/boot"
echo "✓ Mounted"

echo ""
echo "[8/9] Installing Debian 13 + kernel..."
echo "  This takes 5-10 minutes..."

# Install minimal Debian
sudo debootstrap --arch=arm64 --variant=minbase \
    --include=systemd,udev,kmod,init,locales,ca-certificates,sudo,openssh-server,ifupdown,isc-dhcp-client,net-tools \
    trixie "$ROOTFS_MNT" http://deb.debian.org/debian

# Configure system
echo "radxa-a7z" | sudo tee "$ROOTFS_MNT/etc/hostname" >/dev/null

sudo tee "$ROOTFS_MNT/etc/fstab" >/dev/null <<'FSTAB'
LABEL=rootfs    /           ext4    defaults,noatime    0 1
LABEL=boot      /boot       ext4    defaults,noatime    0 2
FSTAB

# Install kernel
echo "  Installing kernel..."
if [ -f "$KERNEL_STAGING/boot/Image" ]; then
    sudo cp "$KERNEL_STAGING/boot/Image" "$ROOTFS_MNT/boot/"
fi
if ls "$KERNEL_STAGING/boot/"*.dtb >/dev/null 2>&1; then
    sudo cp "$KERNEL_STAGING/boot/"*.dtb "$ROOTFS_MNT/boot/" 2>/dev/null || true
fi
if [ -d "$KERNEL_STAGING/lib/modules" ]; then
    sudo cp -r "$KERNEL_STAGING/lib/modules/"* "$ROOTFS_MNT/lib/modules/"
fi

# Boot config
sudo mkdir -p "$ROOTFS_MNT/boot/extlinux"
sudo tee "$ROOTFS_MNT/boot/extlinux/extlinux.conf" >/dev/null <<'EXTLINUX'
label Debian
    kernel /boot/Image
    fdt /boot/sun60i-a733-cubie-a7z.dtb
    append root=LABEL=rootfs rootwait rw console=ttyS0,115200 console=tty1
EXTLINUX

# Set passwords
echo "root:debian" | sudo chroot "$ROOTFS_MNT" chpasswd
sudo chroot "$ROOTFS_MNT" useradd -m -s /bin/bash -G sudo radxa || true
echo "radxa:radxa" | sudo chroot "$ROOTFS_MNT" chpasswd

# Enable SSH
sudo chroot "$ROOTFS_MNT" systemctl enable ssh

# Network config
sudo tee "$ROOTFS_MNT/etc/network/interfaces" >/dev/null <<'INTERFACES'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto end0
iface end0 inet dhcp
INTERFACES

# Locale
echo "en_US.UTF-8 UTF-8" | sudo tee "$ROOTFS_MNT/etc/locale.gen" >/dev/null
sudo chroot "$ROOTFS_MNT" locale-gen

echo "✓ System installed and configured"

# Step 9: Finalize
echo ""
echo "[9/9] Finalizing..."
sync

# Cleanup happens via trap

echo ""
echo "================================================"
echo "✅ UFS-Compatible Image Ready"
echo "================================================"
echo ""
echo "Image: $IMAGE_FILE"
echo "Sector size: 4096 bytes (UFS compatible)"
echo ""
echo "Flash to UFS storage:"
echo "  Linux:   sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4096 status=progress"
echo "  macOS:   sudo dd if=$IMAGE_FILE of=/dev/rdiskX bs=4096"
echo "  Windows: Use Win32DiskImager or Rufus (DD mode)"
echo ""
echo "Default credentials:"
echo "  root / debian"
echo "  radxa / radxa"
echo ""
echo "Serial console: 115200 8N1"
echo ""
