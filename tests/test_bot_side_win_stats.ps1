param(
    [Parameter(Mandatory = $true)][string]$SideStatsSource,
    [Parameter(Mandatory = $true)][string]$InstallerSource
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SideStatsSource -Raw
$installer = Get-Content -LiteralPath $InstallerSource -Raw

if (-not $source.Contains('HookEvent("round_start"') -or
    -not $source.Contains('HookEvent("round_end"') -or
    -not $source.Contains('winner != CS_TEAM_T && winner != CS_TEAM_CT') -or
    -not $source.Contains('m_bWarmupPeriod') -or
    -not $source.Contains('g_eligibleRound = false;') -or
    -not $source.Contains('data/bot_side_win_stats.txt') -or
    -not $source.Contains('store.ExportToFile(g_storePath)') -or
    -not $source.Contains('ShowCounts(client, "This map session"') -or
    -not $source.Contains('ShowCounts(client, "All maps"') -or
    -not $source.Contains('RegConsoleCmd("sm_sidewin"')) {
    throw 'Side-win counts must persist and omit warmup, draws and duplicate round-end events.'
}
if (-not $installer.Contains('bot_side_win_stats.sp') -or
    -not $installer.Contains('000_bot_side_win_stats.smx')) {
    throw 'Deployment must compile and install the independent side-win plugin.'
}

Write-Host 'Persistent CT/T round-win statistics checks passed.'
