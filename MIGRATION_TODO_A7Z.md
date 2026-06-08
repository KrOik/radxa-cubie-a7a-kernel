# Radxa Cubie A7A → A7Z 迁移 TODO 清单

## 项目概述

**目标**: 将当前 A7A 内核项目迁移到 A7Z，并配置 GitHub Actions 自动构建

**关键差异**: A7Z 使用 UFS 存储 (而非 A7A 的 SD/eMMC)，需要调整设备树、分区布局和启动配置

---

## 阶段 1: 上游源码调研与准备

### 1.1 调研 A7Z 官方支持状态

- [ ] **检查 Radxa 上游是否有 A7Z 专用分支**
  - 仓库: https://github.com/radxa/allwinner-device
  - 检查是否存在 `configs/cubie_a7z/` 目录
  - 分支: `device-a733-v1.4.8` 或更新版本
  - **预期结果**: 找到 A7Z 的 board.dts 和 defconfig

- [ ] **确认 A7Z 设备树 (DTS) 可用性**
  - 当前已知: `sun60i-a733-cubie-a7z.dtb` 存在于 stock 固件
  - 需要确认源码位置: 
    - `radxa/allwinner-device` → `configs/cubie_a7z/linux-6.6/board.dts`
    - 或从 stock 固件反编译: `dtc -I dtb -O dts sun60i-a733-cubie-a7z.dtb`
  - **关键差异点**:
    - UFS 控制器启用 (`&ufs { status = "okay"; }`)
    - SD/eMMC 控制器可能禁用
    - 引脚复用差异 (如果 PCB 布局不同)

- [ ] **调研 U-Boot 对 A7Z UFS 支持**
  - 仓库: https://github.com/radxa/u-boot
  - 分支: `allwinner-aiot-v2018.07`
  - 确认 UFS 扫描路径: `sunxi_flash_ufs 0:2` (即 `/dev/sda2`)
  - 验证是否需要单独的 A7Z U-Boot defconfig

- [ ] **检查 BSP 版本兼容性**
  - 当前使用: `cubie-aiot-v1.4.8`
  - 确认 A7Z 是否需要更新版本 (v1.4.9+)
  - 检查 UFS PHY 驱动完整性: `allwinner-bsp/drivers/ufs/`

---

## 阶段 2: 代码仓库结构调整

### 2.1 重命名与重新组织项目

- [ ] **决策: 项目命名策略**
  - **选项 A**: 重命名为 `radxa-cubie-a7z-kernel` (新仓库)
  - **选项 B**: 保持 `radxa-cubie-a7a-kernel`，支持双板构建 (推荐)
  - **推荐**: 选项 B，通过构建参数切换

- [ ] **创建 A7Z 专用配置目录**
  ```bash
  mkdir -p configs/a7z/
  # 将来存放:
  # - configs/a7z/board.dts (或 board-overclocked.dts)
  # - configs/a7z/cubie_a7z_defconfig
  # - configs/a7z/extlinux-ufs.conf.template
  ```

- [ ] **更新 README.md**
  - 添加 A7Z 硬件规格表
  - 说明 A7A vs A7Z 差异 (存储、分区布局)
  - 提供双板构建指南

---

## 阶段 3: 设备树 (DTS) 适配

### 3.1 获取/创建 A7Z 设备树

- [ ] **从上游获取 A7Z board.dts**
  ```bash
  # 如果上游存在
  git clone --branch device-a733-v1.4.8 --depth 1 \
    https://github.com/radxa/allwinner-device.git
  cp allwinner-device/configs/cubie_a7z/linux-6.6/board.dts \
    configs/a7z/board.dts
  ```

- [ ] **或从 A7A DTS 移植**（如果上游无 A7Z 源码）
  - 基础文件: `configs/board-overclocked.dts`
  - 修改项:
    1. **Board ID**: `board = "A733", "A733-CUBIE-A7Z-...";`
    2. **UFS 启用**:
       ```dts
       &ufs {
           status = "okay";
       };
       ```
    3. **SD/eMMC 评估**: 确认 `&sdc0`, `&sdc2` 状态
       - 如果 A7Z 仍保留 SD 槽 → 保持 `okay`
       - 如果仅 UFS → 改为 `disabled`
    4. **引脚复用检查**: UART/I2C/SPI/GPIO 是否有差异

