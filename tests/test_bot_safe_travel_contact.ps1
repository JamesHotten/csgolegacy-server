param([Parameter(Mandatory = $true)][string]$CoreSource)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $CoreSource -Raw
$block = [regex]::Match($source, '(?s)// BEGIN CT_HOLD_READY_GUN.*?// END CT_HOLD_READY_GUN').Value
$switch = [regex]::Match($block, 'if \(IsSafe\(iClient\)\)\s*\{\s*iButtons &= ~IN_SPEED;\s*if \(([^\r\n]+)\)\s*SwitchWeapon\(iClient, GetPlayerWeaponSlot\(iClient, CS_SLOT_KNIFE\)\);\s*\}')
if (-not $switch.Success) {
    throw 'Cannot find the safe-travel automatic knife switch.'
}

# Evaluate the actual emitted SourcePawn predicate with a small, explicit
# grammar, so this can catch regressions without running a game server.
$predicate = $switch.Groups[1].Value.Replace('g_bIsProBot[iClient]', 'isPro').Replace('g_bDontSwitch[iClient]', 'noSwitch').Replace('BotIsHiding(iClient)', 'hiding').Replace('GetEntData(iClient, g_iBotNearbyEnemiesOffset) == 0', '!nearby')
$terms = $predicate -split ' && '
$known = @('bCTGuardWithGun', 'bEnemyVisible', 'isPro', 'noSwitch', 'hiding', 'nearby', 'bGunSwitchActionFree')
foreach ($term in $terms) {
    if ($term.TrimStart('!') -cnotin $known) { throw "Unknown knife-switch predicate term: $term" }
}

function Test-KnifeSwitch($state) {
    foreach ($term in $terms) {
        $value = $state[$term.TrimStart('!')]
        if ($term.StartsWith('!')) { $value = -not $value }
        if (-not $value) { return $false }
    }
    return $true
}

for ($mask = 0; $mask -lt (1 -shl $known.Count); $mask++) {
    $state = @{}
    for ($index = 0; $index -lt $known.Count; $index++) {
        $state[$known[$index]] = [bool]($mask -band (1 -shl $index))
    }
    $expected = $state.isPro -and $state.bGunSwitchActionFree -and -not ($state.bCTGuardWithGun -or $state.bEnemyVisible -or $state.noSwitch -or $state.hiding -or $state.nearby)
    if ((Test-KnifeSwitch $state) -ne $expected) {
        throw "Safe-travel knife switch regressed (visible=$($state.bEnemyVisible), nearby=$($state.nearby), holding=$($state.bCTGuardWithGun), pro=$($state.isPro), blocked=$($state.noSwitch), hiding=$($state.hiding))."
    }
}
Write-Host 'Safe-travel knife switch: 128 cases passed, including nearby threats, visible contact, action priority and quiet travel.'
