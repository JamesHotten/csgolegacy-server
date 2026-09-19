param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$CTDirectorSource
)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $CoreSource -Raw
$run = [regex]::Match($text, '(?s)public Action OnPlayerRunCmd\(.*?void ProcessCombat\(').Value
$director = Get-Content -LiteralPath $CTDirectorSource -Raw
$watchdog = [regex]::Match($director, '(?s)void ReleaseStalledOrders\(\).*?void SetOrderLook\(').Value

if (-not $run.Contains('g_bTacticalHoldReached[iClient]') -or
    -not $run.Contains('fDistanceToTacticalGoal <= 128.0') -or
    -not $run.Contains('fDistanceToTacticalGoal <= 256.0') -or
    -not $run.Contains('!g_bBombPlanted')) {
    throw 'CT initial defense must have an arrival/release buffer, without holding during bomb retakes.'
}
if (-not $run.Contains('bHoldInitialCTPosition') -or
    -not $run.Contains('GetEntData(iClient, g_iBotNearbyEnemiesOffset) == 0') -or
    -not $run.Contains('fVel[0] = 0.0;') -or
    -not $run.Contains('fVel[1] = 0.0;') -or
    -not $run.Contains('iButtons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);')) {
    throw 'A settled CT must stop native idle wandering only while safely holding a quiet angle.'
}
if (-not $run.Contains('(bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition)') -or
    -not $run.Contains('!bEnemyVisible') -or
    -not $run.Contains('GetTask(iClient) != ESCAPE_FROM_FLAMES')) {
    throw 'CT hold must yield to visible combat and urgent native tasks.'
}
if (-not $watchdog.Contains('g_orderArrived[client]') -or
    -not $watchdog.Contains('distance <= 128.0') -or
    -not $watchdog.Contains('distance <= 256.0') -or
    -not $watchdog.Contains('g_phase == Phase_Initial')) {
    throw 'The CT director must not release a settled initial defender inside the hold buffer.'
}

Write-Host 'CT opening hold and movement-buffer regression checks passed.'
