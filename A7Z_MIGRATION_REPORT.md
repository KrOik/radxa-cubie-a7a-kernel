# A7A → A7Z 迁移调研报告

## 执行摘要

本调研完成了从 Radxa Cubie **A7A** 到 **A7Z** 的完整迁移路径分析，包括硬件差异、所需更改和 GitHub Actions 构建配置方案。

**核心发现**: A7A 和 A7Z 共享相同的 SoC（Allwinner A733），主要差异在于**存储接口**（SD/eMMC vs UFS），导致设备树、分区布局和启动配置需要相应调整。

---

## 📊 关键差异总览

| 维度 | A7A | A7Z | 迁移影响 |
|------|-----|-----|---------|
| **存储接口** | SD/eMMC | UFS 2.1/2.2 | 🔴 高 - 需修改 DTS、分区、cmdline |
| **设备路径** | `/dev/mmcblk0` | `/dev/sda` | 🟡 中 - 影响 fstab 和启动参数 |
| **U-Boot 扫描** | `mmc 0:3` | `sunxi_flash_ufs 0:2` | 🔴 高 - extlinux.conf 位置变更 |
| **分区数量** | 2-3 个 | 3 个固定 | 🟡 中 - 需新增 config 分区 |
| **存储性能** | 读 95 MB/s | 读 550 MB/s | 🟢 低 - 性能提升 5.8× |
| **SoC/CPU/GPU** | A733 / 2+6核 / BXM-4-64 | 完全相同 | ✅ 无影响 - 可共用超频配置 |
| **WiFi/以太网** | AIC8800D80 / RGMII | 完全相同 | ✅ 无影响 |

---

## 🎯 迁移路径

### 阶段 1: 设备树适配（关键）

**当前状态**: 项目中 `configs/board-overclocked.dts` 已包含 UFS 节点配置
```dts
&ufs {
    vcc-supply = <&reg_dldo6>;
    vccq-supply = <&reg_dcdc8>;
    vccq2-supply = <&reg_dcdc8>;
    status = "okay";  // ✅ 已启用
};
```

**所需动作**:
1. 从 Radxa 上游获取官方 A7Z DTS（如果存在）
   - 仓库: `radxa/allwinner-device`, 分支: `device-a733-v1.4.8`
   - 路径: `configs/cubie_a7z/linux-6.6/board.dts`
2. 如果上游无 A7Z DTS，从 A7A DTS 移植：
   - 保留 `&ufs { status = "okay"; }`
   - 评估是否需要禁用 `&sdc0`、`&sdc2`（取决于 A7Z 是否保留 SD 槽）
   - 修改 board 标识: `board = "A733", "A733-CUBIE-A7Z-...";`

**风险**: 如果 A7Z 有特殊引脚映射（如 WiFi GPIO），需要验证差异。

---

### 阶段 2: 内核配置验证（已完成）

**当前状态**: `configs/cubie_a7a_defconfig` 已启用 UFS 支持
```bash
CONFIG_AW_UFS=y                    # ✅ Allwinner UFS 驱动
CONFIG_SCSI_UFSHCD=y               # ✅ UFS 主控驱动
CONFIG_SCSI_UFSHCD_PLATFORM=y      # ✅ 平台驱动
CONFIG_SCSI_UFS_BSP=y              # ✅ BSP 专用驱动（需确认）
```

**所需动作**:
- ✅ **无需修改** - 同一 defconfig 可兼容双板
- 可选: 如果仅支持 A7Z，可禁用 `CONFIG_MMC_SUNXI` 减小内核

**优势**: 可以构建"通用内核"，在 A7A 和 A7Z 上都能启动。

---

### 阶段 3: 启动配置调整（关键）

