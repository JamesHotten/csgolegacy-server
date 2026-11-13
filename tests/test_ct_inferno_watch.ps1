param(
    [string]$CTDirectorSource = "$PSScriptRoot\..\mods\bot_ct_tactics.sp",
    [string]$InfernoSource = "$PSScriptRoot\..\mods\include\bot_ct_inferno_watch.inc",
    [string]$InstallerSource = "$PSScriptRoot\..\mods\install_ct_tactics.ps1",
    [string]$CoreSource
)
$ErrorActionPreference = 'Stop'
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$source = Get-Content -LiteralPath $InfernoSource -Raw
$installer = Get-Content -LiteralPath $InstallerSource -Raw
foreach ($required in @('g_infernoMap = StrEqual(map, "de_inferno", false)',
    'return g_infernoMap && g_cvInfernoWatch.BoolValue;',
    'if (InfernoWatchEnabled()) infernoProfile = TryBuildInfernoOpening',
    'if (!infernoProfile) BuildStandardTargets(count);',
    'if (siteLocalWatch && InfernoWatchEnabled())',
    'g_hasLook[client] = CTInferno_ClearSight(eye, g_orderLook[client]);')) {
    if (-not $ct.Contains($required)) { throw "Missing Inferno scope/fallback rule: $required" }
}
foreach ($required in @('TR_TraceHullFilterEx', 'TR_TraceRayFilterEx', '!TR_DidHit(trace) && !TR_StartSolid(trace)',
    'NavMeshArea_GetPlaceCanonical', '"TopofMid", "Balcony", "Banana", "Banana", "TopofMid"',
    'return fits && CTInferno_ClearSight(eye, aim);')) {
    if (-not $source.Contains($required)) { throw "Missing paired station safety rule: $required" }
}
if ($source -match 'CreateTimer|OnGameFrame|TeleportEntity|BotMoveTo|SetEntProp|SetEntData') {
    throw 'Inferno validation must not become a second movement/combat controller.'
}
if (-not $installer.Contains('bot_ct_inferno_watch.inc')) { throw 'Installer must deliver the Inferno profile.' }
foreach ($required in @('CreateNative("BotCTTactics_GetHoldRadius", Native_GetHoldRadius)',
    'g_phase == Phase_Initial && InfernoWatchEnabled()', 'g_infernoPreciseOrder[client] = false;',
    'return 32.0;', 'return 128.0;', 'distance <= holdRadius * 2.0',
    'float displacementStep = precise ? 32.0 : 64.0;',
    'if (precise && timeout < 5.0) timeout = 5.0;')) {
    if (-not $ct.Contains($required)) { throw "Missing precision hold lifecycle rule: $required" }
}
if ($CoreSource) {
    $core = Get-Content -LiteralPath $CoreSource -Raw
    foreach ($required in @('MarkNativeAsOptional("BotCTTactics_GetHoldRadius")', 'float fCTHoldRadius = 128.0;',
        'fCTHoldRadius < 128.0 ? fCTHoldRadius : 96.0', 'fDistanceToTacticalGoal <= fCTHoldRadius',
        'fDistanceToTacticalGoal <= fCTReleaseRadius', 'fDistanceToTacticalGoal > fTacticalMoveStopDistance')) {
        if (-not $core.Contains($required)) { throw "Missing scoped BetterBots arrival bridge: $required" }
    }
}
Write-Host 'Inferno paired positions, map scope, wall rejection and deployment wiring checks passed.'
