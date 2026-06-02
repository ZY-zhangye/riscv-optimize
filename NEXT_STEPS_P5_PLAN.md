# P4 → P5 过渡计划

**当前状态**: P4 受限双发射已完成，最新 commit 为 `268531a P4 fix: Latch ds_flush in ID stage to extend flush window`

**目标**: 规划向 P5（完整顺序双发射）过渡的工作

---

## 1. P5 工作前置条件检查清单

在启动 P5 之前，必须确认以下项目：

### 1.1 P4 功能稳定性
- [ ] `test/run_xsim.bat base` 100% 通过（所有基线测试无失败）
- [ ] `DUAL_ISSUE_ENABLE` 关闭时，提交 PC 序列与 P0 基线完全一致
- [ ] `DUAL_ISSUE_ENABLE` 开启时，ALU-only 双发射在至少 3 个独立测试中证明 IPC > 1.0

### 1.2 性能计数器齐全度
- [ ] 确认以下计数器已实现且能正确计数：
  - `perf_fetch_pair`: 每周期 fetch 两条有效的次数
  - `perf_decode_pair`: 每周期 decode 两条有效的次数
  - `perf_issue_pair`: 每周期同时发射两条的次数
  - `perf_retire_pair`: 每周期同时提交两条的次数
  - `perf_lane1_block_*`: 各类型的 lane1 阻止原因计数
  - `perf_stall_cycles`: 流水线停顿周期计数

### 1.3 P4 定向测试覆盖
- [ ] 验收 P4 定向测试全部通过：
  - 独立 ALU 双发射
  - intra-pair RAW 禁止
  - WAW 禁止或正确提交
  - branch 后禁发 slot1
  - load-use 禁止双发射

### 1.4 代码质量与文档
- [ ] `exe_lane_simple.sv` 代码注释清晰，易于扩展
- [ ] P4 stage summary 已记录在案（IPC、失败案例、禁用规则列表）
- [ ] RTL 中 branch 相关信号在 lane0/lane1 层面已清晰标记

### 1.5 CI/工具链
- [ ] Vivado 仿真流程能正确处理 `DUAL_ISSUE_ENABLE` 宏的开闭
- [ ] 性能计数器和波形导出脚本已可用

---

## 2. P5a 子阶段详细实施计划

**P5a 目标**: lane1 支持 branch/jump，但仍不支持访存。此时 lane1 能产生真正的 branch redirect，增加 architectural state 修改范围。

### 2.1 主要改动模块

#### 2.1.1 `exe_lane_simple.sv` 扩展
**当前状态**: 仅有 ALU 执行，不产生 redirect。
**改动点**:
- 新增 `comp_unit` 模块或直接实例化分支比较逻辑
  - 输入: `rs1_val`, `rs2_val`, `op_type` (beq/bne/blt/bge/bltu/bgeu)
  - 输出: `taken`, `target`（预计+2-3 个组合逻辑层）
- 分支 target 计算与 lane0 共用（或独立实现，预计 +1 逻辑层）
- 新增输出信号:
  - `exe_lane1_branch_valid`
  - `exe_lane1_branch_taken`
  - `exe_lane1_branch_target`
  - `exe_lane1_branch_mispred_flag`

**预期代码变化**: +60-80 行

#### 2.1.2 `id_stage.sv` issue_select 逻辑
**当前状态**: lane1 被禁止发射（或只在 shadow 模式）。
**改动点**:
- 扩展 `issue_select.sv` 的 lane1 可配对判断
  - 添加 `is_branch_or_jump(inst)` 函数识别分支指令
  - 新增检查: branch 指令被允许进入 lane1
  - 若 slot0 是 branch/jump，lane1 仍禁止（维持 P4 规则）

**预期代码变化**: +30-40 行

#### 2.1.3 `cpu_top.sv` 或独立的 `branch_redirect_arbiter.sv`
**当前状态**: 仅 lane0 能产生 redirect。
**改动点**:
- 新增 branch redirect 仲裁逻辑
  - lane0 redirect 优先于 lane1
  - 若 lane0 是 taken branch，lane1 必须被 squash
  - 生成最终的 `redirect_valid`, `redirect_target` 信号
  - 生成 `lane1_squash` 信号（用于杀死 lane1 在 mem/wb 中的结果）
- 扩展 PC mux 逻辑
  - `next_pc` 选择: lane0_redirect > lane1_redirect > seq_pc

**预期代码变化**: +80-120 行

#### 2.1.4 `id_stage.sv` 或 `instr_queue.sv` 的 flush 处理
**当前状态**: 仅处理 lane0 redirect flush。
**改动点**:
- 确保 lane1 redirect 也能正确清空 instruction queue
- 若 lane1 产生 redirect，lane0 在同 cycle 的指令应被 squash（如果还未提交）
- 检查 branch target alignment（特别是 lane1 跳转到未对齐地址）

