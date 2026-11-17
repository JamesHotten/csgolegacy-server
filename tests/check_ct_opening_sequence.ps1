[CmdletBinding()]
param([Parameter(Mandatory)][string]$Log)
$ErrorActionPreference = 'Stop'
$maps = 'de_inferno','de_train','de_mirage','de_nuke','de_dust2','de_overpass','de_vertigo','de_cache','de_ancient','de_anubis'
$lines = Get-Content -LiteralPath $Log
if ($lines -match '^CT_SITE_INVALID|Exception reported|Engine Error|Unable to load plugin') {
    throw 'Opening fixture reported a setup/runtime error.'
}
if (@($lines -match '^CT_SITE_SURVEY_DONE$').Count -ne 1) { throw 'Opening sequence did not finish.' }
$plans = @($lines -match '^CT_SITE_DISTRIBUTION ')
$results = @($lines -match '^CT_SITE_OCCUPANCY ')
if ($plans.Count -ne $maps.Count -or $results.Count -ne $maps.Count) { throw 'Opening sequence must contain one result per map.' }
$failed = @(
    for ($i = 0; $i -lt $maps.Count; $i++) {
        $map = $maps[$i]
        if ($plans[$i] -notmatch ('^CT_SITE_DISTRIBUTION map=' + $map + ' round=1 calibration=3 orders=([23]),([23]) aim_ok=[1-3],[1-3] named_mask=\d+,\d+ target_in=[1-3],[1-3]$') -or
            ([int]$Matches[1] + [int]$Matches[2]) -ne 5) {
            "$map opening distribution failed: $($plans[$i])"
            continue
        }
        # Four half-second samples on each site, including the final sample.
        # Longer quiet-hold retests can be run on slow multilevel maps.
        if ($results[$i] -notmatch ('^CT_SITE_OCCUPANCY map=' + $map + ' round=1 samples=52 occupied=(\d+),(\d+) longest=(\d+),(\d+) final_mask=3$') -or
            [int]$Matches[3] -lt 4 -or [int]$Matches[4] -lt 4) {
            "$map actual A/B hold failed: $($results[$i])"
        }
    }
)
if ($failed.Count) { throw ($failed -join [Environment]::NewLine) }
'CT_OPENING_SEQUENCE_PASS maps=10 actual_both_sites_at_end=10'
