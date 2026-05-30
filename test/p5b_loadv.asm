# P5b Load Verification v2: lane1 lw reads known value from dmem
# Fix: use full 32-bit value in lui, add NOPs for load completion

    addi x10, x0, 3           # mul inputs
    addi x11, x0, 4
    lui  x13, 0x80001         # Wrong: this gives 0x80000, not 0x80001000
    # Actually, I'll just use a direct addi to set addr
    # 0x80001000 doesn't fit in 12-bit imm. Use lui properly:
    # Let me skip lui and use direct addressing

    # Simpler: use a stack-like address near the data section
    # Use x13 = 0x100 (safe dmem addr)
    addi x13, x0, 0           # Start with x13=0
    # Actually just store to dmem[0] - first word
    addi x14, x0, 1           # x14 = 1 (pass value)
    # Store to dmem[0x100] = dmem[64] to avoid instruction conflict
    addi x13, x13, 256        # x13 = 0x100
    sw   x14, 0(x13)          # mem[0x100] = 1
    mul  x12, x10, x11        # 6-cycle stall
    nop                        # padding
    nop                        # padding
    nop                        # padding
    addi x15, x0, 0            # lane0 ALU
    lw   x16, 0(x13)          # lane1 LOAD: x16 = mem[0x100]
    nop                        # gap for load WB
    nop
    nop
    addi x3, x16, 0           # x3 = x16 (should be 1)
    nop
    nop                       # 80000044: CHECK POINT
