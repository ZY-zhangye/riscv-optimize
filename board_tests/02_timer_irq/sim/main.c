#include "../../platform/my_cpu_mmio.h"

/* ============================================================
 * CONFIGURABLE: Timer load value (simulation: short interval)
 * ============================================================ */
#define TIMER_LOAD_VALUE  100u   /* short interval for simulation */

/* ============================================================
 * Timer IRQ test (sim): fixed frame/border pattern on 4x8 matrix
 * 4 rows x 8 columns, bit0 = bottom-right (position 1)
 *
 * Row 0 (top, bits 24-31): 1 1 1 1 1 1 1 1 = 0xFF
 * Row 1 (bits 16-23):      1 0 0 0 0 0 0 1 = 0x81
 * Row 2 (bits  8-15):      1 0 0 0 0 0 0 1 = 0x81
 * Row 3 (bottom, bits 0-7):1 1 1 1 1 1 1 1 = 0xFF
 * ============================================================ */
#define LED_PATTERN  0xFF8181FFu

static volatile uint32_t g_irq_count;

/* ============================================================
 * Trap handler - placed in .trap section
 * Timer ISR: displays frame pattern and clears interrupt
 * ============================================================ */
__attribute__((interrupt("machine"), section(".trap")))
void trap_handler(void)
{
    uint32_t mcause;
    __asm__ volatile("csrr %0, 0x342" : "=r"(mcause));

    if (mcause == 0x8000000Bu) {   /* Machine external interrupt */
        uint32_t irq_id = plic_claim();

        if (irq_id == TIMER_INT_ID) {
            g_irq_count++;
            mmio_write32(LED_VALUE, LED_PATTERN);
            mmio_write32(TIMER_INTCLR, 1u);
        }

        plic_complete(irq_id);
    }
}

void main(void)
{
    g_irq_count = 0;
    mmio_write32(LED_VALUE, 0);

    /* ---- PLIC: enable timer interrupt (ID=1) ---- */
    plic_set_priority(TIMER_INT_ID, 1);
    plic_enable(1u << TIMER_INT_ID);
    mmio_write32(PLIC_THRESHOLD, 0);

    /* ---- Timer: periodic mode with interrupt ---- */
    mmio_write32(TIMER_LOAD, TIMER_LOAD_VALUE);
    mmio_write32(TIMER_CTRL,
        TIMER_CTRL_ENABLE | TIMER_CTRL_INT_ENABLE
        | TIMER_CTRL_MODE_PERIODIC | TIMER_CTRL_RELOAD);

    /* ---- Set machine trap vector ---- */
    __asm__ volatile("csrw 0x305, %0" :: "r"((uint32_t)trap_handler));

    /* ---- Enable machine external + global interrupts ---- */
    __asm__ volatile("csrs 0x304, %0" :: "r"(1u << 11));   /* MIE.MEIE */
    __asm__ volatile("csrs 0x300, %0" :: "r"(1u << 3));    /* MSTATUS.MIE */

    while (1) {
        __asm__ volatile("wfi");
    }
}
