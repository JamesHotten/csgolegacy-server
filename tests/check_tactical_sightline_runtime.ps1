param(
    [Parameter(Mandatory)] [string]$Log,
    [switch]$ExpectBlocked,
    [switch]$RequireNamedEntrances
)
$ErrorActionPreference = 'Stop'
$maps = 'inferno','train','mirage','nuke','dust2','overpass','vertigo','cache','ancient','anubis'
$phases = 'ct_open','t_cover','t_postplant','ct_retake_stage','ct_retake_commit'
$content = Get-Content -LiteralPath $Log
if (!($content -match '^ANGLE_SURVEY_DONE$') -or ($content -match '^ANGLE_SKIP|\[SM\] Exception')) {
    throw 'Sightline survey did not finish cleanly.'
}
$rows = @($content | ForEach-Object {
    if ($_ -match '^ANGLE_SUMMARY map=de_(\w+) site=([01]) phase=(\w+) orders=(\d+) aims=(\d+) near=(\d+) (?:samples|offset)=(\d+) offset_near=(\d+)') {
        [pscustomobject]@{
            Key = "$($Matches[1])/$($Matches[2])/$($Matches[3])"
            Orders = [int]$Matches[4]
            Aims = [int]$Matches[5]
            Samples = [int]$Matches[7]
            Blocked = [int]$Matches[6] + [int]$Matches[8]
        }
    }
})
foreach ($map in $maps) {
    foreach ($site in 0,1) {
        foreach ($phase in $phases) {
            $case = @($rows | Where-Object Key -eq "$map/$site/$phase")
            if ($case.Count -ne 1 -or $case[0].Orders -lt 1 -or $case[0].Samples -lt 1 -or $case[0].Aims -lt 1) {
                throw "Missing orders, valid test positions or tactical aims for $map/$site/$phase."
            }
        }
    }
}
$blocked = ($rows | Measure-Object -Property Blocked -Sum).Sum
$samples = ($rows | Measure-Object -Property Samples -Sum).Sum
$aims = ($rows | Measure-Object -Property Aims -Sum).Sum
if ($ExpectBlocked) {
    if ($blocked -eq 0) { throw 'Baseline did not reproduce a near-wall aim.' }
    Write-Output "SIGHTLINE_BASELINE cases=$($rows.Count) samples=$samples aims=$aims near_wall=$blocked"
} else {
    if ($blocked -ne 0) { throw "Near-wall aim still present: $blocked" }
    Write-Output "SIGHTLINE_RUNTIME_PASS cases=$($rows.Count) samples=$samples aims=$aims near_wall=0"
}
if ($RequireNamedEntrances) {
    $named = @($content -match '^ENTRANCE_RESULT map=de_')
    $covered = @($named -match 'assigned=[1-9]').Count
    $distinct = @($named -match 'lanes=(3|5|6|7)$').Count
    foreach ($map in $maps) {
        if (@($named -match "^ENTRANCE_RESULT map=de_$map ").Count -ne 4 -or
            !($named -match "^ENTRANCE_RESULT map=de_$map .*assigned=[1-9]")) {
            throw "Incomplete objective entrance evidence for $map."
        }
    }
    if ($covered -lt 36 -or $distinct -lt 10) { throw "Insufficient named entrance coverage: $covered/40; multi-entrance examples: $distinct." }
    Write-Output "OBJECTIVE_ENTRANCE_PASS covered=$covered/40 multi_entrance=$distinct"
}
