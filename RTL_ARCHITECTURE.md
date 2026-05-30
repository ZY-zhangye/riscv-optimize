# RTL 代码架构说明

> 基于 branch `feature/manual-redesign` (commit `474c140`)  
> P1 基线：单发射 5 级流水线，已抽取 decode_unit / hazard_unit / branch_controller

---

## 1. 总体架构

```
 ┌─────────────────────────────────────────────────────────┐
 │                     cpu_top.sv                          │
 │                                                         │
 │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
 │  │ if_stage │→│ id_stage │→│exe_stage │→│mem_stage│→│
 │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
 │       ↑              │             │             │      │
 │  branch redirect     │             │             │      │
 │       └──────────────┴─────────────┘             │      │
 │                                                  ↓      │
 │                  ┌──────────┐  ┌──────────┐  ┌────────┐ │
 │                  │regfile   │  │regfile   │  │wb_stage│ │
 │                  │_csr.sv   │  │s.sv      │←─│        │ │
 │                  └──────────┘  └──────────┘  └────────┘ │
 └─────────────────────────────────────────────────────────┘
```

**流水线**: IF → ID → EX → MEM → WB (5 级，经典 RISC)

**ISA**: RV32I + M (乘除) + Zicsr (CSR)，已移除 FPU 和 Zb*

**总线格式**: 所有流水级之间使用 packed bus 传递指令信息

---

## 2. 模块清单 (16 个)

| 模块 | 行数 | 所属阶段 | 功能 |
|------|------|---------|------|
| `cpu_top.sv` | 279 | 顶层 | 模块互联，信号声明 |
| `if_stage.sv` | 141 | IF | 取指 + 分支预测 + PC 生成 |
| `id_stage.sv` | 264 | ID | 译码调度 + 冒险检测 + 操作数准备 |
| `decode_unit.sv` | 454 | ID | 纯组合译码 (P1 抽取) |
| `hazard_unit.sv` | 63 | ID | 数据冒险检测 + 前递控制 (P1 抽取) |
| `branch_controller.sv` | 102 | EX | 分支比较 + 跳转生成 + BP 更新 (P1 抽取) |
| `exe_stage.sv` | 459 | EX | 执行：ALU/乘除/访存地址/CSR/分支 |
| `forwarding_unit.sv` | 37 | EX | 操作数前递选择 |
| `alu_wrapper.sv` | 29 | EX | ALU 运算 (加减/逻辑/移位/比较) |
| `mul.sv` | 221 | EX | 多周期乘法器 (6-cycle) |
| `divider.sv` | 84 | EX | 多周期除法器 |
| `mem_stage.sv` | 213 | MEM | 访存：load 数据提取 / store / 异常检测 |
| `wb_stage.sv` | 73 | WB | 写回：寄存器堆写入仲裁 |
| `regfiles.sv` | 44 | — | 2R1W 寄存器堆 (x0 硬连线) |
| `regfile_csr.sv` | 209 | — | CSR 寄存器 + 异常控制 + 性能计数器 |
| `write_port_arbiter.sv` | 37 | WB | 写端口仲裁 (为双发射预留) |

---

## 3. Pipeline Bus 格式

### 3.1 FS_DS_BUS: IF → ID

```
{ inst[31:0] , pc[31:0] , bp_hit[1] , bp_taken[1] , bp_target[31:0] }
  66 bits total
```

| 字段 | 位宽 | 说明 |
|------|------|------|
| `inst` | 32 | 指令字 |
| `pc` | 32 | 指令地址 |
| `bp_hit` | 1 | BTB 命中 |
| `bp_taken` | 1 | 预测跳转 |
| `bp_target` | 32 | 预测目标地址 |

### 3.2 DS_ES_BUS: ID → EX

```
{ alu_packet[10], mul_packet[6], mem_packet[38], csr_packet[82],
  br_jmp_packet[106], ctrl_packet[44], src_packet[68] }
  总宽度: 354 (无 Zb) / 382 (有 Zb)
```

包子包结构:

| 子包 | 宽度 | 内容 |
|------|------|------|
| `alu_packet` | 10 | ALU 操作码 `alu_op[9:0]` |
| `mul_packet` | 6 | `{mul_op[4], src1_signed, src2_signed}` |
| `mem_packet` | 38 | `{imm[32], mem_op[5], is_store}` |
| `csr_packet` | 82 | `{csr_rdata, imm, waddr, op, imm_sel, fwd, wen}` |
| `br_jmp_packet` | 106 | `{bp_hit, bp_taken, bp_target, jmp_target, imm, opcode[6], is_jal, is_jalr}` |
| `ctrl_packet` | 44 | `{pc[32], wb_sel[2], is_alu/mul/mem/csr/br_jmp[5], rd[5], wen[1], multi[1]}` |
| `src_packet` | 68 | `{rs1_val[32], rs2_val[32], fwd1[2], fwd2[2]}` |

