# A7Z 迁移状态报告
生成时间：2026-06-08

## 原始需求
完成 A7A 迁移到 A7Z，生成完整镜像打包，配置 GitHub Actions 构建所需的 CI 更改，并完成提交推送到 https://github.com/KrOik/radxa-cubie-a7a-kernel

## 当前实现状态

### ✅ 已完成（阶段性成功）

#### 1. GitHub Actions CI/CD 配置
- [x] 创建 `.github/workflows/build-kernel.yml`
- [x] Matrix 策略支持 A7A 和 A7Z 并行构建
- [x] 源码缓存优化（加速构建）
- [x] 自动生成 artifact（保留 30 天）
- [x] 自动生成 release tarball（保留 90 天）
- [x] 构建摘要报告
- **最新成功构建**：https://github.com/KrOik/radxa-cubie-a7a-kernel/actions/runs/27143340110
- **产物大小**：
  - A7A tarball: 30.5 MB
  - A7Z tarball: 30.5 MB
  - A7A 完整 artifact: 869 MB
  - A7Z 完整 artifact: 869 MB

#### 2. 构建脚本适配
- [x] `scripts/setup-kernel.sh` 支持板型参数
  - 用法：`./setup-kernel.sh [a7a|a7z]`
  - 包含板型特定的 DTS 查找逻辑
- [x] `scripts/apply-patches.sh` 错误处理改进
  - 移除 `-e` 标志，使用 `safe_patch()` 函数
  - 优雅处理缺失的 BSP 文件
- [x] 修复 BSP ramfs 符号链接问题
  - 在 artifact 上传前删除 `bsp/ramfs` 避免 ENOENT 错误

#### 3. 文档创建
- [x] `MIGRATION_TODO_A7Z.md` - 完整迁移清单（530 行，10 阶段 100+ 任务）
- [x] `A7Z_MIGRATION_CHECKLIST.md` - 快速检查清单（389 行，8 阶段 46 检查项）
- [x] `docs/A7A_VS_A7Z_HARDWARE_DIFF.md` - 硬件差异对照（304 行）
- [x] `A7Z_MIGRATION_REPORT.md` - 执行摘要报告（403 行）

#### 4. 提交历史
```
5a80465 Fix artifact upload: remove BSP ramfs with broken symlinks
aeab4a4 Fix setup-kernel.sh error handling for CI
650c196 Fix apply-patches.sh with better error handling
8fa1dbe Fix GitHub Actions workflow issues
4457ca5 Add GitHub Actions CI/CD for A7A and A7Z kernel builds
```

---

### ⚠️ 当前缺陷（核心问题）

#### 问题 1：A7Z 使用的是 A7A 配置（非真正的 A7Z）

**现象**：
- `configs/a7z/` 目录不存在
- `scripts/setup-kernel.sh` 第 41-50 行显示 fallback 逻辑：
  ```bash
  elif [ -f "$DEVICE/configs/cubie_a7a/linux-6.6/board.dts" ]; then
      echo "Warning: No ${BOARD} board.dts found, using A7A as template"
      cp "$DEVICE/configs/cubie_a7a/linux-6.6/board.dts" \
         "$DTS_DIR/sun60i-a733-cubie-${BOARD}.dts"
  ```
- 构建日志会输出：`Warning: No a7z board.dts found, using A7A as template`

**影响**：
- 生成的 `sun60i-a733-cubie-a7z.dtb` 实际上是 A7A 的 DTS 副本
- UFS 相关配置可能缺失或不正确
- 在真实 A7Z 硬件上可能无法正常启动

**根本原因**：
1. Radxa 上游可能没有公开 A7Z 的官方配置
2. 未从 stock 固件提取 A7Z DTS
3. 未手动创建 A7Z 专用配置

---

#### 问题 2：缺少 A7Z defconfig

**现象**：
- `configs/a7z/cubie_a7z_defconfig` 不存在
- `.github/workflows/build-kernel.yml` 第 117-121 行：
  ```yaml
  if [ "${{ matrix.board }}" = "a7z" ] && [ -f arch/arm64/configs/cubie_a7z_defconfig ]; then
    DEFCONFIG="cubie_a7z_defconfig"
  else
    DEFCONFIG="cubie_a7a_defconfig"
  fi
  ```
- 条件永远为 false，A7Z 使用 `cubie_a7a_defconfig`

**影响**：
- 虽然 A7A defconfig 已启用 UFS（`CONFIG_AW_UFS=y`），可以兼容 A7Z
- 但没有针对 A7Z 的特定优化（如禁用 SD/eMMC 驱动以减小内核）

**可接受性**：
- **中等影响** - 当前配置理论上可工作，但不是最优

---

#### 问题 3：缺少完整镜像打包（原始需求的一部分）

**原始需求**：*"生成完整镜像打包"*

