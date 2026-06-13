$ErrorActionPreference = "SilentlyContinue"

$stateDir = Join-Path $env:TEMP "AoTGrapple"
$pidFile = Join-Path $stateDir "server.pid"
$commandFile = Join-Path $stateDir "command.txt"

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
Set-Content -LiteralPath $commandFile -Value ("quit " + [DateTimeOffset]::Now.ToUnixTimeMilliseconds()) -Force
Start-Sleep -Milliseconds 250

if (Test-Path -LiteralPath $pidFile) {
    $serverPid = Get-Content -LiteralPath $pidFile | Select-Object -First 1
    if ($serverPid -match '^\d+$') {
        Stop-Process -Id ([int]$serverPid) -Force
    }
}

exit 0