### 3.3 ES_MS_BUS: EX → MEM

```
{ pc[32], exe_result[32], load_inst[6], rd[5], wen[1], wb_sel[2], csr_wen[1], csr_addr[12], csr_wdata[32] }
  123 bits total
```

### 3.4 MS_WS_BUS: MEM → WB

```
{ pc[32], result[32], rd_addr[5], wen[1] }
  70 bits total
```

---

## 4. 逐模块详解

### 4.1 `if_stage.sv` — 取指阶段

```
输入:  imem_rdata (指令存储数据)
输出:  fs_to_ds_bus (指令 + PC + BP 信息)
       imem_addr (取指地址)
```

**核心逻辑**:
- PC 寄存器 32bit，复位后从 `PC_START` (0x8000_0000) 开始
- 每周期: 若 `ds_allowin=1`，PC 递增 +4；若 `br_taken=1`，PC 跳转到 `br_target`
- 分支预测: 使用 BTB (Branch Target Buffer)，存储于 regfile 内部
- BP 更新: 从 `branch_controller` 接收 `bp_update_*` 信号更新 BTB

**关键端口**:
| 端口 | 方向 | 说明 |
|------|------|------|
| `pc_out` | out | 输出到 imem |
| `inst_in` | in | 从 imem 读入 |
| `ds_allowin` | in | ID 阶段能否接收新指令 |
| `br_taken` / `br_target` | in | 分支重定向 |
| `bp_update_*` | in | BTB 更新 (来自 EX) |

### 4.2 `decode_unit.sv` — 译码单元 (纯组合)

```
输入:  inst[32], pc[32], csr_rdata, BP info, forwarding hints
输出:  各 packet (alu/mul/mem/csr/br_jmp/ctrl/src)
       rs1_addr, rs2_addr, rd_addr
       ​need_rs1, need_rs2, is_load, alu_src2_imm_sel
       inst_lui, inst_auipc, inst_ecall, inst_ebreak, inst_mret
```

**核心逻辑**:
- 完全组合逻辑，无时序元件
- 解码 RV32I 全部整数指令 + M 扩展 + CSR
- 支持立即数类型: I (12bit 符号扩展), S, B, U, J, Z
- 控制信号分类: `is_alu / is_mul / is_mem / is_csr / is_br_jmp / is_system`
- 操作数需求: `need_rs1 / need_rs2` (LUI/AUIPC/JAL 不需要 rs1)
- ALU 操作码: LUI→ADD, AUIPC→ADD, SLT→SLT, etc.

**已移除**: Zb 位操作扩展 (Z_BITMAIN_ENABLE 关闭)

**扩展点 (双发射)**:
- 可实例化 2 个 decode_unit，实现双译码
- `ctrl_packet` 中的 `is_*` 信号直接用于双发射配对判断

### 4.3 `hazard_unit.sv` — 冒险检测单元 (纯组合)

```
输入:  rs1/rs2 地址, need_rs1/need_rs2
       exe_dest_addr/mem_dest_addr (前递源)
       prev_load (上条指令是 load), ds_valid
输出:  src1_fwd[2], src2_fwd[2] (前递控制)
       load_use_hazard (停顿信号)
```

**核心逻辑**:
- `src1_fwd / src2_fwd`:
  - `00`: 使用寄存器堆值
  - `01`: 前递自 EX 阶段 (`exe_result_reg`)
  - `10`: 前递自 MEM 阶段 (`mem_result`)
- `load_use_hazard`: 上条是 load 且当前指令依赖 load 结果 → 停顿 1 周期

**扩展点 (双发射)**:
- 需增加 lane1 的 rs1/rs2 检查
- lane1 对 lane0 的 RAW 依赖 → 配对禁止或停顿

### 4.4 `id_stage.sv` — 译码/发射阶段

```
输入:  fs_to_ds_bus (来自 IF)
       regfile 读数据, CSR 读数据
       前递地址 (来自 EX/MEM)
输出:  ds_to_es_bus (到 EX)
       rs1/rs2 寄存器地址
```

