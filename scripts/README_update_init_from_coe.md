# COE 初始化文件替换脚本使用说明

脚本位置：

```text
project2\update_init_from_coe.bat
```

该脚本用于将 `.coe` 或 `.hex` 初始化文件转换成工程可用的 `.mem` 文件，并生成带有新初始化内容的 bitstream。

当前脚本默认使用 `UPDATE_METHOD=auto`：

- `TARGET_MEMORY=inst`：使用较快的 `updatemem` 替换指令 ROM。
- `TARGET_MEMORY=data` 或 `TARGET_MEMORY=both`：如果当前工程已经生成 word-chunk data RAM 的 MMI，则直接快速替换；如果还没有，则自动执行一次重建来生成快速替换底板。

## 1. 修改脚本配置

打开 `update_init_from_coe.bat`，修改顶部 `USER EDIT AREA` 中带 `[EDIT]` 标注的位置。

### `[EDIT 1]` 源初始化文件

```bat
set "SOURCE_INST_COE=F:\graduation_project\project2\program.coe"
set "SOURCE_DATA_COE=F:\graduation_project\project2\data.coe"
```

- `SOURCE_INST_COE`：指令 ROM 的 `.coe` 或 `.hex` 文件。
- `SOURCE_DATA_COE`：数据 RAM 的 `.coe` 或 `.hex` 文件。

### `[EDIT 2]` 基础 bit 和 MMI

```bat
set "BASE_BIT=%~dp0project-vivado\my_cpu_fast_update_base.bit"
set "MMI_FILE=%~dp0project-vivado\riscv-graduation.runs\impl_1\my_cpu.mmi"
```

`BASE_BIT` 和 `MMI_FILE` 必须来自同一次 Vivado 实现结果，否则 `updatemem` 可能无法正确定位 BRAM。

`my_cpu_fast_update_base.bit` 会在第一次 `rebuild` 成功后自动生成；后续日常替换 COE 时直接复用它。

### `[EDIT 3]` 输出 bit 文件位置和名称

```bat
set "OUTPUT_BIT_DIR=%~dp0project-vivado"
set "OUTPUT_BIT_NAME=my_cpu_updated_from_coe.bit"
```

生成的最终 bitstream 路径为：

```text
%OUTPUT_BIT_DIR%\%OUTPUT_BIT_NAME%
```

### `[EDIT 4]` 替换目标

```bat
set "TARGET_MEMORY=inst"
```

可选值：

```text
inst  只替换指令 ROM
data  只替换数据 RAM
both  同时替换指令 ROM 和数据 RAM
```

### `[EDIT 5]` 更新方式

```bat
set "UPDATE_METHOD=auto"
```

可选值：

```text
auto       推荐。能快速替换时用 updatemem；缺少 byte-bank base 时自动 rebuild 一次。
updatemem 只用 Vivado updatemem 快速替换；要求 BASE_BIT/MMI 已匹配当前布局。
rebuild   重新综合/实现并生成 bit，同时刷新 my_cpu_fast_update_base.bit。
```

注意：旧版 data RAM 的 MMI/BRAM 分片布局是 1-bit lane，`updatemem` 可能报告成功但板上初始化不正确。当前 RTL 已将 data RAM 拆成 16 个 4096x32 word chunk；完成一次 `rebuild` 后，`auto` 会检测到新的 word-chunk MMI 并走快速替换。

### `[EDIT 6 optional]` Vivado 路径

如果命令行中无法直接调用 `vivado`，取消注释并修改：

```bat
rem set "VIVADO_BIN=F:\Xilinx\Vivado\2023.2\bin\vivado.bat"
rem set "UPDATEMEM_BIN=F:\Xilinx\Vivado\2023.2\bin\updatemem.bat"
```

## 2. 常用运行方式

在 `project2` 目录下运行：

```bat
update_init_from_coe.bat
```

或者在任意目录运行完整路径：

```bat
F:\graduation_project\project2\update_init_from_coe.bat
```

## 3. 同时替换 inst 和 data

在脚本顶部设置：

```bat
set "TARGET_MEMORY=both"
set "UPDATE_METHOD=auto"
```

执行流程为：

```text
SOURCE_INST_COE -> inst .mem
SOURCE_DATA_COE -> data .mem + data_chunk00..15 .mem
如果 MMI 已是 byte-bank 布局：
  updatemem 更新 inst ROM
  updatemem 依次更新 data chunk 0..15
否则：
  设置 Vivado fileset generic: INST_MEM_FILE / DATA_MEM_FILE_0..3
  重新运行 synth_1 / impl_1 到 write_bitstream
  复制生成的 my_cpu.bit 到 OUTPUT_BIT_DIR\OUTPUT_BIT_NAME
  同时生成 my_cpu_fast_update_base.bit
```

脚本内部使用的 Tcl 为：

```text
project2\docs\mem_tools\rebuild_bitstream_with_mem.tcl
```

## 4. 命令行临时覆盖

只临时指定指令 COE：

```bat
update_init_from_coe.bat inst.coe
```

指定指令 COE 和输出 bit：

```bat
update_init_from_coe.bat inst.coe output.bit
```

同时指定指令 COE、输出 bit、基础 bit、MMI、数据 COE：

```bat
update_init_from_coe.bat inst.coe output.bit base.bit my_cpu.mmi data.coe
```

注意：命令行第 5 个参数 `data.coe` 只有在脚本中 `TARGET_MEMORY=data` 或 `TARGET_MEMORY=both` 时才会被使用。

## 5. 生成文件

脚本会生成：

```text
project2\build\mem_update\*.mem
project2\project-vivado\uart_tx_irq.bit
project2\project-vivado\my_cpu_fast_update_base.bit
```

其中 `.mem` 是中间转换文件，最终烧录/替换使用 `OUTPUT_BIT_NAME` 指定的 `.bit` 文件。`my_cpu_fast_update_base.bit` 是以后快速替换时使用的基础 bitstream。

如果走 `rebuild` 流程，还会生成时序摘要：

```text
project2\project-vivado\riscv-graduation.runs\impl_1\my_cpu_timing_summary_rebuild_with_mem.rpt
```
