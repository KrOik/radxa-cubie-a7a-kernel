#!/bin/bash
# =============================================================================
# Radxa Cubie A7A — One-Command Flash Script
#
# Usage: sudo ./easy-flash.sh /dev/sdX
#
# Downloads and flashes the complete Debian 13 + Linux 6.6.98+ image
# with CPU @ 2800/3000MHz, GPU @ 1200MHz, WiFi, NPU — all working.
# =============================================================================
set -euo pipefail

DEVICE="${1:-}"
REPO="https://github.com/Rabs9/radxa-cubie-a7a-kernel/releases/download/v3.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[FLASH]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check root
[ "$(id -u)" -eq 0 ] || err "Run with sudo: sudo $0 /dev/sdX"

# Check device
if [ -z "$DEVICE" ] || [ ! -b "$DEVICE" ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo ""
    echo "Radxa Cubie A7A — One-Command Image Flasher"
    echo "Downloads and flashes Debian 13 + Linux 6.6.98+ (overclocked)"
    echo ""
    echo "Available removable devices:"
    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "usb|mmc" || echo "  (none found)"
    exit 1
fi

# Safety checks
if [[ "$DEVICE" == "/dev/sda" ]] && lsblk -d -o TRAN "$DEVICE" 2>/dev/null | grep -q "sata\|nvme"; then
    err "Refusing to write to $DEVICE — looks like a system drive!"
fi

SIZE=$(lsblk -d -b -o SIZE "$DEVICE" 2>/dev/null | tail -1)
if [ "$SIZE" -lt 15000000000 ] 2>/dev/null; then
    err "Device $DEVICE is smaller than 16GB. Need at least 16GB SD card."
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Radxa Cubie A7A — Image Flasher                    ║"
echo "║  Debian 13 + Linux 6.6.98+ (Extreme Overclock)     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
log "Target: $DEVICE ($(lsblk -d -o SIZE "$DEVICE" | tail -1))"
warn "This will ERASE all data on $DEVICE!"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }

IMAGE="radxa-cubie-a7a-debian13-oc-v3.0.0.img.xz"

# Download
log "Downloading image (1.9GB compressed, 10GB uncompressed)..."
wget -q --show-progress -O "/tmp/$IMAGE" "$REPO/$IMAGE"

# Flash
log "Flashing image (decompressing + writing)..."
xz -dc "/tmp/$IMAGE" | dd of="$DEVICE" bs=4M status=progress conv=fsync

# Expand rootfs partition to fill card
log "Expanding rootfs partition to fill card..."
sgdisk -d 3 "$DEVICE" > /dev/null 2>&1
sgdisk -n 3:679936:0 -t 3:EF00 -c 3:"rootfs" "$DEVICE" > /dev/null 2>&1
partprobe "$DEVICE" 2>/dev/null
sleep 2

# Determine partition naming
if [[ "$DEVICE" == *"mmcblk"* ]] || [[ "$DEVICE" == *"loop"* ]]; then
    P3="${DEVICE}p3"
else
    P3="${DEVICE}3"
fi

# Expand filesystem
log "Expanding filesystem..."
e2fsck -fy "$P3" > /dev/null 2>&1
resize2fs "$P3" > /dev/null 2>&1

# Cleanup
rm -f "/tmp/$IMAGE"
sync

echo ""
log "╔══════════════════════════════════════════════════════╗"
log "║  Flash complete!                                     ║"
log "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Insert SD card into Radxa Cubie A7A and power on."
echo ""
echo "  Login:   radxa / radxa"
echo "  SSH:     Starts automatically"
echo "  Serial:  115200 baud (ttyAS0)"
echo ""
echo "  Performance:"
echo "    CPU A55: 2800 MHz (+56%)"
echo "    CPU A76: 3000 MHz (+50%)"
echo "    GPU:     1200 MHz / 273 GFLOPS"
echo "    NPU:     1008 MHz / 130 FPS"
echo ""
