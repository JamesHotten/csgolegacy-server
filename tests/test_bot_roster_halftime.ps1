param(
    [Parameter(Mandatory = $true)][string]$RosterSource,
    [Parameter(Mandatory = $true)][string]$CoreSource
)

$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $RosterSource -Raw
$core = Get-Content -LiteralPath $CoreSource -Raw
$phase = [regex]::Match($text, '(?s)public void BotTeams_EventPhaseEnd\(.*?public Action BotTeams_TimerPhaseCheck\(').Value
$check = [regex]::Match($text, '(?s)bool BotTeams_MaybeFollowSwappedSides\(\).*?void BotTeams_ReconcileSide\(').Value
$rebuild = [regex]::Match($text, '(?s)public Action BotTeams_TimerRebuild\(.*?void BotTeams_RebuildAll\(').Value

if (-not $text.Contains('HookEvent("announce_phase_end", BotTeams_EventPhaseEnd') -or
    -not $phase.Contains('CreateTimer(1.0, BotTeams_TimerPhaseCheck') -or
    -not $text.Contains('g_BTR_PhaseCheckUntil')) {
    throw 'Roster follow-up must watch the complete halftime transition, including overtime.'
}
if (-not $check.Contains('ctMovedToT') -or
    -not $check.Contains('tMovedToCT') -or
    -not $check.Contains('moved <= stayed') -or
    -not $check.Contains('strcopy(g_BTR_CTTeam') -or
    -not $check.Contains('strcopy(g_BTR_TTeam')) {
    throw 'Rosters must swap only when their actual BOT identities moved to opposite sides.'
}
if (-not $rebuild.Contains('BotTeams_MaybeFollowSwappedSides();') -or
    $phase.Contains('BotTeams_RebuildAll()')) {
    throw 'Halftime must reconcile swapped rosters instead of rebuilding all BOTs.'
}
if ($text.Contains('HookEvent("player_disconnect", BotTeams_EventPlayerDisconnect') -or
    -not $text.Contains('void BotTeams_OnClientDisconnect(int client)') -or
    -not $core.Contains('BotTeams_OnClientDisconnect(iClient);')) {
    throw 'BOT disconnects must not be mistaken for human departures on CS:GO Legacy.'
}

Write-Host 'BOT roster halftime follow-up regression checks passed.'
