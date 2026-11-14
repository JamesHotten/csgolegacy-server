param([string]$CoreSource)
$ErrorActionPreference = 'Stop'
$mods = Join-Path $PSScriptRoot '..\mods'
$t = Get-Content -LiteralPath (Join-Path $mods 'bot_t_tactics.sp') -Raw
$installer = Get-Content -LiteralPath (Join-Path $mods 'install_ct_tactics.ps1') -Raw
foreach ($part in @('AppendPlantTarget(site, carrier)', 'AppendPlantTarget(site, bombCarrier)',
    'TR_ClipRayToEntityEx', 'TR_StartSolid(clip)', 'MASK_PLAYERSOLID', 'NavMesh_BuildPath',
    'BotTTactics_IsPlantApproach', 'sm_bot_t_safe_plant', 'm_bInBombZone', 'Native_IsPlantApproach')) {
    if (!$t.Contains($part)) { throw "Missing safe plant rule: $part" }
}
if ($t -match 'SetEntProp[^\r\n]*m_bInBombZone|CreateEvent\("bomb_planted"') {
    throw 'Planting and zone membership must be performed by the engine.'
}
if (!$installer.Contains('BEGIN T_SAFE_PLANT_APPROACH')) { throw 'C4 approach must ship via the installer.' }
if ($CoreSource) {
    $core = Get-Content -LiteralPath $CoreSource -Raw
    if (!$core.Contains('MarkNativeAsOptional("BotTTactics_IsPlantApproach")') -or
        !$core.Contains('BotTTactics_IsPlantApproach(iClient)) fTacticalMoveStopDistance = 8.0;')) {
        throw 'Shorter stop distance must be limited to the opt-in C4 approach order.'
    }
}
if (!$t.Contains('bool managedPlant = IsManagedPlantApproach(client);') -or
    !$installer.Contains('GetTask(iClient) != PLANT_BOMB || bManagedPlantApproach')) {
    throw 'A carrier outside the plant trigger must still be eligible for stall detection.'
}
Write-Host 'Safe plant goal, native planting and carrier-only bridge checks passed.'
