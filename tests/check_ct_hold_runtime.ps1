param(
    [Parameter(Mandatory)][string]$OpeningLog,
    [Parameter(Mandatory)][string]$ArmsLog,
    [Parameter(Mandatory)][string]$NukeFallLog,
    [Parameter(Mandatory)][string]$ExposureBaseline,
    [Parameter(Mandatory)][string]$ExposureCandidate
)
$ErrorActionPreference = 'Stop'
$maps = 'inferno','train','mirage','nuke','dust2','overpass','vertigo','cache','ancient','anubis'
$opening = Get-Content -LiteralPath $OpeningLog
if (!($opening -match '^CT_SITE_SURVEY_DONE$')) { throw 'Opening survey did not complete.' }
foreach ($map in $maps) {
    $plan = @($opening -match "^CT_SITE_DISTRIBUTION map=de_$map round=1 calibration=3 orders=[1-9],[1-9] .*target_in=[1-9],[1-9]$")
    if ($plan.Count -ne 1) { throw "Missing a validated A/B interior assignment on $map." }
}
foreach ($map in 'inferno','train','mirage','dust2') {
    if (!($opening -match "^CT_SITE_OCCUPANCY map=de_$map round=1 samples=36 occupied=[1-9]\d*,[1-9]\d* longest=[1-9]\d*,[1-9]\d* final_mask=3$")) {
        throw "At least one interior defender did not actually settle on $map."
    }
}
$arms = Get-Content -LiteralPath $ArmsLog
if (($arms -match '^CT_ARMS_FAIL') -or !($arms -match '^CT_ARMS_DONE$')) { throw 'Weapon/fall probe failed.' }
foreach ($check in 'rifle_from_knife','pistol_from_knife','world_fall_keeps_order','enemy_damage_releases_order') {
    if (!($arms -match "^CT_ARMS_PASS check=$check(?: |$)")) { throw "Missing $check." }
}
$nuke = Get-Content -LiteralPath $NukeFallLog
foreach ($check in 'world_fall_keeps_route','repeated_stationary_fall_exits_route') {
    if (($nuke -match '^CT_ARMS_FAIL') -or !($nuke -match "^CT_ARMS_PASS check=$check$")) { throw "Nuke route: missing $check." }
}

function Read-Exposure([string]$Path) {
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^EXPOSURE_SUMMARY map=(de_\w+) site=([01]) phase=(\w+) orders=(\d+) valid=(\d+) dual=(\d+) crouch_dual=(\d+) eyes=') {
            [pscustomobject]@{ Case="$($Matches[1])/$($Matches[2])/$($Matches[3])"
                Phase=$Matches[3]; Valid=[int]$Matches[5]; Multi=[int]$Matches[6] }
        }
    }
}
$old = @(Read-Exposure $ExposureBaseline)
$new = @(Read-Exposure $ExposureCandidate)
if ($old.Count -ne 80 -or $new.Count -ne 80 -or
    (Compare-Object ($old.Case | Sort-Object) ($new.Case | Sort-Object))) { throw 'Exposure matrix must contain all 80 matched cases.' }
foreach ($phase in 'ct_open','ct_loose','t_cover','t_postplant') {
    $before = @($old | Where-Object Phase -eq $phase)
    $after = @($new | Where-Object Phase -eq $phase)
    $beforeCount = ($before | Measure-Object Valid -Sum).Sum
    $afterCount = ($after | Measure-Object Valid -Sum).Sum
    $beforeMulti = ($before | Measure-Object Multi -Sum).Sum
    $afterMulti = ($after | Measure-Object Multi -Sum).Sum
    if ($beforeCount -lt 1 -or $afterCount -lt $beforeCount * 0.85 -or $afterMulti * $beforeCount -gt $beforeMulti * $afterCount) {
        throw "Multi-entrance exposure regressed in ${phase}: $beforeMulti/$beforeCount -> $afterMulti/$afterCount."
    }
    "CT_HOLD_EXPOSURE_PASS phase=$phase before=$beforeMulti/$beforeCount after=$afterMulti/$afterCount"
}
$dustOld = $old | Where-Object Case -eq 'de_dust2/0/ct_open'
$dustNew = $new | Where-Object Case -eq 'de_dust2/0/ct_open'
if ($dustNew.Valid -lt $dustOld.Valid -or $dustNew.Multi -ge $dustOld.Multi) { throw 'Dust II A must reduce dual exposure without dropping a sample.' }
$pairCases = @{}
$oldSupport = $newSupport = 0
foreach ($line in Get-Content -LiteralPath $ExposureCandidate) {
    if ($line -notmatch '^CROSSFIRE_MATCHED map=de_(\w+) site=([01]) pairs=(\d+),(\d+) overlap=(\d+),(\d+) support=(\d+),(\d+)$') { continue }
    $key = "$($Matches[1])/$($Matches[2])"
    if ($pairCases.ContainsKey($key) -or $Matches[3] -ne $Matches[4] -or [int]$Matches[6] -gt [int]$Matches[5] -or
        [int]$Matches[8] -lt [int]$Matches[7]) { throw "Matched post-plant crossfire regressed in $key." }
    $pairCases[$key] = $true
    $oldSupport += [int]$Matches[7]
    $newSupport += [int]$Matches[8]
}
if ($pairCases.Count -ne 20 -or $newSupport -lt 1) { throw 'Expected 20 matched A/B post-plant crossfire cases.' }
"CT_HOLD_CROSSFIRE_PASS cases=20 support_before=$oldSupport support_after=$newSupport"
'CT_HOLD_RUNTIME_PASS'
