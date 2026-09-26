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

if (-not $core.Contains('if (BotPurchase_EnsureArmorBeforePrimary(iClient, szWeapon, bIsFullSave))') -or
    -not $core.Contains('if (strcmp(szWeapon, "defuser") == 0 && BotPurchase_ShouldReservePrimary(iClient, iTeam, bIsEco))') -or
    -not $core.Contains('BotEquipment_BuyAffordablePrimary(i))')) {
    throw 'BetterBots must defer the original rifle purchase after buying armor, reserve rifle money, and run the primary fallback.'
}
if (-not $equipment.Contains('bool BotEquipment_BuyAffordablePrimary(int client)') -or
    -not $equipment.Contains('CSWeapon_FAMAS') -or -not $equipment.Contains('CSWeapon_GALILAR') -or
    -not $equipment.Contains('CSWeapon_MP9') -or -not $equipment.Contains('CSWeapon_MAC10') -or
    -not $equipment.Contains('GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) != -1')) {
    throw 'The CT/T fallback must use live prices, check the actual weapon slot, and include affordable rifle/SMG tiers.'
}
if (-not $purchase.Contains('bool BotPurchase_EnsureArmorBeforePrimary') -or
    -not $purchase.Contains('bool BotPurchase_ShouldReservePrimary') -or
    -not $purchase.Contains('CS_GetWeaponPrice(client, team == CS_TEAM_CT ? CSWeapon_MP9 : CSWeapon_MAC10)')) {
    throw 'The purchase policy must explicitly protect an affordable primary for either side.'
}
if (-not $installer.Contains('BEGIN BOT_PRIMARY_FALLBACK')) {
    throw 'Fresh installs must apply the same primary fallback.'
}

Write-Host 'CT/T affordable-primary fallback source checks passed.'
