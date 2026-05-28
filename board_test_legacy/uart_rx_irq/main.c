#include "../my_cpu_mmio.h"

/* ============================================================
 * CONFIGURABLE: Baud rate divisor
 * 115200 @ 175MHz -> BAUD_DIV = 1519
 * ============================================================ */
#define BAUD_DIV  1519u

static volatile uint32_t g_rx_count;   /* Total bytes received */

/* ============================================================
 * Trap handler - UART RX interrupt (PLIC ID = 2).
 * Reads received byte and echoes it back via polling TX.
 * ============================================================ */
__attribute__((interrupt("machine"), section(".trap")))
void trap_handler(void)
{
    uint32_t mcause;
    __asm__ volatile("csrr %0, 0x342" : "=r"(mcause));

    if (mcause == 0x8000000Bu) {            /* Machine external interrupt */
        uint32_t irq_id = plic_claim();

        if (irq_id == UART_RX_INT_ID) {
            uint32_t ch = mmio_read32(UART_DATA);
            g_rx_count++;

            /* Echo back: wait until TX not full, then send */
            while (mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) {}
            mmio_write32(UART_DATA, ch);

            /* Show rx_count on LED for visual feedback */
            mmio_write32(LED_VALUE, g_rx_count);
        }

        plic_complete(irq_id);
    }
}

void main(void)
{
    g_rx_count = 0;
    mmio_write32(LED_VALUE, 0);

    /* ---- UART: enable with baud rate, then add RX interrupt ---- */
    uart_enable_polling(BAUD_DIV);
    mmio_write32(UART_CTRL,
        UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON | UART_CTRL_RX_INT_EN);

    /* ---- PLIC: enable UART RX interrupt (ID=2) ---- */
    plic_set_priority(UART_RX_INT_ID, 1);
    plic_enable(1u << UART_RX_INT_ID);
    mmio_write32(PLIC_THRESHOLD, 0);

    /* ---- Set machine trap vector ---- */
    __asm__ volatile("csrw 0x305, %0" :: "r"((uint32_t)trap_handler));

    /* ---- Enable machine external + global interrupts ---- */
    __asm__ volatile("csrs 0x304, %0" :: "r"(1u << 11));   /* MIE.MEIE */
    __asm__ volatile("csrs 0x300, %0" :: "r"(1u << 3));    /* MSTATUS.MIE */

    while (1) {
        __asm__ volatile("wfi");
    }
}