**核心逻辑**:
1. 锁存 `fs_to_ds_bus` → `fs_to_ds_bus_r`
2. 调用 `decode_unit` 译码
3. 调用 `hazard_unit` 检测冒险
4. WB 阶段前递: 若 regfile_wen 且 waddr 匹配，直接用 wb_data
5. 操作数准备:
   - LUI → src1=0
   - AUIPC → src1=PC
   - 立即数 → src2=imm (I/U 型)
6. 组装 `ds_to_es_bus`
7. Flush 处理: `exception_flag || br_taken` → ds_flush=1
8. 异常编码: ECALL/EBREAK/MRET

**扩展点 (双发射)**:
- 需实例化第二个 decode_unit + hazard_unit (lane1)
- 需接入 instruction queue (替代直接 IF→ID)
- 需增加 issue_select 模块 (配对判断)

### 4.5 `branch_controller.sv` — 分支控制 (纯组合)

```
输入:  bp_pred_* (预测值), br_jmp_* (指令字段), src1/src2 (操作数)
       exe_pc, es_flush, es_valid
输出:  br_taken, br_target (分支结果)
       br_redirect, br_redirect_target (重定向)
       bp_update_* (BP 更新)
       perf_branch_* (性能计数)
```

**核心逻辑**:
- 比较逻辑: `sub_res = src1 - src2`, 提取 `eq/lt/ltu`
- 分支条件: `beq & eq | bne & !eq | blt & lt | ...`
- 跳转: `br_taken = is_jal | is_jalr | (branch & cond)`
- 重定向: 当 `br_taken != bp_pred_taken` 或目标地址不匹配时
- JALR: `br_target = (src1 + imm) & ~1`
- BP 更新: 每周期最多更新一条分支预测

**扩展点 (双发射)**:
- 可实例化第二个 branch_controller 给 lane1
- 需增加 redirect 仲裁 (lane0 优先)

### 4.6 `exe_stage.sv` — 执行阶段

```
输入:  ds_to_es_bus, mem_result (前递), ds_flush
输出:  es_to_ms_bus, dmem_*, branch_redirect, forwarding
```

**核心逻辑**:
- 解包 `ds_to_es_bus` → 各子包
- 前递选择: 调用 `forwarding_unit` 选择 src1/src2
- ALU: `alu_wrapper` 执行
- 乘法: `mul` 模块 (6 周期，`mul_stall` 反压)
- 除法: `divider` 模块 (多周期)
- 访存地址: `src1 + mem_imm` → dmem_addr
- Store 数据: 字节/半字复制，写使能生成
- CSR: RMW 操作 (csrrw/csrrs/csrrc)
- 分支: 调用 `branch_controller`
- 结果选择: bitman > alu > mem_addr > mul > csr > PC+4

**扩展点 (双发射)**:
- 需新增 `exe_lane_simple.sv` 给 lane1 (简化执行通道)
- dmem 端口需增加 mux
- 需增加 lane1 forwarding 数据

### 4.7 `forwarding_unit.sv` — 前递单元

```
输入:  reg_src1/reg_src2 (寄存器值)
       exe_result_reg/mem_result_reg (前递数据)
       src1_fwd/src2_fwd (前递选择码)
输出:  src1/src2 (最终操作数)
```

**核心逻辑**: 纯组合 MUX
- `fwd=01`: 选择 EX 结果 (同周期 ALU→ALU 旁路)
- `fwd=10`: 选择 MEM 结果 (load 后 1 周期)
- `fwd=00`: 选择寄存器值

### 4.8 `alu_wrapper.sv` — ALU 运算

```
输入:  alu_op[10], src1[32], src2[32]
输出:  alu_result[32]
```

**核心逻辑**: one-hot ALU 操作码，纯组合
- ADD/SUB: 加减
- AND/OR/XOR: 按位逻辑
- SLL/SRL/SRA: 移位 (src2[4:0] 移位量)
- SLT/SLTU: 有符号/无符号比较

### 4.9 `mul.sv` — 乘法器

```
输入:  mul_src1/src2, mul_op, is_mul, is_multicycle
输出:  mul_result, mul_stall
```

**核心逻辑**: 多周期 Booth 乘法 (6 周期, MUL_CYCLE=6)
- 支持指令: `mul, mulh, mulhsu, mulhu`
- `mul_stall` 反压 EX 阶段，使指令保持在 EX

### 4.10 `divider.sv` — 除法器

```
输入:  (经由 exe_stage 控制)
输出:  除法结果
```

**核心逻辑**: 多周期恢复余数除法

### 4.11 `mem_stage.sv` — 访存阶段

```
输入:  es_to_ms_bus, dmem_rdata
输出:  ms_to_ws_bus, mem_result (前递), 异常信息
```

