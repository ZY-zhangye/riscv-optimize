# P5a Test 4: Lane0 ALU + Lane1 JAL (link register + redirect)
# Pair: lane0=addi x5,1  lane1=jal x6,skip (TAKEN → redirect, x6=PC+4)
# Tests: lane1 JAL redirects, x6 gets link address, lane0 result valid

    addi x5, x0, 1           # 80000000: lane0 ALU: x5 = 1
    jal  x6, skip             # 80000004: lane1 JAL: x6=PC+4, jump to skip
    addi x7, x0, 1           # 80000008: SKIPPED
    nop                      # 8000000C: SKIPPED
skip:                        # 80000010
    addi x8, x5, 0           # 80000010: x8 = x5 (=1)
    addi x9, x7, 0           # 80000014: x9 = x7 (=0, confirms skipped)
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
