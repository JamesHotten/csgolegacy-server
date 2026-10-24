[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ServerDir)
$ErrorActionPreference = 'Stop'
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir 'srcds.exe'
if (-not (Test-Path -LiteralPath $serverExe)) { throw 'Expected the exact CS:GO server directory.' }
if (Get-CimInstance Win32_Process -Filter "Name='srcds.exe'" | Where-Object { $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe }) { throw 'Stop the target server before installing the CT NAV interface.' }
$sm = Join-Path $ServerDir 'csgo\addons\sourcemod'
$sourcePath = Join-Path $sm 'scripting\navmesh.sp'
$pluginPath = Join-Path $sm 'plugins\navmesh.smx'
$compiler = Join-Path $sm 'scripting\spcomp.exe'
$text = Get-Content -LiteralPath $sourcePath -Raw
# SourcePawn 1.12 requires explicit function/cell types. These conversions
# preserve the original cell payload and dynamic callback invocation.
$text = $text.Replace('NavPathCostFunctor iCostFunction', 'Function iCostFunction')
$text = $text.Replace('view_as<NavPathCostFunctor>(GetNativeFunction(4))', 'GetNativeFunction(4)')
$text = $text.Replace('return g_TerrorNavMeshNavMaxViewDistance;', 'return view_as<int>(g_TerrorNavMeshNavMaxViewDistance);')
foreach ($callback in @('Native_NavMeshAreaGetAdjacentAreas','Native_NavMeshAreaGetIncomingConnections','Native_CSNavAreaGetApproachInfoList')) {
    $pattern = '(?s)(public int ' + $callback + '\(.*?\r?\n\{)(.*?)(\r?\n\})'
    $text = [regex]::Replace($text, $pattern, {
        param($match)
        $body = $match.Groups[2].Value -replace '\breturn;', 'return 0;'
        if ($body -notmatch 'return 0;\s*$') { $body += "`r`n`treturn 0;" }
        $match.Groups[1].Value + $body + $match.Groups[3].Value
    })
}
$anchor = 'CreateNative("NavMeshArea_GetPlace", Native_NavMeshAreaGetPlace);'
if (-not $text.Contains('CreateNative("NavMeshArea_GetPlaceCanonical"')) {
    if (-not $text.Contains($anchor) -or -not $text.Contains('public void OnPluginStart()')) { throw 'Unexpected NAV parser source; refusing an unverified patch.' }
    $text = $text.Replace($anchor, $anchor + "`r`n`t" + 'CreateNative("NavMeshArea_GetPlaceCanonical", Native_CTNavPlaceCanonical);')
    $text = $text.Replace('public void OnPluginStart()', '#include <bot_ct_nav_place>' + "`r`n`r`n" + 'public void OnPluginStart()')
}
$build = Join-Path $sm 'data\ct-nav-place-build'
$backup = Join-Path $sm 'data\ct-nav-place-rollback'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$candidateSource = Join-Path $build 'navmesh.sp'
$candidatePlugin = Join-Path $build 'navmesh.smx'
try {
    Copy-Item -LiteralPath "$PSScriptRoot\include\bot_ct_nav_place.inc" -Destination (Join-Path $sm 'scripting\include\bot_ct_nav_place.inc') -Force
    [System.IO.File]::WriteAllText($candidateSource, $text, [System.Text.UTF8Encoding]::new($false))
    & $compiler "-o$candidatePlugin" $candidateSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidatePlugin)) { throw 'CT NAV interface compilation failed; installed NAV plugin preserved.' }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($path in @($sourcePath,$pluginPath)) {
        $saved = Join-Path $backup ([System.IO.Path]::GetFileName($path))
        if (-not (Test-Path -LiteralPath $saved)) { Copy-Item -LiteralPath $path -Destination $saved }
    }
    Copy-Item -LiteralPath $candidateSource -Destination $sourcePath -Force
    Copy-Item -LiteralPath $candidatePlugin -Destination $pluginPath -Force
} finally {
    foreach ($path in @($candidateSource,$candidatePlugin)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
}
Write-Host 'Installed optional canonical NAV-place reader; legacy API and navigation data unchanged.'
