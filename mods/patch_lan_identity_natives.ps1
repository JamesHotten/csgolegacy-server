[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$pluginsDir = Join-Path $ServerDir "csgo\addons\sourcemod\plugins"
$backupDir = Join-Path $pluginsDir "disabled\lan-identity-originals"

$targets = @{
    "csgo_agentschooser.smx"  = @("GetClientAuthId|LANClientAuthId", "Cookie.Cookie|LanCk.Make", "Cookie.Get|LanCk.Get", "Cookie.Set|LanCk.Set")
    "csgo_spray.smx"          = @("Cookie.Cookie|LanCk.Make", "Cookie.Get|LanCk.Get", "Cookie.Set|LanCk.Set")
    "csgo_weaponstickers.smx" = @("GetClientAuthId|LANClientAuthId")
    "gloves.smx"              = @("GetClientAuthId|LANClientAuthId", "GetSteamAccountID|LANSteamAccountID")
    "kento_rankme.smx"        = @("GetClientAuthId|LANClientAuthId", "RegClientCookie|LANCookieMake", "GetClientCookie|LANCookieRead", "SetClientCookie|LANCookieSave")
    "musickit.smx"            = @("Cookie.Cookie|LanCk.Make", "Cookie.Get|LanCk.Get", "Cookie.Set|LanCk.Set")
    "ranks_matchmaking.smx"   = @("GetSteamAccountID|LANSteamAccountID")
    "weapons.smx"             = @("GetClientAuthId|LANClientAuthId", "GetSteamAccountID|LANSteamAccountID")
}

function Expand-SmxImage {
    param([byte[]]$File, [string]$Path)

    if ($File.Length -lt 24 -or [System.BitConverter]::ToUInt32($File, 0) -ne 0x53504646) {
        throw "Not a valid SourceMod SMX file: '$Path'"
    }

    $compression = $File[6]
    $imageSize = [System.BitConverter]::ToUInt32($File, 11)
    $dataOffset = [System.BitConverter]::ToUInt32($File, 20)
    if ($compression -eq 0) {
        return $File
    }
    if ($compression -ne 1) {
        throw "Unsupported SMX compression type $compression in '$Path'."
    }

    $input = [System.IO.MemoryStream]::new($File, $dataOffset + 2, $File.Length - $dataOffset - 6, $false)
    $deflate = [System.IO.Compression.DeflateStream]::new($input, [System.IO.Compression.CompressionMode]::Decompress)
    $output = [System.IO.MemoryStream]::new()
    try {
        $deflate.CopyTo($output)
        $payload = $output.ToArray()
    } finally {
        $deflate.Dispose()
        $input.Dispose()
        $output.Dispose()
    }

    if ($payload.Length -ne $imageSize - $dataOffset) {
        throw "Unexpected decompressed size in '$Path'."
    }

    $image = [byte[]]::new($imageSize)
    [System.Array]::Copy($File, 0, $image, 0, $dataOffset)
    [System.Array]::Copy($payload, 0, $image, $dataOffset, $payload.Length)
    return $image
}

function Replace-NativeName {
    param([byte[]]$Image, [string]$OldName, [string]$NewName, [string]$Path)

    if ($NewName.Length -gt $OldName.Length) {
        throw "Replacement native '$NewName' is longer than '$OldName'."
    }

    $text = [System.Text.Encoding]::ASCII.GetString($Image)
    $oldOffset = $text.IndexOf($OldName + [char]0, [System.StringComparison]::Ordinal)
    if ($oldOffset -lt 0) {
        if ($text.Contains($NewName + [char]0)) {
            return $false
        }
        throw "Native '$OldName' was not found in '$Path'."
    }

    [System.Array]::Clear($Image, $oldOffset, $OldName.Length)
    $replacement = [System.Text.Encoding]::ASCII.GetBytes($NewName)
    [System.Array]::Copy($replacement, 0, $Image, $oldOffset, $replacement.Length)
    return $true
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($entry in $targets.GetEnumerator()) {
    $pluginPath = Join-Path $pluginsDir $entry.Key
    if (-not (Test-Path -LiteralPath $pluginPath)) {
        throw "Required MOD plugin was not found: '$pluginPath'"
    }

    $backupPath = Join-Path $backupDir $entry.Key
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $pluginPath -Destination $backupPath
    }

    [byte[]]$image = Expand-SmxImage -File ([System.IO.File]::ReadAllBytes($pluginPath)) -Path $pluginPath
    $changed = $false
    foreach ($replacement in $entry.Value) {
        $names = $replacement.Split('|', 2)
        $changed = (Replace-NativeName -Image $image -OldName $names[0] -NewName $names[1] -Path $pluginPath) -or $changed
    }

    if ($changed) {
        # Keep section offsets intact and store the patched image uncompressed.
        $image[6] = 0
        [System.Array]::Copy([System.BitConverter]::GetBytes([uint32]$image.Length), 0, $image, 7, 4)
        [System.IO.File]::WriteAllBytes($pluginPath, $image)
        Write-Host "Patched LAN identity natives in $($entry.Key)."
    } else {
        Write-Host "LAN identity natives already patched in $($entry.Key)."
    }
}
