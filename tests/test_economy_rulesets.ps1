[CmdletBinding()]
param(
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ServerDir)) {
    $ServerDir = Join-Path (Split-Path -Parent $repoRoot) "server"
}
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Message
    )
    if (-not $Text.Contains($Expected)) {
        throw $Message
    }
}

$mainSource = Get-Content -LiteralPath (Join-Path $repoRoot "mods\lan_player_scoreboard.sp") -Raw
$legacySource = Get-Content -LiteralPath (Join-Path $repoRoot "mods\lan_economy_csgo.inc") -Raw
$cs2Source = Get-Content -LiteralPath (Join-Path $repoRoot "mods\lan_economy_cs2.inc") -Raw
$mr12Config = Get-Content -LiteralPath (Join-Path $repoRoot "config\mr12.cfg") -Raw
$deploymentScript = Get-Content -LiteralPath (Join-Path $repoRoot "apply_mods.ps1") -Raw

Assert-Contains $mainSource 'CreateConVar("sm_lan_economy_ruleset", "0"' `
    "The default ruleset must remain the original CS:GO-compatible behavior."
Assert-Contains $mainSource 'if (g_eEconomyRuleset == LanEconomy_Cs2Current)' `
    "The runtime ruleset dispatch is missing."
Assert-Contains $mainSource 'ClearEconomyPhaseState();' `
    "Ruleset changes must invalidate pending reconnect economy."

foreach ($cashConVar in @(
    "cash_team_loser_bonus",
    "cash_team_loser_bonus_consecutive_rounds",
    "cash_team_planted_bomb_but_defused",
    "cash_team_terrorist_win_bomb",
    "cash_team_win_by_defusing_bomb",
    "cash_team_win_by_time_running_out_bomb",
    "cash_team_win_by_hostage_rescue",
    "cash_team_win_by_time_running_out_hostage",
    "cash_team_elimination_bomb_map",
    "cash_team_elimination_hostage_map_ct",
    "cash_team_elimination_hostage_map_t"
)) {
    Assert-Contains $legacySource $cashConVar "Legacy economy lost required cvar '$cashConVar'."
}

Assert-Contains $cs2Source 'team != CS_TEAM_CT' "CS2 bonus must be restricted to CT players."
Assert-Contains $cs2Source 'terroristEliminations * perEliminationBonus' `
    "CS2 CT elimination bonus calculation is missing."
Assert-Contains $cs2Source 'LanEconomyCsgo_GetOfflineTeamAward' `
    "CS2 ruleset must retain the shared base round awards."
Assert-Contains $mr12Config 'mp_maxrounds 24' "MR12 must use 12-round halves."
Assert-Contains $mr12Config 'mp_overtime_maxrounds 6' "MR12 overtime must use three rounds per half."
Assert-Contains $mr12Config 'sm_lan_economy_ruleset 1' `
    "Executing mr12.cfg must enable the current CS2 economy policy."
Assert-Contains $mr12Config 'sm_lan_economy_cs2_ct_kill_bonus 50' `
    "MR12 must configure the official CS2 CT elimination award."
Assert-Contains $deploymentScript 'config\mr12.cfg' `
    "Fresh deployments must install mr12.cfg."

$scriptingDir = Join-Path $ServerDir "csgo\addons\sourcemod\scripting"
$compiler = Join-Path $scriptingDir "spcomp.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "SourceMod compiler was not found: '$compiler'"
}

$output = Join-Path ([System.IO.Path]::GetTempPath()) ("lan-economy-test-{0}.smx" -f [guid]::NewGuid())
try {
    & $compiler (Join-Path $repoRoot "mods\lan_player_scoreboard.sp") `
        ("-i{0}" -f (Join-Path $scriptingDir "include")) ("-o{0}" -f $output)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
        throw "SourcePawn economy ruleset compilation failed."
    }
}
finally {
    if (Test-Path -LiteralPath $output) {
        [System.IO.File]::Delete($output)
    }
}

Write-Host "LAN economy ruleset regression checks passed."
