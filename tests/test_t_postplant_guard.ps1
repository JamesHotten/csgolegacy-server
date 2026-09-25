param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$director = Get-Content -LiteralPath $TDirectorSource -Raw

$priority = [regex]::Match($core, '(?s)// BEGIN TACTICAL_NADE_PRIORITY.*?// END TACTICAL_NADE_PRIORITY').Value
if (-not $priority.Contains('GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted')) {
    throw 'Recorded T attack lineups must not override post-plant guard orders.'
}

$bombPlanted = [regex]::Match($core, '(?s)public void OnBombPlanted\(.*?\r?\n}').Value
if (-not $bombPlanted.Contains('BEGIN T_POSTPLANT_LINEUP_CANCEL') -or
    -not $bombPlanted.Contains('g_iDoingSmokeNum[iClient] = -1;') -or
    -not $bombPlanted.Contains('BotMimic_StopPlayerMimic(iClient);')) {
    throw 'Planting must cancel selected and actively replaying attack lineups.'
}

$afterPriority = $core.Substring($core.IndexOf('// END TACTICAL_NADE_PRIORITY'))
$genericSelection = [regex]::Match($afterPriority, '(?m)^\s*if \(!bHasTacticalOrder && .*g_iDoingSmokeNum\[iClient\] == -1 && fNow >= g_fNadeLineupCooldown\[iClient\].*$').Value
if (-not $genericSelection.Contains('!((g_bBombPlanted || g_bTPlanting || bTPlantUrgent) && GetClientTeam(iClient) == CS_TEAM_T)')) {
    throw 'Generic lineup selection must not create a new travel order during a plant or post-plant.'
}

$directorPlant = [regex]::Match($director, '(?s)public void Event_BombPlanted\(.*?\r?\n}').Value
if (-not $directorPlant.Contains('ClearCombatReleases();')) {
    throw 'All surviving T bots must be eligible for a fresh post-plant assignment.'
}

if (-not $core.Contains('ProcessGrenadeThrow(iClient, g_fBombPos, iNade);')) {
    throw 'Local post-plant denial grenades must remain enabled.'
}

Write-Host 'T post-plant guard regression checks passed.'
