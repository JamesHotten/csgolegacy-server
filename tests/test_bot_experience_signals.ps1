param(
    [Parameter(Mandatory = $true)][string]$RecorderSource,
    [Parameter(Mandatory = $true)][string]$CTDirectorSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
$recorder = Get-Content -LiteralPath $RecorderSource -Raw
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$t = Get-Content -LiteralPath $TDirectorSource -Raw

foreach ($needle in @(
    'CreateNative("BotExperience_RecordSignal"',
    'CREATE TABLE IF NOT EXISTS signals',
    'HookEvent("player_hurt", Event_PlayerHurt',
    'HookEventEx("grenade_thrown", Event_GrenadeThrown',
    'HookEvent("bomb_beginplant", Event_BombBeginPlant',
    'HookEvent("bomb_abortplant", Event_BombAbortPlant',
    'for (int index = 0; index < g_signalCount; index++)',
    'if (!InsertSignal(roundId, index))',
    'SQL_FastQuery(g_database, "ROLLBACK;")'
)) {
    if (-not $recorder.Contains($needle)) { throw "Recorder signal regression: missing $needle" }
}

foreach ($source in @($ct, $t)) {
    if (-not $source.Contains('MarkNativeAsOptional("BotExperience_RecordSignal")') -or
        -not $source.Contains('FeatureType_Native, "BotExperience_RecordSignal"') -or
        -not $source.Contains('ExperienceSignal("first_sight"')) {
        throw 'CT/T signals must remain optional and include first sighting.'
    }
}

if (-not $ct.Contains('ExperienceSignal("order_arrived"') -or
    -not $ct.Contains('ExperienceSignal("order_release"') -or
    -not $t.Contains('ExperienceSignal("stage_exit"') -or
    -not $t.Contains('ExperienceSignal("mid_rotate"') -or
    -not $t.Contains('ExperienceSignal("route_stall"') -or
    -not $t.Contains('ObserveOrderProgress();')) {
    throw 'Route and decision diagnostic signals were removed.'
}

$observe = [regex]::Match($t, '(?s)void ObserveOrderProgress\(\).*?void ClearCombatReleases\(').Value
if (-not $observe.Contains('g_orderStallReported[client] = true;') -or
    $observe.Contains('ReleaseOrder(client') -or $observe.Contains('PlanAttackCommit();')) {
    throw 'T route-stall observation must remain once-per-order and read-only.'
}

Write-Host 'BOT tactical experience signal regression checks passed.'
