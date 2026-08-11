[CmdletBinding()]
param(
    [string]$InstallRoot = $PSScriptRoot,
    [string]$ReleaseTag = "v1.0.0"
)

$ErrorActionPreference = "Stop"
$steamCmd = Join-Path $InstallRoot "steamcmd\steamcmd.exe"
$serverDir = Join-Path $InstallRoot "server"
$cacheDir = Join-Path $InstallRoot ".cache"
$modZip = Join-Path $cacheDir "csgolegacy-mod-overlay.zip"
$modUrl = "https://github.com/JamesHotten/csgolegacy-server/releases/download/$ReleaseTag/csgolegacy-mod-overlay.zip"
$expectedModSha256 = "0F09BA44B7EE3F9EB07CB91BEE9D7B340B05B30F70AB026DBA5649350BD12D14"

if (-not (Test-Path -LiteralPath $steamCmd)) {
    throw "SteamCMD is missing. Run install_server.ps1 first."
}

& $steamCmd `
    "+force_install_dir" $serverDir `
    "+login" "anonymous" `
    "+app_update" "740" "validate" `
    "+quit"
if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
Invoke-WebRequest -Uri $modUrl -OutFile $modZip
$actualModSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $modZip).Hash
if ($actualModSha256 -ne $expectedModSha256) {
    throw "MOD overlay checksum mismatch. Expected $expectedModSha256, got $actualModSha256"
}
Expand-Archive -LiteralPath $modZip -DestinationPath (Join-Path $serverDir "csgo") -Force
& (Join-Path $PSScriptRoot "install_custom_plugins.ps1") -ServerDir $serverDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "config\server.cfg") -Destination (Join-Path $serverDir "csgo\cfg\server.cfg") -Force
Set-Content -LiteralPath (Join-Path $serverDir "steam_appid.txt") -Value "740" -Encoding Ascii

Write-Host "Server and MOD overlay updated."
