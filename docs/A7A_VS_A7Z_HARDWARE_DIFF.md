# Radxa Cubie A7A vs A7Z 硬件差异对照表

## 概述

A7A 和 A7Z 都基于 Allwinner A733 (sun60iw2p1) SoC，共享大部分核心硬件，主要差异在于**存储接口**和**板载配置**。

---

## 关键差异汇总

| 特性 | A7A | A7Z | 影响 |
|------|-----|-----|------|
| **存储接口** | SD/eMMC (sdc0/sdc2) | **UFS** (sunxi_ufs) | 需修改 DTS、分区、启动配置 |
| **存储设备路径** | `/dev/mmcblk0` | `/dev/sda` | 内核 cmdline `root=` 参数 |
| **U-Boot 扫描路径** | `mmc 0:3` (SD 分区 3) | `sunxi_flash_ufs 0:2` (UFS 分区 2) | extlinux.conf 位置 |
| **分区数量** | 通常 1-2 个 (rootfs + boot) | 3 个 (config + EFI + rootfs) | fstab 配置 |
| **板载存储** | 可选 eMMC 或 SD 卡 | **焊接 UFS 芯片** | 无法通过 SD 卡刷机 |
| **SoC 型号** | Allwinner A733 | Allwinner A733 | 完全相同 |
| **CPU 配置** | 2×A76 + 6×A55 | 2×A76 + 6×A55 | 相同 |
| **RAM** | 12GB LPDDR5 | 12GB LPDDR5 | 相同（可能？需确认） |
| **WiFi/BT** | AIC8800D80 USB | AIC8800D80 USB | 相同 |
| **以太网** | Gigabit RGMII | Gigabit RGMII | 相同 |
| **GPU** | PowerVR BXM-4-64 | PowerVR BXM-4-64 | 相同 |
| **NPU** | Vivante VIP9000 | Vivante VIP9000 | 相同 |

---

## 详细对比

### 1. 存储子系统

#### A7A 存储架构
```
SD Card Controller (sdc0):
  - 支持 UHS-I (SDR104, 最高 104 MB/s)
  - 设备路径: /dev/mmcblk0
  - DTS 节点: &sdc0 { status = "okay"; }

eMMC Controller (sdc2):
  - 支持 HS400 (8-bit, 最高 200 MB/s)
  - 设备路径: /dev/mmcblk1
  - DTS 节点: &sdc2 { status = "okay"; }

典型分区布局 (SD):
  mmcblk0p1    16MB    boot0 (BROM)
  mmcblk0p2    16MB    boot-resource (env/logo)
  mmcblk0p3    剩余    rootfs (ext4, GPT 类型 EF00)
```

#### A7Z 存储架构
```
UFS Controller (sunxi_ufs):
  - 支持 UFS 2.1/2.2
  - 理论速度: 顺序读 >500 MB/s, 写 >200 MB/s
  - 设备路径: /dev/sda
  - DTS 节点: &ufs { status = "okay"; }
  
典型分区布局 (UFS):
  sda1         4MB     config (vfat)
  sda2         256MB   EFI/boot (vfat, U-Boot 扫描点)
  sda3         剩余    rootfs (ext4)

关键配置:
  - sda2 必须为 GPT 类型 EF00 (EFI System Partition)
  - extlinux.conf 位于 sda2:/boot/extlinux/extlinux.conf
  - 内核/DTB 需同时存在于 sda2 和 sda3
```

**性能对比**:
| 操作 | SD (A7A, SDR104) | UFS (A7Z, 2.2) |
|------|------------------|----------------|
| 顺序读 | ~95 MB/s | **~550 MB/s** (5.8×) |
| 顺序写 | ~80 MB/s | **~220 MB/s** (2.8×) |
| 随机 4K 读 | ~2-5 MB/s | **~40-60 MB/s** (15×) |
| 随机 4K 写 | ~1-3 MB/s | **~20-40 MB/s** (15×) |

---

### 2. 设备树 (DTS) 差异

