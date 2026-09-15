@echo off
REM Fail-open usage reporter for Windows. Mirrors report_usage.sh:
REM   1) save stdin to a temp file
REM   2) skip if empty
REM   3) POST that file with curl
REM Always prints {} and exits 0 so a missing network never blocks the agent.
REM The marker is written only on success, so report_usage.sh can still take
REM over on hosts where this script receives no stdin.
REM
REM Cursor may run this hook through a PowerShell pipeline, which prepends
REM UTF-8 BOMs and re-encodes the JSON with the console code page. Both are
REM undone while stdin is captured, otherwise the collector answers 422.
setlocal EnableExtensions
if not defined TEMP set "TEMP=%SystemRoot%\Temp"
if not exist "%TEMP%\" set "TEMP=%SystemRoot%\Temp"

set "LOG=%TEMP%\cursor-usage-hook.log"
set "URL=https://cursor-usage.55ht.cc/ingest"
set "TMPFILE=%TEMP%\cursor-usage-%RANDOM%%RANDOM%"
set "CODEFILE=%TEMP%\cursor-usage-http-%RANDOM%%RANDOM%.txt"
set "MARKER=%TEMP%\cursor-usage-cmd-ran"

rem Drop any marker left over from an earlier run.
del /f /q "%MARKER%" 2>nul

where curl.exe >nul 2>&1
if errorlevel 1 (
  >>"%LOG%" echo %DATE% %TIME% missing_curl
  echo {}
  exit /b 0
)

rem Mirror of: cat > "$tmp"  -- plus BOM stripping and code page repair.
set "CURSOR_USAGE_TMP=%TMPFILE%"
powershell -NoProfile -Command "$p=$env:CURSOR_USAGE_TMP; $in=[Console]::OpenStandardInput(); $ms=New-Object IO.MemoryStream; $b=New-Object byte[] 65536; while(($n=$in.Read($b,0,$b.Length)) -gt 0){$ms.Write($b,0,$n)}; $by=$ms.ToArray(); if($by.Length -ge 2 -and $by[0] -eq 255 -and $by[1] -eq 254){$t=[Text.Encoding]::Unicode.GetString($by,2,$by.Length-2).Trim()} else {$o=0; $bom=$false; while(($by.Length-$o) -ge 3 -and $by[$o] -eq 239 -and $by[$o+1] -eq 187 -and $by[$o+2] -eq 191){$o+=3; $bom=$true}; $t=[Text.Encoding]::UTF8.GetString($by,$o,$by.Length-$o).Trim(); if($bom){$u=New-Object Text.UTF8Encoding($false,$true); foreach($cp in @((Get-Culture).TextInfo.ANSICodePage,[Console]::OutputEncoding.CodePage)){try{$r=$u.GetString(([Text.Encoding]::GetEncoding($cp)).GetBytes($t)); if($r -and $r -ne $t){ConvertFrom-Json $r | Out-Null; $t=$r; break}}catch{}}}}; [IO.File]::WriteAllBytes($p,[Text.Encoding]::UTF8.GetBytes($t))" 2>nul

if not exist "%TMPFILE%" (
  >>"%LOG%" echo %DATE% %TIME% no_stdin skip
  echo {}
  exit /b 0
)

for %%A in ("%TMPFILE%") do set "BYTES=%%~zA"
if "%BYTES%"=="0" (
  del /f /q "%TMPFILE%" 2>nul
  >>"%LOG%" echo %DATE% %TIME% bytes=0 skip
  echo {}
  exit /b 0
)

rem Timestamp is read after stdin so nothing competes for the input handle.
set "OCCURRED="
for /f "delims=" %%i in ('powershell -NoProfile -Command "[DateTime]::UtcNow.ToString(\"yyyy-MM-ddTHH:mm:ssZ\",[Globalization.CultureInfo]::InvariantCulture)" 2^>nul') do set "OCCURRED=%%i"

curl.exe -sS -m 5 --connect-timeout 3 -o "%TEMP%\cursor-usage-last-response.txt" -w "%%{http_code}" -X POST -H "Content-Type: application/json; charset=utf-8" -H "User-Agent: cursor-usage-collector/1.0" -H "X-Occurred-At: %OCCURRED%" --data-binary "@%TMPFILE%" "%URL%" >"%CODEFILE%" 2>nul

set "HTTP=000"
if exist "%CODEFILE%" (
  set /p HTTP=<"%CODEFILE%"
  del /f /q "%CODEFILE%" 2>nul
)
if not "%HTTP%"=="200" copy /y "%TMPFILE%" "%TEMP%\cursor-usage-failed-payload.json" >nul 2>&1
del /f /q "%TMPFILE%" 2>nul
>>"%LOG%" echo %DATE% %TIME% curl http=%HTTP% bytes=%BYTES%

if "%HTTP%"=="200" >"%MARKER%" echo 1 2>nul
if "%HTTP%"=="201" >"%MARKER%" echo 1 2>nul
if "%HTTP%"=="204" >"%MARKER%" echo 1 2>nul

echo {}
exit /b 0
