[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineLog,
    [Parameter(Mandatory)][string]$CandidateLog,
    [Parameter(Mandatory)][string]$DisabledLog
)
$ErrorActionPreference = 'Stop'
function Read-Fixture([string]$file, [bool]$enabled) {
    $lines = Get-Content -LiteralPath $file
    if ($lines -match 'Exception reported|Engine Error|CT_SITE_INVALID|^OVC_DEBUG') {
        throw "Invalid crossfire fixture: $file"
    }
    $distribution = @($lines -match '^CT_SITE_DISTRIBUTION map=de_overpass round=1 calibration=3 ')
    if ($distribution.Count -ne 1 -or $distribution[0] -notmatch 'orders=3,2 aim_ok=3,2 .*target_in=2,1$') {
        throw "Opening order/occupancy change: $file"
    }
    for ($phase = 0; $phase -le 1; $phase++) {
        $result = @($lines -match "^OVC_RESULT phase=$phase ")
        if ($result.Count -ne 1) { throw "Missing fixture result (phase $phase): $file" }
        $expected = if ($enabled) { 'shared=7 restroom=1' } else { 'shared=0 restroom=0' }
        if ($result[0] -notmatch "count=2 $expected$") {
            throw "Unexpected crossfire verdict (phase $phase): $($result[0])"
        }
        if ($enabled) {
            $slots = @($lines -match "^OVC_SLOT phase=$phase ")
            if ($slots.Count -ne 2) { throw "Expected two A slots (phase $phase): $file" }
            foreach ($slot in $slots) {
                if ($slot -notmatch ' zone=1 park=7 sectors=1 .* aim=1 at=(\d+) .* hold=24$' -or [int]$Matches[1] -gt 27) {
                    throw "Unsettled/multi-entrance A hold (phase $phase): $slot"
                }
            }
        }
    }
    return @($lines -match '^CT_SITE_PLAN map=de_overpass round=1 ')
}
function Get-Unchanged($plan,[bool]$includeA) {
    foreach ($line in $plan) {
        if ($line -match 'site=([AB]) zone=(\d) goal=([^ ]+) hold=([^ ]+) place=([^ ]+) aim=([^ ]+)') {
            # The plan reports the midpoint rotator as A in horizontal
            # projection; its actual goal is outside the A bomb brush.
            if ($includeA -or $Matches[1] -eq 'B' -or $Matches[2] -eq '0') {
                "$($Matches[1]) $($Matches[2]) $($Matches[3]) $($Matches[4]) $($Matches[5]) $($Matches[6])"
            }
        }
    }
}
$base = @(Read-Fixture $BaselineLog $false)
$pair = @(Read-Fixture $CandidateLog $true)
$off = @(Read-Fixture $DisabledLog $false)
if ($base.Count -ne 5 -or $pair.Count -ne 5 -or $off.Count -ne 5) { throw 'Expected five opening orders' }
$nonsite = @(Get-Unchanged $base $false)
if ($nonsite.Count -ne 3 -or (Compare-Object $nonsite @(Get-Unchanged $pair $false))) {
    throw 'Candidate changed a B defender or the rotator'
}
if (Compare-Object @(Get-Unchanged $base $true) @(Get-Unchanged $off $true)) {
    throw 'Cvar 0 failed to restore all baseline goals/aims/hold radii'
}
Write-Output 'PASS: current vs candidate: 0 -> 3 shared Lower Park samples at planned and actual locations; Restroom covered; both A holders in brush; unchanged B + rotator; cvar off equals baseline.'
