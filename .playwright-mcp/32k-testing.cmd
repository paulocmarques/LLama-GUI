@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "APP_DIR=C:\Users\pegas\Downloads\LLM\Misc LLM Programs\Llama GUI - Repo - USE THIS\REPO\LLama-GUI"
set "APP_HOST=127.0.0.1"
set "APP_PORT=5240"
set "APP_URL=http://127.0.0.1:5240/?preset=32k%%20testing"
cd /d "%APP_DIR%"
set "PY_CMD="
if exist ".venv\Scripts\python.exe" (
    set "PY_CMD=.venv\Scripts\python.exe"
) else (
    where python >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        set "PY_CMD=python"
    ) else (
        where py >nul 2>&1
        if !ERRORLEVEL! EQU 0 set "PY_CMD=py -3"
    )
)
if not defined PY_CMD (
    echo [ERROR] Python was not found on this system.
    echo.
    echo Run windows_install.bat first, or install Python 3 and ensure it is available in PATH.
    echo Download: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $client = [Net.Sockets.TcpClient]::new(); $connect = $client.BeginConnect($env:APP_HOST, [int]$env:APP_PORT, $null, $null); if ($connect.AsyncWaitHandle.WaitOne(300)) { $client.EndConnect($connect); $client.Close(); exit 0 }; $client.Close(); exit 1 } catch { exit 1 }" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    start "" "%APP_URL%" >nul 2>&1
    exit /b 0
)
start "Llama GUI Server" /min cmd /c "%PY_CMD% server.py"
timeout /t 2 /nobreak >nul
start "" "%APP_URL%" >nul 2>&1
exit /b 0
