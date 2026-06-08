# A7Z 迁移快速检查清单

## 🎯 关键决策点

在开始之前，需要明确：

- [ ] **是否有 A7Z 硬件**用于测试？
  - ✅ 有 → 可以完整验证所有功能
  - ❌ 无 → 只能进行静态构建验证，建议先完成 CI 配置

- [ ] **项目命名策略**：
  - **选项 A**: 重命名为 `radxa-cubie-a7z-kernel`（新仓库，专注 A7Z）
  - **选项 B**: 保持 `radxa-cubie-a7a-kernel`，支持双板构建（推荐）

- [ ] **A7Z 设备树来源**：
  - **优先**: 从 Radxa 上游获取官方 DTS
  - **备选**: 从 A7A DTS 修改（需要调整 UFS/SD 节点）
  - **兜底**: 从 stock 固件反编译 DTB

---

## ⚡ 快速开始 (30 分钟验证路径)

### 第 1 步：验证上游源码 (5 分钟)

```bash
# 检查 A7Z 配置是否存在
git clone --depth 1 --branch device-a733-v1.4.8 \
  https://github.com/radxa/allwinner-device.git temp-device
  
ls temp-device/configs/cubie_a7z/  # 如果存在，直接使用
ls temp-device/configs/cubie_a7a/linux-6.6/  # 验证 A7A 6.6 支持

# 检查结果：
# ✅ 如果 cubie_a7z/ 存在 → 跳到第 2 步
# ❌ 如果不存在 → 需要从 A7A 移植 (见下文)
```

### 第 2 步：验证 UFS 配置已就绪 (2 分钟)

```bash
# 当前 defconfig 已包含 UFS 支持
grep "CONFIG_AW_UFS=y" configs/cubie_a7a_defconfig
grep "CONFIG_SCSI_UFSHCD=y" configs/cubie_a7a_defconfig

# ✅ 两者都返回匹配 → UFS 内核驱动已启用
```

### 第 3 步：创建 A7Z 构建配置 (10 分钟)

```bash
# 创建 A7Z 配置目录
mkdir -p configs/a7z/

# 如果上游有 A7Z DTS
cp temp-device/configs/cubie_a7z/linux-6.6/board.dts configs/a7z/board.dts

# 如果需要从 A7A 移植
cp configs/board-overclocked.dts configs/a7z/board-a7z.dts
# 手动编辑：
# 1. 修改 board = "A733", "A733-CUBIE-A7Z-...";
# 2. 验证 &ufs { status = "okay"; } 已存在
# 3. 检查 &sdc0/&sdc2 状态（可能需要禁用）

# 复制 defconfig（或创建专用版本）
cp configs/cubie_a7a_defconfig configs/a7z/cubie_a7z_defconfig
```

### 第 4 步：创建 GitHub Actions Workflow (10 分钟)

```bash
# 创建 workflow 目录
mkdir -p .github/workflows/

# 下载参考模板（或手动创建）
cat > .github/workflows/build-kernel.yml << 'EOF'
name: Build Kernel

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      board:
        description: 'Board type'
        required: true
        default: 'a7z'
        type: choice
        options: [a7a, a7z, both]

jobs:
  build:
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        board: [a7z]  # 先只测试 A7Z
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Install toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
            bc device-tree-compiler flex bison libssl-dev libelf-dev
      
      - name: Clone sources
        run: |
          git clone --branch allwinner-aiot-linux-6.6 --depth 1 \
            https://github.com/radxa/kernel.git kernel-6.6
          git clone --branch cubie-aiot-v1.4.8 --depth 1 \
            https://github.com/radxa/allwinner-bsp.git allwinner-bsp-1.4.8
          git clone --branch device-a733-v1.4.8 --depth 1 \
            https://github.com/radxa/allwinner-device.git allwinner-device-1.4.8
      
      - name: Build
        run: |
          ./scripts/setup-kernel.sh
          cd kernel-6.6
          make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ \
            cubie_a7a_defconfig  # 暂时使用 A7A defconfig
          make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- BSP_TOP=bsp/ \
            -j$(nproc) Image dtbs
      
      - name: Upload
        uses: actions/upload-artifact@v4
        with:
          name: kernel-${{ matrix.board }}
          path: |
            kernel-6.6/arch/arm64/boot/Image
            kernel-6.6/arch/arm64/boot/dts/allwinner/*.dtb
EOF

# 提交并触发构建
git add .github/workflows/build-kernel.yml
git commit -m "Add GitHub Actions build for A7Z"
git push
```

### 第 5 步：验证构建 (3 分钟等待)

```bash
# 在 GitHub 网页上：
# 1. 进入 Actions 标签页
# 2. 观察 "Build Kernel" workflow 运行
# 3. 等待构建完成（约 20-40 分钟）

# 如果失败，检查日志中的错误：
# - 缺少 A7Z DTS → 需要创建/移植
# - 编译错误 → 检查 BSP 版本兼容性
```

