# P5a Stall+Dual test: mul creates pipeline stall, queue fills up,
# then ALU+branch pair dual-issues with lane1 redirect.

    addi x10, x0, 3          # 80000000: x10=3
    addi x11, x0, 4          # 80000004: x11=4
    # mul x12, x10, x11 — multi-cycle stall → queue fills
    mul  x12, x10, x11       # 80000008: x12=12 (6-cycle stall)
    # After stall: queue should have multiple entries → dual-issue
    addi x5, x0, 1           # 8000000C: lane0 ALU: x5=1
    beq  x0, x0, skip         # 80000010: lane1 BR: x0==x0 → TAKEN → redirect
    addi x6, x0, 1           # 80000014: SKIPPED
    nop                       # 80000018: SKIPPED
skip:                         # 8000001C
    # Verify: x5=1 (lane0 result), x6=0 (skipped)
    addi x7, x5, 0           # x7=x5=1
    addi x8, x6, 0           # x8=x6=0
    nop
    nop
    nop
    nop
    nop
    nop
    addi x3, x0, 1           # 8000003C: x3=1
    nop                       # 80000040
    nop                       # 80000044: CHECK POINT
    jal  x0, -4               # 80000048: loop
