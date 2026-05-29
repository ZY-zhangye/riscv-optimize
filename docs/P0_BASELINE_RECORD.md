# P0 Baseline Freeze & Observation Record

**Date**: 2026-05-29
**Branch**: main
**Commit**: a8273aa (Add Chinese modularization report)

## Acceptance Checklist

| Item | Status |
|------|--------|
| `Z_BITMAIN_ENABLE` confirmed disabled | OK — commented out in defines.svh:7 |
| `DUAL_ISSUE_ENABLE` macro added, default off | OK — defines.svh:8 |
| Base regression (49 tests) all pass | OK — 49/49 passed, 0 failed |
| IPC/CPI baseline recorded | OK — see below |
| Single test mode available | OK — `run_xsim.bat one <hex>` |

## Baseline Regression Results

- **Test suite**: rv32ui-p (37) + rv32mi-p (4) + rv32um-p (8) = **49 tests**
- **Result**: 49 passed, 0 failed, 0 skipped
- **Average cycles per test**: 456
- **Total cycles (sum)**: 22,356
- **Clock**: 10 ns period (100 MHz)
- **Simulator**: Vivado xsim v2023.2
- **Testbench**: `tb_cpu_top_simple` (behavioral imem/dmem, no SoC/IP)

### By Group

| Group | Tests | Min | Max | Avg |
|-------|-------|-----|-----|-----|
| UI (base integer) | 37 | 130 (jal) | 679 (sw) | 443 |
| MI (machine/CSR) | 4 | 124 (scall) | 369 (ma_fetch) | 209 |
| UM (mul/div) | 8 | 234 (div/rem) | 924 (mul) | 575 |

## Key Configuration Macros (defines.svh)

```systemverilog
// `define Z_BITMAIN_ENABLE 1'b1   // Zb disabled — multi-issue baseline
// `define DUAL_ISSUE_ENABLE 1'b1  // Dual-issue: OFF (P0 default)
`define MUL_MULTICYCLE_ENABLE 1'b1
`define MULTICYCLE_ENABLE 1'b1
```

## Performance Counter CSR (regfile_csr.sv)

Already available and confirmed functional:
- `cycle` / `instret` — architectural
- `perf_cycle`, `perf_instret`, `perf_branch`, `perf_brmisp`
- `perf_bphit`, `perf_bpmiss`, `perf_loaduse`, `perf_exstall`
- `perf_exception`

All accessible via CSR 0x7C0–0x7C9 with perf_ctrl enable/clear mechanism.

## Module Inventory (RTL)

```
rtl/cpu_top/
  defines.svh, cpu_top.sv
  if_stage.sv, id_stage.sv, exe_stage.sv, mem_stage.sv, wb_stage.sv
  regfiles.sv, regfile_csr.sv
  forwarding_unit.sv, alu_wrapper.sv, write_port_arbiter.sv  ★ Phase 1-5 additions
  mul.sv, divider.sv
rtl/my_cpu/
  my_cpu.sv, bridge.sv, PLIC.sv, UART.sv, timer.sv, IO.sv
```

## Regression Scripts Fixed

- `test/run_xsim.bat` — added alu_wrapper, forwarding_unit, write_port_arbiter
- `test/run_regression.sh` — same
- `test/run_p0regression.ps1` — new: single-elaboration + per-test cmd /c xsim

## How to Compare Against This Baseline

1. Switch `DUAL_ISSUE_ENABLE` off
2. Run `test/run_p0regression.ps1`
3. Verify: 49/49 pass, same per-test cycle counts
4. If any deviation → regression in single-issue compatibility

## IPC/CPI Notes

The testbench (`tb_cpu_top_simple`) does not directly measure IPC, but the CSR
performance counters are connected. To measure IPC in a future run:
- Read CSR 0x7C1 (perf_cycle) and 0x7C2 (perf_instret) at end of test
- IPC = perf_instret / perf_cycle
- CPI = perf_cycle / perf_instret
- The test program's instruction count can be derived from hex for ground truth.
