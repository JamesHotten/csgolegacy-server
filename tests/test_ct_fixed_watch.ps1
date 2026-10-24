param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [string]$CTDirectorSource = "$PSScriptRoot\..\mods\bot_ct_tactics.sp",
    [string]$WatchSource = "$PSScriptRoot\..\mods\include\bot_ct_fixed_watch.inc",
    [string]$SectorSource = "$PSScriptRoot\..\mods\include\bot_ct_watch_sectors.inc",
    [string]$AnglesSource = "$PSScriptRoot\..\mods\include\bot_tactical_angles.inc",
    [string]$InstallerSource = "$PSScriptRoot\..\mods\install_ct_tactics.ps1"
)
$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$watch = Get-Content -LiteralPath $WatchSource -Raw
$sectors = Get-Content -LiteralPath $SectorSource -Raw
$angles = Get-Content -LiteralPath $AnglesSource -Raw
$installer = Get-Content -LiteralPath $InstallerSource -Raw

foreach ($required in @('GetClientTeam(client) != CS_TEAM_CT', '!g_bTacticalHoldReached[client]',
    'g_iEnemyVisibleOffset', 'g_iBotNearbyEnemiesOffset', 'g_bBombPlanted',
    'g_bThrowGrenade[client]', 'g_iDoingSmokeNum[client] != -1', 'BotMimic_IsPlayerMimicing(client)',
    'MOVETYPE_LADDER', 'ESCAPE_FROM_BOMB', 'ESCAPE_FROM_FLAMES', 'CS_SLOT_GRENADE',
    'BotCTTactics_GetOrder(client, goal, route)', 'BotCTTactics_GetAim(client, look)',
    'GetVectorDistance(position, goal) <= 256.0')) {
    if (-not $watch.Contains($required)) { throw "Missing quiet-watch release safeguard: $required" }
}
foreach ($required in @('return attack', 'Defuse bomb', 'Use entity', 'Open door', 'Avoid Flashbang',
    'Blind', 'GrenadeThrowBend')) {
    if (-not $watch.Contains($required)) { throw "Missing essential look exemption: $required" }
}
if ($watch -match 'TeleportEntity|SetEntData|SetEntProp|BotMoveTo|TR_Trace|NavMesh_') {
    throw 'Quiet-watch arbitration must not force aim, edit enemy memory, move bots or recalculate geometry.'
}
if (-not $core.Contains('BotCTWatch_IsQuietHold(iClient) && !BotCTWatch_IsEssentialLook(szDesc, hParams.Get(7) != 0)') -or
    -not $core.Contains('fNow + (bFixedCTWatch ? 0.1 : 0.5)') -or
    -not $core.Contains('BotSetLookAt(iClient, "tactical hold", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);') -or
    -not $core.Contains('BotSetLookAt(iClient, "CT assigned hold", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);')) {
    throw 'Core must arbitrate quiet CT only, retain interruptible attention and preserve original T refresh.'
}
$guard = [regex]::Match($core, '(?s)// BEGIN CT_FIXED_WATCH_LOOK_GUARD.*?// END CT_FIXED_WATCH_LOOK_GUARD').Value
if (-not $guard.Contains('return MRES_Ignored;') -or -not $guard.Contains('return MRES_Supercede;')) {
    throw 'Cached eye-height targets must bypass legacy Z adjustment; competing idle requests must be suppressed.'
}
if (-not $ct.Contains('AssignTargets(bots, count, Route_Fastest, -1, true);') -or
    -not $ct.Contains('CTWatch_GetSector(siteSlots[site]++, siteCounts[site])') -or
    -not $sectors.Contains('if (defenderCount <= 1) return 0;') -or
    -not $angles.Contains('bool constrainSector = false') -or
    -not $angles.Contains('alignment < Cosine(DegToRad(20.1))')) {
    throw 'Opening watch sectors must be site-local and geometry-constrained without changing default T/retake planning.'
}
foreach ($include in @('bot_ct_fixed_watch.inc', 'bot_ct_watch_sectors.inc')) {
    if (-not $installer.Contains($include)) { throw "Installer must deploy $include" }
}
Write-Host 'CT quiet-watch arbitration, release exemptions and site-local sector wiring checks passed.'
