# A7Z Complete Image Build - Status Update

## Current Status: Strategy Changed to Minimal Bootable Image (2026-06-09)

### 🔄 Critical Issue Resolved

**Problem**: Stock A7Z image downloads unavailable
- GitHub releases return `Content-Length: 0` (all .img.xz files)
- Radxa official site returns 404
- Downloaded images have empty GPT partition tables

**New Strategy**: Build minimal bootable image without stock dependencies
- Use Alpine Linux minimal rootfs (~3MB)
- Include custom kernel + modules
- Create proper GPT partition structure
- Document missing boot sectors clearly

### ✅ Latest Changes (Commit pending)

1. **CI Workflow Updated**
   - Downloads Alpine Linux aarch64 minirootfs instead of stock image
   - Creates complete GPT-partitioned image with proper structure
   - Includes custom overclocked kernel
   - Compresses to .img.xz format

2. **Build Script Enhanced**
   - Clear warning messages when boot sectors unavailable
   - Status tracking: `✅ BOOTABLE` vs `⚠️ NEEDS BOOT SECTORS`
   - Detailed instructions for adding boot sectors manually

### 📦 What CI Will Produce

**Kernel Artifacts** (both A7A + A7Z):
- ✅ Kernel Image + DTBs
- ✅ Kernel modules with overclock support
- ✅ Build manifests and checksums

**Complete A7Z Image** (radxa-cubie-a7z-custom.img.xz):
- ✅ GPT partition table (sda1: config 16MB, sda2: boot 300MB, sda3: rootfs)
- ✅ Formatted partitions (ext4 + vfat)
- ✅ Custom kernel 6.6.98+ installed to /boot
- ✅ Kernel modules installed to /lib/modules
- ✅ Alpine Linux minimal rootfs
- ✅ Proper fstab for UFS (/dev/sda*)
- ⚠️ Boot sectors (boot0 + U-Boot) NOT included

### 🔧 Making Image Bootable

**Option 1: Add Boot Sectors from Stock Image** (when available)
```bash
# Extract boot sectors from any working A7Z image
dd if=stock-a7z.img of=boot-sectors.img bs=1M count=16

# Write to custom image
xz -d radxa-cubie-a7z-custom.img.xz
dd if=boot-sectors.img of=radxa-cubie-a7z-custom.img bs=1K seek=8 conv=notrunc
xz -9 radxa-cubie-a7z-custom.img
```

**Option 2: Boot from SD Card** (workaround)
1. Flash custom image to A7Z UFS
2. Boot A7Z from SD card with working U-Boot
3. U-Boot will find and boot kernel from UFS partition 2

**Option 3: Use Existing A7Z** (for testing)
1. Boot existing A7Z system
2. Replace kernel modules: `rsync -av lib/modules/* /lib/modules/`
3. Replace kernel Image: `cp boot/Image /boot/`
4. Reboot to test overclocked kernel

### 📋 Next Steps

1. ✅ Commit strategy changes
2. ⏳ Trigger CI build
3. ⏳ Verify complete image artifact
4. ⏳ Test image on A7Z hardware (requires boot sectors or SD boot)

### Previous Status History

<details>
<summary>Cache Fix (Commit 55b3736)</summary>

**Error**: Clone failures due to cache key instability
**Fix**: Stabilized cache key, removed `hashFiles()`, added cleanup step
**Result**: CI sources clone successfully
</details>

<details>
<summary>Package Dependencies (Commit dbe3113)</summary>

**Error**: `sfdisk` package not found
**Fix**: Changed to `util-linux` package
**Result**: All dependencies install correctly
</details>

<details>
<summary>Loop Device Handling Attempts</summary>

**Tried**:
1. `losetup -P` - partitions not created
2. `kpartx` - cannot handle GPT properly  
3. `partx -a` - failed due to empty GPT in stock image

**Root Cause**: Stock image files unavailable/corrupted
**Resolution**: Changed to minimal image strategy
</details>
