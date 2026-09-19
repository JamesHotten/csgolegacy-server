param([Parameter(Mandatory = $true)][string]$TDirectorSource)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $TDirectorSource -Raw
$assign = [regex]::Match($text, '(?s)void AssignTargets\(.*?\n\}').Value
$commit = [regex]::Match($text, '(?s)void PlanAttackCommit\(.*?void PlanBombRecovery\(').Value
$carrier = [regex]::Match($text, '(?s)int FindBombCarrier\(\).*?int FindLooseC4\(').Value

if (-not $commit.Contains('int bombCarrier = FindBombCarrier();') -or
    -not $commit.Contains('AssignTargets(bots, count, Route_Fastest, bombCarrier, count);')) {
    throw 'The attack commit must explicitly carry the detected C4 owner into target assignment.'
}
if (-not $assign.Contains('g_combatReleased[preferredClient] = false;') -or
    $assign.Contains('IsTBot(preferredClient) && !g_combatReleased[preferredClient]')) {
    throw 'A previously released C4 carrier must rejoin the committed main attack.'
}
if (-not $assign.Contains('CopyVector(g_targets[0], g_orderGoal[preferredClient])')) {
    throw 'The C4 carrier must retain reserved main-route target zero.'
}
if (-not $carrier.Contains('GetPlayerWeaponSlot(client, CS_SLOT_C4)')) {
    throw 'C4 ownership detection must prefer the carrier inventory before entity fallback.'
}

Write-Host 'T bomb-carrier main-route regression checks passed.'
