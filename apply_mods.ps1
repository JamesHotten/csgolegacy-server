[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir,
    [string]$ReleaseTag = "v1.0.0"
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir "srcds.exe"
$csgoDir = Join-Path $ServerDir "csgo"
$modUrl = "https://github.com/JamesHotten/csgolegacy-server/releases/download/$ReleaseTag/csgolegacy-mod-overlay.zip"
$expectedModSha256 = "0F09BA44B7EE3F9EB07CB91BEE9D7B340B05B30F70AB026DBA5649350BD12D14"
$cacheDir = Join-Path $PSScriptRoot ".cache"
$modZip = Join-Path $cacheDir "csgolegacy-mod-overlay.zip"

if (-not (Test-Path -LiteralPath $serverExe)) {
    throw "srcds.exe was not found in '$ServerDir'. Pass the App 740 installation directory."
}
if (-not (Test-Path -LiteralPath $csgoDir)) {
    throw "The CS:GO game directory was not found: '$csgoDir'"
}

$runningServer = Get-CimInstance Win32_Process -Filter "Name = 'srcds.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe) }
if ($runningServer) {
    throw "Stop the target srcds.exe before applying the MOD overlay."
}

New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
Write-Host "Downloading MOD overlay $ReleaseTag..."
Invoke-WebRequest -Uri $modUrl -OutFile $modZip

$actualModSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $modZip).Hash
if ($actualModSha256 -ne $expectedModSha256) {
    throw "MOD overlay checksum mismatch. Expected $expectedModSha256, got $actualModSha256"
}

Write-Host "Applying MODs and SQLite snapshot to $csgoDir..."
Expand-Archive -LiteralPath $modZip -DestinationPath $csgoDir -Force
& (Join-Path $PSScriptRoot "install_custom_plugins.ps1") -ServerDir $ServerDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "config\server.cfg") -Destination (Join-Path $csgoDir "cfg\server.cfg") -Force
Set-Content -LiteralPath (Join-Path $ServerDir "steam_appid.txt") -Value "740" -Encoding Ascii

$startScript = @(
    "@echo off"
    "setlocal"
    "chcp 65001 >nul"
    "cd /d `"%~dp0`""
    "set `"SteamAppId=740`""
    "set `"SteamGameId=740`""
    "echo Starting CS:GO Legacy BetterBots server..."
    "srcds.exe -game csgo -console -usercon -condebug -conclearlog -tickrate 128 -ip 0.0.0.0 -port 27016 -clientport 27006 -insecure -maxplayers_override 20 +game_type 0 +game_mode 1 +map de_mirage +exec server.cfg"
    "endlocal"
)
Set-Content -LiteralPath (Join-Path $ServerDir "start_server.bat") -Value $startScript -Encoding Ascii

Write-Host "MOD deployment complete. Run '$ServerDir\start_server.bat'."
