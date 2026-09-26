param(
    [Parameter(Mandatory = $true)][string]$CoreSource,
    [Parameter(Mandatory = $true)][string]$EquipmentSource,
    [Parameter(Mandatory = $true)][string]$PurchaseSource,
    [Parameter(Mandatory = $true)][string]$InstallerSource
)

$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$equipment = Get-Content -LiteralPath $EquipmentSource -Raw
$purchase = Get-Content -LiteralPath $PurchaseSource -Raw
$installer = Get-Content -LiteralPath $InstallerSource -Raw

if (-not $equipment.Contains('g_BotEquipmentForceChoice') -or
    -not $equipment.Contains('GetRandomInt(0, 1)') -or
    -not $equipment.Contains('g_BotEquipmentForceChoiceUserId') -or
    -not $equipment.Contains('g_BotEquipmentRoutingBuy') -or
    -not $equipment.Contains('if (canRifle && canSMG)') -or
    -not $equipment.Contains('else if (canRifle)') -or
    -not $equipment.Contains('else if (canSMG)') -or
    -not $equipment.Contains('CSWeapon_FAMAS') -or
    -not $equipment.Contains('CSWeapon_MP9') -or
    -not $equipment.Contains('CSWeapon_GALILAR') -or
    -not $equipment.Contains('CSWeapon_MAC10') -or
    -not $equipment.Contains('CSWeapon_AK47')) {
    throw 'Force must lock one 50/50 choice per BOT and round; Full must retain AK to Galil fallback.'
}
if (-not $purchase.Contains('bool BotPurchase_IsPrimaryAlias') -or
    -not $core.Contains('g_BotEquipmentRoutingBuy[iClient]') -or
    -not $core.Contains('BotEquipment_BuyAffordablePrimary(iClient);') -or
    -not $core.Contains('eTeamBuy == BotEquip_Force && !g_bBuyingCheapDrop[iClient]') -or
    -not $core.Contains('strcmp(szWeapon, "mp9") == 0 || strcmp(szWeapon, "mac10") == 0')) {
    throw 'Native BOT buys must use the locked force choice without recursive purchase routing.'
}
if (-not $installer.Contains('BEGIN BOT_FORCE_PRIMARY_POLICY')) {
    throw 'Fresh installs must apply the force-buy primary restriction.'
}

Write-Host 'CT/T 50-50 force-buy and T full-buy Galil fallback checks passed.'
