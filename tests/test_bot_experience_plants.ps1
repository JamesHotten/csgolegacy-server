param([Parameter(Mandatory = $true)][string]$DatabasePath)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DatabasePath)) {
    throw "No BOT experience database at $DatabasePath"
}
$sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
$query = "SELECT count(*) FROM events e JOIN rounds r ON r.id=e.round_id WHERE e.kind='plant' AND e.actor_team=2 AND e.site IN ('A','B');"
$result = & $sqlite -readonly -noheader $DatabasePath $query
if ($LASTEXITCODE -ne 0 -or [int]$result -lt 1) {
    throw 'No round-linked A/B bomb plant is queryable.'
}
Write-Host "BOT experience plant recording passed: $result plant event(s)."