**预期代码变化**: +20-30 行（主要是 flush 条件扩展）

#### 2.1.5 `regfile_csr.sv` 的 branch predictor 更新
**当前状态**: 只有 lane0 更新分支预测。
**改动点**:
- 扩展分支预测 update 接口支持两条分支同时更新（或每周期只更新 older one）
  - 推荐：每周期只更新 older one，降低复杂度
  - 或: 支持两个独立的 BP update port
- 新增 `bp_update_from_lane0/1_valid`, `bp_update_from_lane0/1_*` 信号

**预期代码变化**: +40-60 行

#### 2.1.6 `mem_stage.sv` / 独立 `lane1_commit_queue.sv`
**当前状态**: lane1 结果还未真正流入 MEM 阶段。
**改动点**:
- lane1 branch 不访问内存，但需进入流水
  - 可选: lane1 结果在 exe lane1 直接打拍到 wb
  - 或: 进入 mem_stage 的 lane1 path，但不访存（pass-through）
- 若选择 pass-through，需确保 lane1 可以跳过 dmem 端口仲裁

**预期代码变化**: +30-50 行

### 2.2 细致实施顺序

**第 1 天：需求分析与代码审查**
1. 详细阅读现有 lane0 的 branch compare 和 target 计算逻辑
2. 审查 P4 中 lane1 与 lane0 在 exe/mem/wb 中的打拍和 bypass 机制
3. 确认 branch redirect 信号如何在 `cpu_top.sv` 顶层使用

**第 2-3 天：核心改动**
1. 在 `exe_lane_simple.sv` 中添加 branch compare 模块
2. 在 `issue_select.sv` 中放宽 lane1 可配对条件（允许 branch）
3. 实现 `branch_redirect_arbiter` 逻辑

**第 4 天：流水线集成**
1. 在 `id_stage.sv` 中打拍 lane1 branch valid/target 信号
2. 在 `mem_stage.sv` 中 pass-through lane1 结果
3. 在 `cpu_top.sv` 中连接 redirect 仲裁的最终输出

**第 5 天：性能计数与调试**
1. 新增 lane1 branch 相关的性能计数器
2. 添加波形检查点信号
3. 修改 `run_xsim.bat` 生成 VCD，检查 branch redirect timing

---

## 3. 验收关键点

P5a 完成后必须通过以下验收检查：

### 3.1 功能正确性
- [ ] `DUAL_ISSUE_ENABLE` 关闭时，全部 base 回归通过且 PC 序列不变
- [ ] `DUAL_ISSUE_ENABLE` 开启时，branch-less 程序（纯 ALU）行为与 P4 一致
- [ ] 新增 lane1 branch 定向测试通过：
  ```asm
  # Test: lane0 ALU + lane1 branch (non-taken)
  addi x5, x0, 1
  beq  x0, x0, forward    # lane1: non-taken branch
  addi x6, x0, 0
  forward:
  addi x7, x5, 1
  ```
  预期结果: x5=1, x6=0, x7=2

### 3.2 Redirect 仲裁正确性
- [ ] lane0 branch taken，lane1 (无论是否有效) 被 squash
  ```asm
  beq x0, x0, skip        # lane0: branch taken
  add x5, x0, x0          # lane1: should be squashed
  skip:
  addi x6, x0, 1
  ```
  预期: x5=0(未写), x6=1
  
- [ ] lane0 ALU，lane1 branch taken，正确 redirect
  ```asm
  addi x5, x0, 1
  bne x0, x0, forward     # lane1: branch taken
  addi x6, x0, 0
  forward:
  addi x7, x0, 2
  ```
  预期: PC jump to forward, x5=1, x6=0, x7=2

### 3.3 分支预测更新
- [ ] 单独 lane1 branch 的预测统计正确
- [ ] 若同 cycle lane0 和 lane1 都是 branch，只更新 older one（lane0）

### 3.4 性能计数器
- [ ] `perf_issue_branch_lane1`: lane1 发射分支指令的次数
- [ ] `perf_lane1_branch_mispred`: lane1 分支错误预测次数
- [ ] 验证 lane0 + lane1_branch 能同时发射的 IPC > 1.0

### 3.5 波形检查点
- [ ] 在 VCD 中确认以下信号在正确 cycle 翻转：
  - `exe_lane1_branch_valid`
  - `exe_lane1_branch_target`
  - `lane1_squash`
  - `redirect_valid`

### 3.6 回归无退化
- [ ] branch-heavy 回归（RISC-V tests MI subset）通过
- [ ] 整体 IPC 与 P4 相比不下降

---

## 4. 风险评估与回退策略

