#!/bin/bash
# Fix Radxa Cubie A7Z UFS boot after writing the A7A release rootfs to /dev/sda.
#
# This only repairs the UFS boot layout. It intentionally does not change HDMI,
# SDDM, desktop, or display-manager settings.
#
# Defaults match the tested A7Z UFS layout:
#   /dev/sda1  config vfat
#   /dev/sda2  EFI/boot vfat, scanned by U-Boot as sunxi_flash_ufs 0:2
#   /dev/sda3  rootfs ext4
set -euo pipefail

BOOT_DEV="${BOOT_DEV:-/dev/sda2}"
ROOT_DEV="${ROOT_DEV:-/dev/sda3}"
CONFIG_DEV="${CONFIG_DEV:-/dev/sda1}"

STOCK_KVER="${STOCK_KVER:-5.15.147-14-a733}"
CUSTOM_IMAGE="${CUSTOM_IMAGE:-vmlinuz-6.6.98+-custom}"
CUSTOM_DTB="${CUSTOM_DTB:-allwinner/sun60i-a733-cubie-a7a.dtb}"
STOCK_A7Z_DTB="${STOCK_A7Z_DTB:-allwinner/sun60i-a733-cubie-a7z.dtb}"
DEFAULT_LABEL="${DEFAULT_LABEL:-l1}"

BOOT_MNT="${BOOT_MNT:-/tmp/a7z-ufs-boot}"
ROOT_MNT="${ROOT_MNT:-/tmp/a7z-ufs-root}"
TS="$(date +%Y%m%d-%H%M%S)"

