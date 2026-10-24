param(
    [string]$CanonicalSource = "$PSScriptRoot\..\mods\include\bot_ct_nav_place.inc",
    [string]$CTDirectorSource = "$PSScriptRoot\..\mods\bot_ct_tactics.sp"
)
$ErrorActionPreference = 'Stop'
$canonical = Get-Content -LiteralPath $CanonicalSource -Raw
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
foreach ($required in @('NavMeshArea_PlaceID) - 1', 'index >= 0 && index < g_hNavMeshPlaces.Length',
    'area >= 0 && area < g_hNavMeshAreas.Length', 'SetNativeString(2, place, length)')) {
    if (-not $canonical.Contains($required)) { throw "Missing canonical place safety rule: $required" }
}
if ($canonical -match '\.Set\(|SetEnt|BotMoveTo|TeleportEntity') { throw 'Canonical reader must not mutate NAV or BOT state.' }
if (-not $ct.Contains('MarkNativeAsOptional("NavMeshArea_GetPlaceCanonical")') -or
    -not $ct.Contains('g_cvEntranceWatch.BoolValue && (StrEqual(map, "de_mirage") || StrEqual(map, "de_dust2"))') -or
    -not $ct.Contains('NavMeshArea_GetPlace(area, place, length);')) { throw 'Canonical decoding must be optional and scoped to the two rollout maps, with legacy fallback.' }
Write-Host 'Optional one-based NAV directory reader scope and bounds wiring checks passed.'
