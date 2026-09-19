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
$economyPolicySources = @(
    (Join-Path $PSScriptRoot "mods\lan_economy_policy.inc"),
    (Join-Path $PSScriptRoot "mods\lan_economy_csgo.inc"),
    (Join-Path $PSScriptRoot "mods\lan_economy_cs2.inc")
)
$scriptingDir = Join-Path $ServerDir "csgo\addons\sourcemod\scripting"
$compiler = Join-Path $scriptingDir "spcomp.exe"
$installedSource = Join-Path $scriptingDir "lan_player_scoreboard.sp"
$plugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\000_lan_player_identity.smx"
$oldPlugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\lan_player_scoreboard.smx"

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "SourceMod compiler was not found after applying the MOD overlay: '$compiler'"
}

Copy-Item -LiteralPath $source -Destination $installedSource -Force
foreach ($policySource in $economyPolicySources) {
    if (-not (Test-Path -LiteralPath $policySource)) {
        throw "LAN economy policy source was not found: '$policySource'"
    }
    Copy-Item -LiteralPath $policySource -Destination (Join-Path $scriptingDir ([System.IO.Path]::GetFileName($policySource))) -Force
}
& $compiler "-o$plugin" $installedSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $plugin)) {
    throw "Failed to compile lan_player_scoreboard.sp (exit code $LASTEXITCODE)."
}

if (Test-Path -LiteralPath $oldPlugin) {
    Remove-Item -LiteralPath $oldPlugin -Force
}

Write-Host "Installed unified LAN player identity support."

$teamLogoSource = Join-Path $PSScriptRoot "mods\teamlogos_current_only.sp"
$installedTeamLogoSource = Join-Path $scriptingDir "teamlogos_current_only.sp"
$teamLogoPlugin = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\teamlogos.smx"
$teamLogoBackup = Join-Path $ServerDir "csgo\addons\sourcemod\plugins\disabled\teamlogos.bulk-download-original.smx"

if (-not (Test-Path -LiteralPath $teamLogoSource)) {
    throw "Current-only team logo source was not found: '$teamLogoSource'"
}

Copy-Item -LiteralPath $teamLogoSource -Destination $installedTeamLogoSource -Force
if ((Test-Path -LiteralPath $teamLogoPlugin) -and -not (Test-Path -LiteralPath $teamLogoBackup)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $teamLogoBackup) -Force | Out-Null
    Copy-Item -LiteralPath $teamLogoPlugin -Destination $teamLogoBackup
}
& $compiler "-o$teamLogoPlugin" $installedTeamLogoSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $teamLogoPlugin)) {
    throw "Failed to compile teamlogos_current_only.sp (exit code $LASTEXITCODE)."
}

Write-Host "Installed current-only team logo download support."

$sourceModConfigPath = Join-Path $ServerDir "csgo\cfg\sourcemod\sourcemod.cfg"
if (-not (Test-Path -LiteralPath $sourceModConfigPath)) {
    throw "SourceMod configuration was not found: '$sourceModConfigPath'"
}
$sourceModConfigText = Get-Content -LiteralPath $sourceModConfigPath -Raw
if ($sourceModConfigText -notmatch '(?m)^\s*teamlogo_randomlogos\s+') {
    throw "teamlogo_randomlogos was not found in '$sourceModConfigPath'."
}
$sourceModConfigText = $sourceModConfigText -replace '(?m)^\s*teamlogo_randomlogos\s+\S+\s*$', 'teamlogo_randomlogos 0'
[System.IO.File]::WriteAllText($sourceModConfigPath, $sourceModConfigText, [System.Text.UTF8Encoding]::new($false))

$teamLogoMaterialDir = Join-Path $ServerDir "csgo\materials\panorama\images\tournaments\teams"
$teamLogoConfigDir = Join-Path $ServerDir "csgo\resource\flash\econ\tournaments\teams"
$botRosterPath = Join-Path $ServerDir "csgo\addons\sourcemod\configs\bot_rosters.txt"
$legacyLogoAliases = @{
    "fisher" = "fishr"
    "rustec" = "rustc"
}

foreach ($entry in $legacyLogoAliases.GetEnumerator()) {
    $sourceLogo = Join-Path $teamLogoMaterialDir ($entry.Key + ".svg")
    $targetLogo = Join-Path $teamLogoMaterialDir ($entry.Value + ".svg")
    $sourceConfig = Join-Path $teamLogoConfigDir ($entry.Key + ".cfg")
    $targetConfig = Join-Path $teamLogoConfigDir ($entry.Value + ".cfg")

    if (-not (Test-Path -LiteralPath $sourceLogo) -or -not (Test-Path -LiteralPath $sourceConfig)) {
        throw "Required team logo assets were not found for legacy ID '$($entry.Key)'."
    }

    Copy-Item -LiteralPath $sourceLogo -Destination $targetLogo -Force
    Copy-Item -LiteralPath $sourceConfig -Destination $targetConfig -Force
}

if (-not (Test-Path -LiteralPath $botRosterPath)) {
    throw "BetterBots roster configuration was not found: '$botRosterPath'"
}

$botRosterText = Get-Content -LiteralPath $botRosterPath -Raw
foreach ($entry in $legacyLogoAliases.GetEnumerator()) {
    $botRosterText = $botRosterText -replace ('(?m)("logo"\s+")' + [regex]::Escape($entry.Key) + '("\s*)$'), ('${1}' + $entry.Value + '${2}')
}
[System.IO.File]::WriteAllText($botRosterPath, $botRosterText, [System.Text.UTF8Encoding]::new($false))

Write-Host "Installed five-character Legacy aliases for long team logo IDs."

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
& (Join-Path $PSScriptRoot "mods\install_ct_tactics.ps1") -ServerDir $ServerDir
