param(
    [Parameter(Mandatory)] [string[]]$Log,
    [switch]$ReportOnly,
    [int]$MinUtilityCases = 0
)
$ErrorActionPreference = 'Stop'
$maps = 'inferno','train','mirage','nuke','dust2','overpass','vertigo','cache','ancient','anubis'
$lines = Get-Content -LiteralPath $Log
$cases = @($lines | ForEach-Object {
    if ($_ -match '^LIVE_CASE_RESULT map=de_(\w+) site=([AB]) actual=(-?\d+) outcome=(\w+) winner=(\d+) reason=(\d+) guard_ready=(\d+) retake_stage=(\d+) retake_push=(\d+) z_delta=(\d+) casualty=(\d+) utility=(\d+)$') {
        [pscustomobject]@{
            Map = $Matches[1]; Site = $Matches[2]; Actual = [int]$Matches[3]
            Outcome = $Matches[4]; Winner = [int]$Matches[5]; Reason = [int]$Matches[6]
            Guards = [int]$Matches[7]; Stage = [int]$Matches[8]; Push = [int]$Matches[9]
            Height = [int]$Matches[10]; Casualty = [int]$Matches[11]; Utility = [int]$Matches[12]
        }
    }
})
$failed = @(
    foreach ($map in $maps) {
        foreach ($site in 'A','B') {
            $sample = @($cases | Where-Object { $_.Map -eq $map -and $_.Site -eq $site })
            if ($sample.Count -ne 1) { "$map/$site missing or duplicate"; continue }
            $sample = $sample[0]
            $expected = if ($site -eq 'A') { 0 } else { 1 }
            if ($sample.Outcome -ne 'defused' -or $sample.Actual -ne $expected -or $sample.Winner -ne 3 -or
                $sample.Reason -ne 7 -or $sample.Guards -lt 1 -or ($sample.Stage + $sample.Push) -lt 1) {
                "$map/$site $($sample.Outcome) guards=$($sample.Guards) round_reason=$($sample.Reason)"
            }
        }
    }
)
$utilityCases = @($cases | Where-Object Utility -eq 1).Count
"LIVE_MATRIX cases=$($cases.Count) defused=$(@($cases | Where-Object Outcome -eq 'defused').Count) failed=$($failed.Count) utility_cases=$utilityCases casualty_cases=$(@($cases | Where-Object Casualty -eq 1).Count)"
$failed | Write-Output
if (!$ReportOnly) {
    $nukeB = @($cases | Where-Object { $_.Map -eq 'nuke' -and $_.Site -eq 'B' -and $_.Height -ge 200 })
    if ($failed.Count -or $nukeB.Count -ne 1 -or $utilityCases -lt $MinUtilityCases -or
        !($lines -match 'LIVE_CASE_SUITE_DONE$') -or ($lines -match 'Exception reported|Engine Error')) {
        throw 'Live ten-map objective matrix did not pass.'
    }
    'LIVE_MATRIX_PASS'
}