- [ ] **验证设备树编译**
  ```bash
  # 添加到内核 DTS Makefile
  echo 'dtb-$(CONFIG_ARCH_SUNXI) += sun60i-a733-cubie-a7z.dtb' \
    >> kernel-6.6/arch/arm64/boot/dts/allwinner/Makefile
  
  # 测试编译
  cd kernel-6.6
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    allwinner/sun60i-a733-cubie-a7z.dtb
  ```

### 3.2 超频配置移植 (可选)

- [ ] **复制 CPU/GPU OPP 表**
  - `sun60iw2p1-cpu-vf-overclocked.dtsi` → 可共用
  - `sun60iw2p1-gpu-overclocked.dtsi` → 可共用
  - 在 A7Z board.dts 中包含: `#include "sun60iw2p1-cpu-vf-overclocked.dtsi"`

---

## 阶段 4: 内核配置 (defconfig) 调整

### 4.1 创建 A7Z defconfig

- [ ] **验证 UFS 内核选项**（当前 A7A defconfig 已启用，需确认完整性）
  ```bash
  grep -E "CONFIG_.*UFS|CONFIG_SCSI" configs/cubie_a7a_defconfig
  ```
  必需选项:
  ```
  CONFIG_AW_UFS=y
  CONFIG_SCSI=y
  CONFIG_SCSI_UFSHCD=y
  CONFIG_SCSI_UFSHCD_PLATFORM=y
  CONFIG_SCSI_UFS_BSP=y  # Allwinner BSP UFS 驱动
  ```

- [ ] **评估 SD/eMMC 配置**
  - 如果 A7Z 无 SD 槽: `CONFIG_MMC_SUNXI=n`
  - 如果保留: 保持启用以支持双启动

- [ ] **创建 A7Z 专用 defconfig**（如果需要差异化）
  ```bash
  cp configs/cubie_a7a_defconfig configs/a7z/cubie_a7z_defconfig
  # 根据硬件差异调整配置项
  ```

- [ ] **添加 UFS 错误恢复选项**（提高稳定性）
  ```
  CONFIG_SCSI_UFSHCD_CMD_LOGGING=y
  CONFIG_SCSI_UFS_FAULT_INJECTION=n  # 生产环境关闭
  ```

---

## 阶段 5: 启动配置与分区布局

### 5.1 extlinux.conf 模板

- [ ] **创建 A7Z UFS 专用启动配置**
  ```bash
  # configs/a7z/extlinux-ufs.conf.template
  ```
  关键差异:
  - `root=/dev/sda3` (非 `/dev/mmcblk0p3`)
  - 启动参数保留: `coherent_pool=2M clk_ignore_unused`
  - 添加 UFS 调试选项 (初期): `ufshcd_core.dyndbg=+p`

- [ ] **文档化分区布局**
  ```
  A7Z UFS 标准布局:
  /dev/sda1  4MB   config       vfat
  /dev/sda2  256MB EFI/boot     vfat (U-Boot 扫描点)
  /dev/sda3  剩余  rootfs       ext4
  
  关键要求:
  - sda2 类型必须为 EF00 (EFI System)
  - extlinux.conf 位于 /dev/sda2/boot/extlinux/
  - 内核/DTB 需同时存在于 sda2 和 sda3
  ```

### 5.2 更新部署脚本

- [ ] **修改 `scripts/deploy.sh`**
  - 添加 `--board a7z` 参数
  - UFS 路径判断: 
    ```bash
    if [ "$BOARD" = "a7z" ]; then
        ROOT_DEV=/dev/sda3
        BOOT_DEV=/dev/sda2
    else
        ROOT_DEV=/dev/mmcblk0p3
    fi
    ```

