# A7Z Stock 镜像资源提取计划

## 源镜像信息
- **URL**: https://github.com/radxa-build/radxa-a733/releases/download/rsdk-r6/radxa-a733_bullseye_kde_r6.output_4096.img.xz
- **版本**: Radxa Cubie A7Z Debian 11 (Bullseye) KDE R6
- **状态**: 最新官方镜像
- **大小**: ~4-6 GB（压缩后约 1-2 GB）

## 需要提取的资源

### 优先级 P0：设备树验证

#### 1. A7Z DTB 文件
**目标路径（镜像内）**:
- `/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb`
- 或 `/usr/lib/linux-image-*/allwinner/sun60i-a733-cubie-a7z.dtb`

**提取操作**:
```bash
# 解压镜像
xz -d a7z-stock.img.xz

# 挂载 rootfs 分区（通常是 partition 3）
LOOP_DEV=$(sudo losetup -f --show a7z-stock.img)
sudo partprobe $LOOP_DEV
sudo mkdir -p /mnt/a7z_rootfs
sudo mount ${LOOP_DEV}p3 /mnt/a7z_rootfs

# 查找 DTB
find /mnt/a7z_rootfs/boot -name "*.dtb" | grep a7z
find /mnt/a7z_rootfs/usr/lib -name "*.dtb" | grep a7z

# 复制 DTB
sudo cp /mnt/a7z_rootfs/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb \
  ./sun60i-a733-cubie-a7z.dtb

# 反编译为 DTS
dtc -I dtb -O dts -o a7z-stock.dts sun60i-a733-cubie-a7z.dtb
```

**用途**:
- 与我们的 `configs/a7z/board.dts` 对比
- 验证 UFS 配置、引脚映射、时钟频率
- 确认 SD/eMMC 节点状态

---

#### 2. 内核配置文件
**目标路径**:
- `/boot/config-*` - 运行中内核的 .config
- `/proc/config.gz` - 如果启用了 CONFIG_IKCONFIG

**提取操作**:
```bash
# 方法 1：从 /boot 复制
sudo cp /mnt/a7z_rootfs/boot/config-* ./a7z-stock.config

# 方法 2：如果有 config.gz
sudo zcat /mnt/a7z_rootfs/proc/config.gz > ./a7z-stock.config
```

**用途**:
- 对比官方启用的内核选项
- 验证 UFS 驱动配置
- 检查是否有我们遗漏的关键选项

---

### 优先级 P1：启动配置

#### 3. extlinux.conf
**目标路径**:
- `/boot/extlinux/extlinux.conf`

**提取操作**:
```bash
sudo cp /mnt/a7z_rootfs/boot/extlinux/extlinux.conf \
  ./a7z-stock-extlinux.conf
```

**用途**:
- 验证官方的内核 cmdline 参数
- 确认根分区路径（应为 `/dev/sda3`）
- 检查是否有特殊的启动参数

---

#### 4. fstab
**目标路径**:
- `/etc/fstab`

**提取操作**:
```bash
sudo cp /mnt/a7z_rootfs/etc/fstab ./a7z-stock-fstab
```

**用途**:
- 确认 UFS 分区挂载方式
- 验证 EFI 分区路径（`/dev/sda2` → `/boot`）
- 检查 swap 配置

---

### 优先级 P2：U-Boot 和 Boot Sectors

#### 5. U-Boot 二进制
**目标路径**:
- 镜像前 16 MB（boot0 + U-Boot）

**提取操作**:
```bash
# 提取前 16 MB
dd if=a7z-stock.img of=a7z-boot-sectors.img bs=1M count=16

# 分离 boot0 和 U-Boot
dd if=a7z-stock.img of=boot0.bin bs=1k count=32
dd if=a7z-stock.img of=u-boot.bin bs=1k skip=128 count=1024
```

**用途**:
- 用于完整镜像打包
- 验证 U-Boot 版本和配置
- 确认 UFS 驱动版本

---

#### 6. 分区表布局
**提取操作**:
```bash
# 查看分区信息
sudo fdisk -l a7z-stock.img
sudo parted a7z-stock.img print

# 导出 GPT 分区表
sudo sgdisk -p a7z-stock.img > a7z-partition-layout.txt
```

**预期布局**:
```
Partition 1: 16 MB, Type: 8300 (Linux filesystem) - config
Partition 2: 300 MB, Type: EF00 (EFI System) - /boot
Partition 3: Remaining, Type: 8300 (Linux filesystem) - rootfs
```

---

### 优先级 P3：系统信息

#### 7. 内核版本和模块
**提取操作**:
```bash
# 查找内核版本
ls /mnt/a7z_rootfs/lib/modules/

# 提取内核 Image
sudo cp /mnt/a7z_rootfs/boot/Image ./a7z-stock-Image

# 查看内核版本字符串
strings a7z-stock-Image | grep "Linux version"
```

---

#### 8. 固件文件
**目标路径**:
- `/lib/firmware/` - WiFi、蓝牙、GPU 固件

**提取操作**:
```bash
# 复制所有固件
sudo cp -r /mnt/a7z_rootfs/lib/firmware ./a7z-firmware/

# 重点关注 Allwinner 特定固件
find ./a7z-firmware -name "*aic*" -o -name "*sunxi*"
```

---

## 提取后的对比分析

