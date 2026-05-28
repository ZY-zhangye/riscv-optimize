#!/bin/bash
# Quick regression: xvlog+xelab already done, just copy hex and run xsim
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
mkdir -p results

UI_TESTS="add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti sltu sltiu beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu sw lw"
MI_TESTS="csr scall sbreak ma_fetch"
UM_TESTS="mul mulh mulhu mulhsu div divu rem remu"

run_one() {
    local hex="test/hex/riscv-tests/${1}.hex"
    local label="$2"
    if [ ! -f "$hex" ]; then
        echo "[SKIP] $label — hex missing"
        return
    fi
    cp "$hex" test/program.hex
    xsim test_snap -runall > "results/${label}.txt" 2>&1
    if grep -q "Test passed." "results/${label}.txt"; then
        echo "[PASS] $label"
        PASS=$((PASS+1))
    else
        echo "[FAIL] $label"
        FAIL=$((FAIL+1))
    fi
}

MODE="${1:-base}"

if [ "$MODE" = "base" ] || [ "$MODE" = "all" ]; then
    echo "=== RV32I User ==="
    for t in $UI_TESTS; do run_one "rv32ui-p-$t" "ui-$t"; done
    echo "=== RV32I Machine ==="
    for t in $MI_TESTS; do run_one "rv32mi-p-$t" "mi-$t"; done
    echo "=== RV32M ==="
    for t in $UM_TESTS; do run_one "rv32um-p-$t" "um-$t"; done
fi

echo "=== Done: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
