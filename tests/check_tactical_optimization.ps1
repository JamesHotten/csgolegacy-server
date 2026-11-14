param(
    [Parameter(Mandatory)][string]$StallLog,
    [Parameter(Mandatory)][string]$RetakeLog,
    [Parameter(Mandatory)][string]$ComboLog,
    [Parameter(Mandatory)][string]$UtilityLog,
    [Parameter(Mandatory)][string]$StabilityLog
)
$ErrorActionPreference = 'Stop'
$stall = Get-Content -LiteralPath $StallLog -Raw
$retake = Get-Content -LiteralPath $RetakeLog -Raw
$combo = Get-Content -LiteralPath $ComboLog -Raw
$utility = Get-Content -LiteralPath $UtilityLog -Raw
$stability = Get-Content -LiteralPath $StabilityLog -Raw
foreach ($log in $stall,$retake,$combo,$utility,$stability) {
    if ($log -match 'Exception reported|Engine Error|ROUTE_STALL_FAIL|PLANT_ROUTE_FAIL') { throw 'Runtime failure in the supplied console logs.' }
}
if ($stability -notmatch '(?m)^TACTICAL_MATCH_ROUND round=2 ct=5 t=5 .* swapped=10 warmup=0\r?$' -or
    $stability -notmatch '(?m)^TACTICAL_MATCH_ROUND round=4 ct=5 t=5 .* swapped=10 warmup=0\r?$' -or
    $stability -notmatch '(?m)^TACTICAL_MATCH_FALLBACK orders=0 phases=[3-9]\r?$') {
    throw 'The short match did not preserve BOT identities through both half switches and clear orders on disable.'
}
foreach ($map in 'de_inferno','de_mirage','de_nuke') {
    if ($stall -notmatch "(?m)^ROUTE_STALL_PASS map=$map retries=1 peer_changes=0\r?`$") { throw "$map did not preserve peer orders in the controlled stall." }
    if ($retake -notmatch "(?m)^PLANT_ROUTE_PASS map=$map " -or $retake -notmatch "(?m)^RETAKE_ROUND map=$map winner=3 reason=7\r?`$") {
        throw "$map did not log a real defuse and CT objective win."
    }
}
if ($combo -notmatch 'T fake runner .* show=[AB] main=[AB]' -or $combo -notmatch 'CT paired pressure: .* and ' -or $combo -notmatch 'CT paired pressure returned to original coverage') {
    throw 'The optional variants did not enter and leave their expected states.'
}
$mirage = [regex]::Match($utility, '(?s)Map Load: de_mirage\b.*?(?=\*\*\* Map Load:|\z)').Value
if ($mirage -notmatch '(?m)^MIRAGE_UTILITY actual=smokegrenade_detonate' -or $mirage -notmatch '(?m)^RETAKE_ROUND map=de_mirage winner=3 reason=7') {
    throw 'No actual Mirage smoke detonation plus round outcome was captured.'
}
Write-Output 'TACTICAL_OPTIMIZATION_RUNTIME_PASS'
