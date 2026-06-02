@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM RISC-V CPU regression — ModelSim/Questa flow
REM Uses tb_cpu_top_simple (cpu_top only, no Xilinx IP / PLL)
REM ============================================================
REM Usage: run_all.bat [base|all]
REM ============================================================

set UI_INSTS=lh lhu sh sb lb lbu sw lw add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti jalr sltu sltiu beq bne blt bge bltu bgeu jal lui auipc
set MI_INSTS=csr scall sbreak ma_fetch
set UM_INSTS=mul mulh mulhu mulhsu div divu rem remu

set MODE=%~1
if "%MODE%"=="" set MODE=base

set RTL_CPU=rtl\cpu_top
set RTL_SOC=rtl\my_cpu
set HEX_DIR=test\hex\riscv-tests

if not exist results mkdir results

REM ===== Compile RTL =====
echo.
echo ====== Compiling RTL (ModelSim vlog) ======
vlib work 2>nul
vlog -sv -work work ^
    +incdir+%RTL_CPU% +incdir+%RTL_SOC% +incdir+test ^
    +define+DEBUG_EN +define+USE_RTL_DIVIDER_MODEL ^
    %RTL_CPU%\defines.svh ^
    %RTL_CPU%\alu_wrapper.sv ^
    %RTL_CPU%\branch_controller.sv ^
    %RTL_CPU%\cpu_top.sv ^
    %RTL_CPU%\decode_unit.sv ^
    %RTL_CPU%\divider.sv ^
    %RTL_CPU%\exe_stage.sv ^
    %RTL_CPU%\forwarding_unit.sv ^
    %RTL_CPU%\hazard_unit.sv ^
    %RTL_CPU%\id_stage.sv ^
    %RTL_CPU%\if_stage.sv ^
    %RTL_CPU%\mem_stage.sv ^
    %RTL_CPU%\mul.sv ^
    %RTL_CPU%\regfile_csr.sv ^
    %RTL_CPU%\regfiles.sv ^
    %RTL_CPU%\wb_stage.sv ^
    %RTL_CPU%\write_port_arbiter.sv ^
    test\behav_multiplier.sv ^
    test\tb_cpu_top_simple.sv
if errorlevel 1 (
    echo [ERROR] Compilation failed
    exit /b 1
)
echo Compilation OK

if /I "%MODE%"=="base" goto :run_base
if /I "%MODE%"=="all"  goto :run_all
goto :run_base

:run_all
set RUN_Z=1
goto :run_base

:run_base
echo.
echo ====== Base Regression ======
call :run_group "rv32ui-p" "%UI_INSTS%" "ui"
if errorlevel 1 goto :fail
call :run_group "rv32mi-p" "%MI_INSTS%" "mi"
if errorlevel 1 goto :fail
call :run_group "rv32um-p" "%UM_INSTS%" "um"
if errorlevel 1 goto :fail

if "%RUN_Z%"=="1" (
    echo.
    echo ====== Z-bitman Regression ======
    call :run_group "rv32uzba-p"  "%ZBA_INSTS%"  "zba"
    if errorlevel 1 goto :fail
    call :run_group "rv32uzbb-p"  "%ZBB_INSTS%"  "zbb"
    if errorlevel 1 goto :fail
    call :run_group "rv32uzbkb-p" "%ZBKB_INSTS%" "zbkb"
    if errorlevel 1 goto :fail
    call :run_group "rv32uzbs-p"  "%ZBS_INSTS%"  "zbs"
    if errorlevel 1 goto :fail
)

echo.
echo ==============================================
echo Regression Complete — All tests passed
echo ==============================================
exit /b 0

:run_group
set "PREFIX=%~1"
set "TESTS=%~2"
set "LABEL=%~3"
echo.
echo --- %LABEL% ---
for %%t in (%TESTS%) do (
    set "HEX=%HEX_DIR%\%PREFIX%-%%t.hex"
    if not exist "!HEX!" (
        echo [SKIP] !HEX! not found
    ) else (
        call :run_one "%PREFIX%-%%t" "%LABEL%_%%t" "!HEX!"
        if errorlevel 1 exit /b 1
    )
)
exit /b 0

:run_one
set "NAME=%~1"
set "RESULT=%~2"
set "HEX_FILE=%~3"

REM Convert backslashes to forward slashes for ModelSim
set "HEX_FWD=%HEX_FILE:\=/%"

echo [RUN] %NAME%
vsim -c -do "run -all; quit -f" ^
    +MEM_FILE=%HEX_FWD% ^
    tb_cpu_top_simple > "results\%RESULT%.txt" 2>&1

findstr /C:"Test passed." "results\%RESULT%.txt" >nul
if errorlevel 1 (
    echo [FAIL] %NAME%
    type "results\%RESULT%.txt"
    exit /b 1
) else (
    echo [PASS] %NAME%
)
exit /b 0

:fail
echo.
echo ==============================================
echo Regression FAILED
echo ==============================================
exit /b 1
