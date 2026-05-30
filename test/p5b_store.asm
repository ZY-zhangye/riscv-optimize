# P5b Test: Lane1 store via mul stall
# After mul stall, lane0 ALU + lane1 store dual-issue.
# Store writes 0x42 to dmem[0x100]; test passes if pipeline OK.

    addi x10, x0, 3           # x10=3
    addi x11, x0, 4           # x11=4
    lui  x13, 0x80001         # x13 = 0x80001000
    addi x14, x0, 0x42        # x14 = 0x42 (value to store)
    mul  x12, x10, x11        # 6-cycle stall → queue fills
    nop                        # padding
    nop                        # padding
    nop                        # padding
    addi x15, x0, 0            # lane0 ALU: x15=0
    sw   x14, 0(x13)          # lane1 store: mem[0x80001000]=0x42
    nop
    nop
    nop
    nop
    nop
    nop
    addi x3, x0, 1            # x3=1 (PASS)
    nop
    nop                       # 80000044: CHECK POINT
