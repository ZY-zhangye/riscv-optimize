# RISC-V Core Superscalar Roadmap

本文档目录只做规划，不修改 RTL。目标是把当前单发射 5 级流水线，逐步推进到受限双发射、完整顺序双发射，并给出继续走向乱序执行的可实施路线。

规划遵循三个原则：

1. 每个阶段都必须能独立编译、仿真、回归。
2. 每次只扩大一个架构维度，例如先扩大取指，再扩大译码，再扩大执行，再扩大提交。
3. 所有阶段都保留可退回的单发射模式，确保调试时可以快速定位是双发射逻辑问题还是原有流水线问题。

## 当前基线

当前工程主体：

- `rtl/cpu_top/if_stage.sv`: 单 PC、单 32-bit 指令取指、带 64 项 bimodal 分支预测。
- `rtl/cpu_top/id_stage.sv`: 单指令译码、寄存器堆读地址输出、冒险检测、前递选择生成。
- `rtl/cpu_top/exe_stage.sv`: 单执行通道，已抽出 `forwarding_unit` 和 `alu_wrapper`。
- `rtl/cpu_top/mem_stage.sv`: 单访存通道，处理 load 扩展、异常、中断、CSR 写。
- `rtl/cpu_top/wb_stage.sv`: 单写回通道，已接入 `write_port_arbiter`，但第二写口尚未真正使用。
- `rtl/cpu_top/regfiles.sv`: 2 读 1 写、组合读。
- `rtl/cpu_top/defines.svh`: 当前 Z-bitman 关闭，适合作为多发射基线。

关键现状：

- 级间总线仍是单通道 packed bus。
- 流水握手是 `valid/allowin` 单槽位协议。
- 指令存储器接口只有一组 `imem_addr/imem_en/imem_rdata`。
- 数据存储器接口只有一组 `dmem_addr/dmem_en/dmem_wen/dmem_wdata/dmem_rdata`。
- 精确异常、中断、CSR 更新都假设一次只有一条指令处在同一流水级。

## 总体路线

推荐路线分 9 个大阶段：

| 阶段 | 名称 | 目标 | 性能形态 | 风险 |
|---|---|---|---|---|
| P0 | 基线冻结与观测 | 固定可回归基线，补齐度量 | 单发射 | 低 |
| P1 | 双发射前置抽象 | 把单槽位逻辑包装成 lane-ready 结构 | 单发射 | 低 |
| P2 | 双取指与指令队列 | 前端一次拿两条，但后端仍单发射 | 单发射，可观测 fetch2 | 中 |
| P3 | 双译码与寄存器读扩展 | 能同时译码两条，仍只发射一条 | 单发射，可 shadow lane1 | 中 |
| P4 | 受限双发射 | lane0 任意旧指令，lane1 只发简单 ALU 类 | 部分双发射 | 中高 |
| P5 | 完整顺序双发射 | 两条指令按序发射、执行、提交 | 2-wide in-order | 高 |
| P6 | 性能完善 | 分支、访存、多周期单元、CSR 的双发射优化 | 稳定 2-wide | 高 |
| P7 | 乱序前置 | ROB、重命名、提交框架，执行仍近似顺序 | OoO shell | 很高 |
| P8 | 真正乱序 | 保留站、发射队列、LSQ、物理寄存器堆 | OoO superscalar | 极高 |

不要从 P0 直接跳到 P5 或 P8。最容易成功的路径是每阶段只改一组接口，并让旧单发射路径继续存在。

## 推荐执行节奏

每个阶段都按下面节奏执行：

1. 新建 feature 分支或明确当前工作区改动。
2. 只实现该阶段的最小目标。
3. 跑至少 `test/run_xsim.bat base` 或同等 base 回归。
4. 增加该阶段的定向测试。
5. 写阶段总结，记录 IPC、失败案例、仍禁用的 pairing 规则。
6. 只有阶段验收通过后，进入下一阶段。

## 总架构目标图

受限双发射目标：

```text
fetch2 -> instr_queue -> decode0/decode1 -> issue_select
                                      lane0 -> EX/MEM/WB existing path
                                      lane1 -> simple ALU lane -> WB/commit serialize
```

完整顺序双发射目标：

```text
fetch2 -> align/predict -> queue -> decode2 -> hazard_pair
                 -> issue lane0 -> exe0 -> mem0 -> wb0
                 -> issue lane1 -> exe1 -> mem1 -> wb1
                                      -> in-order commit/exception arbiter
```

乱序目标：

```text
fetch/decode -> rename -> dispatch -> issue queues -> FU/LSU -> writeback
                                            -> ROB in-order commit
```

## 目录说明

- `phase_plan.md`: 每个阶段的详细实施步骤和验收门禁。
- `verification_plan.md`: 定向测试、回归、性能计数器、波形检查建议。
- `handoff_prompts.md`: 给后续 AI 的分阶段执行提示词。

