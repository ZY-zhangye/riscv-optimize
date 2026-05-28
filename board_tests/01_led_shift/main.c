#include "../platform/my_cpu_mmio.h"

/* ============================================================
 * LED test: fixed checkerboard pattern on 4x8 matrix
 * 4 rows x 8 columns, bit0 = bottom-right (position 1)
 * Each row right-to-left: bit0 = rightmost, bit7 = leftmost
 *
 * Row 0 (top, bits 24-31): 1 0 1 0 1 0 1 0 = 0xAA
 * Row 1 (bits 16-23):      0 1 0 1 0 1 0 1 = 0x55
 * Row 2 (bits  8-15):      1 0 1 0 1 0 1 0 = 0xAA
 * Row 3 (bottom, bits 0-7):0 1 0 1 0 1 0 1 = 0x55
 * ============================================================ */
#define LED_PATTERN  0xAA55AA55u

void main(void)
{
    mmio_write32(LED_VALUE, LED_PATTERN);

    while (1) {
        __asm__ volatile("wfi");
    }
}
