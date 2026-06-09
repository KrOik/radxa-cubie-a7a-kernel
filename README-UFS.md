# Radxa Cubie A7Z - UFS存储启动说明

## 重要提示 ⚠️

**你的A7Z开发板使用UFS存储，需要特殊的镜像格式！**

普通的512字节扇区镜像**无法在UFS上启动**，会出现：
```
GUID Partition Table Header signature is wrong
part_get_info_efi: *** ERROR: Invalid GPT ***
```

## 问题原因

- **UFS存储**: 使用4096字节逻辑扇区
- **标准镜像**: 使用512字节扇区
- **结果**: GPT分区表位置不匹配，U-Boot找不到分区

## 解决方案

### 方案1：使用GitHub Actions自动构建（推荐）

1. **触发构建**
   ```bash
   git add .
   git commit -m "Build UFS-compatible image"
   git push
   ```

2. **等待构建完成**（约15-20分钟）
   - 访问: https://github.com/你的用户名/radxa-cubie-a7a-kernel/actions
   - 等待 "Build Radxa Cubie Kernel" 完成

3. **下载UFS镜像**
   - 点击成功的构建
   - 下载 `ufs-image-a7z` artifact
   - 解压得到 `radxa-cubie-a7z-ufs.img.xz`

4. **烧录到UFS存储**
   ```bash
   # 解压
   xz -d radxa-cubie-a7z-ufs.img.xz
   
   # 烧录（必须使用 bs=4096！）
   sudo dd if=radxa-cubie-a7z-ufs.img of=/dev/sdX bs=4096 status=progress conv=fsync
   ```

### 方案2：本地手动构建

**前提条件**: Linux系统（或WSL2）

```bash
# 1. 安装工具
sudo apt install gdisk parted debootstrap qemu-user-static

# 2. 下载已编译的内核
# 从GitHub Actions下载 release-tarball-a7z

# 3. 下载官方镜像（用于提取U-Boot）
wget https://github.com/radxa-build/radxa-a733/releases/download/20250425-1422/radxa-a733_bullseye_kde_r6.output_4096.img.xz

# 4. 创建UFS镜像
sudo ./scripts/create-ufs-image.sh \
    radxa-a7z-ufs.img \
    radxa-cubie-a7z-kernel-*.tar.gz \
    radxa-a733_bullseye_kde_r6.output_4096.img.xz \
    4

# 5. 烧录
sudo dd if=radxa-a7z-ufs.img of=/dev/sdX bs=4096 status=progress
```

## 烧录注意事项

### ✅ 正确方式
```bash
# Linux
sudo dd if=radxa-cubie-a7z-ufs.img of=/dev/sdX bs=4096 status=progress conv=fsync

# macOS
sudo dd if=radxa-cubie-a7z-ufs.img of=/dev/rdiskX bs=4096

# Windows (在WSL2中)
sudo dd if=radxa-cubie-a7z-ufs.img of=/dev/sdX bs=4096 status=progress
```

### ❌ 错误方式
```bash
# 错误！不要用 bs=1M 或其他值
dd if=image.img of=/dev/sdX bs=1M        # ❌ 会失败
dd if=image.img of=/dev/sdX bs=512       # ❌ 会失败
dd if=image.img of=/dev/sdX              # ❌ 默认512，会失败
```

**必须使用 `bs=4096`**，否则分区表会错位！

## 验证镜像

### 检查扇区大小
```bash
# 镜像文件
sgdisk -p radxa-cubie-a7z-ufs.img | grep "sector size"
# 应该显示: Logical sector size: 4096 bytes

# UFS设备（烧录后）
sudo blockdev --getss /dev/sdX   # 应该输出: 4096
```

### 检查GPT头位置
```bash
# 在offset 4096应该看到 "EFI PART" 签名
hexdump -C radxa-cubie-a7z-ufs.img -n 64 -s 4096 | head -2
# 00001000  45 46 49 20 50 41 52 54  ...  (EFI PART)
```

## 启动后

### 默认登录
- **root** / debian
- **radxa** / radxa

### 网络
- 自动DHCP (eth0/end0)
- SSH已启用

### 串口控制台
- 波特率: 115200
- 数据位: 8
- 停止位: 1
- 校验: None

## 常见问题

### Q: 为什么之前的镜像不能用？
A: 之前的镜像用512字节扇区创建，UFS需要4096字节扇区。扇区大小不同，GPT分区表位置就不同，无法转换。

### Q: 可以转换现有镜像吗？
A: 不行，必须重新创建。GPT结构是硬编码的，不能简单转换。

### Q: 为什么必须用 bs=4096？
A: `dd`的`bs`参数控制块大小。如果用512或1M，会破坏4K对齐，导致分区表错位。

### Q: 官方镜像能直接用吗？
A: 官方镜像可能用512扇区，需要检查。最保险的是用我们的UFS脚本重新构建。

### Q: 镜像多大？
A: 默认4GB（可调整）。压缩后约400-600MB。

## 技术细节

### 分区布局
```
Partition 1: U-Boot SPL    (2MB-16MB,  offset 2MB)
Partition 2: Boot (ext4)   (16MB-144MB)
Partition 3: Root (ext4)   (144MB-end)
```

### 扇区对比
| 项目 | 标准镜像 | UFS镜像 |
|------|---------|---------|
| 逻辑扇区 | 512字节 | 4096字节 |
| GPT位置 | offset 512 | offset 4096 |
| 分区对齐 | 1MB | 2MB |
| 文件系统块 | 4096 | 4096 |

### 为什么UFS用4096？
UFS是为手机/嵌入式设计的高性能存储：
- 原生4KB页大小
- 更好的随机读写性能
- 减少写放大
- 降低功耗

## 参考资料

- [UFS规范](https://www.jedec.org/standards-documents/focus/flash/universal-flash-storage-ufs)
- [Linux UFS驱动](https://www.kernel.org/doc/html/latest/scsi/ufs.html)
- [GPT分区表](https://en.wikipedia.org/wiki/GUID_Partition_Table)
- [Allwinner A733启动流程](https://linux-sunxi.org/A733)

## 更新日志

- **2026-06-09**: 创建UFS兼容镜像构建系统
  - 添加 `create-ufs-image.sh` 脚本
  - 修改GitHub Actions支持UFS镜像
  - 添加完整文档

---

**如有问题，请提交Issue或查看 `UFS-IMAGE-GUIDE.md` 获取更多技术细节。**