- [ ] **修改 `scripts/flash-image.sh`**
  - A7Z 不支持 SD 卡刷写（UFS 焊接在板上）
  - 添加警告: "A7Z requires in-place upgrade via SSH, not SD flashing"

- [ ] **增强 `scripts/fix-a7z-ufs-boot.sh`**（已有基础版本）
  - 支持从 A7A 镜像迁移
  - 自动检测 UFS 设备
  - 验证 U-Boot 兼容性

---

## 阶段 6: 构建脚本适配

### 6.1 支持多板构建

- [ ] **修改 `scripts/setup-kernel.sh`**
  ```bash
  # 添加参数: ./scripts/setup-kernel.sh [a7a|a7z]
  BOARD="${1:-a7a}"
  
  if [ "$BOARD" = "a7z" ]; then
      BOARD_DTS_SRC="${DEVICE_DIR}/configs/cubie_a7z/linux-6.6/board.dts"
      DEFCONFIG="cubie_a7z_defconfig"
  else
      BOARD_DTS_SRC="${DEVICE_DIR}/configs/cubie_a7a/linux-6.6/board.dts"
      DEFCONFIG="cubie_a7a_defconfig"
  fi
  ```

- [ ] **修改 `scripts/build.sh`**
  - 接受 `BOARD=a7z` 环境变量
  - 选择对应 defconfig
  - 输出产物包含板型标识: `output/a7z/Image`

- [ ] **创建便捷脚本**
  ```bash
  # scripts/build-a7z.sh (新建)
  #!/bin/bash
  export BOARD=a7z
  ./scripts/setup-kernel.sh a7z
  ./scripts/build.sh
  ./scripts/package.sh a7z
  ```

---

## 阶段 7: GitHub Actions CI/CD 配置

### 7.1 创建 Workflow 文件

- [ ] **创建 `.github/workflows/build-kernel.yml`**
  ```yaml
  name: Build Radxa Cubie Kernel
  
  on:
    push:
      branches: [main, dev]
    pull_request:
      branches: [main]
    workflow_dispatch:
      inputs:
        board:
          description: 'Board type'
          required: true
          default: 'a7z'
          type: choice
          options:
            - a7a
            - a7z
            - both
  
  jobs:
    build-matrix:
      name: Build ${{ matrix.board }}
      runs-on: ubuntu-24.04
      strategy:
        matrix:
          board: [a7a, a7z]
      
      steps:
        - name: Checkout repository
          uses: actions/checkout@v4
        
        - name: Setup build environment
          run: |
            sudo apt-get update
            sudo apt-get install -y \
              gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
              bc device-tree-compiler cpio kmod python3 swig \
              flex bison libssl-dev libncurses-dev libelf-dev \
              git wget
        
        - name: Cache source repositories
          uses: actions/cache@v4
          with:
            path: |
              kernel-6.6
              allwinner-bsp-1.4.8
              allwinner-device-1.4.8
            key: sources-${{ hashFiles('scripts/apply-patches.sh') }}
        
        - name: Clone upstream sources
          run: |
            git clone --branch allwinner-aiot-linux-6.6 --depth 1 \
              https://github.com/radxa/kernel.git kernel-6.6
            git clone --branch cubie-aiot-v1.4.8 --depth 1 \
              https://github.com/radxa/allwinner-bsp.git allwinner-bsp-1.4.8
            git clone --branch device-a733-v1.4.8 --depth 1 \
              https://github.com/radxa/allwinner-device.git allwinner-device-1.4.8
        
        - name: Apply patches
          run: ./scripts/apply-patches.sh
        
        - name: Setup kernel tree
          run: ./scripts/setup-kernel.sh ${{ matrix.board }}
        
        - name: Build kernel
          run: |
            cd kernel-6.6
            make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
              BSP_TOP=bsp/ cubie_${{ matrix.board }}_defconfig
            make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
              BSP_TOP=bsp/ -j$(nproc) Image dtbs modules
        
        - name: Package artifacts
          run: |
            mkdir -p artifacts/${{ matrix.board }}
            cp kernel-6.6/arch/arm64/boot/Image artifacts/${{ matrix.board }}/
            cp kernel-6.6/arch/arm64/boot/dts/allwinner/sun60i-a733-cubie-${{ matrix.board }}.dtb \
              artifacts/${{ matrix.board }}/
            
            # 打包模块
            cd kernel-6.6
            make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
              modules_install INSTALL_MOD_PATH=../artifacts/${{ matrix.board }}/modules \
              INSTALL_MOD_STRIP=1
        
        - name: Upload artifacts
          uses: actions/upload-artifact@v4
          with:
            name: kernel-${{ matrix.board }}-${{ github.sha }}
            path: artifacts/${{ matrix.board }}/
            retention-days: 30
        
        - name: Create release archive
          if: startsWith(github.ref, 'refs/tags/')
          run: |
            cd artifacts/${{ matrix.board }}
            tar -czf ../../radxa-cubie-${{ matrix.board }}-kernel-${{ github.ref_name }}.tar.gz *
        
        - name: Upload to release
          if: startsWith(github.ref, 'refs/tags/')
          uses: softprops/action-gh-release@v1
          with:
            files: radxa-cubie-${{ matrix.board }}-kernel-${{ github.ref_name }}.tar.gz
  ```

