param(
    [Parameter(Mandatory = $true)][string]$ServerDir,
    [string]$TargetTeam = 'LargadosyPelados'
)
$ErrorActionPreference = 'Stop'
$profile = Get-Content -LiteralPath (Join-Path $ServerDir 'csgo\botprofile.db') -Raw
$rosters = Get-Content -LiteralPath (Join-Path $ServerDir 'csgo\addons\sourcemod\configs\bot_rosters.txt') -Raw
$teams = [regex]::Matches($rosters, '(?ms)"(?<team>[^"\r\n]+)"\s*\{\s*"players"\s*"(?<players>[^"\r\n]+)"\s*"logo"\s*"(?<logo>[^"\r\n]*)"')
$team = @($teams | Where-Object { $_.Groups['team'].Value -ceq $TargetTeam })
if ($team.Count -ne 1) { throw "Expected exactly one target roster: $TargetTeam" }
$failures = @()
foreach ($player in $team[0].Groups['players'].Value.Split(',')) {
    $pattern = '(?m)^\s*[^/\r\n=]+"' + [regex]::Escape($player.Trim()) + '"\s*\r?$'
    if (-not [regex]::IsMatch($profile, $pattern)) { $failures += "No BOT profile: $player" }
}
$logo = $team[0].Groups['logo'].Value
if ($logo) {
    foreach ($relative in @("csgo\materials\panorama\images\tournaments\teams\$logo.svg", "csgo\resource\flash\econ\tournaments\teams\$logo.cfg")) {
        if (-not (Test-Path -LiteralPath (Join-Path $ServerDir $relative))) { $failures += "Missing roster asset: $relative" }
    }
}
if ($failures.Count) { throw ($failures -join '; ') }
Write-Host "Roster profile and declared-logo assets passed: $TargetTeam"
