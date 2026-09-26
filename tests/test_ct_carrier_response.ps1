param([Parameter(Mandatory = $true)][string]$CTDirectorSource)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $CTDirectorSource -Raw
$contact = [regex]::Match($source, '(?s)public any Native_ReportContact\(.*?void RememberSiteEnemy\(').Value
$response = [regex]::Match($source, '(?s)void PlanCarrierResponse\(.*?void RememberSiteEnemy\(').Value

if (-not $contact.Contains('IsBombCarrier(enemy)') -or
    -not $contact.Contains('ReleaseOrder(spotter, "bomb carrier spotted")') -or
    -not $contact.Contains('g_combatReleased[spotter] = true') -or
    -not $contact.Contains('PlanCarrierResponse(enemyPosition);') -or
    $contact.IndexOf('PlanCarrierResponse(enemyPosition);') -gt $contact.IndexOf('g_lastContactAt[site] > 0.0') -or
    -not $contact.Contains('GetPlayerWeaponSlot(client, CS_SLOT_C4)') -or
    -not $contact.Contains('m_hOwnerEntity')) {
    throw 'Confirmed C4 carrier sightings must override the ordinary contact cooldown without interrupting the spotter.'
}
if (-not $response.Contains('CollectCTBots(bots)') -or
    -not $response.Contains('AssignTargets(bots, count, Route_Fastest)') -or
    -not $response.Contains('g_phase = Phase_CarrierResponse') -or
    -not $response.Contains('g_carrierLastPlanAt + 8.0') -or
    -not $source.Contains('g_combatReleased[bots[index]]') -or
    -not $source.Contains('g_phase != Phase_CarrierResponse') -or
    -not $source.Contains('public void Event_BombPlanted(') -or
    -not $source.Contains('public void Event_BombDropped(')) {
    throw 'All available CTs must rotate once, while combat, drop and plant behavior remains owned by existing paths.'
}

Write-Host 'CT C4-carrier full-response checks passed.'
