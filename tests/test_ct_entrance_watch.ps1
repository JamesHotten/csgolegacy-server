param(
    [string]$CTDirectorSource = "$PSScriptRoot\..\mods\bot_ct_tactics.sp",
    [string]$EntranceSource = "$PSScriptRoot\..\mods\include\bot_ct_entrance_watch.inc",
    [string]$NavDirectory
)
$ErrorActionPreference = 'Stop'
$ct = Get-Content -LiteralPath $CTDirectorSource -Raw
$source = Get-Content -LiteralPath $EntranceSource -Raw
foreach ($required in @('TacticalAngles_IsVisible(eye, target, client, fraction)',
    'distance < 128.0', 'distance > 1800.0', 'FloatAbs(candidate[2] - hold[2]) > 400.0',
    'usedEntrances & (1 << entry)', 'delete areas;', 'return false;')) {
    if (-not $source.Contains($required)) { throw "Missing entrance selection safeguard: $required" }
}
if ($source -match 'CreateTimer|OnGameFrame|TeleportEntity|BotMoveTo|SetEntProp|SetEntData') {
    throw 'Entrance selection must be cached, read-only geometry work, not a movement/combat controller.'
}
if (-not $ct.Contains('siteLocalWatch && g_plan == Plan_Standard && g_cvEntranceWatch.BoolValue') -or
    $ct.IndexOf('SetOrderLook(client, g_tSpawn, sector, siteLocalWatch);') -gt $ct.IndexOf('CTEntrance_SelectLook(client,')) {
    throw 'Only standard opening holds may refine an already valid fallback aim.'
}
if ($NavDirectory) {
    foreach ($map in @('de_mirage','de_dust2')) {
        $reader = [System.IO.BinaryReader]::new([System.IO.File]::OpenRead((Join-Path $NavDirectory "$map.nav")))
        try {
            if ($reader.ReadUInt32() -ne 4277009102) { throw "Invalid NAV: $map" }
            $version = $reader.ReadUInt32()
            if ($version -ge 10) { [void]$reader.ReadUInt32() }
            [void]$reader.ReadUInt32()
            if ($version -ge 14) { [void]$reader.ReadByte() }
            $count = $reader.ReadUInt16()
            $names = @()
            for ($index=0; $index -lt $count; $index++) {
                $length = $reader.ReadUInt16()
                $names += [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes($length)).TrimEnd([char]0)
            }
            $expected = if ($map -eq 'de_mirage') { @('TRamp','PalaceInterior','Connector','Apartments','Catwalk') } else { @('LongA','Short','UpperTunnel','BDoors') }
            foreach ($place in $expected) {
                if ($names -cnotcontains $place -or -not $source.Contains('"' + $place + '"')) { throw "$map entrance missing: $place" }
            }
        } finally { $reader.Dispose() }
    }
}
Write-Host 'CT named entrance selection wiring and NAV-label checks passed (not a live sightline test).'
