param([string]$CoreSource)
$ErrorActionPreference = 'Stop'
$mods = Join-Path (Split-Path -Parent $PSScriptRoot) 'mods'
$ct = Get-Content -LiteralPath (Join-Path $mods 'bot_ct_tactics.sp') -Raw
$t = Get-Content -LiteralPath (Join-Path $mods 'bot_t_tactics.sp') -Raw
$util = Get-Content -LiteralPath (Join-Path $mods 'include/bot_mirage_utility.inc') -Raw
foreach ($needle in 'RetakeHasHumanCT()', 'm_hBombDefuser', 'g_defuserRetiredUserId', 'm_bHasDefuser', 'm_flC4Blow') {
    if (!$ct.Contains($needle)) { throw "Missing defuser handoff safeguard: $needle" }
}
foreach ($needle in 'AddDust2PostPlantEntrance', 'HasStalledPlantApproach', 'SeparatePostPlantCover',
    'ObjectiveWatch_Available', 'remaining[client] == room', 'GetPlayerWeaponSlot(client, CS_SLOT_C4) > MaxClients') {
    if (!$t.Contains($needle)) { throw "Missing post-plant/route safeguard: $needle" }
}
if (!$util.Contains('g_utilityAssignedLane[client] == lane') -or !$util.Contains('g_utilityDeadline[client] = now + 4.0;') -or
    !$util.Contains('BotMimic_StopPlayerMimic(client)')) { throw 'Mirage lineup must be bound to its lane and release on timeout.' }
if ($CoreSource -and !(Select-String -LiteralPath $CoreSource -SimpleMatch 'GetTask(iClient) != PLANT_BOMB || bManagedPlantApproach' -Quiet)) {
    throw 'The compiled-source migration must monitor a carrier traveling outside of the plant zone.'
}
'Objective handoff, approach stalls, named coverage and Mirage utility wiring passed.'
