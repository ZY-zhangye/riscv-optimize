# Superscalar Phase Plan

本文档给出从当前单发射设计到受限双发射、完整顺序双发射、乱序执行的详细阶段计划。每个阶段都列出目标、主要改动文件、实施步骤、验收标准和暂不处理事项。

## P0: 基线冻结与观测

### 目标

在不改变功能的前提下，把当前单发射基线固定下来，确保后续每一步都有可比较的正确性和性能数据。

### 主要文件

- `rtl/cpu_top/defines.svh`
- `rtl/cpu_top/regfile_csr.sv`
- `test/run_xsim.bat`
- `test/tb_cpu_top_simple.sv`
- `docs/perf_counters.md`

### 实施步骤

1. 确认当前 `Z_BITMAIN_ENABLE` 是否作为多发射基线保持关闭。
2. 记录当前 base 回归测试列表和通过结果。
3. 记录 CoreMark 或代表性 board test 的周期数。
4. 确认现有性能计数器至少能统计：
   - cycles
   - retired instructions
   - branch count
   - branch miss
   - load-use stall
   - EX multi-cycle stall
5. 新增或确认一个 `DUAL_ISSUE_ENABLE` 宏，默认关闭。
6. 后续所有双发射改动都必须在 `DUAL_ISSUE_ENABLE` 关闭时保持单发射行为一致。

### 验收标准

- `test/run_xsim.bat base` 通过。
- 单条测试 `test/run_xsim.bat one <hex>` 可用。
- 保存一份基线 IPC/CPI 记录。
- `DUAL_ISSUE_ENABLE` 关闭时，仿真日志中的提交 PC 序列与原基线一致。

### 暂不处理

- 不改 fetch 宽度。
- 不改寄存器堆端口。
- 不改 packed bus 宽度。

## P1: 双发射前置抽象

### 目标

把当前单槽位逻辑整理成可以复制到 lane0/lane1 的结构，但行为仍是单发射。

### 主要文件

- `rtl/cpu_top/defines.svh`
- `rtl/cpu_top/id_stage.sv`
- `rtl/cpu_top/exe_stage.sv`
- `rtl/cpu_top/mem_stage.sv`
- `rtl/cpu_top/wb_stage.sv`
- 新增可选文件：
  - `rtl/cpu_top/hazard_unit.sv`
  - `rtl/cpu_top/decode_unit.sv`
  - `rtl/cpu_top/branch_controller.sv`
  - `rtl/cpu_top/pipeline_types.svh`

### 实施步骤

1. 从 `id_stage.sv` 抽出纯组合 `decode_unit`。
   - 输入：`inst`, `pc`, `bp packet`, `csr_rdata`, forwarding metadata。
   - 输出：当前 `ds_to_es_bus` 所需各 packet、源寄存器地址、目的寄存器地址、指令类型。
2. 从 `id_stage.sv` 抽出 `hazard_unit`。
   - 输入：`rs1/rs2`, `need_rs1/need_rs2`, EX/MEM/WB 目的寄存器，load 标记。
   - 输出：`src1_fwd`, `src2_fwd`, `load_use_hazard`。
3. 从 `exe_stage.sv` 或 `cpu_top.sv` 抽出 `branch_controller`。
   - 统一管理异常跳转、分支纠正、预测更新。
4. 给每个 pipeline packet 增加注释或局部 typedef 风格说明。
5. 保持外部模块端口不变，只替换内部逻辑。

### 验收标准

- `DUAL_ISSUE_ENABLE` 关闭时回归 100% 通过。
- `id_stage.sv` 中译码、冒险、打包逻辑边界清晰，后续可实例化两次。
- 不引入新的时序寄存器，不改变组合读和 1 周期存储读语义。

### 暂不处理

- 不引入 lane1。
- 不改 IF/MEM/WB 端口宽度。

## P2: 双取指与指令队列

### 目标

前端能够一次获取两条连续指令，并放入 instruction queue；后端仍每周期最多发射一条。该阶段验证 fetch2、对齐、预测、flush 的基础行为。

### 推荐接口方案

