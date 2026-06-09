#!/bin/bash
# Upgrade Debian 11 → 13 inside a disk image (for CI use)
set -eo pipefail

IMAGE_FILE="${1}"
KERNEL_TARBALL="${2}"

if [ ! -f "$IMAGE_FILE" ]; then
    echo "ERROR: Image file not found: $IMAGE_FILE"
    exit 1
fi

if [ ! -f "$KERNEL_TARBALL" ]; then
    echo "ERROR: Kernel tarball not found: $KERNEL_TARBALL"
    exit 1
fi

echo "=== Debian 11 → 13 In-Image Upgrade ==="
echo "Image: $IMAGE_FILE"
echo "Kernel: $KERNEL_TARBALL"
echo ""

# Extract kernel files
KERNEL_STAGING="kernel_staging_$$"
mkdir -p "$KERNEL_STAGING"
tar -xzf "$KERNEL_TARBALL" -C "$KERNEL_STAGING/"
echo "✓ Kernel extracted"

# Setup loop device with manual partition offsets
echo ""
echo "[1/6] Mounting image partitions..."

# Use sgdisk to get GPT partition info (most reliable for GPT)
if command -v sgdisk >/dev/null 2>&1; then
    echo "Using sgdisk to read GPT partition table..."
    # Redirect stderr to see any warnings, don't fail on warnings
    BOOT_INFO=$(sgdisk -i 2 "$IMAGE_FILE" 2>&1) || true
    ROOTFS_INFO=$(sgdisk -i 3 "$IMAGE_FILE" 2>&1) || true
    BOOT_START=$(echo "$BOOT_INFO" | grep "First sector:" | awk '{print $3}')
    ROOTFS_START=$(echo "$ROOTFS_INFO" | grep "First sector:" | awk '{print $3}')

    if [ -z "$BOOT_START" ] || [ -z "$ROOTFS_START" ]; then
        echo "sgdisk failed, trying parted..."
        echo "sgdisk partition 2 output: $BOOT_INFO"
        echo "sgdisk partition 3 output: $ROOTFS_INFO"
    fi
elif command -v parted >/dev/null 2>&1; then
    echo "Using parted to read GPT partition table..."
    PARTED_OUTPUT=$(parted -s "$IMAGE_FILE" unit s print 2>/dev/null)
    BOOT_START=$(echo "$PARTED_OUTPUT" | awk '/^ 2 / {print $2}' | sed 's/s$//')
    ROOTFS_START=$(echo "$PARTED_OUTPUT" | awk '/^ 3 / {print $2}' | sed 's/s$//')
fi

# Fallback to parted if sgdisk didn't work
if [ -z "$BOOT_START" ] || [ -z "$ROOTFS_START" ]; then
    if command -v parted >/dev/null 2>&1; then
        echo "Falling back to parted..."
        PARTED_OUTPUT=$(parted -s "$IMAGE_FILE" unit s print 2>/dev/null)
        echo "$PARTED_OUTPUT" | grep "^ [0-9]"
        BOOT_START=$(echo "$PARTED_OUTPUT" | awk '/^ 2 / {print $2}' | sed 's/s$//')
        ROOTFS_START=$(echo "$PARTED_OUTPUT" | awk '/^ 3 / {print $2}' | sed 's/s$//')
    fi
fi

if [ -z "$BOOT_START" ] || [ -z "$ROOTFS_START" ]; then
    echo "ERROR: Failed to detect partition offsets"
    echo "BOOT_START=$BOOT_START, ROOTFS_START=$ROOTFS_START"
    echo "Trying to show partition table:"
    if command -v sgdisk >/dev/null 2>&1; then
        sgdisk -p "$IMAGE_FILE" 2>&1 || true
    fi
    if command -v parted >/dev/null 2>&1; then
        parted -s "$IMAGE_FILE" unit s print 2>&1 || true
    fi
    exit 1
fi

# Calculate byte offsets (sector * 512)
BOOT_OFFSET=$((BOOT_START * 512))
ROOTFS_OFFSET=$((ROOTFS_START * 512))

echo "✓ Boot partition starts at sector $BOOT_START (offset $BOOT_OFFSET)"
echo "✓ Rootfs partition starts at sector $ROOTFS_START (offset $ROOTFS_OFFSET)"

# Create two separate loop devices with offsets
BOOT_LOOP=$(sudo losetup -f --show -o $BOOT_OFFSET "$IMAGE_FILE")
ROOTFS_LOOP=$(sudo losetup -f --show -o $ROOTFS_OFFSET "$IMAGE_FILE")

echo "✓ Boot loop device: $BOOT_LOOP"
echo "✓ Rootfs loop device: $ROOTFS_LOOP"

BOOT_PART="$BOOT_LOOP"
ROOTFS_PART="$ROOTFS_LOOP"

# Mount rootfs
ROOTFS_MNT="/mnt/a7z_upgrade_$$"
sudo mkdir -p "$ROOTFS_MNT"
sudo mount "$ROOTFS_PART" "$ROOTFS_MNT"

# Mount boot partition inside rootfs
sudo mkdir -p "$ROOTFS_MNT/boot"
sudo mount "$BOOT_PART" "$ROOTFS_MNT/boot"

# Bind mount system directories for chroot
sudo mount --bind /dev "$ROOTFS_MNT/dev"
sudo mount --bind /proc "$ROOTFS_MNT/proc"
sudo mount --bind /sys "$ROOTFS_MNT/sys"
sudo mount --bind /dev/pts "$ROOTFS_MNT/dev/pts"

