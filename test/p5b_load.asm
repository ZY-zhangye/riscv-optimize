# P5b Test: Lane1 load after mul stall
# After mul stall, lane0 ALU + lane1 lw dual-issue.
# lw reads from dmem, result goes to x16.
# Test passes if pipeline reaches check point.

    addi x10, x0, 3           # x10=3
    addi x11, x0, 4           # x11=4
    # Store known value to dmem first (via lane0)
    lui  x13, 0x80001         # x13 = 0x80001000
    addi x14, x0, 0x55        # x14 = 0x55
    sw   x14, 0(x13)          # mem[0x80001000] = 0x55
    # Now stall with mul
    mul  x12, x10, x11        # 6-cycle stall → queue fills
    nop                        # padding
    nop                        # padding
    nop                        # padding
    addi x15, x0, 0            # lane0 ALU: x15=0
    lw   x16, 0(x13)          # lane1 load: x16 = mem[0x80001000] = 0x55
    # x16 should be 0x55 now
    nop
    nop
    nop
    nop
    nop
    addi x3, x0, 1            # x3=1 (PASS)
    nop
    nop                       # 80000044: CHECK POINT
