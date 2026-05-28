@echo off
setlocal EnableExtensions

rem ============================================================
rem USER EDIT AREA
rem ============================================================
rem Set DRY_RUN=1 to preview files without deleting them.
set "DRY_RUN=0"

rem Delete common Vivado/XSim log files: *.log, *.jou, *.str.
set "CLEAN_LOG_FILES=1"

rem Delete generated temporary memory-update files under build\mem_update.
set "CLEAN_MEM_UPDATE_TEMP=1"

rem Delete Vivado .Xil cache directories. This is safe but may make the next
rem Vivado run a little slower. Default is off.
set "CLEAN_XIL_CACHE=0"

rem Command line shortcuts:
rem   clean_project_logs.bat /dry
rem   clean_project_logs.bat /xil
rem   clean_project_logs.bat /all
if /I "%~1"=="/dry" set "DRY_RUN=1"
if /I "%~1"=="/xil" set "CLEAN_XIL_CACHE=1"
if /I "%~1"=="/all" (
    set "CLEAN_LOG_FILES=1"
    set "CLEAN_MEM_UPDATE_TEMP=1"
    set "CLEAN_XIL_CACHE=1"
)
if /I "%~1"=="/?" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="--help" goto :usage

set "ROOT=%~dp0"

echo Project root:
echo   %ROOT%
echo DRY_RUN=%DRY_RUN%
echo.

if not "%CLEAN_LOG_FILES%"=="1" goto :skip_log_files
echo === Cleaning log files ===
for /r "%ROOT%" %%F in (*.log *.jou *.str) do (
    echo DEL  "%%~fF"
    if not "%DRY_RUN%"=="1" del /f /q "%%~fF" >nul 2>nul
)
:skip_log_files

if not "%CLEAN_MEM_UPDATE_TEMP%"=="1" goto :skip_mem_update_temp
echo.
echo === Cleaning build\mem_update ===
if exist "%ROOT%build\mem_update" (
    echo RMDIR "%ROOT%build\mem_update"
    if not "%DRY_RUN%"=="1" rmdir /s /q "%ROOT%build\mem_update" >nul 2>nul
) else (
    echo SKIP "%ROOT%build\mem_update" not found
)
:skip_mem_update_temp

if not "%CLEAN_XIL_CACHE%"=="1" goto :skip_xil_cache
echo.
echo === Cleaning .Xil cache directories ===
if exist "%ROOT%.Xil" (
    echo RMDIR "%ROOT%.Xil"
    if not "%DRY_RUN%"=="1" rmdir /s /q "%ROOT%.Xil" >nul 2>nul
) else (
    echo SKIP "%ROOT%.Xil" not found
)
if exist "%ROOT%project-vivado\.Xil" (
    echo RMDIR "%ROOT%project-vivado\.Xil"
    if not "%DRY_RUN%"=="1" rmdir /s /q "%ROOT%project-vivado\.Xil" >nul 2>nul
) else (
    echo SKIP "%ROOT%project-vivado\.Xil" not found
)
if exist "%ROOT%test\.Xil" (
    echo RMDIR "%ROOT%test\.Xil"
    if not "%DRY_RUN%"=="1" rmdir /s /q "%ROOT%test\.Xil" >nul 2>nul
) else (
    echo SKIP "%ROOT%test\.Xil" not found
)
:skip_xil_cache

echo.
echo DONE.
exit /b 0

:usage
echo Usage:
echo   %~nx0
echo   %~nx0 /dry
echo   %~nx0 /xil
echo   %~nx0 /all
echo.
echo Default deletes only log/journal/string files and build\mem_update.
echo It does not delete source files, XPR, XDC, bitstreams, MMI, reports, or runs.
echo /dry previews what would be deleted.
echo /xil also deletes .Xil cache directories.
echo /all enables all cleanup options.
exit /b 0
