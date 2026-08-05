@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  CUDA build + run + timing script
REM
REM  ENCODING: this file is pure ASCII on purpose.
REM  Save as UTF-8 (no BOM) or ANSI - either works.
REM  Do NOT add non-ASCII characters: cmd.exe mis-seeks goto
REM  labels in multibyte batch files.
REM
REM  Usage
REM    build.bat                      : pick a .cu from a menu
REM    build.bat src\kernel.cu 4 4 4  : explicit path + run args
REM    build.bat kernel 4 4 4         : name only (searched under root)
REM    drag & drop a .cu file onto this batch file
REM
REM  Everything after the source file is passed to the program.
REM
REM  common\ folder
REM    All .cpp / .cu in common\ are always compiled together and
REM    common\ is added to the include path.
REM    e.g. common\DS_timer.h + common\DS_timer.cpp
REM         -> just #include "DS_timer.h" in your source
REM
REM  Any .cpp sitting next to the source file is also compiled.
REM  Output goes to build\.
REM ============================================================

cd /d "%~dp0"
set "ROOT=%~dp0"
set "OUTDIR=%ROOT%build"
set "COMMON=%ROOT%common"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

REM ============================================================
REM  0. Split argv:  %1 = source,  rest = program arguments
REM     (capture ROOT before shift - shift moves %0 too)
REM ============================================================
set "INPUT="
set "RUNARGS="
if not "%~1"=="" set "INPUT=%~1"

:collectargs
shift
if "%~1"=="" goto :collected
set "RUNARGS=!RUNARGS! %1"
goto :collectargs
:collected

if defined INPUT goto :resolve

REM ============================================================
REM  1. Pick a source file (recursive scan)
REM ============================================================
:choose
echo.
echo ===================================================
echo  Select a .cu file to build
echo ===================================================
set /a IDX=0
for /f "delims=" %%F in ('dir /s /b /a-d "%ROOT%*.cu" 2^>nul') do (
    set "P=%%F"
    echo !P! | findstr /i /c:"\build\" /c:"\common\" >nul
    if errorlevel 1 (
        set /a IDX+=1
        set "FILE[!IDX!]=%%F"
        set "REL=!P:%ROOT%=!"
        echo    [!IDX!] !REL!
    )
)
if %IDX%==0 echo    ^(no .cu files found under this folder^)
echo ---------------------------------------------------
echo    Q = quit
echo.
set "INPUT="
set /p "INPUT=Number or filename/path: "

if "!INPUT!"=="" goto :choose
if /i "!INPUT!"=="Q" exit /b 0

REM ============================================================
REM  2. Resolve input to a real path
REM ============================================================
:resolve

echo !INPUT!| findstr /r "^[0-9][0-9]*$" >nul
if !errorlevel! equ 0 (
    for /f %%N in ("!INPUT!") do set "SRC=!FILE[%%N]!"
    if defined SRC goto :resolved
    echo.
    echo  [ERROR] no such entry in the list: !INPUT!
    goto :choose
)

set "CAND=!INPUT!"
if /i not "!CAND:~-3!"==".cu" set "CAND=!CAND!.cu"

if exist "!CAND!" (
    for %%F in ("!CAND!") do set "SRC=%%~fF"
    goto :resolved
)

for /f "delims=" %%F in ('dir /s /b /a-d "%ROOT%!CAND!" 2^>nul') do (
    set "SRC=%%F"
    goto :resolved
)

echo.
echo  [ERROR] file not found: !INPUT!
if defined RUNARGS (pause & exit /b 1)
goto :choose

REM ============================================================
:resolved
REM ============================================================
if not exist "%SRC%" (
    echo  [ERROR] source file does not exist: %SRC%
    pause & exit /b 1
)

for %%F in ("%SRC%") do (
    set "SRCDIR=%%~dpF"
    set "SRCREL=%%~fF"
    set "BASE=%%~nF"
)
set "SRCREL=!SRCREL:%ROOT%=!"
set "EXE=%OUTDIR%\%BASE%.exe"

