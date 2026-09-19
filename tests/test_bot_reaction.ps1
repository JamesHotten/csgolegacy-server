param([Parameter(Mandatory = $true)][string]$CoreSource)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $CoreSource -Raw
$assignment = [regex]::Match($text, '(?s)public void OnClientPostAdminCheck\(.*?public void OnRoundPreStart\(').Value
$run = [regex]::Match($text, '(?s)public Action OnPlayerRunCmd\(.*?void ProcessCombat\(').Value
$guard = [regex]::Match($text, '(?s)void ApplyReactionGuard\(.*?public void OnPlayerSpawn\(').Value
$spawn = [regex]::Match($text, '(?s)public void OnPlayerSpawn\(.*?public void BotMimic_OnPlayerStopsMimicing\(').Value
$disconnect = [regex]::Match($text, '(?s)public void OnClientDisconnect\(.*?void ParseMapNades\(').Value

if (-not $assignment.Contains('Math_GetRandomFloat(0.18, 0.22)') -or
    -not $assignment.Contains('Math_GetRandomFloat(6000.0, 7500.0)') -or
    -not $assignment.Contains('Math_GetRandomFloat(0.22, 0.30)') -or
    -not $assignment.Contains('Math_GetRandomFloat(4500.0, 6500.0)')) {
    throw 'Professional bot reaction and turn-speed profiles are not human-paced.'
}
if ($assignment.Contains('g_fReactionTime[iClient] = 0.0;') -or
    $assignment.Contains('g_fLookAngleMaxAccel[iClient] = 100000.0;') -or
    -not $text.Contains('HUMAN_REACTION_PROFILE_V2')) {
    throw 'An instant-reaction or near-instant-turn profile remains.'
}
if (-not $run.Contains('ProcessCombat(iClient, iButtons, fVel, fAngles, iDefIndex, fSpeed, fNow);') -or
    -not $run.Contains('ApplyReactionGuard(iClient, iButtons, iDefIndex, fNow);')) {
    throw 'The final attack buttons are not guarded after custom combat.'
}
if (-not $guard.Contains('g_fReactionLockUntil[iClient] = fNow + g_fReactionTime[iClient];') -or
    -not $guard.Contains('fNow - g_fLastVisibleEnemyAt[iClient] > 0.75') -or
    -not $guard.Contains('iButtons &= ~IN_ATTACK;') -or
    -not $guard.Contains('iSlot == CS_SLOT_PRIMARY || iSlot == CS_SLOT_SECONDARY')) {
    throw 'The guard must delay newly seen firearm targets without blocking grenade throws.'
}
if (-not $spawn.Contains('g_iLastVisibleEnemy[iClient] = 0;') -or
    -not $spawn.Contains('g_fReactionLockUntil[iClient] = 0.0;') -or
    -not $disconnect.Contains('g_iLastVisibleEnemy[iClient] = 0;')) {
    throw 'Reaction state must not leak between lives or reused bot slots.'
}

Write-Host 'BOT reaction profile and firing-gate regression checks passed.'