优先采用双 32-bit 端口，而不是直接把指令接口改成 64-bit：

```systemverilog
output logic [31:0] imem_addr0,
output logic        imem_en0,
input  logic [31:0] imem_rdata0,
output logic [31:0] imem_addr1,
output logic        imem_en1,
input  logic [31:0] imem_rdata1
```

原因：

- 当前指令是固定 32-bit，双端口更直观。
- FPGA BRAM 后续可映射为 true dual port 或复制 ROM。
- 比 64-bit line 更少处理跨 8-byte 边界问题。

### 主要文件

- `rtl/cpu_top/cpu_top.sv`
- `rtl/cpu_top/if_stage.sv`
- `rtl/my_cpu/my_cpu.sv`
- 测试平台中的 instruction memory
- 新增：
  - `rtl/cpu_top/instr_queue.sv`
  - 可选 `rtl/cpu_top/fetch_bundle.sv`

### 实施步骤

1. 新增 `instr_queue`，深度建议 4 或 8 个 instruction entry。
   - 每个 entry 包含：`valid`, `pc`, `inst`, `bp_hit`, `bp_pred_taken`, `bp_pred_target`, `exc_bus`。
2. `if_stage` 每次在队列有空间时请求 `pc` 和 `pc+4`。
3. 保持 `fs_to_ds_bus` 对 ID 仍输出单条指令。
4. 若发生 branch redirect 或 exception redirect，清空队列。
5. PC 更新规则：
   - 若 slot0 预测跳转，则本 fetch bundle 中 slot1 无效。
   - 若 slot0 不跳转且 slot1 预测跳转，下一 PC 为 slot1 target。
   - 初期可以只允许 slot0 做预测，slot1 预测禁用，降低复杂度。
6. 后端仍从队列 pop 1 条。

### 验收标准

- 单发射回归通过。
- 定向测试覆盖：
  - 顺序 fetch pair。
  - branch redirect 清空队列。
  - reset 后 PC 从 `PC_START` 正常开始。
  - 队列满时 IF 停顿，队列空时 ID 停顿。
- 提交 PC 序列和 P0 基线一致。

### 暂不处理

- 不发射两条。
- 不同时译码两条。
- 不改 regfile 读端口。

## P3: 双译码与寄存器读扩展

### 目标

后端能够同时拿到两条候选指令并译码，但仍只提交 lane0 到现有单发射执行链路。lane1 进入 shadow mode，只做译码和 hazard 观测，不改变 architectural state。

### 主要文件

- `rtl/cpu_top/id_stage.sv`
- `rtl/cpu_top/regfiles.sv`
- `rtl/cpu_top/cpu_top.sv`
- `rtl/cpu_top/defines.svh`
- `rtl/cpu_top/instr_queue.sv`
- 新增：
  - `rtl/cpu_top/regfiles_4r1w.sv` 或扩展原 `regfiles.sv`
  - `rtl/cpu_top/issue_select.sv`

### 实施步骤

1. 将 `instr_queue` pop 接口扩展为最多输出两条：
   - `inst0_valid/inst0_bundle`
   - `inst1_valid/inst1_bundle`
   - `pop_count`
2. 实例化两个 `decode_unit`。
3. 寄存器堆扩展为 4 读 1 写。
   - 保持组合读。
   - 单写口广播给所有读副本。
   - `x0` 仍硬连为 0。
4. 新增 `issue_select`，但初期永远选择：
   - lane0 valid 时发 lane0。
   - lane1 只输出 debug/perf shadow 信息，不进入 EX。
5. 增加 shadow 检查信号：
   - lane1 是否可配对。
   - lane1 与 lane0 是否存在 RAW/WAW。
   - lane1 指令类型。

### 验收标准

- `DUAL_ISSUE_ENABLE` 关闭时行为完全等于单发射。
- `DUAL_ISSUE_ENABLE` 开启但 `DUAL_ISSUE_COMMIT_ENABLE` 关闭时，回归仍通过。
- 波形中可看到每周期最多两个 decode 结果。
- lane1 shadow 不写寄存器、不访问内存、不更新 CSR、不改变 PC。

