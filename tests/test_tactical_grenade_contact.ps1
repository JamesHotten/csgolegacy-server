param(
    [Parameter(Mandatory = $true)][string]$CTDirectorSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($CTDirectorSource, $TDirectorSource)) {
    $text = Get-Content -LiteralPath $path -Raw
    $handler = [regex]::Match($text, '(?s)public void Event_Contact\(Event event,.*?\n\}').Value
    if (-not $handler.Contains('if (IsUtilityWeaponFire(event))') -or
        -not $handler.Contains('return;') -or
        $handler.IndexOf('if (IsUtilityWeaponFire(event))') -gt $handler.IndexOf('ReleaseOrder(client, "weapon contact")')) {
        throw "Utility fire must be ignored before tactical contact release: $path"
    }
    if (-not $text.Contains('ReplaceString(weapon, sizeof(weapon), "weapon_", "", false);')) {
        throw "CS:GO weapon_fire names have a weapon_ prefix: $path"
    }
    foreach ($grenade in @('smokegrenade','flashbang','hegrenade','molotov','incgrenade','decoy')) {
        if (-not $text.Contains("StrEqual(weapon, `"$grenade`", false)")) {
            throw "Missing utility weapon filter $grenade in $path"
        }
    }
    if (-not $handler.Contains('ReleaseOrder(client, "weapon contact")')) {
        throw "Real gunfire must still release the tactical order: $path"
    }
}

Write-Host 'CT/T utility-fire contact regression checks passed.'
