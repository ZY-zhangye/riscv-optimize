#!/bin/bash
# Regression test script for I+M+Zicsr baseline
# Uses xsim with behavioral multiplier and RTL divider model

set -e

cd "$(dirname "$0")/.."

# Test sets
UI_TESTS="add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti sltu sltiu beq bne blt bge bltu bgeu jal jalr lui auipc lh lhu sh sb lb lbu sw lw"
MI_TESTS="csr scall sbreak ma_fetch"
UM_TESTS="mul mulh mulhu mulhsu div divu rem remu"

MODE="${1:-base}"

compile() {
    echo "=== Compiling RTL ==="
    xvlog --sv -i rtl/cpu_top -i rtl/my_cpu -i test \
        -d DEBUG_EN -d USE_RTL_DIVIDER_MODEL \
        rtl/cpu_top/defines.svh \
        rtl/cpu_top/cpu_top.sv \
        rtl/cpu_top/divider.sv \
        rtl/cpu_top/exe_stage.sv \
        rtl/cpu_top/id_stage.sv \
        rtl/cpu_top/if_stage.sv \
        rtl/cpu_top/mem_stage.sv \
        rtl/cpu_top/mul.sv \
        rtl/cpu_top/regfile_csr.sv \
        rtl/cpu_top/regfiles.sv \
        rtl/cpu_top/wb_stage.sv \
        test/behav_multiplier.sv \
        test/tb_cpu_top_simple.sv 2>&1 | grep -E "ERROR|FATAL" || echo "Compile OK"
}

run_test() {
    local test_name="$1"
    local hex_file="test/hex/riscv-tests/${test_name}.hex"
    local result_name="$2"

    if [ ! -f "$hex_file" ]; then
        echo "[SKIP] $test_name — hex file not found"
        return 0
    fi

    rm -rf xsim.dir

    xelab -debug typical tb_cpu_top_simple -s test_snap \
        -generic_top "MEM_FILE=$hex_file" 2>&1 | grep -E "ERROR|FATAL" && return 1

    xsim test_snap -runall 2>&1 | grep -q "Test passed."
    if [ $? -eq 0 ]; then
        echo "[PASS] $result_name"
    else
        echo "[FAIL] $result_name"
        return 1
    fi
}

run_group() {
    local prefix="$1"
    local tests="$2"
    local label="$3"
    local failed=0

    echo ""
    echo "=== $label ==="
    for t in $tests; do
        run_test "${prefix}-${t}" "${prefix}-${t}" || failed=1
    done
    return $failed
}

# Main
mkdir -p results

compile

if [ "$MODE" = "base" ] || [ "$MODE" = "all" ]; then
    run_group "rv32ui-p" "$UI_TESTS" "RV32I User Instructions"
    run_group "rv32mi-p" "$MI_TESTS" "RV32I Machine Instructions"
    run_group "rv32um-p" "$UM_TESTS" "RV32M Instructions"
fi

echo ""
echo "Regression complete."