---

## 📋 完整迁移检查清单

### Phase 1: 准备工作 ✅

- [ ] Fork 本仓库到你的 GitHub 账号
- [ ] 克隆到本地: `git clone https://github.com/YOUR_USERNAME/radxa-cubie-a7z-kernel.git`
- [ ] 验证本地交叉编译工具链安装
- [ ] 阅读 `MIGRATION_TODO_A7Z.md` 和 `docs/A7A_VS_A7Z_HARDWARE_DIFF.md`

### Phase 2: 源码调研 🔍

- [ ] 检查 Radxa 上游是否有 A7Z 配置
  ```bash
  git ls-remote --heads https://github.com/radxa/allwinner-device.git | grep a7z
  ```
- [ ] 下载并检查 A7Z DTS 文件
- [ ] 验证 UFS 驱动在当前 defconfig 中已启用
- [ ] 确认 U-Boot 版本支持 UFS（检查 radxa/u-boot 仓库）

### Phase 3: 配置文件创建 📝

- [ ] 创建 `configs/a7z/` 目录结构
- [ ] 获取或移植 A7Z board.dts
  - [ ] 验证 `&ufs { status = "okay"; }`
  - [ ] 检查电源供应配置 (vcc-supply)
  - [ ] 评估 SD/eMMC 节点状态
- [ ] 创建 A7Z defconfig（或确认与 A7A 共用）
- [ ] 创建 A7Z extlinux.conf 模板
  ```bash
  cp scripts/fix-a7z-ufs-boot.sh scripts/create-a7z-image.sh
  # 修改为完整镜像生成脚本
  ```

### Phase 4: 构建脚本适配 🛠️

- [ ] 修改 `scripts/setup-kernel.sh` 支持 `--board a7z` 参数
- [ ] 修改 `scripts/build.sh` 自动选择 A7Z 配置
- [ ] 更新 `scripts/deploy.sh` 处理 UFS 设备路径
- [ ] 创建 `scripts/build-a7z.sh` 快捷脚本
- [ ] 测试本地构建 A7Z 内核（如果无硬件，只测试编译）

### Phase 5: GitHub Actions 配置 ⚙️

- [ ] 创建 `.github/workflows/build-kernel.yml`
  - [ ] 配置构建矩阵 (a7a, a7z)
  - [ ] 添加源码缓存加速
  - [ ] 配置构建产物上传
- [ ] 创建 `.github/workflows/release.yml`（标签触发）
- [ ] 配置仓库 Actions 权限
  - Settings → Actions → General → Workflow permissions: Read and write
- [ ] 测试 push 触发构建
- [ ] 测试手动触发 workflow

### Phase 6: 文档更新 📚

- [ ] 更新 `README.md`
  - [ ] 添加 A7Z 硬件规格表
  - [ ] 说明 A7A vs A7Z 差异
  - [ ] 添加 CI 状态徽章
  - [ ] 更新构建指南
- [ ] 创建 `docs/BUILD_A7Z.md`（详细构建说明）
- [ ] 创建 `docs/UPGRADE_A7A_TO_A7Z.md`（迁移指南）
- [ ] 更新 `scripts/fix-a7z-ufs-boot.sh` 注释

### Phase 7: 测试验证 🧪

#### 无硬件验证（静态检查）
- [ ] 验证 DTB 编译无错误
- [ ] 检查 defconfig 完整性
- [ ] 确认 GitHub Actions 构建通过
- [ ] 下载并检查构建产物（Image + DTB 大小合理）

#### 有硬件验证（完整测试）
- [ ] **启动测试**
  - [ ] U-Boot 识别 UFS 设备
  - [ ] 内核加载无 UFS 错误
  - [ ] 根文件系统成功挂载
  - [ ] 系统正常启动到登录界面
  
- [ ] **存储性能测试**
  ```bash
  sudo hdparm -Tt /dev/sda
  # 预期: 顺序读 >500 MB/s
  
  sudo fio --name=randread --ioengine=libaio --iodepth=16 \
    --rw=randread --bs=4k --direct=1 --size=1G \
    --numjobs=4 --runtime=60 --group_reporting \
    --filename=/dev/sda
  # 预期: 4K 随机读 >40 MB/s
  ```

- [ ] **硬件功能验证**
  - [ ] CPU 频率调节: `watch -n1 "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"`
  - [ ] GPU 可用性: `ls -l /dev/dri/renderD128`
  - [ ] NPU 测试: `~/ai-sdk/examples/vpm_run/vpm_run -s sample_v3.txt -l 10`
  - [ ] WiFi 连接: `nmcli dev wifi connect SSID password PASSWORD`
  - [ ] 以太网 1Gbps: `ethtool eth0 | grep Speed`
  - [ ] HDMI 输出: `modetest -M sunxi-drm`
  
