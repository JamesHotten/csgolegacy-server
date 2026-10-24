param(
    [string]$CTDirectorSource = "$PSScriptRoot\..\mods\bot_ct_tactics.sp",
    [string]$PerceptionSource = "$PSScriptRoot\..\mods\include\bot_loose_c4_perception.inc",
    [string]$InstallerSource = "$PSScriptRoot\..\mods\install_ct_tactics.ps1"
)
$ErrorActionPreference = 'Stop'
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$sight = Get-Content -LiteralPath $PerceptionSource -Raw
$installer = Get-Content -LiteralPath $InstallerSource -Raw
$drop = [regex]::Match($ct, '(?s)public void Event_BombDropped\(.*?\n\}').Value
if ($drop.Contains('PlanLooseBombGuard(') -or $drop.Contains('CreateTimer(')) {
    throw 'A global bomb_dropped event must not reveal C4 to CT.'
}
foreach ($expected in @('g_roundLive', 'g_blindUntil[client]', 'BotStuff_CanSeeLooseC4(client, bomb)',
    'EntRefToEntIndex(g_guardBombRef)', 'guardCount == 0', 'g_guardSlot[selected] = target',
    'BotStuff_HasVisibleEnemy(client)', 'now - g_lastCombatAt[client] < 2.5',
    'g_guardStalls[client] >= 3', 'ClearLooseBombGuard();')) {
    if (-not $ct.Contains($expected)) { throw "Missing loose-C4 lifecycle safeguard: $expected" }
}
$reinforce = [regex]::Match($ct, '(?s)int RequestReinforcement\(.*?void ReleaseOrder\(').Value
if (-not $reinforce.Contains('if (g_phase == Phase_GuardLooseBomb) return 0;')) {
    throw 'Ordinary site reinforcement must not overwrite a confirmed C4 guard.'
}
$release = [regex]::Match($ct, '(?s)void ReleaseOrder\(.*?void ClearOrders\(').Value
if ($release.IndexOf('g_lastCombatAt[client] = GetGameTime()') -gt $release.IndexOf('!g_hasOrder[client]')) {
    throw 'Repeated combat must refresh the quiet window even for already-released guards.'
}
foreach ($expected in @('LineGoesThroughSmoke(eye, position)', 'GetVectorDotProduct(viewDirection, direction) < 0.5',
    'BotIsVisible(client, position, true, bomb)', 'GetClientTeam(client) != CS_TEAM_CT',
    'm_hOwnerEntity', 'TR_TraceRayFilterEx')) {
    if (-not $sight.Contains($expected)) { throw "Missing actual CT sight constraint: $expected" }
}
if (-not $installer.Contains('bot_loose_c4_perception.inc') -or
    -not $installer.Contains('CreateNative("BotStuff_CanSeeLooseC4"') -or
    -not $installer.Contains('CreateNative("BotStuff_HasVisibleEnemy"')) {
    throw 'The installer must deploy and idempotently register the perception bridge.'
}
Write-Host 'CT loose-C4 sight, all-guard membership, combat recovery and priority wiring checks passed.'
