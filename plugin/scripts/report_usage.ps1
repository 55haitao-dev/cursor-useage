# Fail-open usage reporter for Windows. Uses PowerShell only (no curl/Python).
# Prefer payload file from report_usage.cmd (stdin is unreliable after nesting).
# Falls back to $input / redirected stdin for manual pipe tests.
param(
    [Parameter(Position = 0)]
    [string]$PayloadFile
)

$ErrorActionPreference = 'Stop'
$logLine = {
    param([string]$msg)
    try {
        $log = Join-Path $env:TEMP 'cursor-usage-hook.log'
        Add-Content -LiteralPath $log -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $body = $null
    $mode = 'none'
    if ($PayloadFile -and (Test-Path -LiteralPath $PayloadFile)) {
        $body = [IO.File]::ReadAllBytes($PayloadFile)
        $mode = 'file'
    }
    else {
        $text = ($input | Out-String)
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $body = [Text.Encoding]::UTF8.GetBytes($text.Trim())
            $mode = 'input'
        }
        elseif ([Console]::IsInputRedirected) {
            $ms = New-Object System.IO.MemoryStream
            $buf = New-Object byte[] 8192
            $stdin = [Console]::OpenStandardInput()
            while (($n = $stdin.Read($buf, 0, $buf.Length)) -gt 0) {
                $ms.Write($buf, 0, $n)
            }
            $body = $ms.ToArray()
            $mode = 'stdin'
        }
    }

    if (-not $body -or $body.Length -eq 0) {
        & $logLine ("{0:u} mode={1} bytes=0 skip" -f (Get-Date).ToUniversalTime(), $mode)
        exit 0
    }

    $occurred = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $req = [System.Net.HttpWebRequest]::Create('https://cursor-usage.55ht.cc/ingest')
    $req.Method = 'POST'
    $req.ContentType = 'application/json; charset=utf-8'
    $req.UserAgent = 'cursor-usage-collector/1.0'
    $req.Timeout = 5000
    $req.ReadWriteTimeout = 5000
    [void]$req.Headers.Add('X-Occurred-At', $occurred)
    $req.ContentLength = $body.Length
    $stream = $req.GetRequestStream()
    $stream.Write($body, 0, $body.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $resp.Close()
    & $logLine ("{0:u} mode={1} bytes={2} http={3}" -f (Get-Date).ToUniversalTime(), $mode, $body.Length, $code)
}
catch {
    & $logLine ("{0:u} error={1}" -f (Get-Date).ToUniversalTime(), $_.Exception.Message)
}
exit 0
