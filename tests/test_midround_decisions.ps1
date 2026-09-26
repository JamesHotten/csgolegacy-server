param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource,
    [Parameter(Mandatory = $true)][string]$CTDirectorSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$t = Get-Content -LiteralPath $TDirectorSource -Raw
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw

if (-not $core.Contains('BEGIN T_MIDROUND_CONTACT_BRIDGE') -or
    -not $core.Contains('BotTTactics_ReportContact(iClient, iVisibleEnemy);') -or
    -not $core.Contains('MarkNativeAsOptional("BotTTactics_ReportContact");')) {
    throw 'T sighting bridge must be optional and receive a confirmed visible enemy.'
}

$tDecision = [regex]::Match($t, '(?s)void TryMidRoundRotation\(\).*?bool ShouldUrgentlyPlant\(').Value
if (-not $tDecision.Contains('g_midRotationUsed') -or
    -not $tDecision.Contains('g_siteEnemyUserId[1]') -or
    -not $tDecision.Contains('remaining < 55.0') -or
    -not $tDecision.Contains('FindLooseC4() != -1') -or
    -not $tDecision.Contains('Distance2D(carrierPosition, g_attackA ? g_siteA : g_siteB) < 800.0') -or
    -not $tDecision.Contains('aliveT < 3') -or
    -not $tDecision.Contains('g_attackA = !g_attackA;') -or
    -not $t.Contains('if (g_midRotationActive)') -or
    -not $t.Contains('g_phase == TPhase_UrgentPlant || g_midRotationActive')) {
    throw 'T rotation must require distinct defenders, spare time, a recoverable C4 and a single committed destination.'
}

$ctDecision = [regex]::Match($ct, '(?s)void TryReorganizeDefense\(.*?public void Event_RoundStart').Value
$reinforce = [regex]::Match($ct, '(?s)int RequestReinforcement\(.*?void ReleaseOrder\(').Value
if (-not $ctDecision.Contains('recentEnemies < 2') -or
    -not $ctDecision.Contains('g_reorganizedSite[site] = true') -or
    -not $ctDecision.Contains('g_plan != Plan_Standard') -or
    -not $ctDecision.Contains('recentEnemies >= 4') -or
    -not $ctDecision.Contains('!g_fullRotateSite[0] && !g_fullRotateSite[1]') -or
    -not $ctDecision.Contains('recentEnemies >= 3 && g_siteCasualtyAt[site]') -or
    -not $ctDecision.Contains('g_fullRotateSite[site] = true') -or
    -not $ct.Contains('otherDistance >= siteDistance + 300.0') -or
    -not $reinforce.Contains('otherDefenders <= 1') -or
    -not $reinforce.Contains('!allowEmptyOtherSite') -or
    -not $reinforce.Contains('onlyOtherSite && !protectsOtherSite') -or
    -not $reinforce.Contains('client == additionalExcluded') -or
    -not $ct.Contains('CT setup reviewed; surviving anchors retained.')) {
    throw 'CT reorganization must require confirmed site pressure, avoid repeated rotations and retain an opposite-site anchor.'
}

Write-Host 'T rotation and CT defense reorganization regression checks passed.'
