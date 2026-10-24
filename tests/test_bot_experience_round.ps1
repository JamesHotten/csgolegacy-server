param([Parameter(Mandatory = $true)][string]$DatabasePath)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "No BOT experience database at $DatabasePath"
}
$sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
$query = "SELECT count(*) FROM rounds WHERE map <> '' AND started_at > 0 AND ct_plan <> 'none' AND t_plan <> 'none' AND winner IN (2,3);"
$result = & $sqlite -readonly -noheader $DatabasePath $query
if ($LASTEXITCODE -ne 0 -or [int]$result -lt 1) {
    throw 'No completed round with CT and T opening plans is queryable.'
}
Write-Host "BOT experience round recording passed: $result complete round(s)."
