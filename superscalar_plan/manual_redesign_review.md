# Manual Redesign Branch Review

审查日期：2026-05-30  
当前分支：`feature/manual-redesign`  
当前 HEAD：`a002f91 @ Docs: RTL architecture reference for P1 baseline`

## 结论

这条分支适合作为“手写重做 P2/P3/P4/P5”的基线。它停在 P1 抽象之后，只包含：

- P0 基线与回归基础设施。
- P1 抽取后的 `decode_unit`、`hazard_unit`、`branch_controller`。
- `RTL_ARCHITECTURE.md` 架构参考文档。

它没有包含 `main` 上的 P2/P3/P4 实现，也没有包含 `feature/P5a` 上 DeepSeek 写出的 P5a/P5b 代码。因此后续手写时，可以只参考那些分支的测试思路和 bug fix，不必继承其结构。

## 分支状态

当前分支相对 `main`：

- 当前多 1 个提交：`RTL_ARCHITECTURE.md`。
- 落后 `main` 4 个提交：P2 instruction queue、P3 dual decode/4R1W、P4 constrained dual issue、P4 flush fix。

当前分支相对 `feature/P5a`：

- 当前多 1 个文档提交。
- 落后 13 个实现提交。

建议后续继续在 `feature/manual-redesign` 上手写，不要从 `feature/P5a` merge 或 cherry-pick 大段实现。可以逐个查看它的 directed tests、波形检查点和已发现 bug。

## 需要先修正或记住的事项

### 1. `RTL_ARCHITECTURE.md` 的部分 bus 宽度已不准

当前 `defines.svh` 中：

- `BR_JMP_PACKET_WIDTH = 106`
- `SRC_PACKET_WIDTH = 68`
- no-Zb `CTRL_PACKET_WIDTH = 46`
- no-Zb `DS_ES_WIDTH = 356`

而 `RTL_ARCHITECTURE.md` 写的是 `CTRL_PACKET=44`、`DS_ES_BUS=354`。手写前建议先修正文档，或者后续不要以该文档的宽度数字作为改 RTL 的依据。以 `defines.svh` 为准。

### 2. 所有 side-effect 输出后续都必须 valid-gated

当前单发射代码里有一些信号只用 `flush` 控制，没有显式加 stage valid：

- `branch_controller.sv`: `br_redirect`
- `exe_stage.sv`: `dmem_en`
- `exe_stage.sv`: `exe_csr_wen`
- `exe_stage.sv`: `exe_regfile_wen`

单发射基线可能靠流水线持续有效和 NOP 掩盖问题，但双发射、instruction queue、bubble、lane kill 之后，这类信号必须统一遵守：

```systemverilog
side_effect_enable = lane_valid && !lane_flush && original_enable;
```

手写建议：进入 P2/P3 之前不要大改行为；但从 P4 开始，新增 lane 的任何写寄存器、写 CSR、写内存、redirect、BP update、retire 计数，都必须带 `valid && !kill`。

### 3. `ds_flush` 不能只做组合瞬时信号

`main` 上的 `268531a P4 fix: Latch ds_flush in ID stage to extend flush window` 修过一个重要问题：引入 queue 后，flush 信号如果只组合传递，可能在错误路径指令真正进入 EX 前已经消失。

手写时建议把这个思想提前纳入 P2：

- redirect/exception 到达时，IF queue 必须清空。
- ID 中已经持有的指令必须记录 `flush/kill` 位。
- kill 位随 instruction entry 一起流过 ID/EX/MEM/WB。
- 被 kill 的指令允许占用流水线，但绝不能写 architectural state。

不要把 flush 仅理解成“当前周期给一个 NOP”。双发射后它更像每条指令 entry 的 `valid/kill` 元数据。

### 4. `decode_unit` 需要更多显式元数据给 `issue_select`

当前 `decode_unit` 已经足够复用，但给 pairing 判断的输出还不够直接。后续不要让 `issue_select` 去拆 packed packet 猜类型，建议给 `decode_unit` 追加结构化元数据：

- `is_alu_inst`
- `is_mul_inst`
- `is_load_inst`
- `is_store_inst`
- `is_mem_inst`
- `is_csr_inst`
- `is_branch_inst`
- `is_jal_inst`
- `is_jalr_inst`
- `is_br_jmp_inst`
- `is_system_inst`
- `is_fence_inst`
- `regfile_wen`
- `rd_addr`
- `need_rs1`
- `need_rs2`
- `may_redirect`
- `may_exception`
- `may_write_mem`
- `may_write_csr`

这样 P3/P4 的 pairing 规则会很清楚，后续手写也更不容易把 CSR、branch、load-store 混进 lane1。