**核心逻辑**:
- Load 数据提取: 根据 load_inst (LB/LH/LW/LBU/LHU) 和地址低 2bit
  进行字节/半字选择 + 符号/零扩展
- 结果选择: `mem_result = is_mem ? load_data : exe_result`
- 异常检测:
  - 指令地址非对齐 (IAM): 分支目标 [1:0] != 00
  - Load 地址非对齐 (LAM): LW 且 addr[1:0]!=0, LH 且 addr[0]!=0
  - Store 地址非对齐 (SAM): 同理
  - 外部中断 (PLIC_IRQ): 仅在 MIE 开启时
- 异常码生成: 异常 > 中断 > 正常
- CSR 写: ecall/ebreak/mret + 正常 CSR

### 4.12 `wb_stage.sv` — 写回阶段

```
输入:  ms_to_ws_bus (lane0), ms1_to_ws_bus (lane1, 预留)
输出:  regfile_wen/waddr/wdata
```

**核心逻辑**:
- Lane0 数据锁存
- Lane1 数据锁存 (预留, 通过 `ifdef DUAL_ISSUE_COMMIT_ENABLE`)
- 调用 `write_port_arbiter` 仲裁双写口 → 单写口

### 4.13 `regfiles.sv` — 寄存器堆

```
输入:  写口 (wen, waddr, wdata)
       读口 (raddr1, raddr2)
       (可选扩展: raddr3, raddr4 给双发射)
输出:  rdata1, rdata2
```

**核心逻辑**:
- 32x32bit 触发器阵列
- x0 硬连线为 0 (读 x0 始终返回 0，写 x0 被忽略)
- 2R1W (当前版本), 可扩展至 4R1W
- 组合读 (无需额外周期)

### 4.14 `regfile_csr.sv` — CSR 寄存器 + 异常控制

```
输入:  CSR 读写, 异常码, 性能事件
输出:  csr_rdata, exception_flag, exception_addr
```

**CSR 寄存器**:
- Machine: `mstatus/misa/mtvec/mepc/mcause/mhartid/mie/mip/mtval`
- Vendor: `mvendorid/marchid/mimpid/mscratch`
- 性能: `cycle/instret/perf_ctrl + perf_*` (7C0-7C9)

**异常控制**:
- 异常入口: `mstatus[MIE]→MPIE`, `mstatus[MIE]←0`, `mepc←坏地址`
- MRET 返回: `mstatus[MPIE]→MIE`, PC←mepc
- 中断使能: `MIE & MEIE` (mstatus[3] & mie[11])

**性能计数器** (PERF_CTRL[0] 使能):
| CSR | 功能 |
|-----|------|
| 7C1 | 周期数 |
| 7C2 | 退休指令数 |
| 7C3 | 分支指令数 |
| 7C4 | 分支误预测数 |
| 7C5 | BP 命中数 |
| 7C6 | BP 未命中数 |
| 7C7 | load-use 停顿数 |
| 7C8 | EX 多周期停顿数 |
| 7C9 | 异常数 |

### 4.15 `write_port_arbiter.sv` — 写口仲裁

```
输入:  wb_*_0 (lane0), wb_*_1 (lane1)
输出:  regfile_* (单写口)
```

**核心逻辑**:
- 单发射模式: 直接透传 lane0
- 双发射预留: 同一寄存器冲突时 lane1 停顿 (冲突=两者地址相同且非 x0)

### 4.16 `cpu_top.sv` — 顶层互联

**核心信号** (约 100 个声明):
- IF↔ID: `fs_to_ds_bus`, `ds_allowin`
- ID↔EX: `ds_to_es_bus`, `es_allowin`
- EX↔MEM: `es_to_ms_bus`, `ms_allowin`
- MEM↔WB: `ms_to_ws_bus`, `ws_allowin`
- 分支: `br_redirect` / `br_redirect_target` (EX→IF)
- BP 更新: `bp_update_*` (EX→IF)
- 前递: `exe_dest_addr`, `mem_dest_addr` (EX/MEM→ID)
- 异常: `exception_flag`, `exception_addr` (CSR→IF)

**实例化顺序**: IF → ID → EX → MEM → WB → regfiles + regfile_csr

---

## 5. 关键设计决策

### 5.1 Packed Bus 架构
所有流水级之间用宽位宽 packed bus 传递指令信息。优点：单信号连线，易于后续扩展宽度和 lane 复制。缺点：需统一解包逻辑。

### 5.2 分支预测 (BTB)
- 存储在 `if_stage` 内部 (非独立模块)
- 使用 `bp_update_*` 接口更新 (来自 EX 的 branch_controller)
- 初始状态: 简单直接映射 BTB，不预测时默认不跳

