# P5a Test 1: Lane0 ALU + Lane1 non-taken branch
# Pair: lane0=addi x5,1  lane1=bne x0,x1,skip (NT)
# Tests: lane1 executes non-taken branch, fall-through lane0 ALU executes

    addi x5, x0, 1           # 80000000: lane0 ALU: x5 = 1
    bne  x0, x1, skip         # 80000004: lane1 BR: x0!=x1? NT → fall-through
    addi x6, x0, 1           # 80000008: lane0 ALU: x6 = 1 (must execute)
    nop                      # 8000000C: padding
skip:                        # 80000010
    addi x7, x5, 0           # 80000010: x7 = x5
    addi x8, x6, 0           # 80000014: x8 = x6
    nop                      # 80000018
    nop                      # 8000001C
    nop                      # 80000020
    nop                      # 80000024
    nop                      # 80000028
    nop                      # 8000002C
    nop                      # 80000030
    nop                      # 80000034
    nop                      # 80000038
    addi x3, x0, 1           # 8000003C: write x3=1 (WB before 0x44)
    nop                      # 80000040: padding
    nop                      # 80000044: CHECK POINT — x3 already 1
    jal  x0, -4               # 80000048: infinite loop
