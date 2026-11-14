param(
    [string]$NavDirectory
)
$ErrorActionPreference = 'Stop'
$mods = Join-Path $PSScriptRoot '..\mods'
$profiles = Get-Content -LiteralPath (Join-Path $mods 'include\bot_tactical_map_profiles.inc') -Raw
$ct = Get-Content -LiteralPath (Join-Path $mods 'bot_ct_tactics.sp') -Raw
$t = Get-Content -LiteralPath (Join-Path $mods 'bot_t_tactics.sp') -Raw
$installer = Get-Content -LiteralPath (Join-Path $mods 'install_ct_tactics.ps1') -Raw
$maps = @('de_inferno','de_train','de_mirage','de_nuke','de_dust2','de_overpass','de_vertigo','de_cache','de_ancient','de_anubis')
$declared = @([regex]::Matches($profiles, '"(de_[a-z0-9]+)"') | ForEach-Object { $_.Groups[1].Value })
if (($maps -join ',') -cne ($declared -join ',')) { throw 'Unexpected map profile coverage or order.' }
$rows = [regex]::Matches(($profiles -split 'g_TacticalRetakePlaces',2)[0], '\{\{([^{}]+)\},\s*\{([^{}]+)\}\}')
$retakeRows = [regex]::Matches(($profiles -split 'g_TacticalRetakePlaces',2)[1], '\{\{([^{}]+)\},\s*\{([^{}]+)\}\}')
if ($rows.Count -ne $maps.Count -or $retakeRows.Count -ne $maps.Count) { throw 'Each of the ten maps requires exactly two site profiles.' }
for ($index = 0; $index -lt $maps.Count; $index++) {
    $map = $maps[$index]
    $navNames = $null
    if ($NavDirectory -and $map -ne 'de_cache') {
        $reader = [IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $NavDirectory "$map.nav")))
        try {
            if ($reader.ReadUInt32() -ne 4277009102) { throw "Invalid NAV: $map" }
            $version = $reader.ReadUInt32()
            if ($version -ge 10) { [void]$reader.ReadUInt32() }
            [void]$reader.ReadUInt32()
            if ($version -ge 14) { [void]$reader.ReadByte() }
            $count = $reader.ReadUInt16()
            $navNames = for ($i = 0; $i -lt $count; $i++) {
                [Text.Encoding]::ASCII.GetString($reader.ReadBytes($reader.ReadUInt16())).TrimEnd([char]0)
            }
        } finally { $reader.Dispose() }
    }
    foreach ($site in 1,2) {
        $places = @([regex]::Matches($rows[$index].Groups[$site].Value, '"([^"]*)"') |
            ForEach-Object { $_.Groups[1].Value })
        if ($places.Count -ne 5 -or !$places[0] -or !$places[3] -or $places[3] -ceq $places[4]) {
            throw "$map site $site needs a watch entrance and a distinct main/optional split."
        }
        foreach ($place in $places) {
            if ($place -and $navNames -and $navNames -cnotcontains $place) { throw "$map NAV lacks $place." }
        }
        $retake = @([regex]::Matches($retakeRows[$index].Groups[$site].Value, '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
        if ($retake.Count -ne 3 -or @($retake | Sort-Object -Unique).Count -ne 3) { throw "$map needs three distinct retake entrances." }
        foreach ($name in $retake) {
            if ($navNames -and $navNames -cnotcontains $name) { throw "$map retake NAV lacks $name." }
        }
    }
}
foreach ($token in @('sm_bot_ct_clear_opening_watch', 'TacticalAngles_RequireClearWatch',
    'CTEntrance_ResolveWatch', 'if (infernoProfile) ApplyInfernoOpeningAims')) {
    if (!$ct.Contains($token)) { throw "Missing CT scope or fallback: $token" }
}
foreach ($token in @('sm_bot_t_map_routes', 'sm_bot_t_sync_carrier_ready', 'CarrierReadyForCommit()',
    'g_attackContact', 'elapsed >= stageTimeout', 'MarkNativeAsOptional("NavMesh_BuildPath")',
    'if (mainCount == 0)', 'AssignTargets(bots, count, Route_Fastest, bombCarrier, count)')) {
    if (!$t.Contains($token)) { throw "Missing T scope or fallback: $token" }
}
if (!$installer.Contains('bot_tactical_map_profiles.inc')) { throw 'Map profiles are not installed.' }
Write-Host 'Ten CT/T map profiles, named NAV labels and independent fallback wiring passed.'
