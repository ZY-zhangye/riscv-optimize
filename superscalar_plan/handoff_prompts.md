# Handoff Prompts For Future AI Sessions

这些提示词用于把后续执行任务拆给其它 AI。每次只交给一个阶段，避免它试图一次完成全部超标量改造。

## 通用开场提示词

```text
你正在 F:\riscv-optimize 中工作。请先阅读：
- superscalar_plan/README.md
- superscalar_plan/phase_plan.md 中当前阶段
- superscalar_plan/verification_plan.md
- rtl/cpu_top/README 或现有架构文档

只实施我指定的阶段，不要提前实现后续阶段。保持 DUAL_ISSUE_ENABLE 关闭时单发射行为兼容。不要重构无关模块。完成后运行可用的 base 回归或解释为什么无法运行，并写阶段总结。
```

## P0 提示词

```text
请只做 P0: 基线冻结与观测。目标是确认当前单发射基线、补齐或记录性能计数和回归命令。不要修改流水线结构，不要实现双发射。输出一份基线记录文档，说明当前测试结果、关键宏、IPC/CPI 采集方式和后续比较方法。
```

## P1 提示词

```text
请只做 P1: 双发射前置抽象。把 id_stage 中适合复用的译码/冒险逻辑抽成 decode_unit/hazard_unit 或等价小模块，但保持端口和行为不变。不要新增 lane1，不要改 IF/MEM/WB 宽度。完成后证明单发射回归仍通过。
```

## P2 提示词

```text
请只做 P2: 双取指与指令队列。实现 fetch2 和 instr_queue，但后端仍每周期只发射一条指令。必须保持提交 PC 序列与原单发射一致。先在仿真 testbench 中支持双指令读口，再考虑 SoC 顶层。不要实现双译码或双执行。
```

## P3 提示词

```text
请只做 P3: 双译码与寄存器读扩展。让 instruction queue 可以向 ID 提供两条候选指令，实例化两个译码路径，并把寄存器堆扩展为 4R1W 组合读。lane1 只做 shadow，不允许写寄存器、访存、更新 CSR 或改变 PC。不要实现真正双发射。
```

## P4 提示词

```text
请只做 P4: 受限双发射。lane0 保持原有完整执行路径，lane1 只允许简单 ALU/ALU-imm/LUI/AUIPC。slot0 是控制流、CSR、异常、mul/div、访存冲突或存在 pair RAW/WAW 时，必须退化单发射。先用最小 directed test 证明两条独立 ALU 能同周期发射并正确提交。
```

## P5a 提示词

```text
请只做 P5a: lane1 branch/jump 支持。不要同时打开 lane1 memory/CSR/mul/div。实现 branch redirect 仲裁，lane0 older 优先，mispredict 时能 squash younger 指令。补充分支 directed tests。
```

## P5b 提示词

```text
请只做 P5b: lane1 load/store 支持的第一步。限制一个 pair 中最多一个 memory op，保持 store 顺序和 load-use hazard 正确。不要实现 dual LSU。补充 load/store directed tests。
```

## P5c 提示词

```text
请只做 P5c: CSR/system 的顺序双发射策略。优先采用保守规则：CSR/system/exception-prone 指令强制单发，或者只允许 older slot 执行。目标是 MI tests 全部通过和 precise exception 不被破坏。
```

## P5d 提示词

```text
请只做 P5d: mul/div 多周期单元在双发射中的仲裁。初期 pair 中最多一个 mul/div，共享现有单元，busy 时正确 backpressure。不要复制 divider。目标是 UM tests 通过。
```

## P6 提示词

```text
请只做 P6: 顺序双发射性能完善。先统计 lane1 block reason，再选择一个最高收益限制解除，例如 intra-pair forwarding 或 writeback queue 优化。不要开始乱序。提交前给出 IPC 或 dual_issue_rate 对比。
```

## P7 提示词

```text
请只做 P7: 乱序前置 shell。引入 ROB/rename table/free list 框架，但保持执行顺序等价，不实现真正乱序调度。重点验证 ROB in-order commit、异常记录和 branch recovery 框架。
```

## P8a 提示词

```text
请只做 P8a: ALU-only OoO island。只有简单 ALU 指令进入 issue queue 乱序调度，其它指令强制按序。实现 rename、ROB、issue queue、wakeup/select 的最小闭环。不要碰 load/store OoO。
```

## 给 AI 的硬性限制

```text
硬性限制：
1. 不要一次实现多个阶段。
2. 不要删除单发射兼容路径。
3. 不要把 load 的 1 周期内存读当作组合读。
4. 不要让 squash 指令写 regfile/CSR/memory。
5. 不要在没有 directed test 的情况下打开新的 pairing 规则。
6. 不要重写整个 CPU；优先沿用现有 valid/allowin 握手和模块边界。
```

