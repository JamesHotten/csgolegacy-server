param(
    [Parameter(Mandatory)][string[]]$ObjectiveLog,
    [Parameter(Mandatory)][string[]]$ContactLog
)
$ErrorActionPreference = 'Stop'
$maps = 'inferno','train','mirage','nuke','dust2','overpass','vertigo','cache','ancient','anubis'
& "$PSScriptRoot/check_tactical_live_matrix.ps1" -Log $ObjectiveLog
$retake = @{}
foreach ($path in $ObjectiveLog) {
    $current = ''
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^LIVE_CASE_BEGIN map=de_(\w+) site=([AB])$') {
            $map = $Matches[1]
            $site = $Matches[2]
            $current = "$map/$site"
            $retake[$current] = 0
        } elseif ($line -match 'CT profiled retake assigned site=([01]) lane=\S+ bot=' -and $current) {
            $expected = if ($current.EndsWith('/A')) { '0' } else { '1' }
            if ($Matches[1] -ne $expected) { throw "Retake assigned the wrong bombsite: $current" }
            $retake[$current]++
        } elseif ($line -match '^LIVE_CASE_RESULT ') {
            $current = ''
        }
    }
}
$lines = @(Get-Content -LiteralPath $ContactLog)
if ($lines -match '^TEAMWORK_INVALID |Exception reported|Engine Error') { throw 'Contact matrix has an invalid setup or runtime error' }
if (!($lines -match '^TEAMWORK_SUITE_DONE maps=')) { throw 'Contact matrix did not finish' }
$contact = @{}
foreach ($line in $lines) {
    if ($line -notmatch '^TEAMWORK_CONTACT map=de_(\w+) site=([01]) reported=([01]) moved=(\d+) valid=(\d+) weak_kept=([01])$') { continue }
    $at = if ($Matches[2] -eq '0') { 'A' } else { 'B' }
    $key = "$($Matches[1])/$at"
    $moved = [int]$Matches[4]
    if ($contact.ContainsKey($key) -or [int]$Matches[3] -ne 1 -or $moved -gt 1 -or [int]$Matches[5] -ne $moved -or [int]$Matches[6] -ne 1) {
        throw "Unexpected/floor-blocked reinforcement or lost reserve on $key ($line)"
    }
    $contact[$key] = $moved
}
foreach ($map in $maps) {
    foreach ($site in 'A','B') {
        if (!$contact.ContainsKey("$map/$site")) { throw "Missing contact case $map/$site" }
    }
    $named = $retake["$map/A"] + $retake["$map/B"]
    $moved = $contact["$map/A"] + $contact["$map/B"]
    if ($named -eq 0 -and $moved -eq 0) { throw "No profiled action observed for $map" }
    "CT_TEAMWORK_MAP map=de_$map named_retake=$named safe_relief=$moved"
}
"CT_TEAMWORK_PASS maps=10 contacts=$($contact.Count) named_sites=$(@($retake.Values | Where-Object { $_ -gt 0 }).Count) moved_sites=$(@($contact.Values | Where-Object { $_ -gt 0 }).Count)"
