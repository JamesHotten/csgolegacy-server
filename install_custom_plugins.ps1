[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$source = Join-Path $PSScriptRoot "mods\lan_player_scoreboard.sp"
$scriptingDir = Join-Path $ServerDir "csgo\addons\sourcemod\scripting"
$compiler = Join-Path $scriptingDir "spcomp.exe"
$installedSource = Join-Path $scriptingDir "lan_player_scoreboard.sp"
$plugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\lan_player_scoreboard.smx"

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "SourceMod compiler was not found after applying the MOD overlay: '$compiler'"
}

Copy-Item -LiteralPath $source -Destination $installedSource -Force
& $compiler "-o$plugin" $installedSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $plugin)) {
    throw "Failed to compile lan_player_scoreboard.sp (exit code $LASTEXITCODE)."
}

Write-Host "Installed LAN scoreboard reconnect support."
