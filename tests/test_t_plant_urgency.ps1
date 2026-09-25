param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$director = Get-Content -LiteralPath $TDirectorSource -Raw

if (-not $director.Contains('aliveT <= 2 && aliveCT <= 2') -or
    -not $director.Contains('g_cvPlantUrgency.FloatValue') -or
    -not $director.Contains('PlanUrgentPlant();') -or
    -not $director.Contains('g_phase = TPhase_UrgentPlant;') -or
    -not $director.Contains('RefreshUrgentOrders();') -or
    -not $director.Contains('CreateNative("BotTTactics_IsUrgentPlant"')) {
    throw 'Low-player and late-round T plans must prioritize the C4 route.'
}
if (-not $director.Contains('HookEvent("bomb_beginplant", Event_BombBeginPlant') -or
    -not $director.Contains('HookEvent("bomb_abortplant", Event_BombAbortPlant') -or
    -not $director.Contains('PlanPlantCover(planter, position);') -or
    -not $director.Contains('g_phase = TPhase_PlantCover;')) {
    throw 'T guards must receive positions at the beginning of a plant and recover on abort.'
}
if (-not $core.Contains('BEGIN T_PLANT_COVER_BRIDGE') -or
    -not $core.Contains('g_bTPlanting = false;') -or
    -not $core.Contains('!g_bBombPlanted && !g_bTPlanting') -or
    -not $core.Contains('(g_bBombPlanted || g_bTPlanting) && bHasTacticalAim') -or
    -not $core.Contains('BEGIN T_URGENT_OBJECTIVE_PRIORITY') -or
    -not $core.Contains('!g_bTPlanting && !bTPlantUrgent')) {
    throw 'BetterBots must yield opening lineups and hold plant-cover angles.'
}

Write-Host 'T planting urgency and cover regression checks passed.'
