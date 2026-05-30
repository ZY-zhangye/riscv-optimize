# P5a Verification: Force dual-issue via mul stall
# mul takes 6 cycles (MUL_CYCLE). During the stall, IF keeps pushing
# to the instr queue. After stall: queue has >=2 entries → dual-issue.
#
# This verifies that the lane1 branch execution actually fires
# when dual-issue conditions are met.

    addi x10, x0, 3          # x10 = 3
    addi x11, x0, 4          # x11 = 4
    # mul x12, x10, x11 — 6-cycle stall — queue fills
    mul  x12, x10, x11       # x12 = 12 (MULTICYCLE STALL → queue buffers)
    # After stall: queue full → dual-issue these pairs:
    addi x13, x0, 1          # lane0: x13 = 1
    addi x14, x0, 2          # lane1: x14 = 2
    addi x15, x0, 3          # lane0/lane1: x15 = 3
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    addi x3, x0, 1           # 8000003C: x3 = 1
    nop                      # 80000040
    nop                      # 80000044: CHECK POINT
    jal  x0, -4               # 80000048: loop
