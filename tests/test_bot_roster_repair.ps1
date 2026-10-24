param([Parameter(Mandatory = $true)][string]$ServerDir)
$ErrorActionPreference = 'Stop'
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$fixture = Join-Path $temporaryRoot ('csgo-roster-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$fixture\csgo\addons\sourcemod\configs" -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $ServerDir 'srcds.exe') -Destination "$fixture\srcds.exe"
    $backup = Join-Path $ServerDir 'csgo\addons\sourcemod\data\bot-roster-assets-rollback'
    $profileInput = if (Test-Path -LiteralPath "$backup\botprofile.db") { "$backup\botprofile.db" } else { Join-Path $ServerDir 'csgo\botprofile.db' }
    $rosterInput = if (Test-Path -LiteralPath "$backup\bot_rosters.txt") { "$backup\bot_rosters.txt" } else { Join-Path $ServerDir 'csgo\addons\sourcemod\configs\bot_rosters.txt' }
    Copy-Item -LiteralPath $profileInput -Destination "$fixture\csgo\botprofile.db"
    Copy-Item -LiteralPath $rosterInput -Destination "$fixture\csgo\addons\sourcemod\configs\bot_rosters.txt"
    $beforeProfile = Get-Content -LiteralPath "$fixture\csgo\botprofile.db" -Raw
    $beforeRosters = Get-Content -LiteralPath "$fixture\csgo\addons\sourcemod\configs\bot_rosters.txt" -Raw
    & "$PSScriptRoot\..\mods\patch_bot_roster_assets.ps1" -ServerDir $fixture
    & "$PSScriptRoot\test_bot_roster_assets.ps1" -ServerDir $fixture
    $afterProfile = Get-Content -LiteralPath "$fixture\csgo\botprofile.db" -Raw
    if (-not $afterProfile.StartsWith($beforeProfile, [System.StringComparison]::Ordinal)) { throw 'Repair modified existing BOT profiles.' }
    $expectedRosters = [regex]::Replace($beforeRosters, '(?ms)("LargadosyPelados"\s*\{\s*"players"\s*"[^"\r\n]+"\s*"logo"\s*")larg(")', '${1}${2}')
    if ((Get-Content -LiteralPath "$fixture\csgo\addons\sourcemod\configs\bot_rosters.txt" -Raw) -cne $expectedRosters) { throw 'Repair modified players, other teams or unexpected roster fields.' }
    $firstHashes = @(Get-FileHash -LiteralPath "$fixture\csgo\botprofile.db", "$fixture\csgo\addons\sourcemod\configs\bot_rosters.txt" | Select-Object -ExpandProperty Hash)
    & "$PSScriptRoot\..\mods\patch_bot_roster_assets.ps1" -ServerDir $fixture
    $secondHashes = @(Get-FileHash -LiteralPath "$fixture\csgo\botprofile.db", "$fixture\csgo\addons\sourcemod\configs\bot_rosters.txt" | Select-Object -ExpandProperty Hash)
    if (($firstHashes -join ',') -cne ($secondHashes -join ',')) { throw 'Repair is not idempotent.' }
    foreach ($name in @('zmb','happ','Leomonster')) {
        if ([regex]::Matches($afterProfile, '(?m)^\s*[^/\r\n=]+"' + $name + '"\s*\r?$').Count -ne 1) { throw "Duplicate/missing profile: $name" }
    }
    Write-Host 'Roster repair fixture passed: old profiles/players preserved; no-logo fallback and idempotence verified.'
} finally {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedFixture -Leaf) -notmatch '^csgo-roster-test-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup target.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