log() { printf '[A7Z-UFS-FIX] %s\n' "$*"; }
die() { printf '[A7Z-UFS-FIX][ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"
[ -b "$BOOT_DEV" ] || die "$BOOT_DEV is not a block device"
[ -b "$ROOT_DEV" ] || die "$ROOT_DEV is not a block device"
[ -b "$CONFIG_DEV" ] || die "$CONFIG_DEV is not a block device"

need_file() {
  local path="$1"
  [ -f "$path" ] || die "Missing required file: $path"
}

mkdir -p "$BOOT_MNT" "$ROOT_MNT"

cleanup() {
  umount "$BOOT_MNT" 2>/dev/null || true
  umount "$ROOT_MNT" 2>/dev/null || true
}
trap cleanup EXIT

cleanup

log "Mounting $BOOT_DEV -> $BOOT_MNT"
mount "$BOOT_DEV" "$BOOT_MNT"
log "Mounting $ROOT_DEV -> $ROOT_MNT"
mount "$ROOT_DEV" "$ROOT_MNT"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV")"
BOOT_UUID="$(blkid -s UUID -o value "$BOOT_DEV")"
CONFIG_UUID="$(blkid -s UUID -o value "$CONFIG_DEV")"

[ -n "$ROOT_UUID" ] || die "Could not read UUID for $ROOT_DEV"
[ -n "$BOOT_UUID" ] || die "Could not read UUID for $BOOT_DEV"
[ -n "$CONFIG_UUID" ] || die "Could not read UUID for $CONFIG_DEV"

need_file "$ROOT_MNT/boot/vmlinuz-$STOCK_KVER"
need_file "$ROOT_MNT/boot/initrd.img-$STOCK_KVER"
need_file "$ROOT_MNT/boot/$CUSTOM_IMAGE"
need_file "$ROOT_MNT/usr/lib/linux-image-$STOCK_KVER/$STOCK_A7Z_DTB"
need_file "$ROOT_MNT/usr/lib/linux-image-custom/$CUSTOM_DTB"

log "Backing up existing boot/root configuration"
for f in \
  "$BOOT_MNT/boot/extlinux/extlinux.conf" \
  "$BOOT_MNT/extlinux/extlinux.conf" \
  "$ROOT_MNT/boot/extlinux/extlinux.conf" \
  "$ROOT_MNT/etc/fstab"; do
  if [ -f "$f" ]; then
    cp "$f" "$f.bak-a7z-ufs-$TS"
    log "Backup: $f.bak-a7z-ufs-$TS"
  fi
done

log "Populating U-Boot-scanned EFI partition with kernels and DTBs"
mkdir -p \
  "$BOOT_MNT/boot/extlinux" \
  "$BOOT_MNT/extlinux" \
  "$BOOT_MNT/usr/lib/linux-image-$STOCK_KVER/allwinner" \
  "$BOOT_MNT/usr/lib/linux-image-custom/allwinner"

cp -f "$ROOT_MNT/boot/vmlinuz-$STOCK_KVER" "$BOOT_MNT/boot/"
cp -f "$ROOT_MNT/boot/initrd.img-$STOCK_KVER" "$BOOT_MNT/boot/"
cp -f "$ROOT_MNT/boot/$CUSTOM_IMAGE" "$BOOT_MNT/boot/"
cp -f "$ROOT_MNT/usr/lib/linux-image-$STOCK_KVER/$STOCK_A7Z_DTB" \
  "$BOOT_MNT/usr/lib/linux-image-$STOCK_KVER/$STOCK_A7Z_DTB"
cp -f "$ROOT_MNT/usr/lib/linux-image-custom/$CUSTOM_DTB" \
  "$BOOT_MNT/usr/lib/linux-image-custom/$CUSTOM_DTB"

log "Writing extlinux menu with 6.6 default and 5.15 fallback"
cat > "$BOOT_MNT/boot/extlinux/extlinux.conf" <<EOF
## A7Z UFS boot menu generated $TS
## $BOOT_DEV is scanned by U-Boot as sunxi_flash_ufs 0:2; rootfs is $ROOT_DEV.
## l1 is the tested 6.6 custom kernel using the release A7A custom DTB.

default $DEFAULT_LABEL
menu title Radxa Cubie A7Z UFS Boot
prompt 1
timeout 30

label l0
    menu label Stock Kernel $STOCK_KVER (A7Z UFS fallback)
    linux /boot/vmlinuz-$STOCK_KVER
    initrd /boot/initrd.img-$STOCK_KVER
    fdtdir /usr/lib/linux-image-$STOCK_KVER/
    append root=UUID=$ROOT_UUID console=ttyAS0,115200n8 rootwait clk_ignore_unused quiet splash loglevel=4 rw earlycon consoleblank=0 console=tty1 coherent_pool=2M irqchip.gicv3_pseudo_nmi=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 kasan=off

label l1
    menu label Custom Kernel 6.6.98+ (A7A DTB, tested on A7Z UFS)
    linux /boot/$CUSTOM_IMAGE
    fdt /usr/lib/linux-image-custom/$CUSTOM_DTB
    append root=$ROOT_DEV console=ttyAS0,115200n8 rootwait rootfstype=ext4 rw earlycon loglevel=7 consoleblank=0 console=tty1 coherent_pool=2M clk_ignore_unused irqchip.gicv3_pseudo_nmi=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1

label l2
    menu label Custom Kernel 6.6.98+ (stock A7Z DTB experiment)
    linux /boot/$CUSTOM_IMAGE
    fdt /usr/lib/linux-image-$STOCK_KVER/$STOCK_A7Z_DTB
    append root=$ROOT_DEV console=ttyAS0,115200n8 rootwait rootfstype=ext4 rw earlycon loglevel=7 consoleblank=0 console=tty1 coherent_pool=2M clk_ignore_unused irqchip.gicv3_pseudo_nmi=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF

cp -f "$BOOT_MNT/boot/extlinux/extlinux.conf" "$BOOT_MNT/extlinux/extlinux.conf"
mkdir -p "$ROOT_MNT/boot/extlinux"
cp -f "$BOOT_MNT/boot/extlinux/extlinux.conf" "$ROOT_MNT/boot/extlinux/extlinux.conf"

log "Writing rootfs fstab"
cat > "$ROOT_MNT/etc/fstab" <<EOF
UUID=$CONFIG_UUID /config vfat defaults,x-systemd.automount,fmask=0077,dmask=0077 0 2
UUID=$BOOT_UUID /boot/efi vfat defaults,x-systemd.automount,fmask=0077,dmask=0077 0 2
UUID=$ROOT_UUID / ext4 defaults 0 1
EOF

if [ -f "$ROOT_MNT/home/radxa/.bashrc" ] && \
   ! chroot "$ROOT_MNT" bash -n /home/radxa/.bashrc 2>/dev/null; then
  log "Fixing /home/radxa/.bashrc parse error by removing one trailing orphan fi"
  cp "$ROOT_MNT/home/radxa/.bashrc" "$ROOT_MNT/home/radxa/.bashrc.bak-a7z-ufs-$TS"
  sed -i '${/^fi$/d;}' "$ROOT_MNT/home/radxa/.bashrc"
fi

sync

log "Resulting extlinux menu:"
grep -nE 'default|prompt|timeout|label|menu label|linux |fdt |fdtdir |append root' \
  "$BOOT_MNT/boot/extlinux/extlinux.conf"

log "Done. Reboot and verify:"
cat <<EOF
  uname -a
  findmnt /
  nmcli dev status
  ls -l /dev/vipcore /dev/dri/renderD128
  cd /home/radxa/ai-sdk/examples/vpm_run && ./vpm_run -s sample_v3.txt -l 3 -d 0
EOF
