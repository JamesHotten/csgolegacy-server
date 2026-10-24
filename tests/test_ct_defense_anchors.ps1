param(
    [Parameter(Mandatory = $true)][string]$CTDirectorSource,
    [string]$NavDirectory
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $CTDirectorSource -Raw
$profiles = [ordered]@{
    de_inferno = @('BombsiteA', 'Pit', 'BombsiteB', 'Ruins')
    de_train = @('BombsiteA', 'Connector', 'BombsiteB', 'BPlatform')
    de_mirage = @('BombsiteA', 'Stairs', 'BombsiteB', 'Shop')
    de_nuke = @('BombsiteA', 'Heaven', 'BombsiteB', 'Decon')
    de_dust2 = @('BombsiteA', 'LongA', 'BombsiteB', 'BDoors')
    de_overpass = @('BombsiteA', 'BackofA', 'BombsiteB', 'Construction')
    de_vertigo = @('BombsiteA', 'BackofA', 'BombsiteB', 'BackofB')
    de_ancient = @('BombsiteA', 'SideHall', 'BombsiteB', 'Ruins')
    de_anubis = @('BombsiteA', 'Heaven', 'BombsiteB', 'BackofB')
}

foreach ($map in $profiles.Keys) {
    $places = $profiles[$map]
    $profileSource = 'StrEqual(map, "' + $map + '", false))' + "`n" +
        '        SetAnchorProfile("' + ($places -join '", "') + '");'
    if (-not $source.Contains($profileSource)) {
        throw "Missing or unexpected CT defense anchor profile for $map."
    }

    if ($NavDirectory) {
        $navPath = Join-Path $NavDirectory ($map + '.nav')
        $stream = [System.IO.File]::OpenRead($navPath)
        $reader = [System.IO.BinaryReader]::new($stream)
        try {
            if ($reader.ReadUInt32() -ne 4277009102) { throw "Invalid NAV magic: $navPath" }
            $version = $reader.ReadUInt32()
            if ($version -ge 10) { [void]$reader.ReadUInt32() }
            [void]$reader.ReadUInt32() # BSP size
            if ($version -ge 14) { [void]$reader.ReadByte() }
            $count = $reader.ReadUInt16()
            $names = @()
            for ($index = 0; $index -lt $count; $index++) {
                $length = $reader.ReadUInt16()
                $names += [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes($length)).TrimEnd([char]0)
            }
            foreach ($place in $places) {
                if ($names -cnotcontains $place) { throw "$map NAV lacks place $place." }
            }
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    }
}
if ($source.Contains('StrEqual(map, "de_cache", false)')) {
    throw 'Cache is intentionally out of scope and must use the generic fallback.'
}
if (-not $source.Contains('NavMeshArea_GetPlace(') -or
    -not $source.Contains('TryAppendNamedAnchor(') -or
    -not $source.Contains('BuildDefensiveSiteTargets(')) {
    throw 'CT defense anchors must resolve named NAV places, then safely fall back to the generic site planner.'
}
if (-not $source.Contains('BuildDefensiveSiteTargets(0, countA') -or
    -not $source.Contains('BuildDefensiveSiteTargets(1, countB')) {
    throw 'The standard CT setup must assign both A and B from their anchor profiles.'
}
if (-not $source.Contains('BuildAround(sitePosition, missing') -or
    -not $source.Contains('g_anchorResolved[site][slot]')) {
    throw 'Invalid or unavailable anchors must fall back individually without disabling CT tactics.'
}

Write-Host 'CT defense anchor profile wiring checks passed.'
