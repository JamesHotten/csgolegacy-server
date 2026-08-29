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
$mr15Config = Get-Content -LiteralPath (Join-Path $repoRoot "config\mr15.cfg") -Raw
$competitiveOverride = Get-Content -LiteralPath (Join-Path $repoRoot "config\gamemode_competitive_server.cfg") -Raw
$deploymentScript = Get-Content -LiteralPath (Join-Path $repoRoot "apply_mods.ps1") -Raw

Assert-Contains $mainSource 'CreateConVar("sm_lan_economy_ruleset", "0"' `
    "The default ruleset must remain the original CS:GO-compatible behavior."
Assert-Contains $mainSource 'if (g_eEconomyRuleset == LanEconomy_Cs2Current)' `
    "The runtime ruleset dispatch is missing."
Assert-Contains $mainSource 'ClearEconomyPhaseState();' `
    "Ruleset changes must invalidate pending reconnect economy."
Assert-Contains $mainSource 'RegConsoleCmd("sm_refund"' `
	"The public CS2 refund command is missing."
Assert-Contains $mainSource 'RegServerCmd("sm_lan_economy_apply"' `
	"The atomic mode-apply command is missing."
Assert-Contains $mainSource 'LanEconomy_CanRefund' `
    "The refund command must enforce the public refund policy."
Assert-Contains $mainSource 'g_bRefundUsed[client][index] ||' `
    "Used refund entries must be recycled so later purchases remain refundable."
foreach ($requiredInvalidation in @(
    'HookEvent("weapon_fire"',
    'HookEvent("player_hurt"',
    'HookEvent("bomb_begindefuse"',
    'CS_OnCSWeaponDrop',
    'InvalidateAllRefunds(GetClientOfUserId(event.GetInt("userid")))',
    'ClearAllRefundState()'
)) {
    Assert-Contains $mainSource $requiredInvalidation `
        "Refund invalidation path '$requiredInvalidation' is missing."
}

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
Assert-Contains $mr12Config 'sm_lan_economy_apply 1' `
    "Executing mr12.cfg must atomically apply the complete CS2 policy."
if ($mr12Config -match '(?m)^mp_') {
    throw "mr12.cfg must not mutate match CVars outside the plugin transaction."
}
Assert-Contains $deploymentScript 'config\mr12.cfg' `
    "Fresh deployments must install mr12.cfg."
Assert-Contains $mr15Config 'sm_lan_economy_apply 0' `
    "Executing mr15.cfg must atomically restore the CS:GO economy policy."
if ($mr15Config -match '(?m)^mp_') {
    throw "mr15.cfg must not mutate match CVars outside the plugin transaction."
}
Assert-Contains $deploymentScript 'config\mr15.cfg' `
    "Fresh deployments must install mr15.cfg."
Assert-Contains $competitiveOverride 'sm_lan_economy_apply' `
	"The final competitive-mode override must reapply the selected transaction."
if ($competitiveOverride.Contains('exec mr15')) {
	throw "The per-map competitive override must not silently reset MR12 to MR15."
}
Assert-Contains $deploymentScript 'config\gamemode_competitive_server.cfg' `
    "Fresh deployments must install the final competitive-mode override."

$scriptingDir = Join-Path $ServerDir "csgo\addons\sourcemod\scripting"
$compiler = Join-Path $scriptingDir "spcomp.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "SourceMod compiler was not found: '$compiler'"
}

$output = Join-Path ([System.IO.Path]::GetTempPath()) ("lan-economy-test-{0}.smx" -f [guid]::NewGuid())
$policyTestOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("lan-economy-policy-test-{0}.smx" -f [guid]::NewGuid())
$runtimeProbeOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("lan-economy-runtime-probe-{0}.smx" -f [guid]::NewGuid())
try {
    & $compiler (Join-Path $repoRoot "mods\lan_player_scoreboard.sp") `
        ("-i{0}" -f (Join-Path $scriptingDir "include")) ("-o{0}" -f $output)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
        throw "SourcePawn economy ruleset compilation failed."
    }

    & $compiler (Join-Path $repoRoot "tests\economy_policy_selftest.sp") `
        ("-i{0}" -f (Join-Path $scriptingDir "include")) ("-o{0}" -f $policyTestOutput)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $policyTestOutput)) {
        throw "SourcePawn public economy policy test compilation failed."
    }

    & $compiler (Join-Path $repoRoot "tests\economy_runtime_probe.sp") `
        ("-i{0}" -f (Join-Path $scriptingDir "include")) ("-o{0}" -f $runtimeProbeOutput)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $runtimeProbeOutput)) {
        throw "SourcePawn live economy probe compilation failed."
    }
}
finally {
    if (Test-Path -LiteralPath $output) {
        [System.IO.File]::Delete($output)
    }
    if (Test-Path -LiteralPath $policyTestOutput) {
        [System.IO.File]::Delete($policyTestOutput)
    }
    if (Test-Path -LiteralPath $runtimeProbeOutput) {
        [System.IO.File]::Delete($runtimeProbeOutput)
    }
}

Write-Host "LAN economy ruleset regression checks passed."