**当前状态**：
- ✅ 生成了 kernel Image
- ✅ 生成了 DTB 文件
- ✅ 生成了 modules tarball
- ❌ **未生成可直接刷写的 `.img` 或 `.img.xz` 完整镜像**

**缺失内容**：
1. 没有 rootfs 集成脚本
2. 没有分区表创建（UFS 需要 3 分区：config + EFI + rootfs）
3. 没有 boot0 + U-Boot 打包
4. 没有一键刷写脚本（`flash-image.sh` 仅支持 A7A SD 卡）

**现有的镜像脚本**：
- `scripts/flash-image.sh` - 仅支持 A7A SD 卡刷写
- `scripts/easy-flash.sh` - 仅支持 A7A
- `scripts/fix-a7z-ufs-boot.sh` - A7Z UFS 启动修复（需要已有系统）

---

### ❌ 未完成的关键任务

根据 `MIGRATION_TODO_A7Z.md`，以下是未完成的核心任务：

#### 阶段 1：上游源码调研（0%）
- [ ] 验证 Radxa 上游是否有 A7Z 专用分支
  - 仓库：https://github.com/radxa/allwinner-device
  - 分支：`device-a733-v1.4.8`
  - 检查：`configs/cubie_a7z/` 是否存在
- [ ] 确认 A7Z DTS 可用性
  - 选项 A：从上游获取
  - 选项 B：从 stock 固件反编译（`dtc -I dtb -O dts`）
  - 选项 C：从 A7A DTS 手动移植

#### 阶段 2：代码仓库结构（20%）
- [x] 创建文档（已完成）
- [ ] 创建 `configs/a7z/` 目录结构
- [ ] 更新 README.md（添加 A7Z 部分）

#### 阶段 3：设备树适配（0%）
- [ ] 获取/创建 A7Z board.dts
- [ ] 验证 UFS 节点配置
- [ ] 评估 SD/eMMC 节点状态
- [ ] 修改 board ID 标识
- [ ] 测试编译 DTB

#### 阶段 4：内核配置（10%）
- [x] 验证 UFS 选项已启用（当前 A7A defconfig 已包含）
- [ ] 创建 `configs/a7z/cubie_a7z_defconfig`
- [ ] 优化 A7Z 专用选项（如禁用 MMC）

#### 阶段 5：启动配置（0%）
- [ ] 创建 A7Z extlinux.conf 模板
  - UFS 路径：`root=/dev/sda3`（而非 A7A 的 `/dev/mmcblk0p3`）
  - U-Boot 扫描：`sunxi_flash_ufs 0:2`（而非 `mmc 0:3`）
- [ ] 修改 `scripts/deploy.sh` 支持 A7Z
- [ ] 增强 `scripts/fix-a7z-ufs-boot.sh`

#### 阶段 6：构建脚本（70%）
- [x] 修改 `setup-kernel.sh`（已支持参数，但 fallback 到 A7A）
- [ ] 修改 `build.sh`（使其真正使用 A7Z 配置）
- [ ] 创建 `scripts/build-a7z.sh` 便捷脚本

#### 阶段 7：GitHub Actions（90%）
- [x] 创建 workflow 文件
- [x] Matrix 构建
- [x] 源码缓存
- [x] Artifact 上传
- [ ] 完整镜像构建步骤（可选，但原始需求提到）

#### 阶段 8：完整镜像打包（0%）
- [ ] 集成 rootfs（Debian 13）
- [ ] 创建 UFS 分区布局脚本
- [ ] 打包 boot0 + U-Boot
- [ ] 生成 `.img.xz` 单文件镜像
- [ ] 更新 `flash-image.sh` 支持 A7Z UFS

#### 阶段 9：测试验证（0%）
- [ ] 本地编译测试
- [ ] 硬件启动测试（需要 A7Z 实体设备）
- [ ] UFS 性能测试
- [ ] 基础硬件功能验证

#### 阶段 10：文档与发布（50%）
- [x] 迁移文档（已完成）
- [ ] 更新 README.md（添加 A7Z 说明）
- [ ] 创建 Release（可通过 GitHub Actions 自动化）

---

## 实际完成度评估

### 按原始需求评估

**原始需求**：*"完成 A7A 迁移到 A7Z 生成完整镜像打包配置 GitHub Actions 构建所需的 CI 更改"*

| 需求项 | 状态 | 完成度 |
|--------|------|--------|
| **GitHub Actions CI 配置** | ✅ 完成 | 100% |
| **双板并行构建** | ✅ 完成 | 100% |
| **A7Z 真实设备树** | ❌ 缺失 | 0% |
| **A7Z defconfig** | ⚠️ 使用 A7A | 30% |
| **完整镜像打包** | ❌ 缺失 | 0% |
| **文档与调研** | ✅ 完成 | 100% |

**总体完成度**：**55%**（CI 部分完成，但 A7Z 实际上是 A7A 配置的复制品）

---

## 下一步行动建议

### 立即可执行（无需硬件）

