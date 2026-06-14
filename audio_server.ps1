$ErrorActionPreference = "SilentlyContinue"

$stateDir = Join-Path $env:TEMP "AoTGrapple"
$pidFile = Join-Path $stateDir "server.pid"
$commandFile = Join-Path $stateDir "command.txt"

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

if (Test-Path -LiteralPath $pidFile) {
    $oldPid = Get-Content -LiteralPath $pidFile | Select-Object -First 1
    if ($oldPid -match '^\d+$' -and [int]$oldPid -ne $PID) {
        Stop-Process -Id ([int]$oldPid) -Force
    }
}

Set-Content -LiteralPath $pidFile -Value $PID -Force

$candidates = @(
    "ue4ss\Mods\AoTGrapple\grapple.wav",
    "Mods\AoTGrapple\grapple.wav",
    "grapple.wav"
)

$soundPath = $null
foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
        $soundPath = $path
        break
    }
}

if (-not $soundPath) {
    exit 2
}

$player = New-Object System.Media.SoundPlayer $soundPath
$player.Load()
$lastCommand = ""
$palworldWasSeen = $false

function Test-PalworldRunning {
    return [bool](Get-Process -Name "Palworld-Win64-Shipping", "Palworld" -ErrorAction SilentlyContinue)
}

while ($true) {
    if (Test-PalworldRunning) {
        $palworldWasSeen = $true
    } elseif ($palworldWasSeen) {
        $player.Stop()
        break
    }

    if (Test-Path -LiteralPath $commandFile) {
        $command = Get-Content -LiteralPath $commandFile -Raw
        if ($command -and $command -ne $lastCommand) {
            $lastCommand = $command
            if ($command -like "play*") {
                $player.Stop()
                $player.Play()
            } elseif ($command -like "stop*") {
                $player.Stop()
            } elseif ($command -like "quit*") {
                $player.Stop()
                break
            }
        }
    }
    Start-Sleep -Milliseconds 20
}

Remove-Item -LiteralPath $pidFile -Force

