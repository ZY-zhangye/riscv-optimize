@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Vivado xsim regression for the current non-DEBUG my_cpu top.
REM Pass/fail follows the old Questa tests: the transcript must contain "Test passed.".

set UI_INSTS=lh lhu sh sb lb lbu sw lw add addi sub and andi or ori xor xori sll srl sra slli srli srai slt slti jalr sltu sltiu beq bne blt bge bltu bgeu jal lui auipc
set MI_INSTS=csr scall sbreak ma_fetch
set UM_INSTS=mul mulh mulhu mulhsu div divu rem remu

set ZBA_INSTS=sh1add sh2add sh3add
set ZBB_INSTS=andn orn xnor min max minu maxu sext_b sext_h zext_h orc_b rev8
set ZBKB_INSTS=brev8 pack packh zip unzip
set ZBS_INSTS=bclr bclri bext bexti binv binvi bset bseti

set MODE=%~1
if "%MODE%"=="" set MODE=base

set PY_CMD=python
python --version >nul 2>nul
if errorlevel 1 set PY_CMD=py

if not exist results mkdir results
if not exist xsim_work mkdir xsim_work

if /I "%MODE%"=="one" (
    if "%~2"=="" goto :usage
    call :compile_design
    if errorlevel 1 exit /b 1
    call :run_one "%~n2" "%~2"
    exit /b !ERRORLEVEL!
)

call :compile_design
if errorlevel 1 exit /b 1

if /I "%MODE%"=="base" goto :run_base_only
if /I "%MODE%"=="all" goto :run_all
if /I "%MODE%"=="z" goto :run_z_only
if /I "%MODE%"=="zba" goto :run_zba_only
if /I "%MODE%"=="zbb" goto :run_zbb_only
if /I "%MODE%"=="zbkb" goto :run_zbkb_only
if /I "%MODE%"=="zbs" goto :run_zbs_only
goto :usage

:compile_design
echo.
echo ====== Compiling current my_cpu design for xsim ======
set RTL_CPU=..\rtl\cpu_top
set RTL_SOC=..\rtl\my_cpu
set IP_ROOT=..\project-vivado\riscv-graduation.gen\sources_1\ip
set PLL_XSIM=..\project-vivado\riscv-graduation.ip_user_files\sim_scripts\PLL\xsim

call xvhdl "%IP_ROOT%\multiplier\sim\multiplier.vhd" "%IP_ROOT%\divider\sim\divider.vhd" > results\xsim_compile_vhdl.txt
if errorlevel 1 (
    echo VHDL IP compile failed.
    type results\xsim_compile_vhdl.txt
    exit /b 1
)

call xvlog --sv -i "%RTL_CPU%" -i "%RTL_SOC%" -i "%IP_ROOT%\ipstatic" ^
    "%IP_ROOT%\PLL\PLL_clk_wiz.v" ^
    "%IP_ROOT%\PLL\PLL.v" ^
    "%RTL_CPU%\alu_wrapper.sv" ^
    "%RTL_CPU%\branch_controller.sv" ^
    "%RTL_CPU%\cpu_top.sv" ^
    "%RTL_CPU%\decode_unit.sv" ^
    "%RTL_CPU%\divider.sv" ^
    "%RTL_CPU%\exe_lane_simple.sv" ^
    "%RTL_CPU%\exe_stage.sv" ^
    "%RTL_CPU%\forwarding_unit.sv" ^
    "%RTL_CPU%\hazard_unit.sv" ^
    "%RTL_CPU%\id_stage.sv" ^
    "%RTL_CPU%\if_stage.sv" ^
    "%RTL_CPU%\instr_queue.sv" ^
    "%RTL_CPU%\issue_select.sv" ^
    "%RTL_CPU%\mem_stage.sv" ^
    "%RTL_CPU%\mul.sv" ^
    "%RTL_CPU%\regfile_csr.sv" ^
    "%RTL_CPU%\regfiles.sv" ^
    "%RTL_CPU%\wb_stage.sv" ^
    "%RTL_CPU%\write_port_arbiter.sv" ^
    "%RTL_SOC%\bridge.sv" ^
    "%RTL_SOC%\IO.sv" ^
    "%RTL_SOC%\my_cpu.sv" ^
    "%RTL_SOC%\PLIC.sv" ^
    "%RTL_SOC%\timer.sv" ^
    "%RTL_SOC%\UART.sv" ^
    "test\tb_my_cpu_xsim.sv" ^
    "%PLL_XSIM%\glbl.v" > results\xsim_compile_sv.txt
if errorlevel 1 (
    echo SystemVerilog compile failed.
    type results\xsim_compile_sv.txt
    exit /b 1
)

call xelab -debug typical ^
    -L xpm -L unisims_ver -L unimacro_ver -L secureip ^
    -L xbip_utils_v3_0_10 -L mult_gen_v12_0_19 -L div_gen_v5_1_20 ^
    tb_my_cpu_xsim glbl -s tb_my_cpu_xsim_snapshot > results\xsim_elab.txt
if errorlevel 1 (
    echo Elaboration failed.
    type results\xsim_elab.txt
    exit /b 1
)
exit /b 0

:run_base_only
call :run_base
if errorlevel 1 goto :fail
echo.
echo BASE TESTS PASSED!
exit /b 0