#### 优先级 P0：验证上游 A7Z 配置

```bash
# 方法 1：克隆上游 device 仓库
git clone --branch device-a733-v1.4.8 --depth 1 \
  https://github.com/radxa/allwinner-device.git temp_device

# 检查是否存在 A7Z 配置
ls -la temp_device/configs/cubie_a7z/

# 如果存在，复制到项目
if [ -d "temp_device/configs/cubie_a7z" ]; then
  mkdir -p configs/a7z
  cp temp_device/configs/cubie_a7z/linux-6.6/board.dts \
     configs/a7z/board.dts
  cp temp_device/configs/cubie_a7z/linux-6.6/board_defconfig \
     configs/a7z/cubie_a7z_defconfig
fi

# 方法 2：从 stock 固件提取（如果有 A7Z 设备）
# dtc -I dtb -O dts /boot/dtb/allwinner/sun60i-a733-cubie-a7z.dtb \
#   -o configs/a7z/board-from-stock.dts
```

#### 优先级 P1：创建 A7Z 配置（如果上游不存在）

**手动移植 DTS**：
1. 复制 `configs/board-overclocked.dts` → `configs/a7z/board.dts`
2. 修改 board ID：
   ```dts
   / {
       model = "Radxa Cubie A7Z";
       compatible = "radxa,cubie-a7z", "allwinner,sun60i-a733";
   };
   ```
3. 确保 UFS 启用：
   ```dts
   &ufs {
       status = "okay";
   };
   ```
4. 评估 SD/eMMC 节点（根据硬件决定）

**创建 A7Z defconfig**：
```bash
cp configs/cubie_a7a_defconfig configs/a7z/cubie_a7z_defconfig
# 可选优化：
# - 禁用 CONFIG_MMC_SUNXI（如果 A7Z 无 SD 槽）
# - 启用 UFS 调试选项（开发阶段）
```

#### 优先级 P1：创建 A7Z 启动配置

**extlinux.conf 模板**：
```bash
mkdir -p configs/a7z
cat > configs/a7z/extlinux.conf.template <<'EOF'
label Radxa Cubie A7Z
  kernel /Image
  fdt /allwinner/sun60i-a733-cubie-a7z.dtb
  append root=/dev/sda3 rw rootwait console=ttyS0,115200 earlycon=uart8250,mmio32,0x02500000
EOF
```

#### 优先级 P2：完整镜像打包（可选）

**简化版本**（仅打包内核+模块）：
- 当前 tarball 已包含所有必需文件
- 用户可手动解压到现有系统

**完整版本**（包含 rootfs）：
- 需要额外工作（下载/构建 Debian rootfs）
- 需要 U-Boot 二进制文件
- 创建分区表和 GPT 镜像
- 预估工作量：4-6 小时

---

### 需要硬件测试

#### 优先级 P0：启动验证（需要 A7Z 设备）

1. 刷写当前构建的内核到 A7Z
2. 验证 UFS 识别：`lsblk` 应显示 `/dev/sda`
3. 验证基础功能：网络、USB、显示

---

## 与构建日志的对比

### 构建成功的证据
```
Build Kernel (a7z) - Setup kernel tree: ✅ success
Build Kernel (a7z) - Configure kernel: ✅ success (使用 cubie_a7a_defconfig)
Build Kernel (a7z) - Build kernel Image and DTBs: ✅ success
Build Kernel (a7z) - Build kernel modules: ✅ success
Build Kernel (a7z) - Install modules: ✅ success
Build Kernel (a7z) - Upload artifacts: ✅ success
```

### 隐藏的警告（日志中未显示）
- `setup-kernel.sh` 可能输出：*"Warning: No a7z board.dts found, using A7A as template"*
- 但这条警告在 CI 日志中不会导致失败，构建继续进行

---

## 结论

### 当前状态
✅ **GitHub Actions CI/CD 已完整配置并成功运行**
- 双板并行构建工作正常
- Artifact 生成和上传成功
- 构建流程稳定可靠

⚠️ **A7Z 配置实际上是 A7A 的复制品**
- 缺少真实的 A7Z 设备树
- 缺少 A7Z defconfig
- 可能在真实 A7Z 硬件上工作，但未经验证

❌ **完整镜像打包缺失**
- 当前仅有 kernel Image + DTB + modules tarball
- 缺少可直接刷写的 `.img` 镜像
- 用户需要手动集成到现有系统

### 建议
1. **如果有 A7Z 设备**：测试当前构建的内核是否能启动
2. **如果网络恢复**：验证上游是否有 A7Z 官方配置
3. **如果需要完整镜像**：需要额外 4-6 小时工作完成镜像打包

### 风险评估
- **当前构建的 A7Z 内核可能可用**（因为 A7A defconfig 已启用 UFS）
- **但未经硬件验证**，不能保证在真实 A7Z 上正常工作
- **建议在推广前进行硬件测试**