### 5.3 前递网络
- 2 级前递: EX→EX (同周期), MEM→EX (load 后 1 周期)
- 仅前递地址 (选择在 exe_stage 的 forwarding_unit 完成)
- WB→ID 组合前递 (在 id_stage 内完成)

### 5.4 CSR 与异常
- 所有 CSR 访问通过 MEM 阶段 (`regfile_csr`)
- 异常在 MEM 阶段检测并处理
- 异常标志: `exception_flag` → 刷新 IF/ID, PC 跳转到 `mtvec`

### 5.5 乘除处理
- 乘法: 6-cycle Booth，通过 `mul_stall` 反压 EX
- 除法: 多周期恢复余数法，通过 `is_multicycle` 反压
- 反压传播: EX stall → ID stall → IF stall

---

## 6. 模块依赖关系

```
cpu_top
 ├─ if_stage ──────────────────────────────────────────┐
 ├─ id_stage                                            │
 │   ├─ decode_unit                                      │
 │   └─ hazard_unit                                      │
 ├─ exe_stage                                            │
 │   ├─ forwarding_unit                                  │
 │   ├─ alu_wrapper                                      │
 │   ├─ mul                                              │
 │   ├─ divider                                          │
 │   └─ branch_controller ← (redirect → if_stage) ──────┘
 ├─ mem_stage
 ├─ wb_stage
 │   └─ write_port_arbiter
 ├─ regfiles
 └─ regfile_csr
```

---

## 7. 关键宏开关

| 宏 | 位置 | 状态 | 说明 |
|----|------|------|------|
| `DUAL_ISSUE_ENABLE` | defines.svh | 关闭 (注释) | 双发射使能总开关 |
| `DUAL_ISSUE_COMMIT_ENABLE` | — | 关闭 | 双发射提交使能 |
| `Z_BITMAIN_ENABLE` | defines.svh | 关闭 (注释) | Zb 位操作扩展 |
| `MUL_MULTICYCLE_ENABLE` | defines.svh | 开启 | 多周期乘法 |
| `MULTICYCLE_ENABLE` | defines.svh | 开启 | 多周期除法 |
| `DEBUG_EN` | tb | 开启 | 仿真 debug 输出 |
| `USE_RTL_DIVIDER_MODEL` | tb | 开启 | 使用 RTL 除法器模型 |

---

## 8. 双发射改造路线

从当前 P1 基线出发，后续改造涉及:

| 步骤 | 新增模块 | 修改模块 |
|------|---------|---------|
| P2 (双取指+队列) | `instr_queue.sv` | if_stage, cpu_top |
| P3 (双译码+4R1W) | `issue_select.sv` | id_stage, regfiles, cpu_top |
| P4 (受限双发射) | `exe_lane_simple.sv` | issue_select, cpu_top, wb_stage |
| P5a (lane1 分支) | — | exe_lane_simple, issue_select, cpu_top |
| P5b (lane1 访存) | — | exe_lane_simple, issue_select, cpu_top, mem_stage |
| P5c (lane1 CSR) | — | issue_select, cpu_top |
| P5d (lane1 乘除) | — | exe_lane_simple, issue_select |

---

## 9. 测试基础设施

| 文件 | 说明 |
|------|------|
| `test/tb_cpu_top_simple.sv` | 快速仿真 testbench (含 imem/dmem 行为模型) |
| `test/regress.sh` | 回归脚本 (rv32ui/mi/um) |
| `test/run_xsim.bat` | Vivado XSim 编译+仿真 |
| `test/asm_to_hex.py` | Python RISC-V 汇编器 (开发辅助) |
| `test/hex/riscv-tests/` | 预编译 riscv-tests hex 文件 |

**Testbench 检查点**: `wb_pc == 0x80000044` 时检查 `x3 == 1` (PASS) 或 `!=1` (FAIL)。

---

## 10. 快速验证

```bash
# 编译
xvlog --sv -i rtl/cpu_top -i rtl/my_cpu -i test \
  -d DEBUG_EN -d USE_RTL_DIVIDER_MODEL \
  rtl/cpu_top/*.sv test/behav_multiplier.sv test/tb_cpu_top_simple.sv

# 仿真 (单测试)
xelab -debug typical tb_cpu_top_simple -s test_snap
xsim test_snap -runall --testplusarg "MEM_FILE=test/hex/riscv-tests/rv32ui-p-add.hex"

# 回归
bash test/regress.sh base
```
