# 文档索引

本目录包含 Radxa Cubie A7A/A7Z 内核项目的详细文档。

---

## 📚 文档列表

### 核心文档

- **[A7A vs A7Z 硬件差异对照表](A7A_VS_A7Z_HARDWARE_DIFF.md)**
  - A7A 和 A7Z 的详细硬件对比
  - 存储子系统差异（SD/eMMC vs UFS）
  - 设备树、内核配置、启动流程差异
  - 分区布局和 fstab 配置对比
  - **适用人群**: 需要理解两板差异的开发者

### 迁移指南

- **[A7Z 迁移完整 TODO 清单](../MIGRATION_TODO_A7Z.md)**
  - 从 A7A 迁移到 A7Z 的分阶段任务列表
  - 10 个阶段共 100+ 具体任务
  - 包含上游源码配置、GitHub Actions CI/CD、测试验证
  - 预估工作量：10-16 小时（不含硬件测试）
  - **适用人群**: 执行迁移的开发者

- **[A7Z 迁移快速检查清单](../A7Z_MIGRATION_CHECKLIST.md)**
  - 30 分钟快速验证路径
  - 8 个 Phase 共 46 个检查项
  - 常见问题预警与解决方案
  - 进度追踪表格
  - **适用人群**: 项目管理者和执行者

---

## 🎯 文档使用流程

### 场景 1: 我想了解 A7A 和 A7Z 的差异

1. 阅读 **[A7A vs A7Z 硬件差异对照表](A7A_VS_A7Z_HARDWARE_DIFF.md)**
2. 重点关注：
   - 存储接口差异（SD/eMMC vs UFS）
   - 启动流程差异（U-Boot 扫描路径）
   - 分区布局差异（2 分区 vs 3 分区）

### 场景 2: 我要执行 A7A → A7Z 迁移

**第一步：规划**
1. 阅读 **[A7Z 迁移完整 TODO](../MIGRATION_TODO_A7Z.md)** 了解全貌
2. 使用 **[快速检查清单](../A7Z_MIGRATION_CHECKLIST.md)** 进行进度管理

**第二步：执行**（推荐顺序）
1. **快速验证**（30 分钟）:
   - 检查上游源码是否有 A7Z 配置
   - 验证 UFS 内核配置
   - 创建 GitHub Actions workflow
   
2. **核心迁移**（6-8 小时）:
   - 创建/移植 A7Z 设备树
   - 适配构建脚本
   - 配置 CI/CD
   - 更新文档

3. **测试验证**（4-6 小时，需硬件）:
   - 启动测试
   - 存储性能测试
   - 硬件功能验证

**第三步：发布**（1-2 小时）
1. 创建 Git 标签
2. 验证 GitHub Release
3. 编写 Release Notes

### 场景 3: 我只想配置 GitHub Actions 自动构建

1. 跳转到 **[快速检查清单](../A7Z_MIGRATION_CHECKLIST.md)** 的 "快速开始 → 第 4 步"
2. 复制 workflow 模板到 `.github/workflows/build-kernel.yml`
3. 推送代码触发构建
4. 预计 20-40 分钟完成首次构建

---

## 📖 文档约定

### 复选框标记
- `[ ]` - 待完成
- `[x]` - 已完成
- `⚠️` - 需要特别注意
- `🔵` - 可选/增强功能

### 优先级标记
- **P0（必须）**: 阻塞性任务，不完成无法继续
- **P1（重要）**: 推荐完成，影响用户体验
- **P2（可选）**: 增强功能，时间允许时完成

### 代码块类型
- `bash` - 在终端执行的命令
- `yaml` - GitHub Actions workflow 配置
- `dts` - 设备树源码
- `conf` - 配置文件

---

## 🔍 关键概念速查

| 概念 | A7A | A7Z | 说明 |
|------|-----|-----|------|
| **存储接口** | SD/eMMC | UFS | A7Z 使用高速 UFS 存储 |
| **设备路径** | `/dev/mmcblk0` | `/dev/sda` | 影响 fstab 和内核 cmdline |
| **U-Boot 扫描** | `mmc 0:3` | `sunxi_flash_ufs 0:2` | 影响 extlinux.conf 位置 |
| **分区数量** | 2-3 个 | 3 个 | A7Z 必须有 config + EFI + rootfs |
| **分区类型** | p3=EF00 | p2=EF00 | U-Boot 只扫描 EFI 类型分区 |
| **内核配置** | `CONFIG_MMC_SUNXI=y` | `CONFIG_AW_UFS=y` | A7A defconfig 已同时启用 |
| **超频配置** | 通用 | 通用 | CPU/GPU OPP 表可共用 |

---

## 🛠️ 相关脚本

项目根目录的关键脚本：

| 脚本 | 用途 | 支持板型 |
|------|------|----------|
| `scripts/setup-kernel.sh` | 设置内核树（BSP 链接、DTS 复制） | A7A（需修改支持 A7Z） |
| `scripts/build.sh` | 完整构建流程（config + 编译） | A7A（需修改支持 A7Z） |
| `scripts/deploy.sh` | 部署到板上（SSH） | A7A（需修改支持 A7Z） |
| `scripts/fix-a7z-ufs-boot.sh` | **A7Z UFS 启动修复** | **A7Z 专用** |
| `scripts/flash-image.sh` | SD 卡刷写镜像 | A7A（A7Z 不支持） |
| `scripts/easy-flash.sh` | 一键下载+刷写 | A7A（A7Z 不支持） |

---

## 📊 迁移进度追踪

建议使用 GitHub Projects 或 Issues 追踪迁移任务：

1. **创建 Milestone**: "A7Z Support v1.0"
2. **创建 Issues**: 从检查清单中提取关键任务
3. **使用 Labels**:
   - `priority:p0` - 阻塞性任务
   - `priority:p1` - 重要任务
   - `priority:p2` - 可选任务
   - `status:blocked` - 等待依赖
   - `needs-hardware` - 需要物理设备测试

---

## 🤝 贡献指南

### 报告问题

如果你在迁移过程中遇到问题：

1. 检查 **[快速检查清单](../A7Z_MIGRATION_CHECKLIST.md)** 中的"常见问题预警"
2. 搜索 GitHub Issues 是否有类似问题
3. 如果是新问题，创建 Issue 并包含：
   - 板型（A7A/A7Z）
   - 内核版本
   - 错误日志
   - 已尝试的解决方案

### 完善文档

欢迎提交 PR 改进文档：

- 修正错误信息
- 补充测试结果
- 添加硬件兼容性信息
- 翻译为其他语言

---

## 📞 获取帮助

- **Radxa 官方论坛**: https://forum.radxa.com/
- **GitHub Issues**: https://github.com/YOUR_USERNAME/radxa-cubie-a7z-kernel/issues
- **Radxa Discord**: https://rock.sh/go

---

## 📝 更新日志

- **2026-06-08**: 创建 A7Z 迁移文档套件
  - 硬件差异对照表
  - 完整 TODO 清单
  - 快速检查清单
  - 文档索引

---

最后更新: 2026-06-08