#### A7A DTS (`sun60i-a733-cubie-a7a.dts`)
```dts
// SD/eMMC 控制器启用
&sdc0 {
    status = "okay";
    bus-width = <4>;
    cd-gpios = <&pio PF 6 GPIO_ACTIVE_LOW>;
    // ...
};

&sdc2 {
    status = "okay";
    bus-width = <8>;
    non-removable;
    // eMMC 配置
};

// UFS 禁用或未定义（可能）
&ufs {
    status = "disabled";  // 或直接不存在
};
```

#### A7Z DTS (`sun60i-a733-cubie-a7z.dts` - 预期)
```dts
// UFS 控制器启用
&ufs {
    status = "okay";
    vcc-supply = <&reg_dcdc4>;  // 电源供应
    vccq-supply = <&reg_aldo3>;
    vccq2-supply = <&reg_aldo3>;
    // PHY 配置...
};

// SD/eMMC 评估
&sdc0 {
    status = "disabled";  // 如果无 SD 槽
};

&sdc2 {
    status = "disabled";  // A7Z 无 eMMC
};
```

**迁移动作**: 从 A7A DTS 复制时，需翻转 UFS/SDC 节点的 status 属性。

---

### 3. 内核配置差异

#### UFS 驱动依赖项 (A7Z 必需)
```bash
# 通用 SCSI 层
CONFIG_SCSI=y
CONFIG_SCSI_DMA=y
CONFIG_BLK_DEV_SD=y

# UFS 核心驱动
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y

# Allwinner UFS BSP 驱动
CONFIG_AW_UFS=y          # BSP 专用驱动
CONFIG_SCSI_UFS_BSP=y    # 可能的配置名

# 调试选项（开发阶段）
CONFIG_SCSI_UFSHCD_CMD_LOGGING=y
```

**现状**: `configs/cubie_a7a_defconfig` 已启用上述选项，说明同一 defconfig 可能兼容双板。

#### SD/eMMC 配置 (A7A 必需)
```bash
CONFIG_MMC=y
CONFIG_MMC_SUNXI=y
CONFIG_MMC_SDHCI_SUNXI=y
```

**决策**: 如果保持双板兼容，保留 MMC 配置；如果仅支持 A7Z，可禁用以减小内核。

---

### 4. U-Boot 引导差异

#### A7A 引导流程
```
1. BROM → boot0 (SPL, 分区 1)
2. boot0 → U-Boot (分区 2 或固定偏移)
3. U-Boot 扫描: mmc 0:3 → /boot/extlinux/extlinux.conf
4. 加载: /boot/Image + /usr/lib/linux-image-custom/sun60i-a733-cubie-a7a.dtb
5. 启动内核: root=/dev/mmcblk0p3
```

#### A7Z 引导流程
```
1. BROM → boot0 (SPL, UFS LUN 0 固定偏移)
2. boot0 → U-Boot (UFS LUN 0)
3. U-Boot 扫描: sunxi_flash_ufs 0:2 → /boot/extlinux/extlinux.conf
                 ^^^^^^^^^^^^^^^^^ 
                 关键差异：扫描分区 2，非分区 3
4. 加载: /boot/vmlinuz-custom + /usr/lib/linux-image-custom/sun60i-a733-cubie-a7z.dtb
5. 启动内核: root=/dev/sda3
```

**风险点**: U-Boot UFS 驱动稳定性未知，需测试验证。

---

### 5. 分区表对比

#### A7A GPT 布局示例
```bash
$ sgdisk -p /dev/mmcblk0
Number  Start      End        Size       Code  Name
   1    8192       40959      16.0 MiB   8300  boot0
   2    40960      73727      16.0 MiB   8300  boot-resource
   3    73728      剩余       剩余        EF00  rootfs
        ^^^^                             ^^^^
        U-Boot 扫描此分区                必须为 EF00
```

#### A7Z GPT 布局示例
```bash
$ sgdisk -p /dev/sda
Number  Start      End        Size       Code  Name
   1    2048       10239      4.0 MiB    8300  config
   2    10240      534527     256.0 MiB  EF00  EFI/boot ← U-Boot 扫描点
   3    534528     剩余       剩余        8300  rootfs
```

