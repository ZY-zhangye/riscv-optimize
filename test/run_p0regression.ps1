# P0 Baseline Regression
# Strategy: compile+elaborate once, then cmd /c xsim per test (avoids bash = mangling)
param([string]$Mode = "base")

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

$UI_TESTS = @("add","addi","sub","and","andi","or","ori","xor","xori",
    "sll","srl","sra","slli","srli","srai","slt","slti","sltu","sltiu",
    "beq","bne","blt","bge","bltu","bgeu","jal","jalr","lui","auipc",
    "lh","lhu","sh","sb","lb","lbu","sw","lw")
$MI_TESTS = @("csr","scall","sbreak","ma_fetch")
$UM_TESTS = @("mul","mulh","mulhu","mulhsu","div","divu","rem","remu")

$Passed = 0
$Failed = 0
$TotalCycles = 0
$TestCount = 0
$Results = @()

Push-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path "results" | Out-Null

# ===== Compile =====
Write-Host "===== Compiling RTL for xsim =====" -ForegroundColor Cyan
$rtl_cpu = "rtl\cpu_top"
$rtl_soc = "rtl\my_cpu"
$sv_files = @(
    "$rtl_cpu\defines.svh",
    "$rtl_cpu\alu_wrapper.sv",
    "$rtl_cpu\cpu_top.sv",
    "$rtl_cpu\divider.sv",
    "$rtl_cpu\exe_stage.sv",
    "$rtl_cpu\forwarding_unit.sv",
    "$rtl_cpu\id_stage.sv",
    "$rtl_cpu\if_stage.sv",
    "$rtl_cpu\mem_stage.sv",
    "$rtl_cpu\mul.sv",
    "$rtl_cpu\regfile_csr.sv",
    "$rtl_cpu\regfiles.sv",
    "$rtl_cpu\wb_stage.sv",
    "$rtl_cpu\write_port_arbiter.sv",
    "test\behav_multiplier.sv",
    "test\tb_cpu_top_simple.sv"
)

$compile_out = & xvlog --sv -i $rtl_cpu -i $rtl_soc -i test -d DEBUG_EN -d USE_RTL_DIVIDER_MODEL $sv_files 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Compilation failed" -ForegroundColor Red
    $compile_out | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Pop-Location; exit 1
}
Write-Host "Compilation OK" -ForegroundColor Green

# ===== Elaborate =====
Write-Host "===== Elaborating snapshot =====" -ForegroundColor Cyan
$elab_out = & xelab -debug typical tb_cpu_top_simple -s p0_snap 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Elaboration failed" -ForegroundColor Red
    $elab_out | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Pop-Location; exit 1
}
Write-Host "Elaboration OK" -ForegroundColor Green

# ===== Run one test via cmd /c (preserves = in arguments) =====
function Run-Test {
    param([string]$TestName, [string]$ResultName)
    # Forward slashes required — xsim passes through Tcl, \r becomes carriage return
    $hex_abs = "$ProjectRoot\test\hex\riscv-tests\$TestName.hex" -replace '\\', '/'
    if (-not (Test-Path $hex_abs)) {
        Write-Host "[SKIP] $ResultName" -ForegroundColor Yellow
        return
    }

    $result_file = "$ProjectRoot\results\$ResultName.txt"
    $plusarg = "MEM_FILE=$hex_abs"
    $cmd = "cd /d `"$ProjectRoot`" && xsim p0_snap -runall --testplusarg `"$plusarg`""
    $output = cmd /c $cmd 2>&1
    $out_str = $output -join "`n"

    # Save output
    $output | Out-File -FilePath $result_file -Encoding ascii

    if ($out_str -match "Test passed\.") {
        $cycles = "N/A"
        if ($out_str -match "Time:\s+(\d+)") {
            # $time with %0t in 1ps precision → divide by 10000 for cycles (10ns clock)
            $time_ps = [int]$Matches[1]
            $cycles = [math]::Floor($time_ps / 10000)
        }
        Write-Host "[PASS] $ResultName  ($cycles cycles)" -ForegroundColor Green
        $script:Passed++
        $script:Results += [PSCustomObject]@{Name=$ResultName;Cycles=$cycles}
        if ($cycles -ne "N/A") {
            $script:TotalCycles += $cycles
            $script:TestCount++
        }
    } else {
        Write-Host "[FAIL] $ResultName" -ForegroundColor Red
        $script:Failed++
        $script:Results += [PSCustomObject]@{Name=$ResultName;Cycles="FAIL"}
        $output | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
}

# ===== Run groups =====
function Run-Group {
    param([string]$Label, [string]$Prefix, [string[]]$Tests)
    Write-Host "`n===== $Label =====" -ForegroundColor Cyan
    foreach ($t in $Tests) {
        Run-Test "${Prefix}-$t" "${Label}_$t"
    }
}

if ($Mode -eq "base" -or $Mode -eq "all") {
    Run-Group "ui" "rv32ui-p" $UI_TESTS
    Run-Group "mi" "rv32mi-p" $MI_TESTS
    Run-Group "um" "rv32um-p" $UM_TESTS
}

# ===== Save baseline record =====
$baseline_csv = "$ProjectRoot\results\p0_baseline.csv"
$Results | Export-Csv -Path $baseline_csv -NoTypeInformation
Write-Host "`nBaseline results saved to: results/p0_baseline.csv" -ForegroundColor Cyan

# ===== Summary =====
Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "P0 Baseline Regression Complete" -ForegroundColor Cyan
Write-Host "Passed: $Passed  Failed: $Failed" -ForegroundColor $(if ($Failed -eq 0) { "Green" } else { "Red" })
if ($TestCount -gt 0) {
    $avgCycles = [math]::Round($TotalCycles / $TestCount)
    Write-Host "Average cycles: $avgCycles (over $TestCount tests)" -ForegroundColor Cyan
}
Write-Host "==============================================" -ForegroundColor Cyan

Pop-Location
if ($Failed -eq 0) { exit 0 } else { exit 1 }
