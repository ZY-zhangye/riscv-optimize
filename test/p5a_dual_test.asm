# P5a Dual-Issue Verification: mul stall + ALU+branch pair
# Mul takes 6 cycles, during which IF fills the queue.
# After the stall, instructions pair: ALU(lane0) + branch(lane1).

    # Setup for mul
    addi x10, x0, 3           # x10=3
    addi x11, x0, 4           # x11=4
    mul  x12, x10, x11        # x12=12 (6-cycle stall — queue fills)

    # After stall, queue has these ready:
    # 8000000C: addi x5, x0, 1    (writes x5 → lane0 OK)
    # 80000010: beq  x0, x0, skip  (branch → lane1 OK, no write → single_writer OK)
    # 80000014: addi x6, x0, 1    (skipped if redirect)
    # 80000018: nop                (skipped)
    addi x5, x0, 1
    beq  x0, x0, skip          # TAKEN → lane1 redirect
    addi x6, x0, 1             # SKIPPED
    nop                        # SKIPPED
skip:
    addi x7, x5, 0             # x7=x5=1
    addi x8, x6, 0             # x8=x6=0
    nop
    nop
    nop
    nop
    nop
    addi x3, x0, 1
    nop
    nop
    jal  x0, -4
