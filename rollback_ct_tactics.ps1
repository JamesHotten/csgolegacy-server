[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir "srcds.exe"
if (-not (Test-Path -LiteralPath $serverExe)) {
    throw "srcds.exe was not found in '$ServerDir'. Pass the exact App 740 server directory."
}

$runningServer = Get-CimInstance Win32_Process -Filter "Name = 'srcds.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe) }
if ($runningServer) {
    throw "Stop the target srcds.exe before full rollback. For immediate live rollback, run: sm_bot_ct_tactics_enable 0"
}

$smRoot = Join-Path $ServerDir "csgo\addons\sourcemod"
$backupDir = Join-Path $smRoot "data\ct-tactics-rollback"
$backupSource = Join-Path $backupDir "bot_stuff.original.sp"
$backupPlugin = Join-Path $backupDir "bot_stuff.original.smx"
$backupProfileConfig = Join-Path $backupDir "bot_stuff.original.cfg"
$botSource = Join-Path $smRoot "scripting\bot_stuff.sp"
$botPlugin = Join-Path $smRoot "plugins\bot_stuff.smx"
$profileConfig = Join-Path $smRoot "configs\bot_stuff.cfg"

foreach ($backup in @($backupSource, $backupPlugin)) {
    if (-not (Test-Path -LiteralPath $backup)) {
        throw "Rollback backup was not found: '$backup'"
    }
}

Copy-Item -LiteralPath $backupSource -Destination $botSource -Force
Copy-Item -LiteralPath $backupPlugin -Destination $botPlugin -Force
if (Test-Path -LiteralPath $backupProfileConfig) {
    Copy-Item -LiteralPath $backupProfileConfig -Destination $profileConfig -Force
}

$directorFiles = @(
    (Join-Path $smRoot "plugins\001_bot_ct_tactics.smx"),
    (Join-Path $smRoot "plugins\002_bot_t_tactics.smx"),
    (Join-Path $smRoot "scripting\bot_ct_tactics.sp"),
    (Join-Path $smRoot "scripting\bot_t_tactics.sp"),
    (Join-Path $ServerDir "csgo\cfg\sourcemod\bot_ct_tactics.cfg"),
    (Join-Path $ServerDir "csgo\cfg\sourcemod\bot_t_tactics.cfg")
)
foreach ($file in $directorFiles) {
    if (Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
    }
}

Write-Host "CT and T tactical directors fully rolled back. Original bot_stuff.sp, bot_stuff.smx and saved profile cfg were restored."
Write-Host "Rollback backups were retained in '$backupDir' for recovery/audit."
