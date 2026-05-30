# P5a Verification: Dual-issue ALU+non-taken-BR after mul stall
# lane0=addi x5,1 + lane1=bne (NT) → lane1 REDIRECT NOT expected
# Linear flow to CHECK POINT, no redirect loop

    addi x10, x0, 3           # 80000000
    addi x11, x0, 4           # 80000004
    mul  x12, x10, x11        # 80000008: 6-cycle stall
    nop                        # 8000000C: padding
    nop                        # 80000010: padding
    nop                        # 80000014: padding
    addi x5, x0, 1            # 80000018: lane0 ALU (x5=1)
    bne  x0, x1, skip          # 8000001C: lane1 BR: x0!=x1→F, NOT taken
    addi x6, x0, 1            # 80000020: EXECUTED (x6=1)
    nop                        # 80000024
skip:
    addi x7, x5, 1            # 80000028: x7=2
    addi x8, x6, 1            # 8000002C: x8=2
    nop                        # 80000030
    nop                        # 80000034
    nop                        # 80000038
    addi x3, x0, 1            # 8000003C: x3=1 (PASS)
    nop                        # 80000040
    nop                        # 80000044: CHECK POINT