### 4.1 风险 1：lane1 branch redirect 与 lane0 的竞争条件
**表现**: 同 cycle 两个 redirect 导致 PC 错误或流水线混乱。
**回退**:
- 立即回到 P4：禁用 lane1 branch 发射（仅 lane0）
- 降级方案：每 cycle 最多允许 lane0 produce redirect，lane1 redirect 延后处理
- 恢复时间: ~2-4 小时

### 4.2 风险 2：branch target calculation 时序违规
**表现**: VCD 中看到 target 信号在流水线中 glitch 或不稳定。
**回退**:
- 添加 1 cycle 额外延迟给 lane1 branch target（不影响 lane0）
- 降级: 强制所有分支单发射，保持 ALU 双发射
- 恢复时间: ~1-2 小时

### 4.3 风险 3：BP update 逻辑冲突
**表现**: 分支预测准确率下降超过 5%。
**回退**:
- 仅允许 lane0 更新 BP，lane1 branch 预测结果不反馈
- 恢复时间: ~1 小时

---

## 5. 工作时间与复杂度分解

### 5.1 各子任务复杂度与时间估算

| 任务 | 复杂度 | 代码行数 | 预计时间 | 风险 |
|------|--------|---------|---------|------|
| 需求分析+代码审查 | 中 | 0 | 4h | 低 |
| `exe_lane_simple` 扩展 branch compare | 中 | +60-80 | 3h | 中 |
| `issue_select` 放宽 lane1 条件 | 低 | +30-40 | 2h | 低 |
| `branch_redirect_arbiter` 实现 | 高 | +80-120 | 5h | 高 |
| 流水线集成（id/mem/wb） | 中 | +100-150 | 4h | 中 |
| 性能计数+BP 更新逻辑 | 中 | +50-80 | 3h | 中 |
| 定向测试编写与验证 | 中 | +200-300 (汇编+hex) | 6h | 中 |
| 波形分析与调试 | 中 | 0 | 4-8h | 中 |
| **总计** | | **+620-860** | **31-35h** | |

### 5.2 建议工作分割点

**Checkpoint A** (完成后可 commit）
- ✅ `exe_lane_simple` branch compare 完成
- ✅ `issue_select` lane1 branch 可配对
- ✅ 基础定向测试通过（仅 lane1 branch，无 redirect）
- **提交**: `P5a-part1: lane1 branch execution without redirect`
- **时间**: Day 1-2 结束

**Checkpoint B** (完成后可 commit)
- ✅ `branch_redirect_arbiter` 完整实现
- ✅ redirect 仲裁测试通过
- ✅ 复杂 redirect 场景覆盖 80%
- **提交**: `P5a-part2: branch redirect arbiter`
- **时间**: Day 3-4 结束

**Checkpoint C** (P5a 完全完成)
- ✅ 所有流水线集成完成
- ✅ base 回归 100% 通过
- ✅ 性能计数器齐全且正确
- ✅ 波形分析确认无异常
- **提交**: `P5a: Full in-order dual-issue with lane1 branch support`
- **时间**: Day 5 结束

---

## 6. 后续阶段预览

### P5b：lane1 支持 load/store（单 LSU 限制）
- 预计难度：**很高**（涉及内存顺序和 store commit 逻辑）
- 前置条件：P5a 100% 稳定
- 估计时间：5-7 天

### P5c：lane1 支持 CSR/system 的安全子集
- 预计难度：**高**（涉及精确异常和中断）
- 估计时间：3-4 天

### P5d：lane1 支持 mul/div，多周期仲裁
- 预计难度：**中等**
- 估计时间：2-3 天

---

## 7. 参考检查清单

启动 P5a 前，请确认：

```checklist
前置条件:
- [ ] P4 base 回归 100% 通过
- [ ] 性能计数器已齐全并正确
- [ ] 最新代码已 commit（不在 WIP 状态）
- [ ] 新建 `git branch feature/P5a` 或在主分支工作

需求理解:
- [ ] 已详细阅读 phase_plan.md P5a 小节
- [ ] 已理解 branch redirect 优先级和 squash 规则
- [ ] 已标注 lane0/lane1 在所有现有模块中的信号差异

代码准备:
- [ ] 备份或分支当前代码
- [ ] 确认 Vivado sim flow 可用
- [ ] 编写 1-2 个基础 ALU+branch 测试 hex 文件

文档准备:
- [ ] 创建 P5a 总结模板文档
- [ ] 准备性能对比表格（P4 vs P5a）
```

---

## 8. 相关文件与文档链接

- 详细实施: `superscalar_plan/phase_plan.md` P5 小节
- 验证计划: `superscalar_plan/verification_plan.md` P5 部分
- AI 执行提示: `superscalar_plan/handoff_prompts.md`（如适用）
- 当前 RTL 根目录: `rtl/cpu_top/`
- 测试脚本: `test/run_xsim.bat`
- 性能计数: `docs/perf_counters.md`