### 暂不处理

- 不执行 lane1。
- 不改 EX/MEM/WB 数据通路。

## P4: 受限双发射

### 目标

实现真正能改变 architectural state 的受限双发射。lane0 保持原有完整指令能力，lane1 只执行简单、低风险指令。先获得可测 IPC 提升，再逐步放宽 pairing 规则。

### 第一版 pairing 规则

lane0：

- 允许现有所有已支持指令。

lane1：

- 只允许：
  - `ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU`
  - `ADDI/ANDI/ORI/XORI/SLTI/SLTIU/SLLI/SRLI/SRAI`
  - `LUI/AUIPC`
- 禁止：
  - load/store
  - branch/jump
  - CSR/system/fence
  - multiply/divide
  - exception-generating instruction

pair 整体限制：

- slot0 是 branch/jump/system/exception 时，不发 slot1。
- slot1 不能读取 slot0 的 rd，初期禁止 intra-pair RAW。
- slot0 和 slot1 不能写同一个非零 rd，初期禁止 WAW。
- 若任一指令读写 CSR，不双发射。
- 若 EX/MEM/WB 中存在会影响 lane1 的未解决 load-use，不双发射。
- 若 instruction queue 只有一条有效指令，只发 lane0。

### 主要文件

- `rtl/cpu_top/id_stage.sv`
- `rtl/cpu_top/exe_stage.sv`
- `rtl/cpu_top/wb_stage.sv`
- `rtl/cpu_top/write_port_arbiter.sv`
- `rtl/cpu_top/cpu_top.sv`
- 新增：
  - `rtl/cpu_top/issue_select.sv`
  - `rtl/cpu_top/exe_lane_simple.sv`
  - `rtl/cpu_top/commit_arbiter.sv` 或 `wb_queue.sv`

### 实施步骤

1. `issue_select` 输出：
   - `issue0_valid`, `issue0_bus`
   - `issue1_valid`, `issue1_bus`
   - `pop_count = issue1_valid ? 2 : 1`
2. 保留现有 `exe_stage` 作为 lane0。
3. 新增 `exe_lane_simple` 作为 lane1。
   - 只包含 forwarding、ALU、结果生成。
   - 不产生 branch redirect。
   - 不访问 dmem。
   - 不访问 CSR。
4. 给 lane1 增加独立 pipeline valid 寄存器，推荐先与 lane0 同步流动。
5. 写回策略二选一：
   - P4a 简化版：pairing 规则限制一个 pair 中最多一个 regfile writer。
   - P4b 推荐版：实现 2-entry `wb_queue`，按 lane0 older、lane1 younger 顺序串行写回单写口。
6. retire 计数：
   - lane0 retired 加 1。
   - lane1 真正提交时再加 1。
7. flush 处理：
   - lane0 触发 branch redirect/exception 时，杀掉同 cycle 的 lane1。
   - lane1 初期不会产生 redirect/exception。

### 验收标准

- base 回归通过。
- 新增定向测试：
  - 两条独立 ALU 指令双发射并都写回。
  - lane1 依赖 lane0 时自动退化单发射。
  - slot0 branch 后 slot1 被禁止。
  - slot0 load 后 slot1 读 load rd 时禁止双发射。
  - WAW 被禁止或按提交顺序正确处理。
- IPC 计数显示至少在人工 ALU 测试中超过 1.0。

### 暂不处理

- lane1 不访存。
- lane1 不分支。
- lane1 不执行 mul/div。
- lane1 不执行 CSR。
- 不支持 intra-pair forwarding。

## P5: 完整顺序双发射

### 目标

支持两条指令在保持程序顺序语义的前提下进入双流水线。此时 lane1 不再只限简单 ALU，但仍保持 in-order issue 和 in-order commit。

### 主要挑战

- 4 读 2 写或 4 读 1 写加 commit queue 的取舍。
- 两条指令同时访存时的数据存储器端口和 store 顺序。
- 两条指令同时产生异常时的精确异常选择。
- lane0 branch 与 lane1 指令的有效性。
- 多周期 mul/div 对两条流水线的 backpressure。

