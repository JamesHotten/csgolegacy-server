[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ServerDir)
$ErrorActionPreference = 'Stop'
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir 'srcds.exe'
if (-not (Test-Path -LiteralPath $serverExe)) { throw 'Expected the exact CS:GO server directory.' }
if (Get-CimInstance Win32_Process -Filter "Name='srcds.exe'" | Where-Object { $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe }) {
    throw 'Stop the target server before repairing roster assets.'
}
$profilePath = Join-Path $ServerDir 'csgo\botprofile.db'
$rosterPath = Join-Path $ServerDir 'csgo\addons\sourcemod\configs\bot_rosters.txt'
$profile = Get-Content -LiteralPath $profilePath -Raw
$rosters = Get-Content -LiteralPath $rosterPath -Raw
$newProfile = $profile
$newRosters = $rosters
# Reuse the same existing generic pro-rifle templates as divine/Alisson.
# These are compatibility fallbacks, not claims about real players' ability.
foreach ($template in @('ProP','Rifle','RiflePersonality')) {
    if ($profile -notmatch ('(?m)^\s*Template\s+' + [regex]::Escape($template) + '\s*\r?$')) { throw "Missing required BOT template: $template" }
}
foreach ($name in @('zmb','happ','Leomonster')) {
    $pattern = '(?m)^\s*[^/\r\n=]+"' + [regex]::Escape($name) + '"\s*\r?$'
    if (-not [regex]::IsMatch($newProfile, $pattern)) {
        $newProfile += "`r`n// Roster compatibility fallback; keep existing named profiles unchanged.`r`nProP+Rifle+RiflePersonality `"$name`"`r`nEnd`r`n"
    }
}
$largPattern = '(?ms)("LargadosyPelados"\s*\{\s*"players"\s*"[^"\r\n]+"\s*"logo"\s*")larg(")'
if ([regex]::IsMatch($rosters, $largPattern)) {
    $svg = Join-Path $ServerDir 'csgo\materials\panorama\images\tournaments\teams\larg.svg'
    $cfg = Join-Path $ServerDir 'csgo\resource\flash\econ\tournaments\teams\larg.cfg'
    if (-not (Test-Path -LiteralPath $svg) -and -not (Test-Path -LiteralPath $cfg)) {
        $newRosters = [regex]::Replace($rosters, $largPattern, '${1}${2}')
    } elseif (-not (Test-Path -LiteralPath $svg) -or -not (Test-Path -LiteralPath $cfg)) {
        throw 'Partial larg assets found; review manually rather than discarding a real logo.'
    }
}
$backup = Join-Path $ServerDir 'csgo\addons\sourcemod\data\bot-roster-assets-rollback'
$encoding = [System.Text.UTF8Encoding]::new($false)
foreach ($change in @(@($profilePath,$profile,$newProfile), @($rosterPath,$rosters,$newRosters))) {
    if ($change[1] -ceq $change[2]) { continue }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $backupPath = Join-Path $backup ([System.IO.Path]::GetFileName($change[0]))
    if (-not (Test-Path -LiteralPath $backupPath)) { Copy-Item -LiteralPath $change[0] -Destination $backupPath }
    [System.IO.File]::WriteAllText($change[0], $change[2], $encoding)
}
Write-Host 'Roster compatibility repaired: preserve existing profiles; use explicit no-logo fallback where original larg assets are absent.'
