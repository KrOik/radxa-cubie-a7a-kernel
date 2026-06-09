#!/bin/bash
# Create Radxa A7Z image from scratch with Debian 13
set -eo pipefail

IMAGE_FILE="${1}"
KERNEL_TARBALL="${2}"
IMAGE_SIZE_GB="${3:-10}"

if [ -z "$IMAGE_FILE" ] || [ -z "$KERNEL_TARBALL" ]; then
    echo "Usage: $0 <output-image> <kernel-tarball> [size-in-gb]"
    exit 1
fi

if [ ! -f "$KERNEL_TARBALL" ]; then
    echo "ERROR: Kernel tarball not found: $KERNEL_TARBALL"
    exit 1
fi

echo "=== Building Debian 13 A7Z Image from Scratch ==="
echo "Output: $IMAGE_FILE"
echo "Kernel: $KERNEL_TARBALL"
echo "Size: ${IMAGE_SIZE_GB}GB"
echo ""

# Extract kernel files
KERNEL_STAGING="kernel_staging_$$"
mkdir -p "$KERNEL_STAGING"
tar -xzf "$KERNEL_TARBALL" -C "$KERNEL_STAGING/"
echo "✓ Kernel extracted"

# Step 1: Create empty image
echo ""
echo "[1/8] Creating ${IMAGE_SIZE_GB}GB disk image..."
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count=$((IMAGE_SIZE_GB * 1024)) status=progress
echo "✓ Image file created"

# Step 2: Create GPT partition table
echo ""
echo "[2/8] Creating GPT partition table..."
parted -s "$IMAGE_FILE" mklabel gpt

# Create partitions:
# 1: U-Boot SPL (8MB, raw)
# 2: Boot partition (128MB, ext4)
# 3: Root partition (remaining space, ext4)
parted -s "$IMAGE_FILE" mkpart primary 2048s 18431s
parted -s "$IMAGE_FILE" name 1 uboot
parted -s "$IMAGE_FILE" mkpart primary ext4 18432s 280575s
parted -s "$IMAGE_FILE" name 2 boot
parted -s "$IMAGE_FILE" set 2 boot on
parted -s "$IMAGE_FILE" mkpart primary ext4 280576s 100%
parted -s "$IMAGE_FILE" name 3 rootfs

echo "✓ Partitions created"
parted -s "$IMAGE_FILE" print

# Step 3: Setup loop devices with offsets
echo ""
echo "[3/8] Setting up loop devices..."
PARTED_OUTPUT=$(parted -s "$IMAGE_FILE" unit s print)
BOOT_START=$(echo "$PARTED_OUTPUT" | awk '/^ 2 / {print $2}' | sed 's/s$//')
BOOT_END=$(echo "$PARTED_OUTPUT" | awk '/^ 2 / {print $3}' | sed 's/s$//')
ROOTFS_START=$(echo "$PARTED_OUTPUT" | awk '/^ 3 / {print $2}' | sed 's/s$//')
ROOTFS_END=$(echo "$PARTED_OUTPUT" | awk '/^ 3 / {print $3}' | sed 's/s$//')

BOOT_OFFSET=$((BOOT_START * 512))
BOOT_SIZE=$(( (BOOT_END - BOOT_START + 1) * 512 ))
ROOTFS_OFFSET=$((ROOTFS_START * 512))
ROOTFS_SIZE=$(( (ROOTFS_END - ROOTFS_START + 1) * 512 ))

BOOT_LOOP=$(sudo losetup -f --show -o $BOOT_OFFSET --sizelimit $BOOT_SIZE "$IMAGE_FILE")
ROOTFS_LOOP=$(sudo losetup -f --show -o $ROOTFS_OFFSET --sizelimit $ROOTFS_SIZE "$IMAGE_FILE")

echo "✓ Boot loop: $BOOT_LOOP (offset $BOOT_OFFSET, size $BOOT_SIZE bytes)"
echo "✓ Root loop: $ROOTFS_LOOP (offset $ROOTFS_OFFSET, size $ROOTFS_SIZE bytes)"

# Step 4: Format partitions
echo ""
echo "[4/8] Formatting partitions..."
sudo mkfs.ext4 -L boot -F "$BOOT_LOOP"
sudo mkfs.ext4 -L rootfs -F "$ROOTFS_LOOP"
echo "✓ Partitions formatted"

