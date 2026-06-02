# P4 → P5 工作计划审阅摘要

## 📋 计划概览

已完成 **P4 受限双发射**，现规划向 **P5a（lane1 分支支持）** 过渡。

| 方面 | 内容 |
|------|------|
| **当前阶段** | P4 fix (commit 268531a) |
| **下一阶段** | P5a: lane1 支持 branch/jump，不支持访存 |
| **计划文档** | `NEXT_STEPS_P5_PLAN.md`（详细版） |
| **RTL 规模** | 当前 ~3.7k 行；P5a 预计增加 620-860 行 |

---

## 🎯 P5a 工作目标

让 lane1 能执行分支指令并产生正确的 redirect，扩展 lane1 的 ISA 覆盖从纯 ALU 到 ALU + branch。

### 性能预期
- lane0 ALU + lane1 branch: IPC > 1.0（branch-less 部分）
- branch 预测准确率不下降
- 保持 in-order 语义和精确异常

---

## 📝 前置条件（5 项）

在启动 P5a 前，必须确认：

1. **P4 功能稳定**
   - [ ] `test/run_xsim.bat base` 100% 通过
   - [ ] 性能计数器齐全（fetch/decode/issue/retire pair count 等）
   - [ ] P4 定向测试全通过（ALU双发射、RAW/WAW/branch禁止规则）

2. **代码质量**
   - [ ] `exe_lane_simple.sv` 结构清晰，便于扩展
   - [ ] P4 stage summary 文档完成

3. **工具与流程**
   - [ ] Vivado 仿真流程支持宏开闭
   - [ ] VCD 导出与波形查看脚本可用

---

## 🔧 P5a 核心改动（5 个模块）

| 模块 | 改动概述 | 代码量 | 难度 |
|------|---------|--------|------|
| `exe_lane_simple.sv` | 新增 branch compare 和 target 计算 | +60-80 | 中 |
| `issue_select.sv` | 放宽 lane1 可配对条件（允许分支） | +30-40 | 低 |
| `branch_redirect_arbiter.sv` (**新增**) | 处理 lane0/lane1 redirect 仲裁，lane1_squash 生成 | +80-120 | **高** |
| `id_stage.sv` 等流水线 | 打拍 lane1 branch 信号，flush 处理 | +100-150 | 中 |
| `regfile_csr.sv` | BP 更新接口扩展支持 lane1 | +50-80 | 中 |

**总计**: +620-860 行，约 31-35 小时工作量

---

## ✅ 验收标准（6 项）

P5a 完成后必须通过：

| # | 检查项 | 验证方式 |
|---|--------|---------|
| 1 | DUAL_ISSUE_ENABLE=0 时行为不变 | 基线回归 100% |
| 2 | lane1 分支执行正确 | 定向测试：ALU+branch 双发射 |
| 3 | redirect 仲裁正确 | 定向测试：lane0 taken 时 lane1 squash |
| 4 | branch 预测正确 | 分支预测准确率不下降 >5% |
| 5 | 性能计数准确 | perf_issue_branch_lane1, perf_lane1_branch_mispred 等 |
| 6 | 波形无异常 | VCD 中 redirect/squash 信号时序正确 |

---

## ⚠️ 风险与回退

| 风险 | 表现 | 回退方案 | 恢复时间 |
|------|------|---------|---------|
| **redirect 竞争** | 同 cycle 两个 redirect 导致 PC 混乱 | 禁用 lane1 branch，仅 lane0 | 2-4h |
| **时序违规** | branch target glitch | 添加 1 cycle 延迟给 lane1 | 1-2h |
| **BP 冲突** | 预测准确率下降 >5% | 仅 lane0 更新 BP | 1h |

---

## 📅 工作分割与 Checkpoint

### Checkpoint A (Day 1-2)
✅ `exe_lane_simple` branch compare 完成
✅ `issue_select` 放宽条件
✅ 基础定向测试通过（无 redirect）
👉 **commit**: `P5a-part1: lane1 branch execution without redirect`

### Checkpoint B (Day 3-4)
✅ `branch_redirect_arbiter` 完整实现
✅ redirect 仲裁测试通过
👉 **commit**: `P5a-part2: branch redirect arbiter`

### Checkpoint C (Day 5, P5a 完成)
✅ 全部流水线集成
✅ base 回归 100% 通过
✅ 波形无异常
👉 **commit**: `P5a: Full in-order dual-issue with lane1 branch support`

---

## 📊 后续阶段预览

| 阶段 | 工作内容 | 难度 | 时间 |
|------|---------|------|------|
| P5b | lane1 load/store，单 LSU 限制 | 🔴 很高 | 5-7d |
| P5c | lane1 CSR/system 子集 | 🟠 高 | 3-4d |
| P5d | lane1 mul/div，多周期仲裁 | 🟡 中等 | 2-3d |
| P6 | 顺序双发射性能优化 | 🟠 高 | 4-6d |
| P7 | 乱序前置（ROB/rename） | 🔴 很高 | 6-8d |
| P8 | 真正乱序执行 | 🔴 极高 | 8-12d |

---

## 📚 相关文档

- 📖 **详细计划**: `NEXT_STEPS_P5_PLAN.md`（本次生成）
- 📖 **阶段计划**: `superscalar_plan/phase_plan.md` P5 小节
- 📖 **验证计划**: `superscalar_plan/verification_plan.md`
- 📖 **架构分析**: `ARCHITECTURE_ANALYSIS.md`

---

## 🚀 建议下一步

1. **审阅** `NEXT_STEPS_P5_PLAN.md` 中的详细检查清单
2. **确认** 是否准备启动 P5a（或先完成其他优先级工作）
3. **创建** `git branch feature/P5a` 或 `feature/P5a-draft`
4. **运行** P4 完整回归确保基线稳定
5. **开始** Checkpoint A 工作（需 ~8 小时）

---

## 💬 待审阅项目

请确认以下几点：

- [ ] P5a 的工作范围是否合理？
- [ ] 5 个核心模块的改动点是否遗漏或过度设计？
- [ ] 620-860 行代码和 31-35h 时间估算是否现实？
- [ ] 验收标准的 6 项检查是否足够？
- [ ] 是否需要调整 checkpoint 分割或进度？
- [ ] 是否建议并行进行其他优化工作？