### 5. 不要先实现 P5a；先手写一个更稳的 P2/P3/P4

建议顺序：

1. P2: `instr_queue`，但后端仍单发射。
2. P3: `decode2` + `regfiles_4r1w`，lane1 shadow。
3. P4a: lane1 只执行简单 ALU，且一开始可以限制 pair 中最多一个 writer。
4. P4b: 加 `wb_queue` 或明确双写仲裁后，再允许两条 ALU 都写回。
5. P5a: lane1 branch/jump。

你想手写，最重要的是每一步都能回归，不要为了“看起来到了 P5a”牺牲结构。

## 推荐手写路线

### Step A: 固定单发射兼容门

先保持 `DUAL_ISSUE_ENABLE` 默认关闭。任何新增模块都必须有关闭宏后的单发射路径。

验收：

- 关闭宏时 `test/run_p0regression.ps1 base` 通过。
- 提交 PC 序列不变。
- `git diff` 中的单发射路径改动可以逐条解释。

### Step B: 建立 instruction entry 概念

不要继续扩张匿名 packed bus。建议先定义一个清晰的 entry 注释或 macro 约定，至少包含：

- `valid`
- `kill`
- `pc`
- `inst`
- `bp_hit`
- `bp_taken`
- `bp_target`
- `exc_bus`

P2 的 `instr_queue` 存 entry，ID pop entry。后续 lane0/lane1 都传 entry，而不是零散信号。

### Step C: P2 只做 queue，不做双发射

P2 的唯一目标是证明：

- fetch 可以提前填队列。
- redirect 可以清空队列。
- ID 每周期仍只 pop 一条。
- architectural commit 序列与 P1 完全一致。

这个阶段不要动 regfile 端口，不要动 EX/MEM/WB 宽度。

### Step D: P3 lane1 shadow 必须完全无副作用

P3 可以实例化两个 `decode_unit`，但 lane1 只能产生观测信号：

- `lane1_valid`
- `lane1_pc`
- `lane1_inst`
- `lane1_can_pair`
- `lane1_block_reason`

lane1 不允许：

- 写 regfile。
- 访问 dmem。
- 更新 CSR。
- 更新 BP。
- 改 PC。
- 增加 retire 计数。

### Step E: P4 第一版要保守

lane1 第一版只允许：

- ALU register-register。
- ALU immediate。
- `LUI/AUIPC`。

第一版禁止：

- load/store。
- branch/jump。
- CSR/system/fence。
- mul/div。
- pair 内 RAW。
- pair 内 WAW。

如果写回难度高，第一版还可以禁止 pair 中两个 writer。先证明“能安全双发射”，再解除限制。

### Step F: P5a 之前先设计 redirect/kill contract

lane1 branch 不是“给 lane1 加比较器”这么简单。P5a 前必须先写清楚：

- lane0 redirect 和 lane1 redirect 同周期谁优先。
- lane0 taken 时 lane1 是否必杀。
- lane1 redirect 到达时，哪些 queue/ID/EX entry 要 kill。
- BP update 每周期是一口还是两口。
- 被 kill 的 lane1 是否可能已经进入 wb queue。

如果这些 contract 没写完，P5a 会很容易变成信号补丁堆。

## 建议从旧分支借鉴但不要照搬的内容

可以借鉴：

- `main` 的 P4 flush bug 经验。
- `feature/P5a` 的 directed test 思路。
- `feature/P5a` 中暴露出的 x0 single-writer、lane1 load/store、branch redirect 时序问题。

不要直接照搬：

- 大段 P5a/P5b RTL。
- 为了通过测试而加入的临时 blocking assignment 或组合 dmem 快捷路径。
- 在没有明确 valid/kill contract 时扩展 MEM/WB。

## 最小文档建议

后续每完成一个手写阶段，在 `superscalar_plan` 下追加一个短文件：

- `manual_p2_notes.md`
- `manual_p3_notes.md`
- `manual_p4_notes.md`
- `manual_p5a_notes.md`

每个文件只记录四件事：

1. 本阶段打开了什么能力。
2. 本阶段仍然禁止什么能力。
3. 哪些 directed tests 通过。
4. 下一阶段不能破坏的 invariants。

## 第一批推荐任务

1. 修正 `RTL_ARCHITECTURE.md` 中 bus 宽度数字，或标注“宽度以 defines.svh 为准”。
2. 给 `decode_unit` 增加 pairing metadata 输出，但保持现有单发射行为不变。
3. 新建 `instr_queue.sv`，先实现单 pop。
4. 加 P2 directed test：redirect 清空 queue、downstream stall 不丢指令。
5. 再进入 4R1W 和 lane1 shadow。