### 推荐微架构

1. 前端：fetch2 + instruction queue。
2. 译码：decode2 + pair hazard。
3. 发射：in-order issue，禁止越过 older 指令。
4. 执行：
   - `exe0`: 完整执行通道。
   - `exe1`: 逐步补齐 ALU、branch、load/store、mul/div、CSR。
5. 访存：
   - 初期单 LSU，两个 lane 中最多一个 memory op。
   - 后期 dual LSU 或 store/load queue。
6. 提交：
   - 使用 in-order commit buffer。
   - 每周期最多提交两条，但异常/中断严格按 older 指令优先。

### 分阶段实施

#### P5a: lane1 支持 branch/jump 但不支持访存

步骤：

1. lane1 增加 branch compare 和 target 生成。
2. branch redirect 仲裁：
   - lane0 redirect 优先于 lane1。
   - 若 lane0 是 taken branch/jump，则 lane1 必须被 squash，除非能证明 lane1 是正确 fall-through 指令且 lane0 不跳。
3. BP update 支持两个分支更新，或每周期只更新 older one。
4. 完成 branch directed tests。

验收：

- branch-heavy 回归通过。
- lane1 branch mispredict 能正确 flush younger 指令。

#### P5b: lane1 支持 load/store，单 LSU 限制

步骤：

1. decode pair 允许一个 memory op。
2. 若 lane0 和 lane1 都是 memory op，则只发 lane0。
3. 若 lane1 是 memory op，lane0 不是 memory op，则 lane1 使用 LSU。
4. store 必须按程序顺序提交。
5. load-use hazard 扩展到两条 lane。

验收：

- load/store 定向测试通过。
- store 后 load、load 后 ALU、跨 lane load-use 都正确。

#### P5c: lane1 支持 CSR/system 的安全子集

步骤：

1. 初期仍禁止 pair 中出现两个 CSR。
2. CSR 指令只能在 pair 的 older slot 提交，或者强制单发。
3. `mret/ecall/ebreak` 继续强制单发。
4. CSR perf counter 的 retire 数按实际提交数更新。

验收：

- MI tests 通过。
- 异常入口、mret 返回、CSR read-after-write 正确。

#### P5d: lane1 支持 mul/div，多周期仲裁

步骤：

1. 初期只有一个 mul/div 单元，pair 中最多一个 mul/div。
2. 如果 lane1 是 mul/div 且 lane0 非 mul/div，允许 lane1 占用单元。
3. multi-cycle busy 时同时 backpressure 两条 lane 或对应 commit buffer。
4. 后期可复制 multiplier，divider 仍共享。

验收：

- UM tests 通过。
- mul/div stall 不导致 lane 顺序错乱。

### 完整 P5 验收标准

- base 回归通过。
- 若重新启用 Z-bitman，对已实现 Z tests 回归通过。
- 所有新增 directed dual-issue tests 通过。
- 在 ALU-heavy benchmark 中 IPC 明显大于 1。
- 所有异常、中断、branch redirect 都保持 precise state。

## P6: 顺序双发射性能完善

### 目标

让完整顺序双发射不只是能跑，而是在代表性程序上稳定提速。

### 方向

1. 更好的 pairing 规则：
   - 支持 intra-pair RAW forwarding。
   - 支持 WAW，按 younger 覆盖语义提交。
   - 支持 slot0 branch not-taken 时保留 slot1。
2. 前端优化：
   - BTB 支持 slot0/slot1 两个 lookup。
   - branch target alignment 处理。
   - return address stack 可选。
3. 写回优化：
   - 从 4R1W+commit queue 过渡到 4R2W regfile。
   - 或保留单写口但提高 commit queue 深度。
4. 访存优化：
   - data memory true dual port。
   - store buffer。
   - load-store forwarding。
5. 性能计数器：
   - pair issued count。
   - lane1 blocked reason。
   - dual retire count。
   - fetch queue empty/full count。

### 验收标准

- 能解释每类不能双发射的原因。
- CoreMark 或代表 benchmark 有稳定 CPI 改善。
- 频率下降在可接受范围内。

