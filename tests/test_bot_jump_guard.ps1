param([Parameter(Mandatory = $true)][string]$CoreSource)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $CoreSource -Raw
$run = [regex]::Match($text, '(?s)public Action OnPlayerRunCmd\(.*?void ProcessCombat\(').Value

if (-not $text.Contains('BEGIN BOT_JUMP_GUARD') -or
    -not $text.Contains('BOT_JUMP_GUARD_V2_SETTLED_ONLY')) {
    throw 'Settled-only BOT jump guard is missing.'
}
if (-not $run.Contains('iButtons &= ~IN_JUMP') -or
    -not $run.Contains('NAV_MESH_JUMP') -or
    -not $run.Contains('BotMimic_IsPlayerMimicing') -or
    -not $run.Contains('bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition')) {
    throw 'BOT jump guard must suppress settled hops while preserving NAV and mimic jumps.'
}
if ($text.Contains('g_fNextBotJumpAllowed') -or $run.Contains('fNow + 2.0')) {
    throw 'A route-wide jump cooldown would alter active tactical movement.'
}

Write-Host 'BOT jump guard regression checks passed.'
