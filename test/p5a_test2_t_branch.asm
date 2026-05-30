# P5a Test 2: Lane0 ALU + Lane1 taken branch (redirect)
# Pair: lane0=addi x5,1  lane1=beq x0,x0,skip (TAKEN → redirect)
# Tests: lane1 redirect, lane0 ALU result valid, instructions after branch skipped

    addi x5, x0, 1           # 80000000: lane0 ALU: x5 = 1
    beq  x0, x0, skip         # 80000004: lane1 BR: x0==x0 → TAKEN → redirect
    addi x6, x0, 1           # 80000008: SKIPPED (x6 stays 0)
    nop                      # 8000000C: SKIPPED
skip:                        # 80000010
    addi x7, x5, 0           # 80000010: x7 = x5 (=1)
    addi x8, x6, 0           # 80000014: x8 = x6 (=0, confirms skipped)
    nop                      # 80000018
    nop                      # 8000001C
    nop                      # 80000020
    nop                      # 80000024
    nop                      # 80000028
    nop                      # 8000002C
    nop                      # 80000030
    nop                      # 80000034
    nop                      # 80000038
    addi x3, x0, 1           # 8000003C: write x3=1
    nop                      # 80000040
    nop                      # 80000044: CHECK POINT
    jal  x0, -4               # 80000048: loop
