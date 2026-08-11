[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PluginPath,
    [string]$BackupPath,
    [Parameter(Mandatory = $true)]
    [ValidateSet("sqlite", "mysql")]
    [string]$DatabaseDriver
)

$ErrorActionPreference = "Stop"
$PluginPath = [System.IO.Path]::GetFullPath($PluginPath)

$oldCreate = "CREATE TABLE IF NOT EXISTS csgo_agentschooser (steam_id VARCHAR(64) NOT NULL PRIMARY KEY, ct_agent VARCHAR(191) NOT NULL DEFAULT '', t_agent VARCHAR(191) NOT NULL DEFAULT '', updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
$newCreate = "CREATE TABLE IF NOT EXISTS csgo_agentschooser (steam_id VARCHAR(64) NOT NULL PRIMARY KEY, ct_agent VARCHAR(191) NOT NULL DEFAULT '', t_agent VARCHAR(191) NOT NULL DEFAULT '', updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);"
$oldSave = "INSERT INTO csgo_agentschooser (steam_id, ct_agent, t_agent) VALUES ('%s','%s','%s') ON DUPLICATE KEY UPDATE ct_agent=VALUES(ct_agent), t_agent=VALUES(t_agent);"
$newSave = "REPLACE INTO csgo_agentschooser (steam_id, ct_agent, t_agent) VALUES ('%s','%s','%s');"

function Replace-SmString {
    param(
        [byte[]]$Image,
        [string]$OldValue,
        [string]$NewValue
    )

    if ($NewValue.Length -gt $OldValue.Length) {
        throw "Replacement SQL is longer than the compiled string slot."
    }

    $imageText = [System.Text.Encoding]::ASCII.GetString($Image)
    $offset = $imageText.IndexOf($OldValue, [System.StringComparison]::Ordinal)
    if ($offset -lt 0) {
        if ($imageText.Contains($NewValue)) {
            return $false
        }
        throw "Expected SQL string was not found in '$PluginPath'."
    }

    $replacement = [System.Text.Encoding]::ASCII.GetBytes($NewValue)
    [System.Array]::Clear($Image, $offset, $OldValue.Length)
    [System.Array]::Copy($replacement, 0, $Image, $offset, $replacement.Length)
    return $true
}

$file = [System.IO.File]::ReadAllBytes($PluginPath)
if ($file.Length -lt 24 -or [System.BitConverter]::ToUInt32($file, 0) -ne 0x53504646) {
    throw "Not a valid SourceMod SMX file: '$PluginPath'"
}

$compression = $file[6]
$imageSize = [System.BitConverter]::ToUInt32($file, 11)
$dataOffset = [System.BitConverter]::ToUInt32($file, 20)

if ($compression -eq 0) {
    $image = $file
} elseif ($compression -eq 1) {
    # SMX uses zlib. PowerShell 5.1 DeflateStream expects the raw stream,
    # so skip the two-byte zlib header and four-byte Adler-32 trailer.
    $input = [System.IO.MemoryStream]::new($file, $dataOffset + 2, $file.Length - $dataOffset - 6, $false)
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
        throw "Unexpected decompressed SMX size."
    }

    $image = [byte[]]::new($imageSize)
    [System.Array]::Copy($file, 0, $image, 0, $dataOffset)
    [System.Array]::Copy($payload, 0, $image, $dataOffset, $payload.Length)
} else {
    throw "Unsupported SMX compression type: $compression"
}

if ($BackupPath) {
    $BackupPath = [System.IO.Path]::GetFullPath($BackupPath)
}

if ($DatabaseDriver -eq "mysql") {
    $imageText = [System.Text.Encoding]::ASCII.GetString($image)
    if ($imageText.Contains($oldCreate) -and $imageText.Contains($oldSave)) {
        Write-Host "Agents Chooser retains its original MySQL SQL."
        return
    }

    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        Copy-Item -LiteralPath $BackupPath -Destination $PluginPath -Force
        Write-Host "Restored the original MySQL Agents Chooser plugin."
        return
    }

    throw "The plugin is SQLite-patched and no original MySQL backup is available."
}

$changed = (Replace-SmString -Image $image -OldValue $oldCreate -NewValue $newCreate)
$changed = (Replace-SmString -Image $image -OldValue $oldSave -NewValue $newSave) -or $changed

if (-not $changed) {
    Write-Host "Agents database SQL is already SQLite/MySQL compatible."
    return
}

if ($BackupPath) {
    $backupDir = Split-Path -Parent $BackupPath
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $BackupPath)) {
        Copy-Item -LiteralPath $PluginPath -Destination $BackupPath
    }
}

# Store the patched SMX uncompressed. Section offsets remain unchanged.
$image[6] = 0
[System.Array]::Copy([System.BitConverter]::GetBytes([uint32]$image.Length), 0, $image, 7, 4)
[System.IO.File]::WriteAllBytes($PluginPath, $image)
Write-Host "Patched Agents Chooser SQL for SQLite/MySQL compatibility."