# Step 5: Mount partitions
echo ""
echo "[5/8] Mounting partitions..."
ROOTFS_MNT="/mnt/a7z_build_$$"
sudo mkdir -p "$ROOTFS_MNT"
sudo mount "$ROOTFS_LOOP" "$ROOTFS_MNT"
sudo mkdir -p "$ROOTFS_MNT/boot"
sudo mount "$BOOT_LOOP" "$ROOTFS_MNT/boot"
echo "✓ Partitions mounted"

# Step 6: Install Debian 13 base system
echo ""
echo "[6/8] Installing Debian 13 Trixie base system..."
echo "  This will take 5-10 minutes..."

sudo debootstrap --arch=arm64 --variant=minbase \
    --include=systemd,udev,kmod,init,locales,ca-certificates,apt-utils,sudo,openssh-server,network-manager \
    trixie "$ROOTFS_MNT" http://deb.debian.org/debian

echo "✓ Debian 13 base system installed"

# Step 7: Configure system and install kernel
echo ""
echo "[7/8] Configuring system..."

# Set hostname
echo "radxa-a7z" | sudo tee "$ROOTFS_MNT/etc/hostname" >/dev/null

# Configure fstab
sudo tee "$ROOTFS_MNT/etc/fstab" >/dev/null <<'EOF'
LABEL=rootfs    /           ext4    defaults,noatime    0 1
LABEL=boot      /boot       ext4    defaults,noatime    0 2
EOF

# Install custom kernel
echo "  Installing custom kernel..."
if [ -f "$KERNEL_STAGING/boot/Image" ]; then
    sudo cp "$KERNEL_STAGING/boot/Image" "$ROOTFS_MNT/boot/"
fi
if ls "$KERNEL_STAGING/boot/"*.dtb >/dev/null 2>&1; then
    sudo cp "$KERNEL_STAGING/boot/"*.dtb "$ROOTFS_MNT/boot/" 2>/dev/null || true
fi
if [ -d "$KERNEL_STAGING/lib/modules" ]; then
    sudo cp -r "$KERNEL_STAGING/lib/modules/"* "$ROOTFS_MNT/lib/modules/"
fi

# Create extlinux boot config
sudo mkdir -p "$ROOTFS_MNT/boot/extlinux"
sudo tee "$ROOTFS_MNT/boot/extlinux/extlinux.conf" >/dev/null <<'EOF'
label Debian
    kernel /boot/Image
    fdt /boot/sun60i-a733-cubie-a7z.dtb
    append root=LABEL=rootfs rootwait rw console=ttyS0,115200 console=tty1
EOF

# Set root password (debian)
echo "root:debian" | sudo chroot "$ROOTFS_MNT" chpasswd

# Create default user (radxa/radxa)
sudo chroot "$ROOTFS_MNT" useradd -m -s /bin/bash -G sudo radxa
echo "radxa:radxa" | sudo chroot "$ROOTFS_MNT" chpasswd

# Enable SSH
sudo chroot "$ROOTFS_MNT" systemctl enable ssh

# Configure locales
echo "en_US.UTF-8 UTF-8" | sudo tee "$ROOTFS_MNT/etc/locale.gen" >/dev/null
sudo chroot "$ROOTFS_MNT" locale-gen

echo "✓ System configured"
echo "  Default credentials: root/debian, radxa/radxa"

# Step 8: Cleanup and unmount
echo ""
echo "[8/8] Cleaning up..."
sudo umount "$ROOTFS_MNT/boot"
sudo umount "$ROOTFS_MNT"
sudo losetup -d "$BOOT_LOOP"
sudo losetup -d "$ROOTFS_LOOP"
sudo rmdir "$ROOTFS_MNT"
rm -rf "$KERNEL_STAGING"
echo "✓ Cleanup complete"

echo ""
echo "================================================"
echo "✅ Debian 13 A7Z Image Ready"
echo ""
echo "Image: $IMAGE_FILE"
echo "Contents:"
echo "  ✅ Debian 13 Trixie (minimal base system)"
echo "  ✅ Custom kernel 6.6.98+ (A55 2800MHz, A76 3000MHz)"
echo "  ✅ SSH server enabled"
echo "  ✅ NetworkManager for connectivity"
echo ""
echo "Flash to SD card: sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress"
echo ""