REM ============================================================
REM  Collect companion sources
REM   note: for %%C in ("dir\*.cpp") does NOT expand wildcards
REM         when the pattern is quoted -> use dir /b instead.
REM ============================================================
set "EXTRA="
set "EXTRALIST="
set "RDC="
set "INCS=-I "!SRCDIR!.""

REM ---- (1) common\ : always included ----
if exist "%COMMON%\" (
    set "INCS=!INCS! -I "%COMMON%""

    for /f "delims=" %%C in ('dir /b /a-d "%COMMON%\*.cpp" 2^>nul') do (
        set "EXTRA=!EXTRA! "%COMMON%\%%C""
        set "EXTRALIST=!EXTRALIST! common\%%C"
    )

    REM  a .cu in common\ needs relocatable device code
    for /f "delims=" %%C in ('dir /b /a-d "%COMMON%\*.cu" 2^>nul') do (
        set "EXTRA=!EXTRA! "%COMMON%\%%C""
        set "EXTRALIST=!EXTRALIST! common\%%C"
        set "RDC=-rdc=true"
    )
)

REM ---- (2) .cpp next to the source ----
if /i not "!SRCDIR!"=="%COMMON%\" (
    for /f "delims=" %%C in ('dir /b /a-d "!SRCDIR!*.cpp" 2^>nul') do (
        set "EXTRA=!EXTRA! "!SRCDIR!%%C""
        set "EXTRALIST=!EXTRALIST! %%C"
    )
)

REM ============================================================
REM  3. VS2022 x64 environment (skip if already loaded)
REM ============================================================
if not defined VSCMD_ARG_TGT_ARCH (
    echo.
    echo Loading x64 build environment...
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul
    if errorlevel 1 (
        echo  [ERROR] vcvars64.bat failed. Check your Visual Studio path.
        pause & exit /b 1
    )
)

REM ============================================================
REM  4. Compile
REM ============================================================
echo.
echo ===================================================
echo  source : !SRCREL!
if defined EXTRALIST echo  extra  :!EXTRALIST!
echo  output : build\%BASE%.exe
echo ===================================================
echo.

for /f %%i in ('powershell -NoProfile -Command "(Get-Date).Ticks"') do set "T0=%%i"

echo [cmd] nvcc "%SRC%"!EXTRA! -o "%EXE%" -arch=native !RDC! ...
echo.
nvcc "%SRC%"!EXTRA! -o "%EXE%" -arch=native !RDC! -lineinfo -O2 !INCS! --time "%OUTDIR%\compile_time.csv" -Xcompiler "/utf-8 /wd4819 /O2"

set "NVCC_ERR=%errorlevel%"

for /f %%i in ('powershell -NoProfile -Command "[math]::Round(((Get-Date).Ticks - %T0%) / 10000000, 2)"') do set "ELAPSED=%%i"

if not "%NVCC_ERR%"=="0" (
    echo.
    echo  [BUILD FAILED]  elapsed: %ELAPSED% s
    echo   Check the FIRST error message above.
    echo.
    pause & exit /b 1
)

echo.
echo  [BUILD OK]  elapsed: %ELAPSED% s
echo   per-stage breakdown: build\compile_time.csv

REM ============================================================
REM  5. Run  (chcp only affects the child cmd)
REM ============================================================
if not defined RUNARGS (
    echo.
    set /p "RUNARGS=Program arguments (e.g. 4 4 4, Enter = none): "
)

echo.
echo ---------------- program output ----------------
pushd "%SRCDIR%"
cmd /c "chcp 65001 > nul & "%EXE%" !RUNARGS!"
set "RUN_ERR=!errorlevel!"
popd
echo -----------------------------------------------
echo  exit code: !RUN_ERR!
echo.

pause
endlocal
