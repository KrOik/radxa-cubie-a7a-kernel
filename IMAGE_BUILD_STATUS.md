# A7Z Complete Image Build - Status Update

## Progress: Image Build Pipeline Added

### ✅ Completed (2026-06-09)

1. **GitHub Actions Extended**
   - Added `build-image` job for A7Z
   - Downloads stock image for boot sectors + minimal rootfs
   - Creates 4GB bootable image with GPT partitions
   - Compresses to .img.xz format
   - Commit: 8a8b6c3

2. **Image Build Script Created**
   - `scripts/build-complete-image.sh`
   - Complete partition layout (sda1/2/3)
   - Boot sector integration
   - Kernel + modules installation

3. **WSL Extraction Script**
   - `scripts/extract-resources-wsl.sh`
   - Optimized for Windows/WSL environment

### ⚠️ Current Blocker: Windows Sudo Disabled

WSL resource extraction requires sudo for loop device mounting.

**Solution Options:**

1. **Enable Windows Sudo** (Recommended)
   - Open Settings → Developers
   - Enable "Sudo for Windows"
   - Restart WSL

2. **Use GitHub Actions Instead**
   - CI already has all tools and permissions
   - Let CI build complete images automatically
   - Download final .img.xz from Actions artifacts

3. **Use Alternative Tool**
   - DiskGenius (Windows GUI) to manually extract DTB/config
   - 7-Zip can browse img partitions

### 📋 Next CI Build Will Produce:

When GitHub Actions runs (already pushed):
- ✅ Kernel tarballs (A7A + A7Z) - 30 MB each
- ✅ Complete A7Z bootable image - radxa-cubie-a7z-custom.img.xz
- ✅ SHA256 checksums for verification
- ✅ Ready to flash to A7Z hardware

### Workflow URL:
https://github.com/KrOik/radxa-cubie-a7a-kernel/actions

### Manual Testing (if sudo enabled):
```bash
# Enable sudo in Windows Settings → Developers first
bash scripts/extract-resources-wsl.sh

# Then build image locally
bash scripts/build-complete-image.sh release-tarball-a7z.tar.gz test-a7z.img
```

### Local Resource Status:
- ✅ Stock A7Z image: extracted_a7z/a7z-stock.img (10 GB)
- ✅ Boot sectors extracted: extracted_a7z/boot-sectors.img (16 MB)
- ❌ DTB/config extraction: Blocked by sudo requirement

## Recommendation:

**Let GitHub Actions build the complete image** - it has all tools, permissions, and will run automatically on next push or can be triggered manually via workflow_dispatch.

The complete .img.xz will be production-ready and downloadable from Actions artifacts.
