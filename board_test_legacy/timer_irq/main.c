#include "../my_cpu_mmio.h"

/* ============================================================
 * CONFIGURABLE: Timer load value (simulation: short interval)
 * ============================================================ */
#define TIMER_LOAD_VALUE  35000000u   /* ~0.2s per shift @ 175MHz */

static volatile uint32_t g_led_pattern;
static volatile int      g_shift_left;
static volatile uint32_t g_irq_count;

/* ============================================================
 * Trap handler - placed in .trap section
 * Reads interrupt ID from PLIC, matches against TIMER_INT_ID,
 * then shifts LED and clears the interrupt.
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

            /* Shift LED pattern (bouncing left/right) */
            if (g_led_pattern == 0) {
                g_led_pattern = 0x00000001u;
            } else if (g_shift_left) {
                g_led_pattern <<= 1;
                if (g_led_pattern & 0x80000000u)
                    g_shift_left = 0;
            } else {
                g_led_pattern >>= 1;
                if (g_led_pattern & 0x00000001u)
                    g_shift_left = 1;
            }

            mmio_write32(LED_VALUE, g_led_pattern);
            mmio_write32(TIMER_INTCLR, 1u);
        }

        plic_complete(irq_id);
    }
}

void main(void)
{
    g_led_pattern = 0;
    g_shift_left  = 1;
    g_irq_count   = 0;

    mmio_write32(LED_VALUE, 0);

    /* ---- PLIC: enable timer interrupt (ID=1) ---- */
    plic_set_priority(TIMER_INT_ID, 1);
    plic_enable(1u << TIMER_INT_ID);
    mmio_write32(PLIC_THRESHOLD, 0);

    /* ---- Timer: periodic mode with interrupt ---- */
    mmio_write32(TIMER_LOAD, TIMER_LOAD_VALUE);
    mmio_write32(TIMER_CTRL,
        TIMER_CTRL_ENABLE | TIMER_CTRL_INT_ENABLE | TIMER_CTRL_MODE_PERIODIC);

    /* ---- Set machine trap vector ---- */
    __asm__ volatile("csrw 0x305, %0" :: "r"((uint32_t)trap_handler));

    /* ---- Enable machine external + global interrupts ---- */
    __asm__ volatile("csrs 0x304, %0" :: "r"(1u << 11));   /* MIE.MEIE */
    __asm__ volatile("csrs 0x300, %0" :: "r"(1u << 3));    /* MSTATUS.MIE */

    while (1) {
        __asm__ volatile("wfi");
    }
}