:run_all
call :run_base
if errorlevel 1 goto :fail
call :run_z_groups
if errorlevel 1 goto :fail
echo.
echo ALL TESTS PASSED!
exit /b 0

:run_z_only
call :run_z_groups
if errorlevel 1 goto :fail
echo.
echo Z TESTS PASSED!
exit /b 0

:run_base
set "GROUP_NAME=UI instructions"
set "TEST_PREFIX=rv32ui-p"
set "TEST_LIST=%UI_INSTS%"
set "RESULT_PREFIX=ui"
call :run_group
if errorlevel 1 exit /b 1

set "GROUP_NAME=MI instructions"
set "TEST_PREFIX=rv32mi-p"
set "TEST_LIST=%MI_INSTS%"
set "RESULT_PREFIX=mi"
call :run_group
if errorlevel 1 exit /b 1

set "GROUP_NAME=UM instructions"
set "TEST_PREFIX=rv32um-p"
set "TEST_LIST=%UM_INSTS%"
set "RESULT_PREFIX=um"
call :run_group
if errorlevel 1 exit /b 1
exit /b 0

:run_z_groups
set "GROUP_NAME=Zba instructions"
set "TEST_PREFIX=rv32uzba-p"
set "TEST_LIST=%ZBA_INSTS%"
set "RESULT_PREFIX=zba"
call :run_group
if errorlevel 1 exit /b 1

set "GROUP_NAME=Zbb implemented instructions"
set "TEST_PREFIX=rv32uzbb-p"
set "TEST_LIST=%ZBB_INSTS%"
set "RESULT_PREFIX=zbb"
call :run_group
if errorlevel 1 exit /b 1

set "GROUP_NAME=Zbkb instructions"
set "TEST_PREFIX=rv32uzbkb-p"
set "TEST_LIST=%ZBKB_INSTS%"
set "RESULT_PREFIX=zbkb"
call :run_group
if errorlevel 1 exit /b 1

set "GROUP_NAME=Zbs instructions"
set "TEST_PREFIX=rv32uzbs-p"
set "TEST_LIST=%ZBS_INSTS%"
set "RESULT_PREFIX=zbs"
call :run_group
if errorlevel 1 exit /b 1
exit /b 0

:run_zba_only
set "GROUP_NAME=Zba instructions"
set "TEST_PREFIX=rv32uzba-p"
set "TEST_LIST=%ZBA_INSTS%"
set "RESULT_PREFIX=zba"
call :run_group
exit /b %ERRORLEVEL%

:run_zbb_only
set "GROUP_NAME=Zbb implemented instructions"
set "TEST_PREFIX=rv32uzbb-p"
set "TEST_LIST=%ZBB_INSTS%"
set "RESULT_PREFIX=zbb"
call :run_group
exit /b %ERRORLEVEL%

:run_zbkb_only
set "GROUP_NAME=Zbkb instructions"
set "TEST_PREFIX=rv32uzbkb-p"
set "TEST_LIST=%ZBKB_INSTS%"
set "RESULT_PREFIX=zbkb"
call :run_group
exit /b %ERRORLEVEL%

:run_zbs_only
set "GROUP_NAME=Zbs instructions"
set "TEST_PREFIX=rv32uzbs-p"
set "TEST_LIST=%ZBS_INSTS%"
set "RESULT_PREFIX=zbs"
call :run_group
exit /b %ERRORLEVEL%

:run_group
echo.
echo Starting xsim for %GROUP_NAME%...
for %%i in (%TEST_LIST%) do (
    set "TEST_NAME=%TEST_PREFIX%-%%i"
    set "HEX_FILE=hex\riscv-tests\!TEST_NAME!.hex"
    call :run_one "!RESULT_PREFIX!_%%i" "!HEX_FILE!"
    if errorlevel 1 exit /b 1
)
exit /b 0

:run_one
set "RESULT_NAME=%~1"
set "HEX_FILE=%~2"
echo.
echo ====== Simulating %RESULT_NAME% ======
if not exist "%HEX_FILE%" (
    echo [MISSING] %HEX_FILE%
    exit /b 1
)

%PY_CMD% ..\docs\mem_tools\convert_to_mem.py "%HEX_FILE%" "xsim_work\program.mem" > "results\%RESULT_NAME%_convert.txt"
if errorlevel 1 (
    echo Memory conversion failed for %HEX_FILE%.
    type "results\%RESULT_NAME%_convert.txt"
    exit /b 1
)

call xsim tb_my_cpu_xsim_snapshot -runall > "results\%RESULT_NAME%.txt"
if errorlevel 1 (
    echo xsim failed for %RESULT_NAME%.
    type "results\%RESULT_NAME%.txt"
    exit /b 1
)

findstr /C:"Test passed." "results\%RESULT_NAME%.txt" >nul
if errorlevel 1 (
    echo [FAILED] %RESULT_NAME%
    type "results\%RESULT_NAME%.txt"
    exit /b 1
) else (
    echo [PASSED] %RESULT_NAME%
)
exit /b 0

:fail
echo.
echo Failure detected during xsim regression.
exit /b 1

:usage
echo Usage:
echo   run_xsim.bat [base^|all^|z^|zba^|zbb^|zbkb^|zbs]
echo   run_xsim.bat one path\to\test.hex
exit /b 1