### 1. 设备树对比
```bash
# 对比我们的 DTS 和官方 DTS
diff -u configs/a7z/board.dts a7z-stock.dts > a7z-dts-diff.patch

# 关键检查点
grep -A 5 "&ufs" a7z-stock.dts
grep -A 5 "&sdc0" a7z-stock.dts
grep -A 5 "&sdc2" a7z-stock.dts
```

### 2. 内核配置对比
```bash
# 对比配置差异
diff configs/a7z/cubie_a7z_defconfig a7z-stock.config | grep "^[<>]" | head -50

# 重点检查 UFS 相关选项
grep -E "UFS|SCSI" a7z-stock.config
```

### 3. 启动参数对比
```bash
# 对比 extlinux.conf
diff configs/a7z/extlinux.conf.template a7z-stock-extlinux.conf
```

---

## 提取脚本（自动化）

创建 `scripts/extract-a7z-resources.sh`:

```bash
#!/bin/bash
set -euo pipefail

IMG_XZ="$1"
OUTPUT_DIR="extracted_a7z"

if [ ! -f "$IMG_XZ" ]; then
    echo "Usage: $0 <path-to-a7z-stock.img.xz>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 1. 解压镜像
echo "[1/8] Decompressing image..."
xz -dc "../$IMG_XZ" > a7z-stock.img

# 2. 挂载分区
echo "[2/8] Mounting partitions..."
LOOP_DEV=$(sudo losetup -f --show a7z-stock.img)
sudo partprobe "$LOOP_DEV"
sudo mkdir -p /mnt/a7z_boot /mnt/a7z_rootfs

# 挂载 EFI 分区（partition 2）
sudo mount "${LOOP_DEV}p2" /mnt/a7z_boot || true

# 挂载 rootfs（partition 3）
sudo mount "${LOOP_DEV}p3" /mnt/a7z_rootfs

# 3. 提取 DTB
echo "[3/8] Extracting DTB..."
if [ -f /mnt/a7z_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ]; then
    sudo cp /mnt/a7z_boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ./
    dtc -I dtb -O dts -o a7z-stock.dts sun60i-a733-cubie-a7z.dtb
elif [ -f /mnt/a7z_rootfs/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ]; then
    sudo cp /mnt/a7z_rootfs/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb ./
    dtc -I dtb -O dts -o a7z-stock.dts sun60i-a733-cubie-a7z.dtb
fi

# 4. 提取内核配置
echo "[4/8] Extracting kernel config..."
sudo cp /mnt/a7z_boot/config-* ./a7z-stock.config 2>/dev/null || true

# 5. 提取 extlinux.conf
echo "[5/8] Extracting boot config..."
sudo cp /mnt/a7z_boot/extlinux/extlinux.conf ./a7z-stock-extlinux.conf 2>/dev/null || true

# 6. 提取 fstab
echo "[6/8] Extracting fstab..."
sudo cp /mnt/a7z_rootfs/etc/fstab ./a7z-stock-fstab

# 7. 提取内核 Image
echo "[7/8] Extracting kernel Image..."
sudo cp /mnt/a7z_boot/Image ./a7z-stock-Image 2>/dev/null || true

# 8. 提取分区表信息
echo "[8/8] Extracting partition layout..."
sudo fdisk -l a7z-stock.img > a7z-partition-layout.txt
sudo parted a7z-stock.img print >> a7z-partition-layout.txt

# 清理
echo "Cleaning up..."
sudo umount /mnt/a7z_boot /mnt/a7z_rootfs 2>/dev/null || true
sudo losetup -d "$LOOP_DEV"
sudo rmdir /mnt/a7z_boot /mnt/a7z_rootfs

echo ""
echo "✅ Extraction complete! Files in: $OUTPUT_DIR/"
echo ""
echo "Next steps:"
echo "  1. Compare DTS: diff -u ../configs/a7z/board.dts a7z-stock.dts"
echo "  2. Compare config: diff ../configs/a7z/cubie_a7z_defconfig a7z-stock.config"
echo "  3. Compare extlinux: diff ../configs/a7z/extlinux.conf.template a7z-stock-extlinux.conf"
```

---

## 集成到项目

### 更新 A7Z DTS（如果有差异）
```bash
# 如果官方 DTS 更准确，替换我们的版本
cp extracted_a7z/a7z-stock.dts configs/a7z/board.dts

# 或手动合并关键差异
vimdiff configs/a7z/board.dts extracted_a7z/a7z-stock.dts
```

### 更新 A7Z defconfig（如果需要）
```bash
# 对比并添加缺失的关键选项
./scripts/merge-config.sh \
  configs/a7z/cubie_a7z_defconfig \
  extracted_a7z/a7z-stock.config
```

### 验证启动配置
```bash
# 确保 extlinux.conf 与官方一致
diff configs/a7z/extlinux.conf.template extracted_a7z/a7z-stock-extlinux.conf
```

---

## 预期收益

1. **真实的 A7Z 设备树** - 确保硬件兼容性
2. **官方验证的内核配置** - 避免启动问题
3. **正确的启动参数** - 确保能正常进入系统
4. **U-Boot 二进制** - 用于完整镜像打包
5. **分区布局参考** - 用于创建 A7Z 镜像脚本

完成这些提取后，我们的 A7Z 支持将从"理论兼容"升级为"官方验证"。
