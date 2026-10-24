param([Parameter(Mandatory = $true)][string]$DatabasePath)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "No BOT experience database at $DatabasePath"
}
$sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
$query = "SELECT count(*) FROM events e JOIN rounds r ON r.id=e.round_id WHERE e.kind='kill' AND e.victim_team IN (2,3) AND e.weapon IS NOT NULL;"
$result = & $sqlite -readonly -noheader $DatabasePath $query
if ($LASTEXITCODE -ne 0 -or [int]$result -lt 1) {
    throw 'No round-linked kill event is queryable.'
}
Write-Host "BOT experience kill recording passed: $result kill event(s)."
