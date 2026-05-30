# P5a Test 3: Lane0 taken branch → Lane1 squash
# Pair: lane0=beq x0,x0,skip (TAKEN)  lane1=addi x5,1 (SQUASHED)
# Tests: lane0 redirect squashes lane1

    beq  x0, x0, skip         # 80000000: lane0 BR: x0==x0 → TAKEN → squash lane1
    addi x5, x0, 1           # 80000004: lane1: SQUASHED (x5 stays 0)
    addi x5, x0, 2           # 80000008: SKIPPED
    nop                      # 8000000C: SKIPPED
skip:                        # 80000010
    addi x6, x0, 1           # 80000010: x6 = 1
    addi x7, x5, 0           # 80000014: x7 = x5 (=0, confirms squashed)
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
