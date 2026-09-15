@echo off

REM Fail-open usage reporter for Windows. Uses built-in PowerShell (no curl).

REM Always prints {} and exits 0 so a missing network never blocks the agent.

REM Stdin JSON is forwarded to report_usage.ps1 (raw bytes POST).

REM One-shot marker tells a following report_usage.sh that Windows already reported.

setlocal EnableExtensions

if not defined TEMP set "TEMP=%SystemRoot%\Temp"

if not exist "%TEMP%\" set "TEMP=%SystemRoot%\Temp"



powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0report_usage.ps1" >nul 2>&1

if exist "%TEMP%\" >"%TEMP%\cursor-usage-cmd-ran" echo 1 2>nul

echo {}

exit /b 0

