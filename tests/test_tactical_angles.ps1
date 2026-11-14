param(
    [Parameter(Mandatory = $true)][string]$AnglesSource,
    [Parameter(Mandatory = $true)][string]$CTDirectorSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
$angles = Get-Content -LiteralPath $AnglesSource -Raw
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$t = Get-Content -LiteralPath $TDirectorSource -Raw

if (-not $angles.Contains('TacticalAngles_IsVisible') -or
    -not $angles.Contains('TR_TraceRayFilterEx') -or
    -not $angles.Contains('fraction >= 0.90') -or
    -not $angles.Contains('NavMesh_GetNearestArea') -or
    -not $angles.Contains('NavMeshArea_GetCenter')) {
    throw 'The shared angle planner must score visible NAV-projected targets rather than blindly aiming through walls.'
}
if (-not $angles.Contains('return 950.0;') -or
    -not $angles.Contains('return 500.0;') -or
    -not $angles.Contains('return 750.0;') -or
    -not $angles.Contains('case 1: return -35.0;') -or
    -not $angles.Contains('case 4: return 70.0;')) {
    throw 'The shared planner must adapt distance to weapons and spread teammates across distinct sectors.'
}
if (-not $ct.Contains('#include <bot_tactical_angles>') -or
    -not $ct.Contains('TacticalAngles_SelectLook(client, g_orderGoal[client], threat, slot') -or
    -not $t.Contains('#include <bot_tactical_angles>') -or
    -not $t.Contains('TacticalAngles_SelectLook(client, g_orderGoal[client], g_ctSpawn, slot')) {
    throw 'CT setup and T post-plant must use the same stateless angle planner while retaining separate directors.'
}
if ($angles.Contains('CreateTimer(') -or $angles.Contains('OnGameFrame') -or $angles.Contains('OnPlayerRunCmd')) {
    throw 'Angle planning must remain event-driven and cached, not perform NAV/trace work every frame.'
}
foreach ($director in @($ct, $t)) {
    if (!$director.Contains('GetNativeCell(3)') -or !$director.Contains('TacticalAngles_SelectLiveWatch(client, g_orderGoal[client]')) {
        throw 'Both sides must check the actual BOT eye in the live aim query, independently of the movement order.'
    }
}
if (!$angles.Contains('GetClientEyePosition(client, eye)') -or
    !$angles.Contains('if (visible < 152.0) return false;') -or
    !$angles.Contains('look[2] = eye[2];')) {
    throw 'Live watch must reject nearby obstructions and keep alternate rays on the same floor.'
}

Write-Host 'Shared tactical angle-planning regression checks passed.'