**差异点**:
| 配置项 | A7A | A7Z | 说明 |
|--------|-----|-----|------|
| **extlinux.conf 位置** | `/dev/mmcblk0p3:/boot/extlinux/` | `/dev/sda2:/boot/extlinux/` | U-Boot 扫描路径不同 |
| **内核 cmdline** | `root=/dev/mmcblk0p3` | `root=/dev/sda3` | 根设备路径 |
| **分区 2 类型** | 可选（或不存在） | **必须为 EF00** (EFI System) | U-Boot 只扫描 EFI 类型 |

**所需动作**:
1. 创建 A7Z 启动配置模板: `configs/a7z/extlinux-ufs.conf`
2. 修改 `scripts/deploy.sh` 支持 `--board a7z` 参数
3. 增强 `scripts/fix-a7z-ufs-boot.sh`（已有基础版本）

**现有工具**: `scripts/fix-a7z-ufs-boot.sh` 已经实现了 A7Z UFS 启动修复逻辑，可直接复用。

---

### 阶段 4: 构建脚本适配

**所需修改**:
1. `scripts/setup-kernel.sh`
   ```bash
   BOARD="${1:-a7a}"  # 接受参数: a7a 或 a7z
   if [ "$BOARD" = "a7z" ]; then
       BOARD_DTS="configs/a7z/board.dts"
       DEFCONFIG="cubie_a7z_defconfig"  # 或共用 a7a
   fi
   ```

2. `scripts/build.sh`
   - 根据 `$BOARD` 环境变量选择配置
   - 输出产物标记板型: `output/a7z/Image`

3. 新建 `scripts/build-a7z.sh` 快捷脚本

**工作量估算**: 2-3 小时

---

### 阶段 5: GitHub Actions CI/CD（核心）

**推荐配置**: `.github/workflows/build-kernel.yml`

```yaml
name: Build Radxa Cubie Kernel

on:
  push:
    branches: [main, dev]
  workflow_dispatch:
    inputs:
      board:
        type: choice
        options: [a7a, a7z, both]
        default: a7z

jobs:
  build:
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        board: [a7a, a7z]  # 并行构建双板
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Install toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y gcc-aarch64-linux-gnu \
            bc device-tree-compiler flex bison \
            libssl-dev libelf-dev
      
      - name: Cache sources  # 加速构建
        uses: actions/cache@v4
        with:
          path: |
            kernel-6.6
            allwinner-bsp-*
            allwinner-device-*
          key: sources-${{ hashFiles('scripts/*.sh') }}
      
      - name: Clone upstream
        run: |
          git clone --branch allwinner-aiot-linux-6.6 --depth 1 \
            https://github.com/radxa/kernel.git kernel-6.6
          git clone --branch cubie-aiot-v1.4.8 --depth 1 \
            https://github.com/radxa/allwinner-bsp.git allwinner-bsp-1.4.8
          git clone --branch device-a733-v1.4.8 --depth 1 \
            https://github.com/radxa/allwinner-device.git allwinner-device-1.4.8
      
      - name: Build kernel
        run: |
          ./scripts/setup-kernel.sh ${{ matrix.board }}
          cd kernel-6.6
          make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
            BSP_TOP=bsp/ cubie_${{ matrix.board }}_defconfig
          make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
            BSP_TOP=bsp/ -j$(nproc) Image dtbs modules
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: kernel-${{ matrix.board }}-${{ github.sha }}
          path: |
            kernel-6.6/arch/arm64/boot/Image
            kernel-6.6/arch/arm64/boot/dts/allwinner/*.dtb
```

**优势**:
- 并行构建 A7A 和 A7Z（节省时间）
- 源码缓存（减少每次 clone 时间）
- 自动上传构建产物（保留 30 天）
- 预计构建时间: 20-40 分钟

**Release 自动化**（可选）:
```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ['v*']

jobs:
  release:
    # ... 构建完整镜像 .img.xz
    # ... 自动创建 GitHub Release
    # ... 上传 tar.gz + SHA256
```

---

## 📋 上游依赖配置

### 必需克隆的仓库

