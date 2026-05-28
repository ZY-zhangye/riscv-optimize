#include "my_cpu_mmio.h"

/* ============================================================
 * CONFIGURABLE: Set the counter maximum value here
 * ============================================================ */
#define COUNTER_MAX  3500000u   /* ~0.2s per LED shift @ 175MHz */

/* ============================================================
 * Self-increment counter (global, visible in debug/elf)
 * ============================================================ */
static volatile uint32_t g_counter;       /* <-- SELF-INCREMENT COUNTER */
static volatile uint32_t g_led_pattern;   /* Current LED output */
static volatile int      g_shift_left;    /* 1 = left, 0 = right */
static volatile uint32_t g_round;         /* Number of max-hits */

void main(void)
{
    g_counter     = 0;
    g_led_pattern = 0x00000000u;   /* LED = 0 means all off */
    g_shift_left  = 1;
    g_round       = 0;

    mmio_write32(LED_VALUE, 0x00000000u);   /* Reset LED to off */

    while (1) {
        /* ====================================================
         * >>> SELF-INCREMENT COUNTER <<<
         * Increments each loop iteration.
         * When it reaches COUNTER_MAX, LED shifts and counter resets.
         * ==================================================== */
        g_counter++;

        if (g_counter >= COUNTER_MAX) {
            g_counter = 0;      /* Reset counter */
            g_round++;

            if (g_led_pattern == 0x00000000u) {
                /* First shift: light up bit 0 */
                g_led_pattern = 0x00000001u;
            } else if (g_shift_left) {
                g_led_pattern <<= 1;
                if (g_led_pattern & 0x80000000u) {
                    g_shift_left = 0;   /* Reverse: now shift right */
                }
            } else {
                g_led_pattern >>= 1;
                if (g_led_pattern & 0x00000001u) {
                    g_shift_left = 1;   /* Reverse: now shift left */
                }
            }
        }

        mmio_write32(LED_VALUE, g_led_pattern);
    }
}