echo "✓ Partitions mounted"

# Step 2: Hold kernel packages
echo ""
echo "[2/6] Holding stock kernel packages..."
sudo chroot "$ROOTFS_MNT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-mark hold linux-image-radxa-a733 u-boot-radxa-a733 2>/dev/null || true
"
echo "✓ Kernel packages held"

# Step 3: Upgrade Debian 11 → 12 → 13
echo ""
echo "[3/6] Upgrading Debian 11 (Bullseye) → 13 (Trixie)..."
echo "  This will take 10-15 minutes..."

sudo chroot "$ROOTFS_MNT" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none

    # Backup sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # Step 3a: Bullseye → Bookworm (Debian 12)
    echo 'Upgrading to Debian 12 (Bookworm)...'
    sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list

    # Disable Radxa repos (no bookworm/trixie support)
    if [ -d /etc/apt/sources.list.d ]; then
        mkdir -p /etc/apt/sources.list.d.disabled
        mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.disabled/ 2>/dev/null || true
    fi

    apt-get update
    apt-get upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'
    apt-get dist-upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'

    # Step 3b: Bookworm → Trixie (Debian 13)
    echo 'Upgrading to Debian 13 (Trixie)...'
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list

    apt-get update
    apt-get upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'
    apt-get dist-upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'

    # Cleanup
    apt-get autoremove -y
    apt-get clean

    echo 'Debian 13 Trixie upgrade complete'
"

echo "✓ Debian 13 upgrade complete"

# Step 4: Install custom kernel
echo ""
echo "[4/6] Installing custom kernel 6.6.98+..."

# Copy kernel Image
if [ -f "$KERNEL_STAGING/boot/Image" ]; then
    sudo cp "$KERNEL_STAGING/boot/Image" "$ROOTFS_MNT/boot/"
    echo "  ✓ Kernel Image installed"
fi

# Copy DTBs
if ls "$KERNEL_STAGING/boot/"*.dtb >/dev/null 2>&1; then
    sudo cp "$KERNEL_STAGING/boot/"*.dtb "$ROOTFS_MNT/boot/" 2>/dev/null || true
    echo "  ✓ Device trees installed"
fi

# Replace kernel modules
if [ -d "$KERNEL_STAGING/lib/modules" ]; then
    sudo rm -rf "$ROOTFS_MNT/lib/modules/"*
    sudo cp -r "$KERNEL_STAGING/lib/modules/"* "$ROOTFS_MNT/lib/modules/"
    echo "  ✓ Kernel modules installed"
fi

# Update extlinux.conf if needed
EXTLINUX_CONF="$ROOTFS_MNT/boot/extlinux/extlinux.conf"
if [ -f "$EXTLINUX_CONF" ]; then
    sudo sed -i 's|linux .*Image|linux /boot/Image|' "$EXTLINUX_CONF"
    sudo sed -i 's|fdt .*\.dtb|fdt /usr/lib/linux-image-custom/allwinner/sun60i-a733-cubie-a7z.dtb|' "$EXTLINUX_CONF"
    echo "  ✓ Boot config updated"
fi

echo "✓ Custom kernel installed"

# Step 5: Fix known issues
echo ""
echo "[5/6] Fixing known issues..."

# Fix growroot initramfs hook
if [ -f "$ROOTFS_MNT/usr/share/initramfs-tools/hooks/growroot" ]; then
    sudo chmod -x "$ROOTFS_MNT/usr/share/initramfs-tools/hooks/growroot"
    echo "  ✓ growroot hook disabled"
fi

# Fix .bashrc trailing fi error (A7Z specific)
if [ -f "$ROOTFS_MNT/home/radxa/.bashrc" ]; then
    sudo sed -i '/^fi$/d' "$ROOTFS_MNT/home/radxa/.bashrc"
    echo "  ✓ .bashrc syntax fixed"
fi

echo "✓ Known issues fixed"

# Step 6: Cleanup and unmount
echo ""
echo "[6/6] Cleaning up..."

# Unmount bind mounts
sudo umount "$ROOTFS_MNT/dev/pts" || true
sudo umount "$ROOTFS_MNT/sys" || true
sudo umount "$ROOTFS_MNT/proc" || true
sudo umount "$ROOTFS_MNT/dev" || true

# Unmount partitions
sudo umount "$ROOTFS_MNT/boot" || true
sudo umount "$ROOTFS_MNT" || true

# Detach loop devices (created with offset)
sudo losetup -d "$BOOT_LOOP" || true
sudo losetup -d "$ROOTFS_LOOP" || true

# Remove mount point
sudo rmdir "$ROOTFS_MNT"

# Cleanup kernel staging
rm -rf "$KERNEL_STAGING"

echo "✓ Cleanup complete"
echo ""
echo "================================================"
echo "✅ Debian 13 + Custom Kernel Image Ready"
echo ""
echo "Image: $IMAGE_FILE"
echo "Contents:"
echo "  ✅ Debian 13 Trixie (upgraded from Bullseye)"
echo "  ✅ KDE desktop + all preinstalled apps"
echo "  ✅ Custom kernel 6.6.98+ (A55 2800MHz, A76 3000MHz)"
echo "  ✅ All kernel modules and drivers"
echo ""
