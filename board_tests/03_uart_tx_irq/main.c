#include "../platform/my_cpu_mmio.h"

/* ============================================================
 * CONFIGURABLE: Baud rate divisor
 * baud = clock / BAUD_DIV
 * 115200 @ 175MHz -> BAUD_DIV = 1519
 * ============================================================ */
#define BAUD_DIV  1519u

static const char g_msg[] = "UART IRQ TEST PASSED!\n";

/* ---- Pointer into g_msg (volatile, accessed from ISR) ---- */
static volatile int g_tx_idx;
static volatile int g_tx_done;

/* ============================================================
 * Trap handler - placed in .trap section
 * Handles UART TX interrupt (PLIC ID = 3).
 * Sends next character on each interrupt until string end.
 * ============================================================ */
__attribute__((interrupt("machine"), section(".trap")))
void trap_handler(void)
{
    uint32_t mcause;
    __asm__ volatile("csrr %0, 0x342" : "=r"(mcause));

    if (mcause == 0x8000000Bu) {            /* Machine external interrupt */
        uint32_t irq_id = plic_claim();

        if (irq_id == UART_TX_INT_ID) {
            char ch = g_msg[g_tx_idx];

            if (ch != '\0') {
                /* Wait until TX not full, then send next byte */
                while (mmio_read32(UART_STATUS) & UART_STATUS_TX_FULL) {}
                mmio_write32(UART_DATA, (uint32_t)(uint8_t)ch);
                g_tx_idx++;
            } else {
                /* All bytes sent: disable TX interrupt, signal done */
                mmio_write32(UART_CTRL,
                    UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON);
                g_tx_done = 1;
            }
        }

        plic_complete(irq_id);
    }
}

void main(void)
{
    g_tx_idx = 0;
    g_tx_done = 0;

    /* ---- Initial LED = OFF ---- */
    mmio_write32(LED_VALUE, 0x00000000u);

    /* ---- UART init: enable with baud rate, then add TX interrupt ---- */
    uart_enable_polling(BAUD_DIV);
    mmio_write32(UART_CTRL,
        UART_CTRL_UART_EN | UART_CTRL_BOUNDARY_ON | UART_CTRL_TX_INT_EN);

    /* ---- PLIC: enable UART TX interrupt (ID=3) ---- */
    plic_set_priority(UART_TX_INT_ID, 1);
    plic_enable(1u << UART_TX_INT_ID);
    mmio_write32(PLIC_THRESHOLD, 0);

    /* ---- Set machine trap vector ---- */
    __asm__ volatile("csrw 0x305, %0" :: "r"((uint32_t)trap_handler));

    /* ---- Enable machine external + global interrupts ---- */
    __asm__ volatile("csrs 0x304, %0" :: "r"(1u << 11));   /* MIE.MEIE */
    __asm__ volatile("csrs 0x300, %0" :: "r"(1u << 3));    /* MSTATUS.MIE */

    /* ---- Kick off: send first character via interrupt chain ---- */
    mmio_write32(UART_DATA, (uint32_t)(uint8_t)g_msg[0]);
    g_tx_idx = 1;

    /* ---- Wait for all bytes to be sent ---- */
    while (!g_tx_done) {
        __asm__ volatile("wfi");
    }

    /* ---- Done: light all LEDs ---- */
    mmio_write32(LED_VALUE, 0xFFFFFFFFu);

    while (1) {
        __asm__ volatile("wfi");
    }
}