- [ ] **稳定性测试**
  - [ ] 压力测试 30 分钟: `stress-ng --cpu 8 --vm 4 --timeout 1800s`
  - [ ] 温度监控: `watch -n2 "cat /sys/class/thermal/thermal_zone*/temp"`
  - [ ] 重启测试 3 次验证启动稳定性

### Phase 8: 发布管理 🚀

- [ ] 创建 Git 标签
  ```bash
  git tag -a v1.0.0-a7z -m "Initial A7Z support release"
  git push origin v1.0.0-a7z
  ```
- [ ] 验证 GitHub Release 自动创建
- [ ] 检查附件包含 tar.gz 和 SHA256
- [ ] 编写 Release Notes（变更日志）

### Phase 9: 社区贡献（可选）🌍

- [ ] 向 Radxa 报告 A7Z 支持状态
- [ ] 提交超频配置改进 PR
- [ ] 报告 BSP 已知问题（WiFi v1.4.8 bug 等）
- [ ] 更新 Radxa 官方文档/Wiki

---

## 🚨 常见问题预警

### 问题 1: GitHub Actions 构建失败 "404: Repository not found"

**原因**: 子模块或外部依赖访问权限问题

**解决**:
```yaml
# 在 workflow 中添加 token
- uses: actions/checkout@v4
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
```

### 问题 2: 构建超时（超过 6 小时）

**原因**: Free plan 限制

**解决**:
- 使用 ccache 缓存编译对象
- 减少并行任务数
- 拆分为多个 jobs（内核 + 模块 + GPU）

### 问题 3: A7Z DTS 编译错误 "undefined reference"

**原因**: 缺少 BSP dt-bindings 头文件

**解决**:
```bash
# 在 setup-kernel.sh 中确保复制所有 dt-bindings
cp -r allwinner-bsp/include/dt-bindings/* \
  kernel-6.6/include/dt-bindings/
```

### 问题 4: A7Z 启动失败，卡在 U-Boot

**原因**: U-Boot 无法识别 UFS 或找不到 extlinux.conf

**排查**:
```bash
# U-Boot 控制台调试
=> ufsinit 0           # 初始化 UFS 设备
=> ls sunxi_flash_ufs 0:2  # 列出分区 2 文件
=> ls sunxi_flash_ufs 0:2 /boot/extlinux/  # 确认 extlinux.conf 存在

# 如果找不到，检查分区类型
=> gpt read mmc 0  # 错误，应该用 ufs
=> part list ufs 0  # 正确命令
```

### 问题 5: 内核启动后 panic "VFS: Unable to mount root"

**原因**: UFS 驱动未加载或设备路径错误

**排查**:
```bash
# 检查内核日志
dmesg | grep -i ufs
dmesg | grep -i "Waiting for root device"

# 验证 UFS 驱动加载
lsmod | grep ufs
ls /dev/sda*  # 应该看到 sda1, sda2, sda3

# 如果 /dev/sda 不存在，检查 defconfig:
grep CONFIG_SCSI_UFSHCD .config
grep CONFIG_AW_UFS .config
```

---

## 📊 进度追踪

使用此表格追踪迁移进度：

| 阶段 | 任务数 | 已完成 | 进度 | 预估时间 | 实际时间 |
|------|--------|--------|------|----------|----------|
| Phase 1: 准备 | 4 | ☐ | 0% | 0.5h | - |
| Phase 2: 调研 | 4 | ☐ | 0% | 2h | - |
| Phase 3: 配置 | 5 | ☐ | 0% | 2h | - |
| Phase 4: 脚本 | 5 | ☐ | 0% | 2h | - |
| Phase 5: CI | 5 | ☐ | 0% | 2h | - |
| Phase 6: 文档 | 4 | ☐ | 0% | 1h | - |
| Phase 7: 测试 | 15 | ☐ | 0% | 4h | - |
| Phase 8: 发布 | 4 | ☐ | 0% | 1h | - |
| **总计** | **46** | **0** | **0%** | **14.5h** | **-** |

---

## 🎓 下一步行动

**如果你有 A7Z 硬件**:
1. 按照 "快速开始" 完成前 3 步
2. 本地构建并测试启动
3. 配置 GitHub Actions
4. 完整测试所有硬件功能

**如果你没有 A7Z 硬件**:
1. 先完成 GitHub Actions 配置（验证编译）
2. 等待有硬件的贡献者测试反馈
3. 专注于文档和构建脚本完善

**推荐优先级**:
- P0（必须）: Phase 1-5 (CI 构建验证)
- P1（重要）: Phase 6 (文档)
- P2（可选）: Phase 7 (硬件测试)
- P3（增强）: Phase 8-9 (发布与社区)

---

最后更新: 2026-06-08