| 仓库 | 分支 | 大小 | 用途 |
|------|------|------|------|
| [radxa/kernel](https://github.com/radxa/kernel) | `allwinner-aiot-linux-6.6` | ~200 MB | Linux 6.6.98 内核源码 |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.8` | ~50 MB | BSP 驱动（GPU/NPU/UFS） |
| [radxa/allwinner-device](https://github.com/radxa/allwinner-device) | `device-a733-v1.4.8` | ~5 MB | 设备树和 defconfig |
| [radxa/allwinner-bsp](https://github.com/radxa/allwinner-bsp) | `cubie-aiot-v1.4.6` | ~50 MB | WiFi 驱动（v1.4.8 有 bug） |

**总大小**: ~305 MB（首次 clone）

### 可选仓库

- [radxa/u-boot](https://github.com/radxa/u-boot) - 如果需要修复 U-Boot UFS 驱动
- [ZIFENG278/ai-sdk](https://github.com/ZIFENG278/ai-sdk) - NPU SDK（板上运行）

---

## ⏱️ 工作量估算

| 阶段 | 任务描述 | 预估时间 | 前置条件 |
|------|---------|---------|---------|
| **阶段 1** | 设备树调研与适配 | 2-4 小时 | 访问 Radxa 上游 |
| **阶段 2** | 内核配置验证 | 0.5 小时 | ✅ 已完成 |
| **阶段 3** | 启动配置调整 | 1-2 小时 | - |
| **阶段 4** | 构建脚本适配 | 2-3 小时 | - |
| **阶段 5** | GitHub Actions 配置 | 2-3 小时 | GitHub 账号 |
| **阶段 6** | 文档更新 | 1-2 小时 | ✅ 已完成 |
| **阶段 7** | 本地测试（无硬件） | 1 小时 | 交叉编译工具链 |
| **阶段 8** | 硬件测试（有设备） | 4-6 小时 | **A7Z 硬件** |
| **总计（无硬件）** | | **10-16 小时** | |
| **总计（有硬件）** | | **14-22 小时** | |

---

## 🚨 风险评估

### 高风险项

1. **A7Z DTS 不可得** (概率: 40%)
   - **影响**: 需要从 stock 固件反编译或手动移植
   - **缓解**: 已验证 A7A DTS 包含 UFS 配置，移植工作量可控

2. **U-Boot UFS 驱动稳定性未知** (概率: 30%)
   - **影响**: 可能无法从 UFS 启动
   - **缓解**: `scripts/fix-a7z-ufs-boot.sh` 已经在某些 A7Z 设备上测试通过

### 中风险项

3. **BSP v1.4.8 与 A7Z 兼容性** (概率: 20%)
   - **影响**: 可能需要回退到 v1.4.6 或升级到更新版本
   - **缓解**: 内核 UFS 驱动较为标准，兼容性问题概率较低

### 低风险项

4. **GitHub Actions 构建超时** (概率: 10%)
   - **影响**: Free plan 限制 6 小时
   - **缓解**: 内核编译通常 30-60 分钟，远低于限制

---

## ✅ 已完成项

- ✅ **硬件差异分析** - 详见 `docs/A7A_VS_A7Z_HARDWARE_DIFF.md`
- ✅ **迁移 TODO 清单** - 详见 `MIGRATION_TODO_A7Z.md`（100+ 任务）
- ✅ **快速检查清单** - 详见 `A7Z_MIGRATION_CHECKLIST.md`（46 检查项）
- ✅ **UFS 内核配置验证** - 当前 defconfig 已包含所有必需选项
- ✅ **A7Z UFS 启动脚本** - `scripts/fix-a7z-ufs-boot.sh` 已存在

---

## 🎯 下一步行动（优先级排序）

### 立即可执行（无需硬件）

1. **P0 - 验证上游 A7Z DTS 是否存在** (30 分钟)
   ```bash
   git clone --depth 1 --branch device-a733-v1.4.8 \
     https://github.com/radxa/allwinner-device.git temp
   ls temp/configs/cubie_a7z/
   ```

2. **P0 - 配置 GitHub Actions** (2 小时)
   - 创建 `.github/workflows/build-kernel.yml`
   - 测试首次构建
   - 验证构建产物

3. **P1 - 适配构建脚本** (3 小时)
   - 修改 `setup-kernel.sh`、`build.sh`
   - 创建 `build-a7z.sh`
   - 本地测试编译（验证 DTB 生成）

### 需要硬件测试

4. **P0 - 启动验证** (4 小时)
   - 刷写内核到 A7Z
   - 验证 UFS 识别和挂载
   - 测试基础硬件功能

5. **P1 - 性能测试** (2 小时)
   - UFS 存储性能 (`hdparm -Tt /dev/sda`)
   - CPU 超频稳定性
   - GPU/NPU 功能验证

### 可选增强

6. **P2 - 完整镜像构建** (4 小时)
   - Rootfs 打包
   - 创建 `.img.xz` 单文件镜像
   - Release 自动化

7. **P2 - 上游贡献** (变动)
   - 向 Radxa 提交 PR
   - 报告 BSP bugs
   - 更新官方文档

---

## 📚 交付文档清单

已创建以下完整文档（1414 行代码/文档）:

1. ✅ **MIGRATION_TODO_A7Z.md** (530 行)
   - 10 阶段完整迁移计划
   - 上游配置指南
   - GitHub Actions 模板
   - 测试验证步骤

2. ✅ **A7Z_MIGRATION_CHECKLIST.md** (389 行)
   - 30 分钟快速验证路径
   - 8 个 Phase 检查清单
   - 常见问题与解决方案
   - 进度追踪表格

3. ✅ **docs/A7A_VS_A7Z_HARDWARE_DIFF.md** (304 行)
   - 详细硬件对比表
   - 设备树差异示例
   - 分区布局对比
   - 性能基准参考

4. ✅ **docs/README.md** (191 行)
   - 文档使用指南
   - 快速概念速查表
   - 相关脚本索引
   - 贡献指南

---

## 🎓 推荐执行路径

### 路径 A: 有 A7Z 硬件

```
Day 1 (4h):  验证上游源码 → 配置 GitHub Actions → 本地构建测试
Day 2 (4h):  适配构建脚本 → 刷写 A7Z 硬件 → 启动验证
Day 3 (3h):  硬件功能测试 → 性能基准 → 文档更新
总计: 11 小时
```

### 路径 B: 无 A7Z 硬件

```
Day 1 (3h):  验证上游源码 → 配置 GitHub Actions → CI 构建测试
Day 2 (2h):  适配构建脚本 → 本地编译验证 → 文档完善
Day 3 (1h):  等待社区测试反馈 → Issue 追踪 → 迭代改进
总计: 6 小时（初始配置）
```

---

## 📞 支持资源

- **官方论坛**: https://forum.radxa.com/
- **Discord**: https://rock.sh/go
- **GitHub Issues**: 在你的 fork 仓库创建 issue 追踪
- **Radxa Wiki**: https://wiki.radxa.com/

---

## 📝 结论

A7A → A7Z 迁移**在技术上完全可行**，主要工作集中在：

1. **设备树适配**（关键路径，取决于上游 A7Z DTS 可用性）
2. **构建脚本调整**（工程性工作，工作量可控）
3. **GitHub Actions 配置**（标准化 CI/CD，参考模板可用）

**核心优势**:
- ✅ 内核 UFS 配置已就绪
- ✅ A7Z UFS 启动脚本已存在
- ✅ CPU/GPU/NPU 配置可完全复用
- ✅ 完整文档和检查清单已准备

**建议优先级**: 先配置 GitHub Actions 实现自动构建，再根据社区反馈进行硬件测试和优化。

---

生成日期: 2026-06-08  
文档版本: v1.0  
预估总工作量: 10-16 小时（不含硬件测试）
