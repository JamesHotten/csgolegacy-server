[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$Log,[ValidateRange(1,3)][int]$Rounds=1)
$ErrorActionPreference = 'Stop'
foreach ($file in $Log) {
    $lines = Get-Content -LiteralPath $file
    if ($lines -match 'CT_SITE_INVALID|Exception reported|Engine Error' -or -not ($lines -match '^CT_SITE_SURVEY_DONE$')) {
        throw "Invalid Anubis fixture: $file"
    }
    $breakables = @($lines -match '^CT_SITE_FIRE bot=.* hit=func_breakable ')
    if (-not $breakables.Count) { throw "Anubis route-clearing shot not exercised: $file" }
    $retained = @($lines -match 'Retained .* opening order during native breakable clearing\.')
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^CT_SITE_FIRE bot=(.+) weapon=\S+ hit=func_breakable ' -and
            $lines[$i-1] -match ('Released ' + [regex]::Escape($Matches[1]) + ' to native combat AI: weapon contact')) {
            throw "CT hold released for an Anubis path-clearing shot: $($lines[$i])"
        }
    }
    $occupancy = @($lines -match '^CT_SITE_OCCUPANCY map=de_anubis ')
    if ($occupancy.Count -ne $Rounds -or ($occupancy -notmatch 'final_mask=3$')) {
        throw "Anubis did not maintain both occupied sites: $file"
    }
    if (-not $retained.Count) { throw "Expected native route-clearing signal in $file" }
    "ANUBIS_BREAKABLE_PASS rounds=$Rounds hits=$($breakables.Count) kept=$($retained.Count)"
}
