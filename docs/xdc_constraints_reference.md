# XDC Constraints Reference — JYD2025 Contest rv32i

> 芯片型号：请参考 `digital_twin.xpr` 工程设置
> 约束文件位置：`digital_twin.srcs/constrs_1/new/digital_twin.xdc`

---

## 一、管脚约束 (Pin Assignment)

### UART

| Port | Pin | IOSTANDARD | 备注 |
|------|-----|------------|------|
| `i_uart_rx` | D18 | LVCMOS33 | UART 接收 |
| `o_uart_tx` | D17 | LVCMOS33 | UART 发送 |

### 系统差分时钟

| Port | Pin | IOSTANDARD | 备注 |
|------|-----|------------|------|
| `i_sys_clk_p` | AD12 | DIFF_HSTL_II_18 | 200MHz 差分时钟 P 端 |
| `i_sys_clk_n` | AD11 | DIFF_HSTL_II_18 | 200MHz 差分时钟 N 端 |

### virtual_led[31:0] — LVCMOS18

| Bit | Pin | Bit | Pin | Bit | Pin | Bit | Pin |
|-----|-----|-----|-----|-----|-----|-----|-----|
| 31 | B27 | 30 | A27 | 29 | A26 | 28 | B25 |
| 27 | A25 | 26 | B24 | 25 | B23 | 24 | A23 |
| 23 | E30 | 22 | C30 | 21 | D28 | 20 | E26 |
| 19 | F25 | 18 | D23 | 17 | F23 | 16 | F12 |
| 15 | G28 | 14 | E28 | 13 | C29 | 12 | D26 |
| 11 | C25 | 10 | D24 | 9  | E23 | 8  | G23 |
| 7  | E29 | 6  | G25 | 5  | F26 | 4  | C26 |
| 3  | E25 | 2  | C24 | 1  | E24 | 0  | G24 |

**Tcl 代码：**

```tcl
set_property -dict {PACKAGE_PIN B27 IOSTANDARD LVCMOS18} [get_ports {virtual_led[31]}]
set_property -dict {PACKAGE_PIN A27 IOSTANDARD LVCMOS18} [get_ports {virtual_led[30]}]
# ... 其余类似，完整列表见工程 xdc 文件
```

### virtual_seg[39:0] — LVCMOS18

| Bit | Pin | Bit | Pin | Bit | Pin | Bit | Pin |
|-----|-----|-----|-----|-----|-----|-----|-----|
| 39 | AJ28 | 38 | AH30 | 37 | AK29 | 36 | AK28 |
| 35 | AK30 | 34 | AG30 | 33 | AE30 | 32 | AJ27 |
| 31 | AJ29 | 30 | AK26 | 29 | AH26 | 28 | AF28 |
| 27 | AF30 | 26 | AJ26 | 25 | AH27 | 24 | AF26 |
| 23 | AC26 | 22 | AF27 | 21 | AG27 | 20 | AG28 |
| 19 | K11  | 18 | J14  | 17 | G13  | 16 | F13 |
| 15 | H12  | 14 | J11  | 13 | L11  | 12 | J12 |
| 11 | H11  | 10 | J13  | 9  | L16  | 8  | L13 |
| 7  | K13  | 6  | L12  | 5  | K15  | 4  | K16 |
| 3  | J16  | 2  | H16  | 1  | L15  | 0  | K14 |

---

## 二、时钟约束

### PLL 自动生成约束 (pll.xdc)

```tcl
# 输入时钟 200MHz (5.0ns)，差分时钟仅约束 P 端
create_clock -period 5.000 [get_ports clk_in1_p]
set_input_jitter [get_clocks -of_objects [get_ports clk_in1_p]] 0.050
```

### 时钟域交叉约束

```tcl
# 两个 PLL 输出时钟设为异步组
set_clock_groups -asynchronous \
    -group [get_clocks -quiet {*clk_out1*}] \
    -group [get_clocks -quiet {*clk_out2*}]

# 双向 false path
set_false_path -from [get_clocks -quiet {*clk_out1*}] -to [get_clocks -quiet {*clk_out2*}]
set_false_path -from [get_clocks -quiet {*clk_out2*}] -to [get_clocks -quiet {*clk_out1*}]
```

---

## 三、被注释的预留约束

以下约束在工程中已被注释，可按需启用：

```tcl
#create_clock -name clk_out2_pll -period 5.714 -waveform {0 2.857} [get_ports clk_out2_pll]
#set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets -quiet clk_out2_pll]
#set_clock_uncertainty -setup 0.12 [get_clocks clk_out2_pll]
#set_clock_uncertainty -hold 0.08 [get_clocks clk_out2_pll]
#set_property MAX_FANOUT 16 [get_nets -quiet -hierarchical *]
```

---

## 四、约束完整性检查清单

在新建工程时，确认以下项：

- [ ] Pin 约束 — UART / 时钟 / LED / SEG 管脚和电平标准
- [ ] `create_clock` — 输入时钟周期（200MHz, 5.0ns），差分时钟仅约束 P 端
- [ ] `set_input_jitter` — PLL 输入抖动
- [ ] `set_clock_groups` — 异步时钟分组
- [ ] `set_false_path` — 跨异步时钟域路径
- [ ] **待补充** `set_input_delay` / `set_output_delay` — UART、LED、SEG 的 I/O 时序
- [ ] **待补充** `set_clock_uncertainty` — 如 PLL 抖动未覆盖全部场景
- [ ] **待补充** `set_max_delay` / `set_min_delay` — 关键组合逻辑路径
