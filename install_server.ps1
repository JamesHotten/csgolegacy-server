[CmdletBinding()]
param(
    [string]$InstallRoot = $PSScriptRoot,
    [string]$ReleaseTag = "v1.0.0"
)

$ErrorActionPreference = "Stop"
$steamCmdUrl = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
$modUrl = "https://github.com/JamesHotten/csgolegacy-server/releases/download/$ReleaseTag/csgolegacy-mod-overlay.zip"
$expectedModSha256 = "0F09BA44B7EE3F9EB07CB91BEE9D7B340B05B30F70AB026DBA5649350BD12D14"
$steamCmdDir = Join-Path $InstallRoot "steamcmd"
$serverDir = Join-Path $InstallRoot "server"
$cacheDir = Join-Path $InstallRoot ".cache"
$steamCmdZip = Join-Path $cacheDir "steamcmd.zip"
$modZip = Join-Path $cacheDir "csgolegacy-mod-overlay.zip"

New-Item -ItemType Directory -Path $steamCmdDir, $serverDir, $cacheDir -Force | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $steamCmdDir "steamcmd.exe"))) {
    Write-Host "Downloading SteamCMD..."
    Invoke-WebRequest -Uri $steamCmdUrl -OutFile $steamCmdZip
    Expand-Archive -LiteralPath $steamCmdZip -DestinationPath $steamCmdDir -Force
}

Write-Host "Installing/verifying CS:GO Legacy Dedicated Server App 740..."
& (Join-Path $steamCmdDir "steamcmd.exe") `
    "+force_install_dir" $serverDir `
    "+login" "anonymous" `
    "+app_update" "740" "validate" `
    "+quit"
if ($LASTEXITCODE -ne 0) {
    throw "SteamCMD failed with exit code $LASTEXITCODE"
}

Write-Host "Downloading MOD overlay $ReleaseTag..."
Invoke-WebRequest -Uri $modUrl -OutFile $modZip
$actualModSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $modZip).Hash
if ($actualModSha256 -ne $expectedModSha256) {
    throw "MOD overlay checksum mismatch. Expected $expectedModSha256, got $actualModSha256"
}

Write-Host "Applying MOD overlay..."
Expand-Archive -LiteralPath $modZip -DestinationPath (Join-Path $serverDir "csgo") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "config\server.cfg") -Destination (Join-Path $serverDir "csgo\cfg\server.cfg") -Force
Set-Content -LiteralPath (Join-Path $serverDir "steam_appid.txt") -Value "740" -Encoding Ascii

Write-Host "Installation complete. Run start_server.bat."
