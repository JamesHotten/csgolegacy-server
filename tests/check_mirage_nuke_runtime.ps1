param(
    [Parameter(Mandatory)][string]$LogPath,
    [switch]$AlternateSites
)
$ErrorActionPreference = 'Stop'
$log = Get-Content -LiteralPath $LogPath -Raw
if ($log -match 'PLANT_ROUTE_FAIL|Exception reported|Engine Error' -or $log -notmatch '(?m)^PLANT_ROUTE_SERIES_DONE\r?$') {
    throw 'The isolated route series did not finish cleanly.'
}
$sites = if ($AlternateSites) { @{ de_mirage = 'B'; de_nuke = 'A' } } else { @{ de_mirage = 'A'; de_nuke = 'B' } }
foreach ($map in 'de_mirage', 'de_nuke') {
    $site = $sites[$map]
    $stage = [regex]::Match($log, "(?m)^STAGE_RESULT map=$map site=$site elapsed=[\d.]+ ready=(\d+)/(\d+) carrier_ready=(\d)\r?`$")
    if (!$stage.Success -or [int]$stage.Groups[2].Value -ne 5 -or $stage.Groups[3].Value -ne '1') {
        throw "The carrier's actual opening arrival was not verified on $map $site."
    }
    $retake = [regex]::Match($log, "(?m)^PLANT_ROUTE_PASS map=$map plant_to_defuse=([\d.]+) stage_samples=(\d+) commit_samples=\d+\r?`$")
    if (!$retake.Success -or [double]$retake.Groups[1].Value -ge 40.0 -or [int]$retake.Groups[2].Value -lt 1) {
        throw "The actual staged CT retake/defuse did not pass on $map $site."
    }
    Write-Output "$map $site : $($stage.Groups[1].Value)/5 in last sample, carrier ready, defuse $($retake.Groups[1].Value)s"
}
