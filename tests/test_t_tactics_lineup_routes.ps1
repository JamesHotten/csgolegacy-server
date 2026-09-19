param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$director = Get-Content -LiteralPath $TDirectorSource -Raw

$priority = $core.IndexOf('// BEGIN TACTICAL_NADE_PRIORITY')
$movement = $core.IndexOf('if (bHasTacticalOrder)', $core.IndexOf('// BEGIN CT_TACTICS_BRIDGE', $core.IndexOf('float fNow = GetGameTime();')))
if ($priority -lt 0 -or $movement -lt 0 -or $priority -ge $movement) {
    throw 'T opening lineup selection must precede tactical movement.'
}
if (-not $core.Contains('g_iDoingSmokeNum[iClient] = GetNearestGrenade(iClient);') -or
    -not $core.Contains('if (g_iDoingSmokeNum[iClient] != -1 || bLineupReplay)') -or
    -not $core.Contains('bHasTacticalOrder = false;')) {
    throw 'A selected T lineup or active replay must suspend tactical movement.'
}
if (-not $core.Contains('if (!bHasTacticalOrder && g_iDoingSmokeNum[iClient] != -1 && !BotMimic_IsPlayerMimicing(iClient))')) {
    throw 'The existing BetterBots lineup execution path must remain reachable.'
}

$stage = [regex]::Match($director, '(?s)void PlanAttackStage\(\).*?void PlanAttackCommit\(').Value
$commit = [regex]::Match($director, '(?s)void PlanAttackCommit\(\).*?void PlanBombRecovery\(').Value
if (-not $stage.Contains('BuildAround(site, 1, 520.0, 900.0, true, dirX, dirY);')) {
    throw 'The C4 carrier must receive a central staging point.'
}
if ($stage.Contains('BuildAround(site, count, 500.0, 1050.0, false') -or
    $commit.Contains('BuildAround(site, count - 1, 320.0, 850.0, false')) {
    throw 'T split targets must not use a circular spread behind the site.'
}
if (-not $stage.Contains('AssignTargets(bots, count, Route_Fastest') -or
    -not $commit.Contains('AssignTargets(bots, count, Route_Fastest')) {
    throw 'Opening T staging and commit must use direct routes.'
}
if (-not $director.Contains('CreateNative("BotTTactics_ShouldHoldStage"') -or
    -not $director.Contains('g_phase == TPhase_AttackStage') -or
    -not $core.Contains('BotTTactics_ShouldHoldStage(iClient)') -or
    -not $core.Contains('bHoldTAttackStage') -or
    -not $core.Contains('g_bTacticalStageReached[iClient]') -or
    -not $core.Contains('fDistanceToTacticalGoal <= 128.0') -or
    -not $core.Contains('fDistanceToTacticalGoal <= 256.0')) {
    throw 'T attack staging needs an arrival/release buffer independent of commit, bomb recovery and post-plant orders.'
}
if (-not $core.Contains('(bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition)') -or
    -not $core.Contains('GetEntData(iClient, g_iBotNearbyEnemiesOffset) == 0')) {
    throw 'A safely staged T must suppress native idle movement without blocking combat.'
}

$postPlant = [regex]::Match($director, '(?s)void PlanPostPlant\(\).*?void AssignTargets\(').Value
$postPlantLook = [regex]::Match($director, '(?s)void SetPostPlantLook\(.*?void BuildAround\(').Value
if (-not $director.Contains('CreateNative("BotTTactics_GetAim"') -or
    -not $postPlant.Contains('AssignTargets(bots, count, Route_Safest, 0, count, true)') -or
    -not $postPlantLook.Contains('TacticalAngles_SelectLook(client, g_orderGoal[client], g_ctSpawn, slot') -or
    -not $core.Contains('BotTTactics_GetAim(iClient, fTacticalLook)') -or
    -not $core.Contains('BEGIN T_POSTPLANT_HOLD') -or
    -not $core.Contains('g_bTacticalPostPlantReached[iClient]')) {
    throw 'T post-plant positions must receive distributed CT-retake aim angles and a stable quiet hold.'
}

Write-Host 'T lineup priority and attack route regression checks passed.'
