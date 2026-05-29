# Verification And Metrics Plan

多发射改造的风险不只在功能错误，还在“看起来通过但提交顺序、异常顺序或性能计数已经错了”。本计划用于约束每个阶段的验证范围。

## 基础回归

每个阶段至少运行：

```bat
cd test
run_xsim.bat base
```

如果 Z-bitman 后续重新打开，再运行：

```bat
cd test
run_xsim.bat z
```

如果某阶段改动涉及 SoC 外设、PLIC、Timer、UART，还需要跑对应 board tests 或现有 board-level 仿真。

## 定向测试类别

### P2 fetch2/instr_queue

需要覆盖：

- 顺序 PC：`PC, PC+4, PC+8...`
- queue 空、半满、满。
- downstream stall 时 IF 不丢指令。
- branch redirect 清空 queue。
- exception redirect 清空 queue。
- slot0 predicted taken 时 slot1 无效。
- reset 后第一条有效指令 PC 正确。

建议检查：

- `fetch_valid0/1`
- `queue_count`
- `pop_count`
- `fs_to_ds_valid`
- `id_pc`

### P3 decode2/shadow lane

需要覆盖：

- 两条独立 ALU 指令同时 decode。
- lane1 shadow 不改变 regfile、CSR、memory。
- lane1 可配对原因输出正确。
- lane1 因 RAW/WAW/control/memory 被标记不可配对。

建议新增调试信号：

- `dec0_valid`, `dec1_valid`
- `dec1_pairable`
- `dec1_block_reason`

### P4 受限双发射

最小 directed programs：

1. 独立 ALU 双发射：
   ```asm
   addi x5, x0, 1
   addi x6, x0, 2
   add  x7, x5, x6
   addi x8, x0, 3
   ```
   目标：存在至少一个周期双发射，两条结果都正确。

2. intra-pair RAW 禁止：
   ```asm
   addi x5, x0, 1
   addi x6, x5, 1
   ```
   目标：不能同 cycle 发射第二条，除非实现了 pair forwarding。

3. WAW 禁止或正确提交：
   ```asm
   addi x5, x0, 1
   addi x5, x0, 2
   ```
   目标：最终 x5 为 2。

4. branch 后禁发 slot1：
   ```asm
   beq x0, x0, target
   addi x5, x0, 1
   target:
   addi x5, x0, 2
   ```
   目标：x5 为 2，slot1 不产生错误写回。

5. load-use 禁止：
   ```asm
   lw   x5, 0(x10)
   addi x6, x5, 1
   ```
   目标：保持现有 load-use stall 正确。

### P5 完整顺序双发射

需要覆盖：

- lane0 ALU + lane1 ALU。
- lane0 ALU + lane1 branch。
- lane0 branch not-taken + lane1 valid。
- lane0 branch taken + lane1 squash。
- lane0 load + lane1 ALU。
- lane0 ALU + lane1 load。
- lane0 store + lane1 ALU。
- lane0 ALU + lane1 store。
- pair 中两个 writer。
- pair 中同 rd WAW。
- pair 中 lane1 读取 lane0 结果。
- multi-cycle mul/div 与另一条 ALU。
- CSR 强制单发或正确顺序执行。
- exception older/yunger 优先级。

### P7/P8 乱序

需要覆盖：

- RAW 通过 tag wakeup 正确。
- WAR/WAW 通过 rename 正确。
- branch mispredict 后 younger 指令全部 squash。
- exception precise：older exception 发生时 younger 结果不能提交。
- load/store：
  - store 后 load 同地址。
  - store 后 load 不同地址。
  - load 早于 older store address ready 时 replay。

## 性能计数器建议

在 P4 前后建议逐步加入：

- `perf_fetch_pair`: fetch bundle 两条有效。
- `perf_decode_pair`: decode 两条有效。
- `perf_issue_pair`: 同周期发射两条。
- `perf_retire_pair`: 同周期提交两条。
- `perf_lane1_block_raw`
- `perf_lane1_block_waw`
- `perf_lane1_block_control`
- `perf_lane1_block_memory`
- `perf_lane1_block_csr`
- `perf_lane1_block_muldiv`
- `perf_queue_empty`
- `perf_queue_full`

指标公式：

```text
IPC = retired_instructions / cycles
dual_issue_rate = issue_pair / cycles
lane1_utilization = lane1_issued / cycles
pairing_success_rate = issue_pair / decode_pair_candidates
```

## 波形检查点

每个阶段都建议固定一组波形信号：

- PC/fetch:
  - `pc0`, `pc1`
  - `fetch_valid0/1`
  - `bp_pred_taken0/1`
  - `redirect_valid`, `redirect_target`
- queue:
  - `queue_count`
  - `push_count`
  - `pop_count`
- decode/issue:
  - `dec0_pc`, `dec1_pc`
  - `issue0_valid`, `issue1_valid`
  - `issue_block_reason`
- execute:
  - `exe0_valid`, `exe1_valid`
  - `exe0_result`, `exe1_result`
- commit/writeback:
  - `commit0_valid`, `commit1_valid`
  - `commit0_pc`, `commit1_pc`
  - `regfile_wen`, `regfile_waddr`, `regfile_wdata`
- flush:
  - `branch_flush`
  - `exception_flush`
  - `lane1_kill`

## 验收门禁

每个阶段合并前必须回答：

1. 单发射兼容模式是否仍通过？
2. 新增多发射功能是否有 directed test？
3. flush/exception/interrupt 是否保持 precise？
4. 是否记录了新限制和 block reason？
5. 是否有性能计数证明该阶段的价值？
6. 是否没有把本阶段以外的指令类型偷偷打开？

## 常见错误模式

- lane1 被 branch flush 后仍写回。
- pair 中 lane1 读取了 lane0 旧值。
- lane0/lane1 同写一个 rd，最终值错误。
- writeback queue 满时没有 backpressure，导致提交丢失。
- instruction queue redirect 后残留旧路径指令。
- `retired_instructions` 对 squash 指令计数。
- CSR 或 exception 在 lane1 执行后破坏 precise state。
- load 数据 1 周期延迟被误当作组合读。

