$ErrorActionPreference = "SilentlyContinue"

$stateDir = Join-Path $env:TEMP "AoTGrapple"
$pidFile = Join-Path $stateDir "server.pid"
$commandFile = Join-Path $stateDir "command.txt"

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
Set-Content -LiteralPath $commandFile -Value ("stop " + [DateTimeOffset]::Now.ToUnixTimeMilliseconds()) -Force

exit 0

