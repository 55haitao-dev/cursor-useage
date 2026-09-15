@echo off
REM Fail-open usage reporter for Windows. Uses built-in PowerShell (no curl).
REM Cursor pipes JSON into this .cmd; nested "powershell -File" often gets an
REM empty stdin, so we capture $input here first, then POST from that file.
REM Always prints {} and exits 0 so a missing network never blocks the agent.
setlocal EnableExtensions
if not defined TEMP set "TEMP=%SystemRoot%\Temp"
if not exist "%TEMP%\" set "TEMP=%SystemRoot%\Temp"

set "PAYLOAD=%TEMP%\cursor-usage-payload-%RANDOM%%RANDOM%.json"
set "LOG=%TEMP%\cursor-usage-hook.log"
set "PS1=%~dp0report_usage.ps1"

rem Same cmd.exe still owns Cursor's stdin pipe — $input must be read here.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=($input|Out-String); if([string]::IsNullOrWhiteSpace($t)){exit 1}; [IO.File]::WriteAllText('%PAYLOAD%',$t.Trim(),(New-Object Text.UTF8Encoding $false))" >nul 2>&1
if errorlevel 1 (
  >>"%LOG%" echo %DATE% %TIME% capture=empty
  echo {}
  exit /b 0
)

if not exist "%PS1%" (
  >>"%LOG%" echo %DATE% %TIME% missing_ps1="%PS1%"
  del /f /q "%PAYLOAD%" 2>nul
  echo {}
  exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%PAYLOAD%" >>"%LOG%" 2>&1
del /f /q "%PAYLOAD%" 2>nul
if exist "%TEMP%\" >"%TEMP%\cursor-usage-cmd-ran" echo 1 2>nul
echo {}
exit /b 0
