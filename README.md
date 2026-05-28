# riscv-optimize

A RISC-V 32-bit soft processor implemented in SystemVerilog, targeting the Xilinx Kintex-7 FPGA (xc7k325tffg900-2).

## Architecture

- **5-stage pipeline**: IF → ID → EXE → MEM → WB
- **ISA**: RV32IM + Zicsr + Zifencei
- **Bit-manipulation extensions**: Zba, Zbb, Zbc, Zbs (Zbkb, Zbkx)
- **Floating-point**: Zfh (half), F (single), D (double) — via FPU coprocessor
- **Multi-cycle ops**: Hardware multiplier (6-cycle) and divider
- **Branch prediction**: Configurable branch predictor with performance counters
- **CSR**: Full machine-mode CSR support including performance monitoring counters
- **Interrupts**: PLIC-based with Timer and UART IRQ support

## Block Diagram

```
┌─────────────────────────────────────────────────────┐
│  my_cpu (SoC Top)                                    │
│  ┌──────────┐  ┌──────┐  ┌──────┐  ┌─────────────┐ │
│  │ cpu_top  │  │ PLIC │  │UART  │  │Timer        │ │
│  │ (Core)   │  │      │  │      │  │             │ │
│  │          │  │      │  │      │  │             │ │
│  │ IF→ID→   │  │      │  └──┬───┘  └──────┬──────┘ │
│  │ EXE→MEM  │  │      │     │             │        │
│  │ →WB      │  │      │     │             │        │
│  └──────────┘  └──┬───┘     │             │        │
│                   │         │             │        │
│  ┌────────────────┴─────────┴─────────────┴───────┐ │
│  │              Bridge / MMIO Bus                  │ │
│  └────────────────────────────────────────────────┘ │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │
│  │ LEDs │  │  SW  │  │ Keys │  │ 7Seg │  │ Cnt  │ │
│  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘ │
└─────────────────────────────────────────────────────┘
```

## Peripherals

| Peripheral | Base Address   | Description          |
|------------|---------------|----------------------|
| UART       | `0x8001_0000` | TX/RX with IRQ       |
| Timer      | `0x8002_0000` | Configurable timer   |
| LEDs       | `0x8003_0000` | GPIO LED output      |
| PLIC       | `0x8030_0000` | Platform-level intc  |

## Project Structure

```
rtl/
  cpu_top/     — CPU pipeline (IF, ID, EXE, MEM, WB), FPU, CSR, divider, multiplier
  my_cpu/      — SoC top, PLIC, UART, Timer, bridge, IO
constraints/   — XDC pin/clock constraints
ip/            — Xilinx IP cores (PLL, multiplier, divider)
board_tests/   — FPGA board test programs (LED, Timer IRQ, UART, CoreMark)
test/          — Simulation testbenches, hex images, RISC-V compliance tests
docs/          — Performance counters, XDC reference, memory tools
scripts/       — Vivado project creation, COE/hex helpers
```

## Quick Start (Vivado)

```tcl
# Source the project creation script from a new directory
source scripts/create_vivado_project.tcl
```

Or manually in the Vivado Tcl console:

```tcl
set origin_dir [file normalize [pwd]]
set_property target_language SystemVerilog [current_project]

add_files -norecurse [glob -nocomplain "$origin_dir/rtl/cpu_top/*.sv" "$origin_dir/rtl/cpu_top/*.svh"]
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/my_cpu/*.sv" "$origin_dir/rtl/my_cpu/*.svh"]
set_property include_dirs [list "$origin_dir/rtl/cpu_top" "$origin_dir/rtl/my_cpu"] [current_fileset]

add_files -fileset constrs_1 "$origin_dir/constraints/my_cpu.xdc"
add_files -norecurse [glob -nocomplain "$origin_dir/ip/*.xci"]
set_property top my_cpu [current_fileset]
update_compile_order -fileset sources_1
```

## Running Tests

### Simulation

```bat
cd test
run_xsim.bat          # Run with XSim
run_all.bat           # Run all test cases
```

### RISC-V Compliance Tests

Pre-built hex images for RV32I/M/A/F/D/C + Zba/Zbb/Zbc/Zbs/Zbkb/Zbkx/Zfh are in `test/hex/riscv-tests/`.

### CoreMark

Source under `board_tests/05_coremark/src/`, pre-built output in `board_tests/05_coremark/output/`.

## Configurable Options

Edit `rtl/cpu_top/defines.svh`:

| Define                  | Default | Description              |
|-------------------------|---------|--------------------------|
| `MUL_MULTICYCLE_ENABLE` | `1`     | Multi-cycle multiplier   |
| `MULTICYCLE_ENABLE`     | `1`     | Multi-cycle divider      |
| `Z_BITMAIN_ENABLE`      | `1`     | Zb* bit-manip extensions |
| `DEBUG_EN`              | comment | Debug port enable        |
| `PERF_BENCH`            | comment | Benchmark boot mode      |

## Memory Update Flow

See `docs/mem_tools/README.md` for updating instruction/data memory via `.coe` or `.hex` files without re-synthesizing the design.