### 7.2 配置 Secrets 与权限

- [ ] **配置 GitHub Repository Settings**
  - `Settings` → `Actions` → `General`
  - **Workflow permissions**: 选择 "Read and write permissions"
  - 启用 "Allow GitHub Actions to create and approve pull requests"

- [ ] **（可选）配置发布 Token**
  - 如果需要跨仓库操作: `Settings` → `Secrets` → `GITHUB_TOKEN`
  - 对于基本构建，默认 token 已足够

### 7.3 创建辅助 Workflows

- [ ] **创建 `.github/workflows/test-build.yml`**（快速验证）
  - 仅构建 DTB + defconfig 验证
  - 用于 PR 快速检查

- [ ] **创建 `.github/workflows/release.yml`**（标签触发）
  - 构建完整镜像 (.img.xz)
  - 包含 rootfs + 预装模块
  - 自动创建 GitHub Release

---

## 阶段 8: 文档更新

### 8.1 README 重构

- [ ] **添加 A7Z 专用章节**
  - 硬件规格对比表
  - UFS 特定说明
  - 启动故障排查 (U-Boot UFS 扫描失败)

- [ ] **更新构建指南**
  ```markdown
  ## 构建 A7Z 内核
  
  ```bash
  # 本地构建
  ./scripts/build-a7z.sh
  
  # 或通过 GitHub Actions
  1. Fork 本仓库
  2. 进入 Actions 标签页
  3. 选择 "Build Radxa Cubie Kernel"
  4. 点击 "Run workflow" → 选择 "a7z"
  ```

- [ ] **添加 CI 状态徽章**
  ```markdown
  [![Build Status](https://github.com/YOUR_USERNAME/radxa-cubie-a7z-kernel/actions/workflows/build-kernel.yml/badge.svg)](https://github.com/YOUR_USERNAME/radxa-cubie-a7z-kernel/actions)
  ```

### 8.2 创建迁移指南

- [ ] **创建 `docs/UPGRADE_A7A_TO_A7Z.md`**
  - 从 A7A SD 镜像迁移到 A7Z UFS 的完整步骤
  - 分区格式化命令
  - U-Boot 环境变量检查
  - 常见问题 FAQ

---

## 阶段 9: 测试与验证

### 9.1 本地测试（如果有 A7Z 硬件）

- [ ] **验证 DTB 正确性**
  ```bash
  # 在 A7Z 板上
  dtc -I dtb -O dts /boot/sun60i-a733-cubie-a7z.dtb | less
  # 检查: ufs 节点 status = "okay"
  ```

- [ ] **启动测试清单**
  - [ ] U-Boot 识别 UFS 设备 (`ufsinit 0`)
  - [ ] 内核加载无错误 (`dmesg | grep -i ufs`)
  - [ ] 根文件系统挂载成功 (`findmnt /`)
  - [ ] UFS 性能测试:
    ```bash
    sudo hdparm -Tt /dev/sda
    # 预期: 顺序读 >500 MB/s (UFS 2.1/2.2)
    ```

- [ ] **硬件功能验证**
  - [ ] CPU 频率调节: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq`
  - [ ] GPU 加载: `cat /sys/kernel/debug/pvr/status`
  - [ ] NPU 测试: `~/ai-sdk/examples/vpm_run/vpm_run -s sample_v3.txt -l 3`
  - [ ] WiFi/蓝牙连接
  - [ ] 以太网 1Gbps 测试
  - [ ] HDMI 输出

### 9.2 GitHub Actions 测试

- [ ] **验证自动构建**
  - 推送测试提交触发 workflow
  - 检查构建日志无错误
  - 下载 artifacts 验证文件完整性

- [ ] **标签发布测试**
  ```bash
  git tag -a v1.0.0-a7z-rc1 -m "A7Z initial release candidate"
  git push origin v1.0.0-a7z-rc1
  ```
  - 验证 Release 自动创建
  - 检查附件包含 tar.gz

---

## 阶段 10: 上游贡献与维护

### 10.1 向上游反馈

- [ ] **检查是否可提交 PR 到 Radxa**
  - 超频配置文件
  - A7Z defconfig 改进
  - UFS 启动脚本

- [ ] **报告 Bug**
  - A7A WiFi BSP v1.4.8 驱动问题（已知需用 v1.4.6）
  - GPU 模块编译 `.NOTINTERMEDIATE` 兼容性问题

### 10.2 长期维护

- [ ] **订阅上游更新**
  - 监控 `radxa/kernel` 新版本 (Linux 6.7+)
  - 跟踪 BSP 更新 (v1.4.9+)

- [ ] **自动化版本追踪**
  - 创建 `.github/workflows/check-upstream.yml`
  - 每周检查上游新 commit

---

## 检查清单摘要

### 高优先级（P0 - 必须完成）
1. ✅ 获取 A7Z 设备树源码
2. ✅ 验证 UFS 内核配置完整性
3. ✅ 创建 A7Z 专用构建脚本
4. ✅ 配置 GitHub Actions 基础 workflow
5. ✅ 更新 README 说明 A7A vs A7Z 差异

### 中优先级（P1 - 推荐完成）
1. ⚠️ 创建 Release workflow 自动打包
2. ⚠️ 添加 CI 状态徽章
3. ⚠️ 编写 A7A→A7Z 迁移文档
4. ⚠️ 本地测试 A7Z 启动（需要硬件）

### 低优先级（P2 - 增强功能）
1. 🔵 GPU/NPU 模块自动构建
2. 🔵 完整 rootfs 镜像打包 (.img.xz)
3. 🔵 上游贡献 PR
4. 🔵 自动化上游版本追踪

---

## 预估工作量

- **阶段 1-3**（调研与 DTS）: 2-4 小时
- **阶段 4-6**（配置与脚本）: 3-5 小时
- **阶段 7**（GitHub Actions）: 2-3 小时
- **阶段 8-9**（文档与测试）: 3-4 小时
- **总计**: 10-16 小时（不含硬件测试）

## 风险与阻塞点

1. **A7Z DTS 源码不可得** → 需反编译 stock DTB
2. **U-Boot UFS 驱动有 Bug** → 可能需要自行修复或等待上游
3. **BSP v1.4.8 不兼容 A7Z** → 需尝试 v1.4.6 或更新版本
4. **GitHub Actions 构建超时** → Free plan 限制 6 小时，内核编译约 30-60 分钟（应可通过）

---

## 参考资源

- Radxa Kernel: https://github.com/radxa/kernel
- Allwinner BSP: https://github.com/radxa/allwinner-bsp
- Allwinner Device: https://github.com/radxa/allwinner-device
- UFS 驱动文档: `Documentation/scsi/ufs.rst` (kernel)
- GitHub Actions 文档: https://docs.github.com/en/actions
