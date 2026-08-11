[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir "srcds.exe"
$runningServer = Get-CimInstance Win32_Process -Filter "Name = 'srcds.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe) }
if ($runningServer) {
    throw "Stop the target srcds.exe before installing unified LAN identity plugins."
}

$source = Join-Path $PSScriptRoot "mods\lan_player_scoreboard.sp"
$scriptingDir = Join-Path $ServerDir "csgo\addons\sourcemod\scripting"
$compiler = Join-Path $scriptingDir "spcomp.exe"
$installedSource = Join-Path $scriptingDir "lan_player_scoreboard.sp"
$plugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\000_lan_player_identity.smx"
$oldPlugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\lan_player_scoreboard.smx"

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "SourceMod compiler was not found after applying the MOD overlay: '$compiler'"
}

Copy-Item -LiteralPath $source -Destination $installedSource -Force
& $compiler "-o$plugin" $installedSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $plugin)) {
    throw "Failed to compile lan_player_scoreboard.sp (exit code $LASTEXITCODE)."
}

if (Test-Path -LiteralPath $oldPlugin) {
    Remove-Item -LiteralPath $oldPlugin -Force
}

Write-Host "Installed unified LAN player identity support."

$agentsPlugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\csgo_agentschooser.smx"
$agentsBackup = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\disabled\csgo_agentschooser.mysql-original.smx"
$databaseConfigPath = Join-Path $ServerDir "csgo\addons\sourcemod\configs\databases.cfg"
$databaseConfig = Get-Content -LiteralPath $databaseConfigPath -Raw
$agentsBlock = [regex]::Match($databaseConfig, '(?ms)"agents"\s*\{(?<body>.*?)\}')
if (-not $agentsBlock.Success) {
    throw "The agents database entry was not found in '$databaseConfigPath'."
}

$driverMatch = [regex]::Match($agentsBlock.Groups['body'].Value, '(?m)"driver"\s*"(?<driver>[^"]+)"')
if (-not $driverMatch.Success) {
    throw "The agents database driver was not found in '$databaseConfigPath'."
}

$agentsDriver = $driverMatch.Groups['driver'].Value.ToLowerInvariant()
if ($agentsDriver -eq "default") {
    $defaultDriver = [regex]::Match($databaseConfig, '(?m)"driver_default"\s*"(?<driver>[^"]+)"')
    if (-not $defaultDriver.Success) {
        throw "driver_default was not found in '$databaseConfigPath'."
    }
    $agentsDriver = $defaultDriver.Groups['driver'].Value.ToLowerInvariant()
}

if ($agentsDriver -notin @("sqlite", "mysql")) {
    throw "Unsupported agents database driver: '$agentsDriver'"
}

& (Join-Path $PSScriptRoot "mods\patch_agents_database.ps1") -PluginPath $agentsPlugin -BackupPath $agentsBackup -DatabaseDriver $agentsDriver
& (Join-Path $PSScriptRoot "mods\patch_lan_identity_natives.ps1") -ServerDir $ServerDir