## P7: 乱序前置

### 目标

在不立刻实现乱序调度的前提下，引入乱序所需的 architectural shell：ROB、重命名表、物理寄存器或未来可替代结构。

### 推荐顺序

1. 增加 ROB，但仍 in-order issue、in-order execute、in-order commit。
2. 增加 architectural register map table，但初期 map 恒等。
3. 增加 physical register file 框架，但初期每个 architectural register 固定一个 physical register。
4. 把异常、中断、branch recovery 改为通过 ROB 统一处理。
5. 保持旧顺序双发射路径作为对照。

### 主要新增模块

- `rob.sv`
- `rename_table.sv`
- `free_list.sv`
- `physical_regfile.sv`
- `commit_stage.sv`

### 验收标准

- 行为仍等价顺序双发射。
- ROB 中每条指令按程序顺序 retire。
- branch flush 能回滚到正确 map checkpoint。

## P8: 真正乱序执行

### 目标

实现可实际乱序调度、乱序完成、按序提交的 superscalar OoO core。

### 必要组件

1. Rename:
   - rename table
   - free list
   - branch checkpoint
2. Dispatch:
   - ROB allocation
   - issue queue allocation
   - LSQ allocation
3. Wakeup/select:
   - operand ready tracking
   - common data bus 或分布式 bypass
   - oldest-ready select
4. Functional units:
   - ALU x2
   - branch unit
   - multiplier/divider
   - LSU
5. Memory ordering:
   - load queue
   - store queue
   - store-to-load forwarding
   - mis-speculation replay
6. Commit:
   - in-order ROB commit
   - precise exception
   - interrupt boundary

### 推荐实施子阶段

#### P8a: ALU-only OoO island

- 只让简单 ALU 指令进入 issue queue。
- load/store/branch/CSR/mul/div 仍强制按序。
- 验证 rename、wakeup、select、commit 基础正确性。

#### P8b: branch OoO support

- branch 进入 ROB。
- branch checkpoint 和 mispredict recovery。
- younger 指令 squash。

#### P8c: load/store queue

- store address/data 分离。
- load 检查 older stores。
- store commit 后写内存。

#### P8d: multi-cycle FU

- mul/div 加入 issue queue。
- 完成信号写回 ROB/PRF。

### 验收标准

- directed OoO tests 覆盖：
  - RAW/WAR/WAW 通过 rename 正确处理。
  - older exception 阻止 younger commit。
  - branch mispredict 恢复 map/free list/ROB。
  - load-store ordering 正确。
- 性能计数器能显示乱序窗口利用率。

## 关键设计取舍

### 寄存器堆路线

推荐路线：

1. P3 使用 4R1W，便于双译码。
2. P4 使用 4R1W + pairing 限制或小型 writeback queue。
3. P5 根据性能选择：
   - 继续 4R1W + commit queue，硬件简单但写回受限。
   - 升级 4R2W，吞吐更好但面积和时序压力更大。
4. P8 使用 physical register file，端口根据 issue/commit 宽度重新设计。

### 数据存储路线

推荐路线：

1. P4 lane1 禁止访存。
2. P5b pair 中最多一个 memory op。
3. P6 使用 dual-port data memory 或 LSU queue。
4. P8 使用 LSQ。

### 分支路线

推荐路线：

1. P2 只让 slot0 做预测。
2. P4 slot0 是控制流时禁发 slot1。
3. P5a 支持 slot1 branch。
4. P6 做双 lookup BTB/BHT。
5. P8 加 checkpoint recovery。

## 每阶段失败时的退路

- 若 P2 fetch2 导致大量 PC 错乱：退回单 fetch，但保留 instruction queue。
- 若 P3 4R1W 时序差：先用 regfile 复制实现 4 个组合读。
- 若 P4 lane1 写回难稳定：先启用一个 pair 最多一个 writer 的限制。
- 若 P5 精确异常复杂：所有 system/CSR/exception-prone 指令强制单发。
- 若 P8 乱序过大：先只实现 ALU-only OoO island，不碰访存。

