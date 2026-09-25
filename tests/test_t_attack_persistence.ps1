param([Parameter(Mandatory = $true)][string]$TDirectorSource)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $TDirectorSource -Raw
$update = [regex]::Match($text, '(?s)public Action Timer_Update\(Handle timer\).*?bool ShouldUrgentlyPlant\(').Value
$review = [regex]::Match($text, '(?s)void ReviewAttackCommit\(\).*?void PlanUrgentPlant\(').Value

if (-not $update.Contains('g_phase == TPhase_AttackCommit && GetGameTime() >= g_nextAttackReviewAt') -or
    -not $update.Contains('ReviewAttackCommit();') -or
    $update.Contains('g_phase == TPhase_AttackCommit && elapsed >= g_cvInitialHold.FloatValue)') -or
    -not $update.Contains('ShouldUrgentlyPlant()')) {
    throw 'The 28-second checkpoint must review the attack, not abandon it or disable urgent planting.'
}
if (-not $review.Contains('FindLooseC4()') -or
    -not $review.Contains('PlanBombRecovery();') -or
    -not $review.Contains('g_nextAttackReviewAt = GetGameTime() + 5.0;') -or
    -not $review.Contains('g_orderGoal[carrier]') -or
    $review.Contains('ResetDirector();') -or
    $review.Contains('ClearOrders();') -or
    $review.Contains('g_attackA = !g_attackA')) {
    throw 'Attack review must retain the chosen site and orders, while still recovering a dropped C4.'
}

Write-Host 'T attack persistence regression checks passed.'
