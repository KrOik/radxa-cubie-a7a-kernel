# Windows 环境下提取 A7Z 资源

由于 Windows 不能直接挂载 Linux 分区，这里提供几种方法提取 A7Z 镜像中的资源。

## 方法 1：使用 WSL (推荐)

如果你有 WSL (Windows Subsystem for Linux)：

```bash
# 在 WSL 中运行
cd /mnt/d/radxa-cubie-a7a-kernel  # 根据实际路径调整
./scripts/extract-a7z-resources.sh temp_extract/a7z-stock.img.xz
```

## 方法 2：使用 7-Zip 快速查看

7-Zip 可以打开 .img 文件并浏览内容（只读）：

1. 解压 .img.xz：
   ```powershell
   & "C:\Program Files\7-Zip\7z.exe" x temp_extract\a7z-stock.img.xz -otemp_extract\
   ```

2. 用 7-Zip 打开 `a7z-stock.img`
   - 右键 → 7-Zip → Open Archive
   - 浏览到 Partition 2 或 3
   - 手动复制需要的文件

## 方法 3：完全手动提取（当前方法）

### 步骤 1：解压镜像

```powershell
# 等待下载完成后
cd temp_extract

# 使用 7-Zip 解压
& "C:\Program Files\7-Zip\7z.exe" x a7z-stock.img.xz

# 或使用 xz (如果有安装)
xz -d a7z-stock.img.xz
```

### 步骤 2：检查分区布局

```powershell
# 下载 ImDisk 或使用 OSFMount 查看分区信息
# 或者传到 Linux 机器/WSL 进行分析
```

### 步骤 3：需要提取的文件清单

从镜像中需要提取的关键文件：

#### Partition 2 (EFI/Boot - 约 300 MB)
```
/boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb       → 需要
/boot/Image                                          → 需要（用于验证）
/boot/extlinux/extlinux.conf                        → 需要
/boot/config-*                                       → 需要
```

#### Partition 3 (Rootfs - 剩余空间)
```
/etc/fstab                                           → 需要
/lib/modules/*/                                      → 参考
/lib/firmware/                                       → 可选
```

### 步骤 4：使用工具提取

#### 选项 A：DiskGenius (免费，支持 ext4)
1. 下载 DiskGenius：https://www.diskgenius.com/
2. 打开 `a7z-stock.img`
3. 右键分区 2/3 → 浏览文件
4. 复制上述文件到 `extracted_a7z/` 目录

#### 选项 B：Linux Reader (免费)
1. 下载 Linux Reader：https://www.diskinternals.com/linux-reader/
2. 打开镜像
3. 浏览并导出文件

#### 选项 C：传到 WSL/虚拟机
```bash
# 在 WSL 中
sudo mkdir /mnt/a7z_img
sudo mount -o loop,offset=$((512*start_sector)) /mnt/d/path/to/a7z-stock.img /mnt/a7z_img
```

## 方法 4：直接使用在线提取服务（如果镜像不大）

可以使用在线 ext4 查看器（不推荐，安全风险）。

## 等待下载完成后的自动化脚本

下载完成后，在 WSL 或 Linux 环境运行：

```bash
./scripts/extract-a7z-resources.sh
```

这将自动提取所有需要的资源并生成对比报告。

## 当前下载状态

运行以下命令检查下载进度：

```powershell
Get-Item temp_extract\a7z-stock.img.xz | Select-Object Name, Length, LastWriteTime

# 期望大小：约 1.2-1.8 GB（压缩后）
# 解压后：约 4-6 GB
```

## 提取完成后的对比分析

```bash
# 设备树对比
diff -u configs/a7z/board.dts extracted_a7z/a7z-stock.dts

# 内核配置对比
diff configs/a7z/cubie_a7z_defconfig extracted_a7z/a7z-stock.config | head -100

# 启动配置对比
diff configs/a7z/extlinux.conf.template extracted_a7z/a7z-stock-extlinux.conf
```

## 验证 DTB 的关键点

提取 DTB 后，检查以下内容：

```bash
# 反编译 DTB
dtc -I dtb -O dts -o a7z.dts sun60i-a733-cubie-a7z.dtb

# 检查 UFS 配置
grep -A 10 "ufs@" a7z.dts

# 检查 SD/eMMC 状态
grep -A 5 "sdc[02]" a7z.dts

# 检查时钟配置
grep "clock-frequency" a7z.dts
```
