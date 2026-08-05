@echo off
setlocal EnableDelayedExpansion
chcp 65001 > nul
cd /d "%~dp0"

REM ============================================================
REM  사용법 :  build.bat            -> test.cu 빌드
REM            build.bat foo.cu     -> foo.cu 빌드
REM            .cu 파일을 이 배치파일에 드래그&드롭해도 됩니다
REM ============================================================

REM ---- 대상 소스 결정 ----
if "%~1"=="" (set "SRC=test.cu") else (set "SRC=%~nx1")
set "EXE=%~n0_out.exe"
for %%F in ("%SRC%") do set "EXE=%%~nF.exe"

if not exist "%SRC%" (
    echo [오류] 소스 파일을 찾을 수 없습니다: %SRC%
    pause & exit /b 1
)

REM ---- 1. VS2022 x64 환경 (이미 로드됐으면 건너뜀) ----
if not defined VSCMD_ARG_TGT_ARCH (
    echo x64 빌드 환경을 로드하는 중입니다...
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" > nul
    if errorlevel 1 (
        echo [오류] vcvars64.bat 실행 실패. Visual Studio 경로를 확인하세요.
        pause & exit /b 1
    )
)

REM ---- 2. 컴파일 시작 시각 기록 ----
for /f %%i in ('powershell -NoProfile -Command "(Get-Date).Ticks"') do set "T0=%%i"

echo.
echo ===================================================
echo  컴파일: %SRC%  ^-^>  %EXE%
echo ===================================================

REM ---- 3. 컴파일 ----
REM   -arch=native   : 내 GPU에 맞는 아키텍처로 컴파일 (CUDA 11.5+)
REM                    구버전이면 -arch=sm_86 처럼 직접 지정
REM   -lineinfo      : 프로파일러(ncu/nsys)에서 소스 줄 매핑
REM   -O2            : 호스트 코드 최적화
REM   --time         : nvcc 단계별 컴파일 시간을 CSV로 기록
nvcc "%SRC%" -o "%EXE%" ^
     -arch=native ^
     -lineinfo ^
     -O2 ^
     --time compile_time.csv ^
     -Xcompiler "/utf-8 /wd4819 /O2"

set "NVCC_ERR=%errorlevel%"

REM ---- 4. 컴파일 소요 시간 출력 ----
for /f %%i in ('powershell -NoProfile -Command "[math]::Round(((Get-Date).Ticks - %T0%) / 10000000, 2)"') do set "ELAPSED=%%i"

if not "%NVCC_ERR%"=="0" (
    echo.
    echo [컴파일 실패] 소요 시간: %ELAPSED% 초
    echo   -^> 위 에러 메시지에서 '첫 번째' 에러부터 확인하세요.
    echo.
    pause & exit /b 1
)

echo.
echo [컴파일 성공] 소요 시간: %ELAPSED% 초
echo   ^(단계별 상세: compile_time.csv^)
echo.
echo ---------------- 실행 결과 ----------------
"%EXE%"
set "RUN_ERR=%errorlevel%"
echo -------------------------------------------
echo 프로그램 종료 코드: %RUN_ERR%
echo.

REM ---- 5. 프로파일링 옵션 안내 ----
echo [참고] 더 자세한 GPU 분석
echo    nsys profile --stats=true %EXE%      ^(타임라인/전송/커널^)
echo    ncu --set full %EXE%                 ^(커널 내부 지표^)
echo.

pause
endlocal