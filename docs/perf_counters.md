# 性能计数器 CSR 使用说明

本设计在 CSR 模块中加入了一组 32 位性能计数器。标准 `cycle` / `instret` 持续计数；自定义性能计数器位于 RISC-V custom CSR 区间 `0x7C0` 起，可由软件清零、启动和停止。

## CSR 地址

| CSR 地址 | 名称 | 说明 |
| --- | --- | --- |
| `0xC00` | `cycle` | 上电后持续递增的周期计数 |
| `0xC02` | `instret` | 已退休指令数 |
| `0x7C0` | `perf_ctrl` | 性能计数器控制寄存器 |
| `0x7C1` | `perf_cycle` | 启用期间的周期数 |
| `0x7C2` | `perf_instret` | 启用期间的退休指令数 |
| `0x7C3` | `perf_branch` | 解析到的 branch/jump 指令数 |
| `0x7C4` | `perf_brmisp` | 分支/跳转预测错误重定向次数 |
| `0x7C5` | `perf_bphit` | 可预测跳转在 BTB 中命中的次数，不含 `JALR` |
| `0x7C6` | `perf_bpmiss` | 可预测跳转在 BTB 中未命中的次数，不含 `JALR` |
| `0x7C7` | `perf_loaduse` | load-use 冒险导致 ID 阶段停顿的周期数 |
| `0x7C8` | `perf_exstall` | EX 阶段多周期执行单元等待周期数 |
| `0x7C9` | `perf_exception` | trap/interrupt 进入次数，不含 `MRET` |

## 控制寄存器

`perf_ctrl` 位定义：

| 位 | 名称 | 说明 |
| --- | --- | --- |
| `[0]` | enable | `1` 时自定义性能计数器计数，`0` 时暂停 |
| `[1]` | clear | 写 `1` 时清零所有自定义性能计数器 |

常用写法：

```c
write_csr(0x7C0, 0x3); // 清零并启动
write_csr(0x7C0, 0x0); // 停止计数
write_csr(0x7C0, 0x2); // 清零并保持停止
write_csr(0x7C0, 0x1); // 启动但不清零
```

复位后 `perf_ctrl[0]` 默认为 `1`，自定义计数器默认开始计数。若需要精确测量某一段程序，建议在测试开始前写 `0x3` 清零并启动，测试结束后写 `0x0` 停止。

## C 语言读取模板

```c
#include <stdint.h>

#define read_csr(csr) ({            \
    uint32_t __v;                   \
    __asm__ volatile ("csrr %0, " #csr : "=r"(__v)); \
    __v;                            \
})

#define write_csr(csr, val) do {    \
    uint32_t __v = (uint32_t)(val); \
    __asm__ volatile ("csrw " #csr ", %0" :: "r"(__v)); \
} while (0)

#define CSR_PERF_CTRL      0x7C0
#define CSR_PERF_CYCLE     0x7C1
#define CSR_PERF_INSTRET   0x7C2
#define CSR_PERF_BRANCH    0x7C3
#define CSR_PERF_BRMISP    0x7C4
#define CSR_PERF_BPHIT     0x7C5
#define CSR_PERF_BPMISS    0x7C6
#define CSR_PERF_LOADUSE   0x7C7
#define CSR_PERF_EXSTALL   0x7C8
#define CSR_PERF_EXCEPTION 0x7C9
```

## 测量示例

```c
write_csr(0x7C0, 0x3);

/* 被测程序，例如 coremark_main(); */

write_csr(0x7C0, 0x0);

uint32_t cycles   = read_csr(0x7C1);
uint32_t instret  = read_csr(0x7C2);
uint32_t branches = read_csr(0x7C3);
uint32_t brmiss   = read_csr(0x7C4);
uint32_t bphit    = read_csr(0x7C5);
uint32_t bpmiss   = read_csr(0x7C6);
uint32_t loaduse  = read_csr(0x7C7);
uint32_t exstall  = read_csr(0x7C8);
```

可以进一步计算：

```c
double ipc = instret ? ((double)instret / (double)cycles) : 0.0;
double branch_miss_rate = branches ? ((double)brmiss / (double)branches) : 0.0;
double btb_hit_rate = (bphit + bpmiss) ? ((double)bphit / (double)(bphit + bpmiss)) : 0.0;
```

注意：所有自定义性能计数器均为 32 位，长时间运行可能回绕。CoreMark 当前运行规模下周期数低于 `2^32`，可以直接读取。