**迁移脚本**: `scripts/fix-a7z-ufs-boot.sh` 自动化此布局配置。

---

### 6. fstab 配置差异

#### A7A `/etc/fstab`
```fstab
UUID=xxxx-xxxx  /       ext4  defaults  0  1
# 可选 boot 分区（如果单独挂载）
```

#### A7Z `/etc/fstab`
```fstab
UUID=yyyy-yyyy  /config   vfat  defaults,x-systemd.automount  0  2
UUID=zzzz-zzzz  /boot/efi vfat  defaults,x-systemd.automount  0  2
UUID=aaaa-aaaa  /         ext4  defaults                       0  1
```

**注意**: A7Z 需挂载 3 个分区，config 和 boot/efi 为 vfat 类型。

---

### 7. extlinux.conf 参数差异

#### A7A 配置
```conf
label l0
    linux /boot/Image
    fdt /usr/lib/linux-image-custom/allwinner/sun60i-a733-cubie-a7a.dtb
    append root=/dev/mmcblk0p3 rootwait rootfstype=ext4 console=ttyAS0,115200
           ^^^^^^^^^^^^^^^^^^^
           SD/eMMC 设备路径
```

#### A7Z 配置
```conf
label l0
    linux /boot/vmlinuz-6.6.98+-custom
    fdt /usr/lib/linux-image-custom/allwinner/sun60i-a733-cubie-a7z.dtb
    append root=/dev/sda3 rootwait rootfstype=ext4 console=ttyAS0,115200
           ^^^^^^^^^^^^^^
           UFS 设备路径
           
    # 可选 UFS 调试参数（初期测试）
    append ... ufshcd_core.dyndbg=+p scsi_mod.scan=sync
```

---

### 8. 共享硬件组件（无需修改）

以下组件在 A7A 和 A7Z 上完全相同，DTS/配置可直接复用：

- **CPU OPP 表**: `sun60iw2p1-cpu-vf.dtsi` (超频配置通用)
- **GPU 配置**: PowerVR BXM-4-64, 1200 MHz 超频
- **NPU 配置**: Vivante VIP9000, 1008 MHz
- **PMIC**: AXP8191 电源管理
- **以太网**: STMMAC RGMII 千兆网
- **HDMI**: HDMI 2.0 控制器
- **USB**: USB 3.0 + USB 2.0 OTG
- **WiFi/BT**: AIC8800D80 (USB 接口，非 SDIO)
- **UART/I2C/SPI**: 引脚映射相同
- **LED/风扇**: GPIO 控制相同

---

## 迁移核心任务摘要

1. **设备树**: 启用 `&ufs { status = "okay"; }`, 禁用 `&sdc0/&sdc2`
2. **内核 cmdline**: `root=/dev/mmcblk0p3` → `root=/dev/sda3`
3. **分区布局**: 创建 3 分区 UFS 布局，sda2 类型为 EF00
4. **extlinux.conf**: 放置于 `/dev/sda2/boot/extlinux/` (非 sda3)
5. **fstab**: 添加 config 和 boot/efi 挂载点
6. **构建工件**: 确保 DTB 文件名包含 `-a7z` 后缀

---

## 未确认项（需硬件测试）

- [ ] A7Z 是否保留 SD 卡槽（影响 `&sdc0` 配置）
- [ ] UFS 芯片具体型号 (UFS 2.1 vs 2.2)
- [ ] U-Boot UFS 驱动是否稳定 (可能需要更新)
- [ ] A7Z 是否使用不同的 PMIC 配置
- [ ] RAM 容量是否为 12GB (可能有 8GB 版本)

---

## 参考资料

- UFS 规范: https://www.jedec.org/standards-documents/focus/flash/universal-flash-storage-ufs
- Allwinner A733 数据手册: (需 NDA)
- Linux UFS 驱动文档: `Documentation/scsi/ufs.rst`
- 当前项目 A7Z 迁移脚本: `scripts/fix-a7z-ufs-boot.sh`
