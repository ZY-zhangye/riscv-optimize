@echo off
setlocal EnableExtensions

rem Replace inst_ram contents and generate bitstreams without re-synthesis.
rem Default batch mode:
rem   update_inst_ram.bat
rem Single-file mode:
rem   update_inst_ram.bat input.coe [output.bit] [base.bit] [base.mmi]
rem   update_inst_ram.bat input.hex [output.bit] [base.bit] [base.mmi]

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul

if /I "%~1"=="/?" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage

set "BASE_BIT=%~3"
set "MMI_FILE=%~4"

if not defined BASE_BIT set "BASE_BIT=cpu_base.bit"
if not defined MMI_FILE set "MMI_FILE=cpu_base.mmi"
if not defined VIVADO_BIN call :find_vivado

if not exist "%BASE_BIT%" (
    echo ERROR: base bit file not found: %BASE_BIT%
    popd >nul
    exit /b 1
)

if not exist "%MMI_FILE%" (
    echo ERROR: mmi file not found: %MMI_FILE%
    popd >nul
    exit /b 1
)

if not exist "bit" mkdir "bit"
if not exist "mem" mkdir "mem"

call :find_python
if errorlevel 1 (
    popd >nul
    exit /b 1
)

if "%~1"=="" goto :batch_mode

set "INPUT_FILE=%~1"
set "OUT_BIT=%~2"
if not defined OUT_BIT set "OUT_BIT=bit\cpu_new.bit"
if "%~dp2"=="" if not "%~2"=="" set "OUT_BIT=bit\%~2"

call :process_one "%INPUT_FILE%" "%OUT_BIT%" "mem\inst_ram_update.mem"
set "RESULT=%ERRORLEVEL%"
popd >nul
exit /b %RESULT%

:batch_mode
echo === Batch update withMext-withoutMext ===
set "FAILED=0"

for %%S in (withMext withoutMext) do (
    call :process_src "%%S"
    if errorlevel 1 set "FAILED=1"
)

echo.
echo === Verify generated bit files ===
for %%S in (withMext withoutMext) do (
    if exist "bit\bit_%%S.bit" (
        echo OK: bit\bit_%%S.bit
    ) else (
        echo MISSING: bit\bit_%%S.bit
        set "FAILED=1"
    )
)

if "%FAILED%"=="1" (
    echo.
    echo ERROR: one or more bitstreams were not generated successfully.
    popd >nul
    exit /b 1
)

echo.
echo DONE: all bitstreams were generated under bit\
popd >nul
exit /b 0

:process_src
set "SRC_NAME=%~1"
set "SRC_DIR=mem\%SRC_NAME%"
set "SRC_IROM="

if exist "%SRC_DIR%\irom.coe" set "SRC_IROM=%SRC_DIR%\irom.coe"
if not defined SRC_IROM if exist "%SRC_DIR%\irom.hex" set "SRC_IROM=%SRC_DIR%\irom.hex"

if not defined SRC_IROM (
    echo ERROR: irom.coe or irom.hex not found in %SRC_DIR%
    exit /b 1
)

call :process_one "%SRC_IROM%" "bit\bit_%SRC_NAME%.bit" "mem\%SRC_NAME%\irom.mem"
exit /b %ERRORLEVEL%

:process_one
set "INPUT_FILE=%~1"
set "OUT_BIT=%~2"
set "MEM_FILE=%~3"

if not exist "%INPUT_FILE%" (
    echo ERROR: input file not found: %INPUT_FILE%
    exit /b 1
)

echo.
echo === Convert input to mem ===
echo Input : %INPUT_FILE%
echo MEM   : %MEM_FILE%
%PYTHON_CMD% "mem\convert_to_mem.py" "%INPUT_FILE%" "%MEM_FILE%"
if errorlevel 1 (
    echo ERROR: failed to convert %INPUT_FILE% to %MEM_FILE%.
    exit /b 1
)

echo.
echo === Generate updated bitstream ===
echo Base BIT: %BASE_BIT%
echo MMI     : %MMI_FILE%
echo Output  : %OUT_BIT%

call "%VIVADO_BIN%" -mode batch -source "scripts\scriptsupdate_mem.tcl"
if errorlevel 1 (
    echo ERROR: Vivado updatemem failed for %INPUT_FILE%.
    exit /b 1
)

if not exist "%OUT_BIT%" (
    echo ERROR: Vivado finished but output bit was not found: %OUT_BIT%
    exit /b 1
)

echo OK: generated %OUT_BIT%
exit /b 0

:find_python
where py >nul 2>nul
if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
    exit /b 0
)

where python >nul 2>nul
if not errorlevel 1 (
    set "PYTHON_CMD=python"
    exit /b 0
)

echo ERROR: Python was not found. Install Python or make py/python available in PATH.
exit /b 1

:find_vivado
where vivado >nul 2>nul
if not errorlevel 1 (
    set "VIVADO_BIN=vivado"
    exit /b 0
)

for %%D in (C D E F) do (
    for /d %%V in ("%%D:\Xilinx\Vivado\*") do (
        if exist "%%~fV\bin\vivado.bat" (
            set "VIVADO_BIN=%%~fV\bin\vivado.bat"
            exit /b 0
        )
    )
)

set "VIVADO_BIN=vivado"
exit /b 0

:usage
echo Usage:
echo   %~nx0
echo   %~nx0 input.coe [output.bit] [base.bit] [base.mmi]
echo   %~nx0 input.hex [output.bit] [base.bit] [base.mmi]
echo.
echo Default mode:
echo   Converts mem\withMext\irom.*, mem\withoutMext\irom.*
echo   Generates bit\bit_withMext.bit, bit\bit_withoutMext.bit
echo.
echo Environment overrides:
echo   VIVADO_BIN  Vivado command. If unset, the script searches C/D/E/F:\Xilinx\Vivado\*
echo   PROC_PATH   updatemem -proc path, default is defined in scripts\scriptsupdate_mem.tcl
popd >nul
exit /b 0
