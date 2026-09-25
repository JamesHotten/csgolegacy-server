param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$EquipmentSource,
    [Parameter(Mandatory = $true)][string]$RosterSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$equipment = Get-Content -LiteralPath $EquipmentSource -Raw
$roster = Get-Content -LiteralPath $RosterSource -Raw

if (-not $equipment.Contains('full >= 4') -or -not $equipment.Contains('forceOrBetter >= 3') -or
    -not $equipment.Contains('g_BotEquipmentPreviousPlan[team] == BotEquip_Force') -or
    -not $core.Contains('BotEquipment_BeginRound(IsResetRound(), g_bForceT, g_bForceCT);') -or
    -not $core.Contains('BotEquipment_GetRoundPlan(iTeam)') -or
    -not $core.Contains('BotEquipment_GetRoundPlan(iTeam) != BotEquip_Eco')) {
    throw 'Buying must use the requested thresholds and a stable, nonconsecutive force-buy plan.'
}
if (-not $core.Contains('if (iArmor == 0 || !bHasHelmet)') -or
    -not $core.Contains('GetEntProp(iClient, Prop_Data, "m_ArmorValue") > 0') -or
    -not $core.Contains('if (IsTeamForcing(iTeam) && !bHasPrimary)') -or
    -not $core.Contains('g_iCurrentRound == iRoundsBeforeHalftime - 1')) {
    throw 'Damaged full armor and last-round spending rules are not guarded.'
}
if (-not $roster.Contains('g_BTR_CTSlot = 3 - g_BTR_CTSlot;') -or
    -not $roster.Contains('BotTeams_SlotForSide(side), logo') -or
    -not $roster.Contains('moved <= stayed')) {
    throw 'Team names and logos must follow their original match slots only after a real side swap.'
}

Write-Host 'BOT buy-plan and logical team-slot regression checks passed.'
