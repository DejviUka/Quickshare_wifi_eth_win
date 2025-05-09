@echo off
REM ───────────────────────────────────────────────
REM run-wifishare.cmd
REM ───────────────────────────────────────────────
REM Change into this batch file’s folder
pushd "%~dp0"

REM Run the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "wifishare.ps1"

REM Restore original folder
popd

REM Pause so you can see any output/errors
pause
