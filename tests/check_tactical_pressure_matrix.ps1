[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Log,
    [switch]$ReportOnly
)
$ErrorActionPreference = 'Stop'
$maps = 'inferno','train','mirage','nuke','dust2','overpass','vertigo','cache','ancient','anubis'
$wanted = @(foreach ($map in $maps) { "de_$map/A"; "de_$map/B" })
$rows = @(
    foreach ($path in $Log) {
        $lines = Get-Content -LiteralPath $path
        if ($lines -match 'Exception reported|Engine Error|RETAKE_TEST_CLEAR' -or -not ($lines -match '^LIVE_CASE_SUITE_DONE$')) {
            throw "Pressure test did not finish cleanly without auto-clear: $path"
        }
        $result = $null
        foreach ($line in $lines) {
            if ($line -match '^LIVE_CASE_RESULT map=(de_\w+) site=([AB]) actual=(-?\d+) outcome=(\w+) winner=(\d+) reason=(\d+) guard_ready=(\d+) retake_stage=(\d+) retake_push=(\d+) z_delta=(\d+) ') {
                $result = @{
                    Key="$($Matches[1])/$($Matches[2])"; Actual=[int]$Matches[3]; Outcome=$Matches[4]; Winner=[int]$Matches[5];
                    Reason=[int]$Matches[6]; Guards=[int]$Matches[7]; Routes=([int]$Matches[8]+[int]$Matches[9]); Height=[int]$Matches[10]
                }
            }
            elseif ($line -match '^RETAKE_PRESSURE map=(de_\w+) site=([AB]) mode=armed ct=(\d+) t=(\d+) ct_kills=(\d+) t_kills=(\d+) use=(\d+) aborts=(\d+) t_at_use=(-?\d+) use_left=(-?[\d.]+) finish_left=(-?[\d.]+) ') {
                $key="$($Matches[1])/$($Matches[2])"
                if (!$result -or $key -ne $result.Key) { throw "Combat data missing its own result: $key" }
                $expected = if ($key.EndsWith('/A')) { 0 } else { 1 }
                $finished = $result.Winner -eq 3 -and $result.Reason -eq 7 -and $result.Outcome -eq 'defused'
                $staged = $result.Routes -gt 0 -or [int]$Matches[7] -gt 0
                $valid = $result.Actual -eq $expected -and $result.Guards -gt 0 -and $staged -and
                    [int]$Matches[3] -ge 3 -and [int]$Matches[4] -eq 2 -and ([int]$Matches[5] + [int]$Matches[6]) -gt 0 -and
                    ($key -ne 'de_nuke/B' -or $result.Height -ge 200)
                [pscustomobject]@{Site=$key; Valid=$valid; Defused=$finished; Starts=[int]$Matches[7]; TAtFirstUse=[int]$Matches[9];
                    CTKills=[int]$Matches[5]; TKills=[int]$Matches[6]; Winner=$result.Winner; Reason=$result.Reason}
                $result = $null
            }
        }
    }
)
if (($rows.Site -join ',') -ne ($wanted -join ',')) { throw 'Expected exactly ten pressure maps, A then B in map order.' }
$rows | Format-Table -AutoSize
$invalid = @($rows | Where-Object { !$_.Valid })
$win = @($rows | Where-Object Defused)
$open = @($rows | Where-Object Starts -gt 0)
$missing = @($maps | Where-Object {
    $entry = "de_$_/"
    @($win | Where-Object { $_.Site.StartsWith($entry) }).Count -eq 0
})
"PRESSURE_MATRIX sites=$($rows.Count) valid=$($rows.Count-$invalid.Count) opened=$($open.Count) defused=$($win.Count) maps_without_defuse=$($missing -join ',')"
if (!$ReportOnly) {
    if ($invalid.Count -gt 0 -or $missing.Count -gt 0) { throw 'Pressure regression missing valid engagement or actual defuse coverage.' }
    'PRESSURE_MATRIX_PASS'
}
