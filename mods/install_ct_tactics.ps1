[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerDir
)

$ErrorActionPreference = "Stop"
$ServerDir = [System.IO.Path]::GetFullPath($ServerDir)
$serverExe = Join-Path $ServerDir "srcds.exe"
$runningServer = Get-CimInstance Win32_Process -Filter "Name = 'srcds.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $serverExe) }
if ($runningServer) {
    throw "Stop the target srcds.exe before installing CT tactics. Use sm_bot_ct_tactics_enable 0 for live rollback."
}

$smRoot = Join-Path $ServerDir "csgo\addons\sourcemod"
$scriptingDir = Join-Path $smRoot "scripting"
$includeDir = Join-Path $scriptingDir "include"
$pluginDir = Join-Path $smRoot "plugins"
$dataDir = Join-Path $smRoot "data\ct-tactics-rollback"
$buildDir = Join-Path $smRoot "data\ct-tactics-build"
$compiler = Join-Path $scriptingDir "spcomp.exe"
$botSource = Join-Path $scriptingDir "bot_stuff.sp"
$botPlugin = Join-Path $pluginDir "bot_stuff.smx"
$profileConfig = Join-Path $smRoot "configs\bot_stuff.cfg"
$directorSource = Join-Path $PSScriptRoot "bot_ct_tactics.sp"
$tDirectorSource = Join-Path $PSScriptRoot "bot_t_tactics.sp"
$installedDirectorSource = Join-Path $scriptingDir "bot_ct_tactics.sp"
$installedTDirectorSource = Join-Path $scriptingDir "bot_t_tactics.sp"
$directorPlugin = Join-Path $pluginDir "001_bot_ct_tactics.smx"
$tDirectorPlugin = Join-Path $pluginDir "002_bot_t_tactics.smx"
$compatSource = Join-Path $PSScriptRoot "include\bot_stuff_compile_compat.inc"
$navmeshSource = Join-Path $PSScriptRoot "include\navmesh.inc"
$rosterSource = Join-Path $PSScriptRoot "include\bot_team_rosters.inc"
$purchaseSource = Join-Path $PSScriptRoot "include\bot_purchase_policy.inc"
$equipmentSource = Join-Path $PSScriptRoot "include\bot_equipment_policy.inc"
$anglesSource = Join-Path $PSScriptRoot "include\bot_tactical_angles.inc"

foreach ($required in @($compiler, $botSource, $botPlugin, $directorSource, $tDirectorSource, $compatSource, $navmeshSource, $rosterSource, $purchaseSource, $equipmentSource, $anglesSource)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required CT tactics installation file was not found: '$required'"
    }
}

New-Item -ItemType Directory -Path $dataDir, $buildDir, $includeDir -Force | Out-Null
$backupSource = Join-Path $dataDir "bot_stuff.original.sp"
$backupPlugin = Join-Path $dataDir "bot_stuff.original.smx"
$backupProfileConfig = Join-Path $dataDir "bot_stuff.original.cfg"
$text = Get-Content -LiteralPath $botSource -Raw
$alreadyPatched = $text.Contains("BEGIN CT_TACTICS_BRIDGE")
if ($alreadyPatched) {
    if (-not (Test-Path -LiteralPath $backupSource) -or -not (Test-Path -LiteralPath $backupPlugin)) {
        throw "BetterBots is already bridged, but its rollback backup is missing. Refusing to replace the recovery point."
    }
}
else {
    # An overlay/update may deliver a newer pristine BetterBots build. In that
    # case the matching source and SMX become the new rollback point.
    Copy-Item -LiteralPath $botSource -Destination $backupSource -Force
    Copy-Item -LiteralPath $botPlugin -Destination $backupPlugin -Force
    if (Test-Path -LiteralPath $profileConfig) {
        Copy-Item -LiteralPath $profileConfig -Destination $backupProfileConfig -Force
    }
}

# Older bridge revisions did not preserve the profile cfg. Create a migration
# recovery point by reversing only this project's exact historical defaults;
# independently tuned values remain unchanged.
if (-not (Test-Path -LiteralPath $backupProfileConfig) -and (Test-Path -LiteralPath $profileConfig)) {
    $rollbackProfileText = Get-Content -LiteralPath $profileConfig -Raw
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"look_angle_max_accel"\s*)"6750\.0"', '${1}"100000.0"'
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"reaction_time"\s*)"0\.20"', '${1}"0.0"'
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"look_angle_max_accel_min"\s*)"4500\.0"', '${1}"4000.0"'
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"look_angle_max_accel_max"\s*)"6500\.0"', '${1}"7000.0"'
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"reaction_time_min"\s*)"0\.22"', '${1}"0.165"'
    $rollbackProfileText = $rollbackProfileText -replace '(?m)^(\s*"reaction_time_max"\s*)"0\.30"', '${1}"0.325"'
    [System.IO.File]::WriteAllText($backupProfileConfig, $rollbackProfileText, [System.Text.UTF8Encoding]::new($false))
}

function Replace-Once {
    param([string]$Text, [string]$Old, [string]$New, [string]$Label)
    $first = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) {
        throw "Could not patch BetterBots ($Label): expected source text was not found."
    }
    if ($Text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Could not patch BetterBots ($Label): expected source text was ambiguous."
    }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Replace-RegexOnce {
    param([string]$Text, [string]$Pattern, [string]$New, [string]$Label)
    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Could not patch BetterBots ($Label): expected exactly one source match, found $($matches.Count)."
    }
    return [regex]::Replace($Text, $Pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $New }, 1)
}

$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

# Upgrade the first reversible CT/T bridge in place. Older installations have
# movement orders but no contact-report native; preserve their original rollback
# point and add only the missing declarations/state/call site.
if ($alreadyPatched -and -not $text.Contains('BotCTTactics_ReportContact')) {
    $text = Replace-Once $text `
        'native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);' `
        ('native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);' + $newline + 'native bool BotCTTactics_ReportContact(int spotter, int enemy);') `
        'contact native declaration'
    $text = Replace-Once $text `
        'float g_fNadeLineupCooldown[MAXPLAYERS+1]; float g_fTacticalMoveTimestamp[MAXPLAYERS+1];' `
        'float g_fNadeLineupCooldown[MAXPLAYERS+1]; float g_fTacticalMoveTimestamp[MAXPLAYERS+1]; float g_fTacticalContactTimestamp[MAXPLAYERS+1];' `
        'contact throttle'
    $text = Replace-Once $text `
        "`tMarkNativeAsOptional(`"BotCTTactics_GetOrder`");" `
        ("`tMarkNativeAsOptional(`"BotCTTactics_GetOrder`");" + $newline + "`tMarkNativeAsOptional(`"BotCTTactics_ReportContact`");") `
        'optional contact native registration'

    $oldOrderTail = @(
        "`telse if (GetClientTeam(iClient) == CS_TEAM_T && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t`tbHasTacticalOrder = BotTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        '',
        "`tif (bHasTacticalOrder)"
    ) -join $newline
    $newOrderTail = @(
        "`telse if (GetClientTeam(iClient) == CS_TEAM_T && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t`tbHasTacticalOrder = BotTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        '',
        "`tbool bEnemyVisibleForReport = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`tif (GetClientTeam(iClient) == CS_TEAM_CT && bEnemyVisibleForReport && fNow >= g_fTacticalContactTimestamp[iClient]",
        "`t`t&& GetFeatureStatus(FeatureType_Native, `"BotCTTactics_ReportContact`") == FeatureStatus_Available)",
        "`t{",
        "`t`tint iVisibleEnemy = BotGetEnemy(iClient);",
        "`t`tif (IsValidClient(iVisibleEnemy) && IsPlayerAlive(iVisibleEnemy) && GetClientTeam(iVisibleEnemy) == CS_TEAM_T)",
        "`t`t{",
        "`t`t`tBotCTTactics_ReportContact(iClient, iVisibleEnemy);",
        "`t`t`tg_fTacticalContactTimestamp[iClient] = fNow + 1.0;",
        "`t`t}",
        "`t}",
        '',
        "`tif (bHasTacticalOrder)"
    ) -join $newline
    $text = Replace-Once $text $oldOrderTail $newOrderTail 'contact reporting bridge'
}

# Upgrade an installed movement bridge with defensive hold aim support.
if ($alreadyPatched -and -not $text.Contains('BotCTTactics_GetAim')) {
    $text = Replace-Once $text `
        'native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);' `
        ('native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);' + $newline + 'native bool BotCTTactics_GetAim(int client, float lookAt[3]);') `
        'aim native declaration'
    $text = Replace-Once $text `
        "`tMarkNativeAsOptional(`"BotCTTactics_GetOrder`");" `
        ("`tMarkNativeAsOptional(`"BotCTTactics_GetOrder`");" + $newline + "`tMarkNativeAsOptional(`"BotCTTactics_GetAim`");") `
        'optional aim native registration'

    $oldCTOrder = @(
        "`tbool bHasTacticalOrder = false;",
        "`tfloat fTacticalGoal[3];",
        "`tint iTacticalRoute = view_as<int>(SAFEST_ROUTE);",
        "`tif (GetClientTeam(iClient) == CS_TEAM_CT && GetFeatureStatus(FeatureType_Native, `"BotCTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t`tbHasTacticalOrder = BotCTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);"
    ) -join $newline
    $newCTOrder = @(
        "`tbool bHasTacticalOrder = false;",
        "`tbool bHasTacticalAim = false;",
        "`tfloat fTacticalGoal[3], fTacticalLook[3];",
        "`tint iTacticalRoute = view_as<int>(SAFEST_ROUTE);",
        "`tif (GetClientTeam(iClient) == CS_TEAM_CT && GetFeatureStatus(FeatureType_Native, `"BotCTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t{",
        "`t`tbHasTacticalOrder = BotCTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotCTTactics_GetAim`") == FeatureStatus_Available)",
        "`t`t`tbHasTacticalAim = BotCTTactics_GetAim(iClient, fTacticalLook);",
        "`t}"
    ) -join $newline
    $text = Replace-Once $text $oldCTOrder $newCTOrder 'defensive aim acquisition'

    $oldMove = @(
        "`t`tif (!bEnemyVisible && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t}"
    ) -join $newline
    $newMove = @(
        "`t`tif (!bEnemyVisible && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tif (GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal) > 96.0)",
        "`t`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`telse if (bHasTacticalAim)",
        "`t`t`t`tBotSetLookAt(iClient, `"CT tactical hold`", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t}"
    ) -join $newline
    $text = Replace-Once $text $oldMove $newMove 'defensive hold aim'
}

# Older bridge revisions refreshed BotMoveTo every 0.5 seconds.  In CS:GO
# Legacy that can restart the same path continuously when a bot meets a tight
# nav corner, producing the familiar stationary spin.  Keep the order active,
# but submit it to BetterBots only when it is new or materially changed.
if ($alreadyPatched -and -not $text.Contains('g_bTacticalMoveIssued')) {
    $stateMatch = [regex]::Match($text, '(?m)^float g_fNadeLineupCooldown\[MAXPLAYERS\+1\];.*g_fTacticalMoveTimestamp\[MAXPLAYERS\+1\];.*$')
    if (-not $stateMatch.Success) {
        throw 'Could not patch BetterBots (stable tactical movement state): state declaration was not found.'
    }
    $stableState = @(
        $stateMatch.Value,
        'bool g_bTacticalMoveIssued[MAXPLAYERS+1];',
        'float g_fTacticalMoveGoal[MAXPLAYERS+1][3];',
        'int g_iTacticalMoveRoute[MAXPLAYERS+1];',
        'float g_fTacticalMoveLastDistance[MAXPLAYERS+1];',
        'float g_fTacticalProgressTimestamp[MAXPLAYERS+1];'
    ) -join $newline
    $text = Replace-Once $text $stateMatch.Value $stableState 'stable tactical movement state'

    $oldRepeatedMove = @(
        "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`t`tif (!bEnemyVisible && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tif (GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal) > 96.0)",
        "`t`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`telse if (bHasTacticalAim)",
        "`t`t`t`tBotSetLookAt(iClient, `"CT tactical hold`", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t}",
        "`t}",
        "`t// END CT_TACTICS_BRIDGE"
    ) -join $newline
    $newStableMove = @(
        "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`t`tfloat fDistanceToTacticalGoal = GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal);",
        "`t`tif (!bEnemyVisible && fDistanceToTacticalGoal > 96.0)",
        "`t`t{",
        "`t`t`tbool bTacticalGoalChanged = !g_bTacticalMoveIssued[iClient]",
        "`t`t`t`t|| GetVectorDistance(g_fTacticalMoveGoal[iClient], fTacticalGoal) > 48.0",
        "`t`t`t`t|| g_iTacticalMoveRoute[iClient] != iTacticalRoute;",
        "`t`t`tbool bTacticalNeedsRefresh = g_bTacticalMoveIssued[iClient] && !bTacticalGoalChanged",
        "`t`t`t`t&& fNow >= g_fTacticalProgressTimestamp[iClient]",
        "`t`t`t`t&& fDistanceToTacticalGoal > g_fTacticalMoveLastDistance[iClient] - 64.0;",
        "`t`t`tif (bTacticalGoalChanged || bTacticalNeedsRefresh)",
        "`t`t`t{",
        "`t`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`t}",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t`telse if (fNow >= g_fTacticalProgressTimestamp[iClient])",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t}",
        "`t`telse if (!bEnemyVisible && bHasTacticalAim && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tBotSetLookAt(iClient, `"CT tactical hold`", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t`t}",
        "`t}",
        "`telse",
        "`t{",
        "`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t}",
        "`t// END CT_TACTICS_BRIDGE"
    ) -join $newline
    $text = Replace-Once $text $oldRepeatedMove $newStableMove 'stable tactical movement submission'
}

# A single movement submission can be overwritten by the native bot task on
# the next AI update. Reassert only when a 1.5-second checkpoint shows less
# than 64 units of progress. This is slow enough not to recreate the old
# 0.5-second path-reset spin, but keeps A/B assignments from drifting across
# the map under the native AI.
if ($alreadyPatched -and $text.Contains('g_bTacticalMoveIssued') -and -not $text.Contains('g_fTacticalProgressTimestamp')) {
    $text = Replace-Once $text `
        'int g_iTacticalMoveRoute[MAXPLAYERS+1];' `
        (@(
            'int g_iTacticalMoveRoute[MAXPLAYERS+1];',
            'float g_fTacticalMoveLastDistance[MAXPLAYERS+1];',
            'float g_fTacticalProgressTimestamp[MAXPLAYERS+1];'
        ) -join $newline) `
        'tactical progress checkpoint state'

    $progressMove = @(
        "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`t`tfloat fDistanceToTacticalGoal = GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal);",
        "`t`tif (!bEnemyVisible && fDistanceToTacticalGoal > 96.0)",
        "`t`t{",
        "`t`t`tbool bTacticalGoalChanged = !g_bTacticalMoveIssued[iClient]",
        "`t`t`t`t|| GetVectorDistance(g_fTacticalMoveGoal[iClient], fTacticalGoal) > 48.0",
        "`t`t`t`t|| g_iTacticalMoveRoute[iClient] != iTacticalRoute;",
        "`t`t`tbool bTacticalNeedsRefresh = g_bTacticalMoveIssued[iClient] && !bTacticalGoalChanged",
        "`t`t`t`t&& fNow >= g_fTacticalProgressTimestamp[iClient]",
        "`t`t`t`t&& fDistanceToTacticalGoal > g_fTacticalMoveLastDistance[iClient] - 64.0;",
        "`t`t`tif (bTacticalGoalChanged || bTacticalNeedsRefresh)",
        "`t`t`t{",
        "`t`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`t}",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t`telse if (fNow >= g_fTacticalProgressTimestamp[iClient])",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t}",
        "`t`telse if (!bEnemyVisible && bHasTacticalAim && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tBotSetLookAt(iClient, `"CT tactical hold`", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t`t}",
        "`t}",
        "`telse",
        "`t{",
        "`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t}",
        "`t// END CT_TACTICS_BRIDGE"
    ) -join $newline
    $text = Replace-RegexOnce $text `
        '(?ms)^\t\tbool bEnemyVisible = !!GetEntData\(iClient, g_iEnemyVisibleOffset\);.*?^\t// END CT_TACTICS_BRIDGE' `
        $progressMove `
        'tactical progress checkpoint refresh'
}

# The original pack omits these build-only headers. This compact compatibility
# include preserves the same natives/stocks; navmesh.inc comes from the parser
# already installed by the MOD pack.
$text = $text -replace '(?m)^#include <eItems>\r?\n', ('#include <bot_stuff_compile_compat>' + $newline)
$text = $text -replace '(?m)^#include <smlib>\r?\n', ''
$text = $text -replace '(?m)^#include <PTaH>\r?\n', ''

if (-not $text.Contains("BEGIN CT_TACTICS_BRIDGE")) {
    $nativeBridge = @(
        '#include <bot_steamids>',
        '',
        '// BEGIN CT_TACTICS_BRIDGE',
        '// Optional: removing/disabling the director leaves the original BetterBots behavior intact.',
        'native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);',
        'native bool BotCTTactics_GetAim(int client, float lookAt[3]);',
        'native bool BotCTTactics_ReportContact(int spotter, int enemy);',
        'native bool BotTTactics_GetOrder(int client, float goal[3], int &routeType);',
        '// END CT_TACTICS_BRIDGE'
    ) -join $newline
    $text = Replace-Once $text '#include <bot_steamids>' $nativeBridge 'native declaration'

    $text = Replace-Once $text 'float g_fNadeLineupCooldown[MAXPLAYERS+1];' @(
        'float g_fNadeLineupCooldown[MAXPLAYERS+1];',
        'float g_fTacticalMoveTimestamp[MAXPLAYERS+1];',
        'float g_fTacticalContactTimestamp[MAXPLAYERS+1];',
        'bool g_bTacticalMoveIssued[MAXPLAYERS+1];',
        'float g_fTacticalMoveGoal[MAXPLAYERS+1][3];',
        'int g_iTacticalMoveRoute[MAXPLAYERS+1];',
        'float g_fTacticalMoveLastDistance[MAXPLAYERS+1];',
        'float g_fTacticalProgressTimestamp[MAXPLAYERS+1];'
    ) -join $newline 'movement throttle'

    $loadBridge = @(
        '// BEGIN CT_TACTICS_BRIDGE',
        'public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax)',
        '{',
        "`tMarkNativeAsOptional(`"BotCTTactics_GetOrder`");",
        "`tMarkNativeAsOptional(`"BotCTTactics_GetAim`");",
        "`tMarkNativeAsOptional(`"BotCTTactics_ReportContact`");",
        "`tMarkNativeAsOptional(`"BotTTactics_GetOrder`");",
        "`treturn APLRes_Success;",
        '}',
        '// END CT_TACTICS_BRIDGE',
        '',
        'public void OnPluginStart()'
    ) -join $newline
    $text = Replace-Once $text 'public void OnPluginStart()' $loadBridge 'optional native registration'

    $runAnchor = @(
        "`tfloat fNow = GetGameTime();",
        "`tint iDefIndex = GetEntProp(g_iActiveWeapon[iClient], Prop_Send, `"m_iItemDefinitionIndex`");"
    ) -join $newline
    $runBridge = @(
        $runAnchor,
        '',
        "`t// BEGIN CT_TACTICS_BRIDGE",
        "`tbool bHasTacticalOrder = false;",
        "`tbool bHasTacticalAim = false;",
        "`tfloat fTacticalGoal[3], fTacticalLook[3];",
        "`tint iTacticalRoute = view_as<int>(SAFEST_ROUTE);",
        "`tif (GetClientTeam(iClient) == CS_TEAM_CT && GetFeatureStatus(FeatureType_Native, `"BotCTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t{",
        "`t`tbHasTacticalOrder = BotCTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotCTTactics_GetAim`") == FeatureStatus_Available)",
        "`t`t`tbHasTacticalAim = BotCTTactics_GetAim(iClient, fTacticalLook);",
        "`t}",
        "`telse if (GetClientTeam(iClient) == CS_TEAM_T && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t`tbHasTacticalOrder = BotTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        '',
        "`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`tif (GetClientTeam(iClient) == CS_TEAM_CT && bEnemyVisible && fNow >= g_fTacticalContactTimestamp[iClient]",
        "`t`t&& GetFeatureStatus(FeatureType_Native, `"BotCTTactics_ReportContact`") == FeatureStatus_Available)",
        "`t{",
        "`t`tint iVisibleEnemy = BotGetEnemy(iClient);",
        "`t`tif (IsValidClient(iVisibleEnemy) && IsPlayerAlive(iVisibleEnemy) && GetClientTeam(iVisibleEnemy) == CS_TEAM_T)",
        "`t`t{",
        "`t`t`tBotCTTactics_ReportContact(iClient, iVisibleEnemy);",
        "`t`t`tg_fTacticalContactTimestamp[iClient] = fNow + 1.0;",
        "`t`t}",
        "`t}",
        '',
        "`tif (bHasTacticalOrder)",
        "`t{",
        "`t`tif (g_iDoingSmokeNum[iClient] != -1)",
        "`t`t`tSetNadeTimestamp(g_iDoingSmokeNum[iClient], fNow);",
        "`t`tg_iDoingSmokeNum[iClient] = -1;",
        "`t`tif (BotMimic_IsPlayerMimicing(iClient))",
        "`t`t`tBotMimic_StopPlayerMimic(iClient);",
        '',
        "`t`tfloat fDistanceToTacticalGoal = GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal);",
        "`t`tif (!bEnemyVisible && fDistanceToTacticalGoal > 96.0)",
        "`t`t{",
        "`t`t`tbool bTacticalGoalChanged = !g_bTacticalMoveIssued[iClient]",
        "`t`t`t`t|| GetVectorDistance(g_fTacticalMoveGoal[iClient], fTacticalGoal) > 48.0",
        "`t`t`t`t|| g_iTacticalMoveRoute[iClient] != iTacticalRoute;",
        "`t`t`tbool bTacticalNeedsRefresh = g_bTacticalMoveIssued[iClient] && !bTacticalGoalChanged",
        "`t`t`t`t&& fNow >= g_fTacticalProgressTimestamp[iClient]",
        "`t`t`t`t&& fDistanceToTacticalGoal > g_fTacticalMoveLastDistance[iClient] - 64.0;",
        "`t`t`tif (bTacticalGoalChanged || bTacticalNeedsRefresh)",
        "`t`t`t{",
        "`t`t`t`tBotMoveTo(iClient, fTacticalGoal, view_as<RouteType>(iTacticalRoute));",
        "`t`t`t}",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t`telse if (fNow >= g_fTacticalProgressTimestamp[iClient])",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveLastDistance[iClient] = fDistanceToTacticalGoal;",
        "`t`t`t`tg_fTacticalProgressTimestamp[iClient] = fNow + 1.5;",
        "`t`t`t}",
        "`t`t}",
        "`t`telse if (!bEnemyVisible && bHasTacticalAim && fNow >= g_fTacticalMoveTimestamp[iClient])",
        "`t`t{",
        "`t`t`tBotSetLookAt(iClient, `"CT tactical hold`", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);",
        "`t`t`tg_fTacticalMoveTimestamp[iClient] = fNow + 0.5;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t`t}",
        "`t}",
        "`telse",
        "`t{",
        "`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;",
        "`t}",
        "`t// END CT_TACTICS_BRIDGE"
    ) -join $newline
    $text = Replace-Once $text $runAnchor $runBridge 'movement bridge'

    $text = Replace-Once $text `
        'if (g_iDoingSmokeNum[iClient] == -1 && fNow >= g_fNadeLineupCooldown[iClient])' `
        'if (!bHasTacticalOrder && g_iDoingSmokeNum[iClient] == -1 && fNow >= g_fNadeLineupCooldown[iClient])' `
        'grenade selection guard'
    $text = Replace-Once $text `
        'if (g_iDoingSmokeNum[iClient] != -1 && !BotMimic_IsPlayerMimicing(iClient))' `
        'if (!bHasTacticalOrder && g_iDoingSmokeNum[iClient] != -1 && !BotMimic_IsPlayerMimicing(iClient))' `
        'grenade movement guard'
    $pickupCondition = 'if (g_bIsProBot[iClient] && !g_bBombPlanted && GetTask(iClient) != COLLECT_HOSTAGES && GetTask(iClient) != RESCUE_HOSTAGES && GetTask(iClient) != GUARD_LOOSE_BOMB && GetTask(iClient) != PLANT_BOMB && GetTask(iClient) != ESCAPE_FROM_FLAMES)'
    $text = Replace-Once $text $pickupCondition ('if (!bHasTacticalOrder && ' + $pickupCondition.Substring(4)) 'weapon pickup guard'
}

# The first tactical bridge deliberately yielded all grenade lineups to its
# movement order. That suppressed BetterBots' scripted opening utility for T,
# including Mirage window/VIP smoke. Check for a nearby usable lineup before
# accepting the director order and let the existing replay code execute.
if ($text.Contains('BEGIN CT_TACTICS_BRIDGE') -and -not $text.Contains('BEGIN TACTICAL_NADE_PRIORITY')) {
    $priority = @(
        "`t// BEGIN TACTICAL_NADE_PRIORITY",
        "`t// TACTICAL_NADE_PRIORITY_V2_PREPLANT_ONLY",
        "`tif (GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted)",
        "`t{",
        "`t`tbool bLineupReplay = BotMimic_IsPlayerMimicing(iClient);",
        "`t`tif (!bLineupReplay && g_iDoingSmokeNum[iClient] != -1)",
        "`t`t{",
        "`t`t`tif (g_iDoingSmokeNum[iClient] < 0 || g_iDoingSmokeNum[iClient] >= g_aNades.Length)",
        "`t`t`t`tg_iDoingSmokeNum[iClient] = -1;",
        "`t`t`telse",
        "`t`t`t{",
        "`t`t`t`tNadeLineup sSelectedLineup;",
        "`t`t`t`tg_aNades.GetArray(g_iDoingSmokeNum[iClient], sSelectedLineup);",
        "`t`t`t`tif (!IsValidEntity(eItems_FindWeaponByDefIndex(iClient, sSelectedLineup.iDefIndex)))",
        "`t`t`t`t`tg_iDoingSmokeNum[iClient] = -1;",
        "`t`t`t}",
        "`t`t}",
        "`t`tif (!bLineupReplay && g_iDoingSmokeNum[iClient] == -1 && fNow >= g_fNadeLineupCooldown[iClient])",
        "`t`t{",
        "`t`t`tg_iDoingSmokeNum[iClient] = GetNearestGrenade(iClient);",
        "`t`t`tg_fNadeLineupCooldown[iClient] = fNow + 1.0;",
        "`t`t}",
        "`t`tif (g_iDoingSmokeNum[iClient] != -1 || bLineupReplay)",
        "`t`t`tbHasTacticalOrder = false;",
        "`t}",
        "`t// END TACTICAL_NADE_PRIORITY",
        ''
    ) -join $newline
    $text = Replace-Once $text "`tif (bHasTacticalOrder)" ($priority + "`tif (bHasTacticalOrder)") 'opening grenade priority'
}

# Recorded opening lineups are route-level actions: a bot may walk far away
# before replaying one. Once C4 is planted they must never override post-plant
# guard orders. Dynamic combat/denial throws remain handled by BetterBots.
if ($text.Contains('BEGIN TACTICAL_NADE_PRIORITY') -and -not $text.Contains('TACTICAL_NADE_PRIORITY_V2_PREPLANT_ONLY')) {
    $oldPriorityPattern = '(?ms)^\t// BEGIN TACTICAL_NADE_PRIORITY\r?\n.*?^\t// END TACTICAL_NADE_PRIORITY'
    $priorityMatch = [regex]::Match($text, $oldPriorityPattern)
    if (-not $priorityMatch.Success) {
        throw 'Could not patch BetterBots (post-plant lineup priority): priority block was not found.'
    }
    $newPriority = $priorityMatch.Value.Replace(
        "`t// BEGIN TACTICAL_NADE_PRIORITY" + $newline + "`tif (GetClientTeam(iClient) == CS_TEAM_T)",
        "`t// BEGIN TACTICAL_NADE_PRIORITY" + $newline + "`t// TACTICAL_NADE_PRIORITY_V2_PREPLANT_ONLY" + $newline + "`tif (GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted)"
    )
    if ($newPriority -eq $priorityMatch.Value) {
        throw 'Could not patch BetterBots (post-plant lineup priority): legacy T condition was not found.'
    }
    $text = Replace-Once $text $priorityMatch.Value $newPriority 'post-plant lineup priority'
}

if ($text.Contains('BEGIN CT_TACTICS_BRIDGE') -and -not $text.Contains('BEGIN T_POSTPLANT_LINEUP_CANCEL')) {
    $plantCancel = @(
        "`tg_bBombPlanted = true;",
        '',
        "`t// BEGIN T_POSTPLANT_LINEUP_CANCEL",
        "`t// A planted bomb invalidates every recorded attack-lineup trip.",
        "`t// Local combat and bomb-denial throws are intentionally untouched.",
        "`tfor (int iClient = 1; iClient <= MaxClients; iClient++)",
        "`t{",
        "`t`tif (!IsValidClient(iClient) || !IsFakeClient(iClient) || GetClientTeam(iClient) != CS_TEAM_T)",
        "`t`t`tcontinue;",
        "`t`tif (BotMimic_IsPlayerMimicing(iClient))",
        "`t`t`tBotMimic_StopPlayerMimic(iClient);",
        "`t`tg_iDoingSmokeNum[iClient] = -1;",
        "`t}",
        "`t// END T_POSTPLANT_LINEUP_CANCEL"
    ) -join $newline
    $text = Replace-Once $text "`tg_bBombPlanted = true;" $plantCancel 'post-plant lineup cancellation'
}

# The planting animation is already a tactical phase: stop recorded opening
# lineups at its start, then let the T director position the non-planters.
if (-not $text.Contains('BEGIN T_PLANT_COVER_BRIDGE')) {
    $text = Replace-Once $text 'g_bBombPlanted, g_bHalftimeSwitch' 'g_bBombPlanted, g_bTPlanting, g_bHalftimeSwitch' 'plant-cover state'
    $text = Replace-Once $text 'HookEventEx("bomb_beginplant", OnBombBeginPlant);' `
        ('HookEventEx("bomb_beginplant", OnBombBeginPlant);' + $newline + '    HookEventEx("bomb_abortplant", OnBombAbortPlant);') `
        'plant abort hook'
    $text = Replace-Once $text "`tg_bBombPlanted = false;`n`tg_fRoundStart = GetGameTime();".Replace("`n", $newline) `
        "`tg_bBombPlanted = false;`n`tg_bTPlanting = false;`n`tg_fRoundStart = GetGameTime();".Replace("`n", $newline) `
        'plant state round reset'
    $text = Replace-Once $text "`tg_bBombPlanted = true;" `
        ("`tg_bBombPlanted = true;" + $newline + "`tg_bTPlanting = false;") `
        'plant state completion'
    $text = Replace-Once $text 'public void OnBombBeginPlant(Event eEvent, const char[] szName, bool bDontBroadcast)' `
        (@(
            'public void OnBombAbortPlant(Event eEvent, const char[] szName, bool bDontBroadcast)',
            '{',
            "`tg_bTPlanting = false;",
            '}',
            '',
            'public void OnBombBeginPlant(Event eEvent, const char[] szName, bool bDontBroadcast)'
        ) -join $newline) 'plant abort handler'
    $text = Replace-Once $text "`tfloat fPlanterPos[3];" `
        (@(
            "`t// BEGIN T_PLANT_COVER_BRIDGE",
            "`tg_bTPlanting = GetClientTeam(iPlanter) == CS_TEAM_T;",
            "`tif (g_bTPlanting)",
            "`t{",
            "`t`tfor (int iClient = 1; iClient <= MaxClients; iClient++)",
            "`t`t{",
            "`t`t`tif (!IsValidClient(iClient) || !IsFakeClient(iClient) || GetClientTeam(iClient) != CS_TEAM_T)",
            "`t`t`t`tcontinue;",
            "`t`t`tif (BotMimic_IsPlayerMimicing(iClient)) BotMimic_StopPlayerMimic(iClient);",
            "`t`t`tg_iDoingSmokeNum[iClient] = -1;",
            "`t`t}",
            "`t}",
            "`t// END T_PLANT_COVER_BRIDGE",
            "`tfloat fPlanterPos[3];"
        ) -join $newline) 'plant cover opening lineup cancellation'
}

$legacyGenericLineupSelection = 'if (!bHasTacticalOrder && g_iDoingSmokeNum[iClient] == -1 && fNow >= g_fNadeLineupCooldown[iClient])'
$guardedGenericLineupSelection = 'if (!bHasTacticalOrder && !(g_bBombPlanted && GetClientTeam(iClient) == CS_TEAM_T) && g_iDoingSmokeNum[iClient] == -1 && fNow >= g_fNadeLineupCooldown[iClient])'
if ($text.Contains($legacyGenericLineupSelection)) {
    $text = Replace-Once $text $legacyGenericLineupSelection $guardedGenericLineupSelection 'post-plant generic lineup selection'
}

if ($text.Contains('g_bTacticalMoveIssued') -and -not $text.Contains('BEGIN TACTICAL_MOVEMENT_RESET')) {
    $disconnectReset = @(
        "`tg_fNadeLineupCooldown[iClient] = 0.0;",
        "`t// BEGIN TACTICAL_MOVEMENT_RESET",
        "`tg_bTacticalMoveIssued[iClient] = false;",
        "`tg_fTacticalMoveTimestamp[iClient] = 0.0;",
        "`tg_fTacticalContactTimestamp[iClient] = 0.0;",
        "`t// END TACTICAL_MOVEMENT_RESET"
    ) -join $newline
    $text = Replace-Once $text `
        "`tg_fNadeLineupCooldown[iClient] = 0.0;" `
        $disconnectReset `
        'tactical movement disconnect reset'
}

# A native idle task can walk a CT back and forth across the old 96-unit
# arrival cutoff. Treat the initial guard point as a small hold area, re-route
# only after a material departure, and leave combat/retake movement alone.
if ($text.Contains('BEGIN CT_TACTICS_BRIDGE') -and -not $text.Contains('BEGIN CT_INITIAL_HOLD')) {
    $text = Replace-Once $text `
        'bool g_bTacticalMoveIssued[MAXPLAYERS+1];' `
        ('bool g_bTacticalMoveIssued[MAXPLAYERS+1];' + $newline + 'bool g_bTacticalHoldReached[MAXPLAYERS+1];') `
        'CT initial hold state'

    $text = Replace-Once $text `
        ("`tif (bHasTacticalOrder)" + $newline + "`t{") `
        ("`tbool bHoldInitialCTPosition = false;" + $newline + "`tif (bHasTacticalOrder)" + $newline + "`t{") `
        'CT initial hold local state'

    $oldArrival = @(
        "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`t`tfloat fDistanceToTacticalGoal = GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal);",
        "`t`tif (!bEnemyVisible && fDistanceToTacticalGoal > 96.0)",
        "`t`t{",
        "`t`t`tbool bTacticalGoalChanged = !g_bTacticalMoveIssued[iClient]",
        "`t`t`t`t|| GetVectorDistance(g_fTacticalMoveGoal[iClient], fTacticalGoal) > 48.0",
        "`t`t`t`t|| g_iTacticalMoveRoute[iClient] != iTacticalRoute;"
    ) -join $newline
    $newArrival = @(
        "`t`t// BEGIN CT_INITIAL_HOLD",
        "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);",
        "`t`tfloat fDistanceToTacticalGoal = GetVectorDistance(g_fBotOrigin[iClient], fTacticalGoal);",
        "`t`tbool bTacticalGoalChanged = !g_bTacticalMoveIssued[iClient]",
        "`t`t`t|| GetVectorDistance(g_fTacticalMoveGoal[iClient], fTacticalGoal) > 48.0",
        "`t`t`t|| g_iTacticalMoveRoute[iClient] != iTacticalRoute;",
        "`t`tif (bTacticalGoalChanged)",
        "`t`t`tg_bTacticalHoldReached[iClient] = false;",
        "`t`tif (g_bTacticalHoldReached[iClient] && fDistanceToTacticalGoal > 256.0)",
        "`t`t{",
        "`t`t`tg_bTacticalHoldReached[iClient] = false;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tbTacticalGoalChanged = true;",
        "`t`t}",
        "`t`tif (GetClientTeam(iClient) == CS_TEAM_CT && bHasTacticalAim && !g_bBombPlanted",
        "`t`t`t&& !bEnemyVisible && fDistanceToTacticalGoal <= 128.0)",
        "`t`t{",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t}",
        "`t`t`tg_bTacticalHoldReached[iClient] = true;",
        "`t`t}",
        "`t`tbHoldInitialCTPosition = GetClientTeam(iClient) == CS_TEAM_CT && bHasTacticalAim",
        "`t`t`t&& !g_bBombPlanted && !bEnemyVisible && g_bTacticalHoldReached[iClient]",
        "`t`t`t&& fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END CT_INITIAL_HOLD",
        "`t`tif (!bEnemyVisible && !bHoldInitialCTPosition && fDistanceToTacticalGoal > 96.0)",
        "`t`t{"
    ) -join $newline
    # The first install declares bEnemyVisible before the bridge order block;
    # upgraded installations declare it inside. Preserve either layout.
    $innerEnemyLine = "`t`tbool bEnemyVisible = !!GetEntData(iClient, g_iEnemyVisibleOffset);" + $newline
    if (-not $text.Contains($innerEnemyLine)) {
        $oldArrival = $oldArrival.Replace($innerEnemyLine, '')
        $newArrival = $newArrival.Replace($innerEnemyLine, '')
    }
    $text = Replace-Once $text $oldArrival $newArrival 'CT hold arrival hysteresis'

    $text = Replace-Once $text `
        ("`t`t`tg_bTacticalMoveIssued[iClient] = false;" + $newline + "`t`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;" + $newline + "`t`t}" + $newline + "`t}" + $newline + "`telse") `
        ("`t`t}" + $newline + "`t}" + $newline + "`telse") `
        'preserve CT arrival state while aiming'

    $text = Replace-Once $text `
        ("`t`tg_bTacticalMoveIssued[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;" + $newline + "`t}" + $newline + "`t// END CT_TACTICS_BRIDGE") `
        ("`t`tg_bTacticalMoveIssued[iClient] = false;" + $newline + "`t`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;" + $newline + "`t}" + $newline + "`t// END CT_TACTICS_BRIDGE") `
        'clear CT hold with tactical order'

    $quietHold = @(
        "`t// BEGIN CT_INITIAL_HOLD_INPUT",
        "`tif (bHoldInitialCTPosition && !GetEntData(iClient, g_iEnemyVisibleOffset)",
        "`t`t&& GetEntData(iClient, g_iBotNearbyEnemiesOffset) == 0",
        "`t`t&& eItems_GetWeaponSlotByDefIndex(iDefIndex) != CS_SLOT_GRENADE",
        "`t`t&& !g_bThrowGrenade[iClient] && !BotMimic_IsPlayerMimicing(iClient)",
        "`t`t&& GetTask(iClient) != ESCAPE_FROM_FLAMES && GetTask(iClient) != ESCAPE_FROM_BOMB)",
        "`t{",
        "`t`tfVel[0] = 0.0;",
        "`t`tfVel[1] = 0.0;",
        "`t`tiButtons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);",
        "`t}",
        "`t// END CT_INITIAL_HOLD_INPUT",
        '',
        "`treturn Plugin_Changed;",
        '}',
        '',
        'void ProcessWeaponPickup'
    ) -join $newline
    $text = Replace-Once $text `
        ("`treturn Plugin_Changed;" + $newline + '}' + $newline + $newline + 'void ProcessWeaponPickup') `
        $quietHold `
        'CT quiet defensive hold input'

    $text = Replace-Once $text `
        ("`tg_bTacticalMoveIssued[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        ("`tg_bTacticalMoveIssued[iClient] = false;" + $newline + "`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        'CT hold disconnect reset'

    $spawnPrefix = [regex]::Match($text, '(?ms)^public void OnPlayerSpawn\(.*?^    if \(!IsFakeClient\(iClient\)\)\r?\n        return;\r?\n').Value
    if (-not $spawnPrefix) {
        throw 'Could not patch BetterBots (CT hold spawn reset): player-spawn prefix was not found.'
    }
    $text = Replace-Once $text $spawnPrefix `
        ($spawnPrefix + '    g_bTacticalMoveIssued[iClient] = false;' + $newline + '    g_bTacticalHoldReached[iClient] = false;' + $newline) `
        'CT hold spawn reset'
}

# T attack staging needs the same arrival hysteresis as CT setup, but only
# while the T director is explicitly in attack-stage. Commit, dropped-C4 and
# post-plant orders must retain normal movement semantics.
if ($text.Contains('BEGIN CT_INITIAL_HOLD') -and -not $text.Contains('BEGIN T_ATTACK_STAGE_HOLD')) {
    $text = Replace-Once $text `
        'native bool BotTTactics_GetOrder(int client, float goal[3], int &routeType);' `
        ('native bool BotTTactics_GetOrder(int client, float goal[3], int &routeType);' + $newline + 'native bool BotTTactics_ShouldHoldStage(int client);') `
        'T stage hold native declaration'
    $text = Replace-Once $text `
        "`tMarkNativeAsOptional(`"BotTTactics_GetOrder`");" `
        ("`tMarkNativeAsOptional(`"BotTTactics_GetOrder`");" + $newline + "`tMarkNativeAsOptional(`"BotTTactics_ShouldHoldStage`");") `
        'optional T stage hold native'
    $text = Replace-Once $text `
        'bool g_bTacticalHoldReached[MAXPLAYERS+1];' `
        ('bool g_bTacticalHoldReached[MAXPLAYERS+1];' + $newline + 'bool g_bTacticalStageReached[MAXPLAYERS+1];') `
        'T stage arrival state'
    $text = Replace-Once $text `
        ("`tbool bHasTacticalAim = false;" + $newline + "`tfloat fTacticalGoal[3], fTacticalLook[3];") `
        ("`tbool bHasTacticalAim = false;" + $newline + "`tbool bShouldHoldTAttackStage = false;" + $newline + "`tfloat fTacticalGoal[3], fTacticalLook[3];") `
        'T stage hold local state'

    $oldTOrder = @(
        "`telse if (GetClientTeam(iClient) == CS_TEAM_T && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t`tbHasTacticalOrder = BotTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);"
    ) -join $newline
    $newTOrder = @(
        "`telse if (GetClientTeam(iClient) == CS_TEAM_T && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetOrder`") == FeatureStatus_Available)",
        "`t{",
        "`t`tbHasTacticalOrder = BotTTactics_GetOrder(iClient, fTacticalGoal, iTacticalRoute);",
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotTTactics_ShouldHoldStage`") == FeatureStatus_Available)",
        "`t`t`tbShouldHoldTAttackStage = BotTTactics_ShouldHoldStage(iClient);",
        "`t}"
    ) -join $newline
    $text = Replace-Once $text $oldTOrder $newTOrder 'T stage hold acquisition'
    $text = Replace-Once $text `
        'bool bHoldInitialCTPosition = false;' `
        ('bool bHoldInitialCTPosition = false;' + $newline + "`tbool bHoldTAttackStage = false;") `
        'T stage hold flag'

    $ctHoldTail = @(
        "`t`tbHoldInitialCTPosition = GetClientTeam(iClient) == CS_TEAM_CT && bHasTacticalAim",
        "`t`t`t&& !g_bBombPlanted && !bEnemyVisible && g_bTacticalHoldReached[iClient]",
        "`t`t`t&& fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END CT_INITIAL_HOLD"
    ) -join $newline
    $stageHold = @(
        "`t`tbHoldInitialCTPosition = GetClientTeam(iClient) == CS_TEAM_CT && bHasTacticalAim",
        "`t`t`t&& !g_bBombPlanted && !bEnemyVisible && g_bTacticalHoldReached[iClient]",
        "`t`t`t&& fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END CT_INITIAL_HOLD",
        "`t`t// BEGIN T_ATTACK_STAGE_HOLD",
        "`t`tif (!bShouldHoldTAttackStage || bTacticalGoalChanged)",
        "`t`t`tg_bTacticalStageReached[iClient] = false;",
        "`t`tif (g_bTacticalStageReached[iClient] && fDistanceToTacticalGoal > 256.0)",
        "`t`t{",
        "`t`t`tg_bTacticalStageReached[iClient] = false;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tbTacticalGoalChanged = true;",
        "`t`t}",
        "`t`tif (bShouldHoldTAttackStage && !bEnemyVisible && fDistanceToTacticalGoal <= 128.0)",
        "`t`t{",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t}",
        "`t`t`tg_bTacticalStageReached[iClient] = true;",
        "`t`t}",
        "`t`tbHoldTAttackStage = bShouldHoldTAttackStage && !bEnemyVisible",
        "`t`t`t&& g_bTacticalStageReached[iClient] && fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END T_ATTACK_STAGE_HOLD"
    ) -join $newline
    $text = Replace-Once $text $ctHoldTail $stageHold 'T attack stage arrival hysteresis'
    $text = Replace-Once $text `
        'if (!bEnemyVisible && !bHoldInitialCTPosition && fDistanceToTacticalGoal > 96.0)' `
        'if (!bEnemyVisible && !bHoldInitialCTPosition && !bHoldTAttackStage && fDistanceToTacticalGoal > 96.0)' `
        'T stage movement suspension'
    $text = Replace-Once $text `
        ("`t`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;") `
        ("`t`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`t`tg_bTacticalStageReached[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;") `
        'clear T stage arrival without order'
    $text = Replace-Once $text `
        'if (bHoldInitialCTPosition && !GetEntData(iClient, g_iEnemyVisibleOffset)' `
        'if ((bHoldInitialCTPosition || bHoldTAttackStage) && !GetEntData(iClient, g_iEnemyVisibleOffset)' `
        'T quiet staging input'
    $text = Replace-Once $text `
        ("`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        ("`tg_bTacticalHoldReached[iClient] = false;" + $newline + "`tg_bTacticalStageReached[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        'T stage disconnect reset'
    $text = Replace-Once $text `
        ('    g_bTacticalHoldReached[iClient] = false;' + $newline) `
        ('    g_bTacticalHoldReached[iClient] = false;' + $newline + '    g_bTacticalStageReached[iClient] = false;' + $newline) `
        'T stage spawn reset'
}

# Post-plant T positions use the same stable arrival semantics as CT setup,
# while receiving their own director-provided retake angle.
if ($text.Contains('BEGIN T_ATTACK_STAGE_HOLD') -and -not $text.Contains('BEGIN T_POSTPLANT_HOLD')) {
    $text = Replace-Once $text `
        'native bool BotTTactics_ShouldHoldStage(int client);' `
        ('native bool BotTTactics_ShouldHoldStage(int client);' + $newline + 'native bool BotTTactics_GetAim(int client, float lookAt[3]);') `
        'T post-plant aim native declaration'
    $text = Replace-Once $text `
        "`tMarkNativeAsOptional(`"BotTTactics_ShouldHoldStage`");" `
        ("`tMarkNativeAsOptional(`"BotTTactics_ShouldHoldStage`");" + $newline + "`tMarkNativeAsOptional(`"BotTTactics_GetAim`");") `
        'optional T post-plant aim native'
    $text = Replace-Once $text `
        'bool g_bTacticalStageReached[MAXPLAYERS+1];' `
        ('bool g_bTacticalStageReached[MAXPLAYERS+1];' + $newline + 'bool g_bTacticalPostPlantReached[MAXPLAYERS+1];') `
        'T post-plant arrival state'

    $oldTOrderAim = @(
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotTTactics_ShouldHoldStage`") == FeatureStatus_Available)",
        "`t`t`tbShouldHoldTAttackStage = BotTTactics_ShouldHoldStage(iClient);"
    ) -join $newline
    $newTOrderAim = @(
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotTTactics_ShouldHoldStage`") == FeatureStatus_Available)",
        "`t`t`tbShouldHoldTAttackStage = BotTTactics_ShouldHoldStage(iClient);",
        "`t`tif (bHasTacticalOrder && GetFeatureStatus(FeatureType_Native, `"BotTTactics_GetAim`") == FeatureStatus_Available)",
        "`t`t`tbHasTacticalAim = BotTTactics_GetAim(iClient, fTacticalLook);"
    ) -join $newline
    $text = Replace-Once $text $oldTOrderAim $newTOrderAim 'T post-plant aim acquisition'
    $text = Replace-Once $text `
        "`tbool bHoldTAttackStage = false;" `
        ("`tbool bHoldTAttackStage = false;" + $newline + "`tbool bHoldTPostPlantPosition = false;") `
        'T post-plant hold flag'

    $stageHoldTail = @(
        "`t`tbHoldTAttackStage = bShouldHoldTAttackStage && !bEnemyVisible",
        "`t`t`t&& g_bTacticalStageReached[iClient] && fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END T_ATTACK_STAGE_HOLD"
    ) -join $newline
    $postPlantHold = @(
        "`t`tbHoldTAttackStage = bShouldHoldTAttackStage && !bEnemyVisible",
        "`t`t`t&& g_bTacticalStageReached[iClient] && fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END T_ATTACK_STAGE_HOLD",
        "`t`t// BEGIN T_POSTPLANT_HOLD",
        "`t`tbool bTPostPlantAim = GetClientTeam(iClient) == CS_TEAM_T && g_bBombPlanted && bHasTacticalAim;",
        "`t`tif (!bTPostPlantAim || bTacticalGoalChanged)",
        "`t`t`tg_bTacticalPostPlantReached[iClient] = false;",
        "`t`tif (g_bTacticalPostPlantReached[iClient] && fDistanceToTacticalGoal > 256.0)",
        "`t`t{",
        "`t`t`tg_bTacticalPostPlantReached[iClient] = false;",
        "`t`t`tg_bTacticalMoveIssued[iClient] = false;",
        "`t`t`tbTacticalGoalChanged = true;",
        "`t`t}",
        "`t`tif (bTPostPlantAim && !bEnemyVisible && fDistanceToTacticalGoal <= 128.0)",
        "`t`t{",
        "`t`t`tif (bTacticalGoalChanged)",
        "`t`t`t{",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][0] = fTacticalGoal[0];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][1] = fTacticalGoal[1];",
        "`t`t`t`tg_fTacticalMoveGoal[iClient][2] = fTacticalGoal[2];",
        "`t`t`t`tg_iTacticalMoveRoute[iClient] = iTacticalRoute;",
        "`t`t`t`tg_bTacticalMoveIssued[iClient] = true;",
        "`t`t`t}",
        "`t`t`tg_bTacticalPostPlantReached[iClient] = true;",
        "`t`t}",
        "`t`tbHoldTPostPlantPosition = bTPostPlantAim && !bEnemyVisible",
        "`t`t`t&& g_bTacticalPostPlantReached[iClient] && fDistanceToTacticalGoal <= 256.0;",
        "`t`t// END T_POSTPLANT_HOLD"
    ) -join $newline
    $text = Replace-Once $text $stageHoldTail $postPlantHold 'T post-plant arrival hysteresis'
    $text = Replace-Once $text `
        'if (!bEnemyVisible && !bHoldInitialCTPosition && !bHoldTAttackStage && fDistanceToTacticalGoal > 96.0)' `
        'if (!bEnemyVisible && !bHoldInitialCTPosition && !bHoldTAttackStage && !bHoldTPostPlantPosition && fDistanceToTacticalGoal > 96.0)' `
        'T post-plant movement suspension'
    $text = Replace-Once $text `
        'BotSetLookAt(iClient, "CT tactical hold", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);' `
        'BotSetLookAt(iClient, "tactical hold", fTacticalLook, PRIORITY_HIGH, 0.75, false, 8.0, false);' `
        'shared tactical aim label'
    $text = Replace-Once $text `
        '(bHoldInitialCTPosition || bHoldTAttackStage)' `
        '(bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition)' `
        'T post-plant quiet hold input'
    $text = Replace-Once $text `
        ("`t`tg_bTacticalStageReached[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;") `
        ("`t`tg_bTacticalStageReached[iClient] = false;" + $newline + "`t`tg_bTacticalPostPlantReached[iClient] = false;" + $newline + "`t`tg_fTacticalProgressTimestamp[iClient] = 0.0;") `
        'clear T post-plant arrival without order'
    $text = Replace-Once $text `
        ("`tg_bTacticalStageReached[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        ("`tg_bTacticalStageReached[iClient] = false;" + $newline + "`tg_bTacticalPostPlantReached[iClient] = false;" + $newline + "`tg_fTacticalMoveTimestamp[iClient] = 0.0;") `
        'T post-plant disconnect reset'
    $text = Replace-Once $text `
        ('    g_bTacticalStageReached[iClient] = false;' + $newline + $newline) `
        ('    g_bTacticalStageReached[iClient] = false;' + $newline + '    g_bTacticalPostPlantReached[iClient] = false;' + $newline + $newline) `
        'T post-plant spawn reset'
}

# Restore the roster assignment behavior that exists in the pack's original
# compiled SMX but was absent from its shipped (older) SourcePawn source.
if (-not $text.Contains("BEGIN BOT_TEAM_ROSTERS_BRIDGE")) {
    $rosterInclude = @(
        '#include <bot_steamids>',
        '',
        '// BEGIN BOT_TEAM_ROSTERS_BRIDGE',
        '#include <bot_team_rosters>',
        '// END BOT_TEAM_ROSTERS_BRIDGE'
    ) -join $newline
    $text = Replace-Once $text '#include <bot_steamids>' $rosterInclude 'roster include'

    $text = Replace-Once $text `
        '    RegConsoleCmd("team", Command_Team);' `
        ('    RegConsoleCmd("team", Command_Team);' + $newline + '    BotTeams_OnPluginStart();') `
        'roster startup'

    $teamCommand = @(
        '// BEGIN BOT_TEAM_ROSTERS_BRIDGE',
        'public Action Command_Team(int iClient, int iArgs)',
        '{',
        '    return BotTeams_CommandTeam(iClient, iArgs);',
        '}',
        '// END BOT_TEAM_ROSTERS_BRIDGE',
        ''
    ) -join $newline
    $text = Replace-RegexOnce $text '(?ms)^public Action Command_Team\(int iClient, int iArgs\)\s*\{.*?^\}\s*(?=^public Action Command_ValidateBots)' $teamCommand 'team command bridge'

    $mapStartAnchor = 'public void OnMapStart()' + $newline + '{'
    $text = Replace-Once $text $mapStartAnchor ($mapStartAnchor + $newline + '    BotTeams_OnMapStart();') 'roster map startup'
}

# player_disconnect's bot flag is unreliable in CS:GO Legacy during engine
# side switches. Route the still-valid client slot through the roster module
# before BetterBots clears its per-client state.
if ($text.Contains("BEGIN BOT_TEAM_ROSTERS_BRIDGE") -and -not $text.Contains('BotTeams_OnClientDisconnect(iClient);')) {
    $disconnectAnchor = 'public void OnClientDisconnect(int iClient)' + $newline + '{'
    $text = Replace-Once $text $disconnectAnchor `
        ($disconnectAnchor + $newline + "`tBotTeams_OnClientDisconnect(iClient);") `
        'roster disconnect classification'
}

if (-not $text.Contains("BEGIN BOT_PURCHASE_POLICY")) {
    $purchaseInclude = @(
        '#include <bot_team_rosters>',
        '',
        '// BEGIN BOT_PURCHASE_POLICY',
        '#include <bot_purchase_policy>',
        '// END BOT_PURCHASE_POLICY'
    ) -join $newline
    $text = Replace-Once $text '#include <bot_team_rosters>' $purchaseInclude 'CT purchase include'

    $buyStateAnchor = 'bool bIsFullSave = bIsEco && iAccount < 2000;'
    $text = Replace-Once $text $buyStateAnchor `
        ($buyStateAnchor + $newline + $newline + "`tBotPurchase_EnsureArmorBeforePrimary(iClient, szWeapon, bIsFullSave);") `
        'BOT armor priority'

    $oldArmorPolicy = @(
        "`tif (strcmp(szWeapon, `"vest`") == 0 || strcmp(szWeapon, `"vesthelm`") == 0 || strcmp(szWeapon, `"defuser`") == 0)",
        "`t`treturn bIsFullSave ? Plugin_Handled : Plugin_Continue;"
    ) -join $newline
    $newArmorPolicy = @(
        "`tif (strcmp(szWeapon, `"vest`") == 0 || strcmp(szWeapon, `"vesthelm`") == 0 || strcmp(szWeapon, `"defuser`") == 0)",
        "`t{",
        "`t`tbool bOwnsPrimary = GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) != -1;",
        "`t`treturn (bIsFullSave && !bOwnsPrimary) ? Plugin_Handled : Plugin_Continue;",
        "`t}"
    ) -join $newline
    $text = Replace-Once $text $oldArmorPolicy $newArmorPolicy 'saved-rifle armor allowance'
}

# Coordinate decisions with each player's actual primary weapon, armor and cash.
# The original BetterBots drop path is preserved, with safer donor reserves,
# recipient priority and delivery verification added around it.
if (-not $text.Contains("BEGIN BOT_EQUIPMENT_POLICY")) {
    $equipmentInclude = @(
        '#include <bot_purchase_policy>',
        '',
        '// BEGIN BOT_EQUIPMENT_POLICY',
        '#define BOT_EQUIPMENT_CORE',
        '// END BOT_EQUIPMENT_POLICY'
    ) -join $newline
    $text = Replace-Once $text '#include <bot_purchase_policy>' $equipmentInclude 'equipment policy include'

    $equipmentStateMatch = [regex]::Match($text, '(?m)^float g_fNadeLineupCooldown\[MAXPLAYERS\+1\];.*$')
    if (-not $equipmentStateMatch.Success) {
        throw 'Could not patch BetterBots (equipment policy core helpers): state declaration was not found.'
    }
    $equipmentCoreInclude = @(
        $equipmentStateMatch.Value,
        '',
        '// Core-only helpers are included after BetterBots declares its per-client state.',
        '#include <bot_equipment_policy>'
    ) -join $newline
    $text = Replace-Once $text `
        $equipmentStateMatch.Value `
        $equipmentCoreInclude `
        'equipment policy core helpers'

    $text = Replace-Once $text `
        '    BotTeams_OnPluginStart();' `
        ('    BotTeams_OnPluginStart();' + $newline + '    BotEquipment_OnPluginStart();') `
        'equipment status command registration'

    $text = Replace-Once $text `
        "        if (iMoney < iWeaponPrice)`n            continue;".Replace("`n", $newline) `
        "        if (!BotEquipment_CanDonateWeapon(iClient, iWeaponPrice))`n            continue;".Replace("`n", $newline) `
        'primary donor reserve'

    $assignDrops = @(
        '// BEGIN BOT_EQUIPMENT_DROP_COORDINATION',
        'void AssignDrops(ArrayList aBotsT, ArrayList aBotsCT, bool &bNeedDropT, bool &bNeedDropCT)',
        '{',
        '    bNeedDropT = false;',
        '    bNeedDropCT = false;',
        '    AssignTeamDrops(aBotsT, CS_TEAM_T, bNeedDropT);',
        '    AssignTeamDrops(aBotsCT, CS_TEAM_CT, bNeedDropCT);',
        '}',
        '',
        'void AssignTeamDrops(ArrayList donors, int team, bool &needsDonor)',
        '{',
        '    for (int attempts = 0; attempts <= MaxClients; attempts++)',
        '    {',
        '        int recipient;',
        '        int bestPriority = -1;',
        '        for (int client = 1; client <= MaxClients; client++)',
        '        {',
        '            if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != team',
        '                || g_bHasGottenDrop[client] || !GetEntProp(client, Prop_Send, "m_bInBuyZone"))',
        '                continue;',
        '            if (GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) != -1 || BotEquipment_CanSelfBuyPrimary(client))',
        '                continue;',
        '',
        '            int priority = BotEquipment_GetRecipientPriority(client);',
        '            if (priority > bestPriority)',
        '            {',
        '                bestPriority = priority;',
        '                recipient = client;',
        '            }',
        '        }',
        '',
        '        if (recipient == 0)',
        '            return;',
        '        if (donors.Length == 0)',
        '        {',
        '            needsDonor = true;',
        '            return;',
        '        }',
        '',
        '        int entry[2];',
        '        donors.GetArray(0, entry, sizeof(entry));',
        '        donors.Erase(0);',
        '        int donor = entry[0];',
        '        if (!IsValidClient(donor) || !IsPlayerAlive(donor) || GetClientTeam(donor) != team)',
        '            continue;',
        '',
        '        float eyePosition[3];',
        '        GetClientEyePosition(recipient, eyePosition);',
        '        BotSetLookAt(donor, "Use entity", eyePosition, PRIORITY_HIGH, 3.0, false, 5.0, false);',
        '        g_bDropWeapon[donor] = true;',
        '        g_bHasGottenDrop[recipient] = true;',
        '        g_iDropRecipientUserId[donor] = GetClientUserId(recipient);',
        '    }',
        '}',
        '// END BOT_EQUIPMENT_DROP_COORDINATION',
        '',
        'void CollectCheapDroppers'
    ) -join $newline
    $text = Replace-RegexOnce $text `
        '(?ms)^void AssignDrops\(ArrayList aBotsT, ArrayList aBotsCT, bool &bNeedDropT, bool &bNeedDropCT\)\s*\{.*?^\}\s*\r?\n\s*void CollectCheapDroppers' `
        $assignDrops `
        'drop recipient coordination'

    $text = Replace-Once $text `
        '        if (iMoney >= CS_GetWeaponPrice(iClient, eRifle))' `
        '        if (BotEquipment_CanDonateWeapon(iClient, CS_GetWeaponPrice(iClient, eRifle)))' `
        'cheap rifle donor reserve'
    $text = Replace-Once $text `
        '        else if (iMoney >= CS_GetWeaponPrice(iClient, eSMG))' `
        '        else if (BotEquipment_CanDonateWeapon(iClient, CS_GetWeaponPrice(iClient, eSMG)))' `
        'cheap SMG donor reserve'
}

# A donation is asynchronous: the donor first turns toward the recipient and
# executes the drop from OnPlayerRunCmd.  Remember that recipient and validate
# again at execution time.  Do not reopen the recipient after a fixed timeout;
# doing so allowed multiple donors to buy for the same player.  Cheap donors
# now drop their saved primary first and keep the cheaper replacement instead
# of buying over the saved gun and then dropping the replacement as well.
if ($text.Contains('BEGIN BOT_EQUIPMENT_DROP_COORDINATION') -and -not $text.Contains('BEGIN BOT_DROP_EXECUTION_GUARD')) {
    $equipmentStateMatch = [regex]::Match($text, '(?m)^float g_fNadeLineupCooldown\[MAXPLAYERS\+1\];.*$')
    if (-not $equipmentStateMatch.Success) {
        throw 'Could not patch BetterBots (drop recipient state): state declaration was not found.'
    }
    $text = Replace-Once $text `
        $equipmentStateMatch.Value `
        ($equipmentStateMatch.Value + $newline + 'int g_iDropRecipientUserId[MAXPLAYERS+1];') `
        'drop recipient state'

    $oldAssignmentTail = @(
        '        g_bDropWeapon[donor] = true;',
        '        g_bHasGottenDrop[recipient] = true;',
        '        CreateTimer(2.0, BotEquipment_TimerVerifyDrop, GetClientUserId(recipient), TIMER_FLAG_NO_MAPCHANGE);'
    ) -join $newline
    if ($text.Contains($oldAssignmentTail)) {
        $newAssignmentTail = @(
            '        g_bDropWeapon[donor] = true;',
            '        g_bHasGottenDrop[recipient] = true;',
            '        g_iDropRecipientUserId[donor] = GetClientUserId(recipient);'
        ) -join $newline
        $text = Replace-Once $text $oldAssignmentTail $newAssignmentTail 'single donation assignment'
    }

    $oldDropExecution = @(
        "`tif (!g_bFreezetimeEnd && g_bDropWeapon[iClient] && view_as<LookAtSpotState>(GetEntData(iClient, g_iBotLookAtSpotStateOffset)) == LOOK_AT_SPOT)",
        "`t{",
        "`t`tif (g_bCheapDrop[iClient])",
        "`t`t{",
        "`t`t`tg_bBuyingCheapDrop[iClient] = true;",
        "`t`t`tFakeClientCommand(iClient, `"buy %s`", g_szPreviousBuy[iClient]);",
        "`t`t`tg_bBuyingCheapDrop[iClient] = false;",
        "`t`t`tRequestFrame(TossCheapDrop, GetClientUserId(iClient));",
        "`t`t`tg_bCheapDrop[iClient] = false;",
        "`t`t}",
        "`t`telse",
        "`t`t{",
        "`t`t`tCS_DropWeapon(iClient, GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY), true);",
        "`t`t`tFakeClientCommand(iClient, `"buy %s`", g_szPreviousBuy[iClient]);",
        "`t`t}",
        "`t`tg_bDropWeapon[iClient] = false;",
        "`t}"
    ) -join $newline
    $newDropExecution = @(
        "`t// BEGIN BOT_DROP_EXECUTION_GUARD",
        "`tif (!g_bFreezetimeEnd && g_bDropWeapon[iClient] && view_as<LookAtSpotState>(GetEntData(iClient, g_iBotLookAtSpotStateOffset)) == LOOK_AT_SPOT)",
        "`t{",
        "`t`tint iDropRecipient = GetClientOfUserId(g_iDropRecipientUserId[iClient]);",
        "`t`tint iDonatedPrimary = GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY);",
        "`t`tbool bRecipientStillNeedsPrimary = IsValidClient(iDropRecipient) && IsPlayerAlive(iDropRecipient)",
        "`t`t`t&& GetClientTeam(iDropRecipient) == GetClientTeam(iClient)",
        "`t`t`t&& GetPlayerWeaponSlot(iDropRecipient, CS_SLOT_PRIMARY) == -1;",
        "`t`tif (bRecipientStillNeedsPrimary && IsValidEntity(iDonatedPrimary))",
        "`t`t{",
        "`t`t`tCS_DropWeapon(iClient, iDonatedPrimary, true);",
        "`t`t`tg_bBuyingCheapDrop[iClient] = true;",
        "`t`t`tFakeClientCommand(iClient, `"buy %s`", g_szPreviousBuy[iClient]);",
        "`t`t`tg_bBuyingCheapDrop[iClient] = false;",
        "`t`t}",
        "`t`telse if (IsValidClient(iDropRecipient))",
        "`t`t`tg_bHasGottenDrop[iDropRecipient] = false;",
        "`t`tg_bDropWeapon[iClient] = false;",
        "`t`tg_bCheapDrop[iClient] = false;",
        "`t`tg_iDropRecipientUserId[iClient] = 0;",
        "`t}",
        "`t// END BOT_DROP_EXECUTION_GUARD"
    ) -join $newline
    $text = Replace-Once $text $oldDropExecution $newDropExecution 'drop execution validation'
}

if (-not $text.Contains("BEGIN BOT_EQUIPMENT_BUY_STATE")) {
    $oldBuyState = @(
        "`tint iAccount = GetEntProp(iClient, Prop_Send, `"m_iAccount`");",
        "`tint iOwnAvgMoney = (iTeam == CS_TEAM_T) ? g_iAvgMoneyT : g_iAvgMoneyCT;",
        "`tbool bIsResetRound = IsResetRound();",
        "`tbool bIsEco = !bIsResetRound && !IsTeamForcing(iTeam) && iOwnAvgMoney < 3000;",
        "`tbool bIsFullSave = bIsEco && iAccount < 2000;"
    ) -join $newline
    $newBuyState = @(
        "`tint iAccount = GetEntProp(iClient, Prop_Send, `"m_iAccount`");",
        '',
        "`t// BEGIN BOT_EQUIPMENT_BUY_STATE",
        "`tBotEquipmentTier eTeamBuy = BotEquipment_ClassifyTeam(iTeam);",
        "`tBotEquipmentTier ePlayerBuy = BotEquipment_ClassifyPlayer(iClient);",
        "`tbool bIsResetRound = IsResetRound();",
        "`tbool bIsEco = !bIsResetRound && !IsTeamForcing(iTeam) && eTeamBuy == BotEquip_Eco;",
        "`tbool bIsFullSave = bIsEco && ePlayerBuy == BotEquip_Eco;",
        "`t// END BOT_EQUIPMENT_BUY_STATE"
    ) -join $newline
    $text = Replace-Once $text $oldBuyState $newBuyState 'per-player equipment buy state'
}

if ($text.Contains('BEGIN T_PLANT_COVER_BRIDGE')) {
    if ($text.Contains('GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted)')) {
        $text = Replace-Once $text 'GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted)' `
            'GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted && !g_bTPlanting)' `
            'plant-cover lineup priority'
    }
    if ($text.Contains('!(g_bBombPlanted && GetClientTeam(iClient) == CS_TEAM_T)')) {
        $text = Replace-Once $text '!(g_bBombPlanted && GetClientTeam(iClient) == CS_TEAM_T)' `
            '!((g_bBombPlanted || g_bTPlanting) && GetClientTeam(iClient) == CS_TEAM_T)' `
            'plant-cover generic lineup guard'
    }
    if ($text.Contains('GetClientTeam(iClient) == CS_TEAM_T && g_bBombPlanted && bHasTacticalAim')) {
        $text = Replace-Once $text 'GetClientTeam(iClient) == CS_TEAM_T && g_bBombPlanted && bHasTacticalAim' `
            'GetClientTeam(iClient) == CS_TEAM_T && (g_bBombPlanted || g_bTPlanting) && bHasTacticalAim' `
            'plant-cover tactical hold'
    }
}

# Freeze the team's buy call before any individual purchase changes cash.
# Keep the CSGO engine responsible for the actual halftime side switch.
if (-not $text.Contains('BEGIN BOT_ROUND_BUY_PLAN')) {
    $text = Replace-Once $text 'g_iRoundsPlayed == iRoundsBeforeHalftime - 1' `
        'g_iCurrentRound == iRoundsBeforeHalftime - 1' 'last pre-halftime round detection'
    $text = Replace-Once $text "`tg_iAvgMoneyCT = GetTeamAverageMoney(CS_TEAM_CT);" `
        ("`tg_iAvgMoneyCT = GetTeamAverageMoney(CS_TEAM_CT);" + $newline + `
        "`t// BEGIN BOT_ROUND_BUY_PLAN" + $newline + `
        "`tBotEquipment_BeginRound(IsResetRound(), g_bForceT, g_bForceCT);" + $newline + `
        "`t// END BOT_ROUND_BUY_PLAN") 'fixed per-round team buy plan'
    $text = Replace-Once $text 'BotEquipmentTier eTeamBuy = BotEquipment_ClassifyTeam(iTeam);' `
        'BotEquipmentTier eTeamBuy = BotEquipment_GetRoundPlan(iTeam);' 'buy command round plan'
    $text = Replace-Once $text 'bool bIsFullSave = bIsEco && ePlayerBuy == BotEquip_Eco;' `
        'bool bIsFullSave = bIsEco && GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) == -1;' 'team eco save discipline'
    $text = Replace-Once $text 'if (iArmor < 50 || !bHasHelmet)' `
        'if (iArmor == 0 || !bHasHelmet)' 'avoid repairing damaged full armor'
    $text = Replace-Once $text 'bool bOwnsPrimary = GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) != -1;' `
        (@(
            'if (strcmp(szWeapon, "defuser") != 0 && GetEntProp(iClient, Prop_Data, "m_ArmorValue") > 0',
            '            && view_as<bool>(GetEntProp(iClient, Prop_Send, "m_bHasHelmet")))',
            '            return Plugin_Handled;',
            '        bool bOwnsPrimary = GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) != -1;'
        ) -join $newline) 'full armor damage buy guard'
    $text = Replace-Once $text 'else if (!IsTeamForcing(iTeam) && ((((iTeam == CS_TEAM_T) ? g_iAvgMoneyT : g_iAvgMoneyCT) < 3000 && iAccount > 2000 && !bHasPrimary) || iFriendsWithPrimary >= 1))' `
        'else if (BotEquipment_GetRoundPlan(iTeam) == BotEquip_Force && !IsTeamForcing(iTeam) && !bHasPrimary && iAccount > 2000)' `
        'force-buy pistol supplement'
    $forceBuyAnchor = @(
        "`tif (bHasPrimary || (iFriendsWithPrimary >= 1 && !bDefaultPistol))"
    ) -join $newline
    $forceBuy = @(
        "`t// On a final/side-switch round there is no future economy to save for.",
        "`tif (IsTeamForcing(iTeam) && !bHasPrimary)",
        "`t{",
        "`t`tint iRiflePrice = BotEquipment_GetCheapestRiflePrice(i);",
        "`t`tif (iAccount >= iRiflePrice)",
        "`t`t`tFakeClientCommand(i, iTeam == CS_TEAM_T ? `"buy galilar`" : `"buy famas`");",
        "`t`telse if (iAccount >= (iTeam == CS_TEAM_T ? CS_GetWeaponPrice(i, CSWeapon_MAC10) : CS_GetWeaponPrice(i, CSWeapon_MP9)))",
        "`t`t`tFakeClientCommand(i, iTeam == CS_TEAM_T ? `"buy mac10`" : `"buy mp9`");",
        "`t`telse if (iArmor == 0 && iAccount >= 650)",
        "`t`t`tFakeClientCommand(i, `"buy vest`");",
        "`t`telse if (bDefaultPistol && iAccount >= 700)",
        "`t`t`tFakeClientCommand(i, `"buy deagle`");",
        "`t`tcontinue;",
        "`t}",
        '',
        $forceBuyAnchor
    ) -join $newline
    $text = Replace-Once $text $forceBuyAnchor $forceBuy 'final-round buy-out'
}
if ($text.Contains('else if (iAccount >= 700)' + $newline + "`t`t`tFakeClientCommand(i, `"buy deagle`");")) {
    $text = Replace-Once $text 'else if (iAccount >= 700)' `
        'else if (bDefaultPistol && iAccount >= 700)' 'avoid repeated final-round pistol buys'
}
if ($text.Contains('if (bHasPrimary || (iFriendsWithPrimary >= 1 && !bDefaultPistol))')) {
    $text = Replace-Once $text 'if (bHasPrimary || (iFriendsWithPrimary >= 1 && !bDefaultPistol))' `
        'if (bHasPrimary || (BotEquipment_GetRoundPlan(iTeam) != BotEquip_Eco && iFriendsWithPrimary >= 1 && !bDefaultPistol))' `
        'no utility drain during a team eco'
}
if ($text.Contains('int g_iCurrentRound, g_iRoundsPlayed, g_iCTScore, g_iTScore;')) {
    $text = Replace-Once $text 'int g_iCurrentRound, g_iRoundsPlayed, g_iCTScore, g_iTScore;' `
        'int g_iCurrentRound, g_iCTScore, g_iTScore;' 'unused previous-round state'
    $text = Replace-Once $text '    g_iRoundsPlayed = GameRules_GetProp("m_totalRoundsPlayed");' `
        '    // Current round number is read directly in OnRoundPreStart.' 'unused previous-round assignment'
}
if ($text.Contains('BotEquipmentTier ePlayerBuy = BotEquipment_ClassifyPlayer(iClient);')) {
    $text = Replace-Once $text "`tBotEquipmentTier ePlayerBuy = BotEquipment_ClassifyPlayer(iClient);" '' `
        'unused transient player buy state'
}

# An unarmed bot may briefly leave a tactical route to collect a visible primary;
# equipped bots remain fully governed by the CT/T director.
$oldPickupGuard = 'if (!bHasTacticalOrder && g_bIsProBot[iClient] && !g_bBombPlanted'
if ($text.Contains($oldPickupGuard)) {
    $text = Replace-Once $text $oldPickupGuard `
        'if ((!bHasTacticalOrder || GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) == -1) && g_bIsProBot[iClient] && !g_bBombPlanted' `
        'unarmed tactical weapon pickup'
}

# The pack's bot_stuff.cfg profile values are not read by this source. Its
# actual top-bot profile had zero reaction time and effectively unlimited turn
# acceleration. Tune the authoritative assignments and cap first-contact fire
# in the same RunCmd path that also performs custom rifle combat.
if (-not $text.Contains('BEGIN HUMAN_REACTION_GUARD')) {
    $text = Replace-Once $text `
        'float g_fSniperRetreatCooldown[MAXPLAYERS+1];' `
        (@(
            'float g_fSniperRetreatCooldown[MAXPLAYERS+1];',
            'float g_fReactionLockUntil[MAXPLAYERS+1], g_fLastVisibleEnemyAt[MAXPLAYERS+1];',
            'int g_iLastVisibleEnemy[MAXPLAYERS+1];'
        ) -join $newline) `
        'reaction guard state'

    $text = Replace-Once $text `
        ("            g_fLookAngleMaxAccel[iClient] = 100000.0;" + $newline + "            g_fReactionTime[iClient] = 0.0;") `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(6000.0, 7500.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.18, 0.22);") `
        'top-bot reaction profile'
    $text = Replace-Once $text `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(4000.0, 7000.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.165, 0.325);") `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(4500.0, 6500.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.22, 0.30);") `
        'other pro-bot reaction profile'

    $oldCombatCall = @(
        "`tif (g_bIsProBot[iClient] && GetDisposition(iClient) != IGNORE_ENEMIES)",
        "`t`tProcessCombat(iClient, iButtons, fVel, fAngles, iDefIndex, fSpeed, fNow);"
    ) -join $newline
    $newCombatCall = @(
        "`tif (g_bIsProBot[iClient] && GetDisposition(iClient) != IGNORE_ENEMIES)",
        "`t{",
        "`t`tProcessCombat(iClient, iButtons, fVel, fAngles, iDefIndex, fSpeed, fNow);",
        "`t`tApplyReactionGuard(iClient, iButtons, iDefIndex, fNow);",
        "`t}"
    ) -join $newline
    $text = Replace-Once $text $oldCombatCall $newCombatCall 'custom combat reaction call'

    $reactionGuard = @(
        '// BEGIN HUMAN_REACTION_GUARD',
        '// HUMAN_REACTION_PROFILE_V2',
        'void ApplyReactionGuard(int iClient, int &iButtons, int iDefIndex, float fNow)',
        '{',
        "`tint iEnemy = g_iTarget[iClient];",
        "`tif (!IsValidClient(iEnemy) || !IsPlayerAlive(iEnemy) || !GetEntData(iClient, g_iEnemyVisibleOffset))",
        "`t`treturn;",
        '',
        "`tif (g_iLastVisibleEnemy[iClient] != iEnemy || fNow - g_fLastVisibleEnemyAt[iClient] > 0.75)",
        "`t`tg_fReactionLockUntil[iClient] = fNow + g_fReactionTime[iClient];",
        "`tg_iLastVisibleEnemy[iClient] = iEnemy;",
        "`tg_fLastVisibleEnemyAt[iClient] = fNow;",
        '',
        "`tint iSlot = eItems_GetWeaponSlotByDefIndex(iDefIndex);",
        "`tif ((iSlot == CS_SLOT_PRIMARY || iSlot == CS_SLOT_SECONDARY) && fNow < g_fReactionLockUntil[iClient])",
        "`t`tiButtons &= ~IN_ATTACK;",
        '}',
        '// END HUMAN_REACTION_GUARD',
        '',
        'public void OnPlayerSpawn('
    ) -join $newline
    $text = Replace-Once $text 'public void OnPlayerSpawn(' $reactionGuard 'first-contact firing gate'

    $spawnAnchor = @(
        '    if (!IsFakeClient(iClient))',
        '        return;',
        '    g_bTacticalMoveIssued[iClient] = false;',
        '    g_bTacticalHoldReached[iClient] = false;',
        '    g_bTacticalStageReached[iClient] = false;',
        '    g_bTacticalPostPlantReached[iClient] = false;',
        '',
        '    if (g_bIsProBot[iClient])'
    ) -join $newline
    $spawnReset = @(
        '    if (!IsFakeClient(iClient))',
        '        return;',
        '    g_bTacticalMoveIssued[iClient] = false;',
        '    g_bTacticalHoldReached[iClient] = false;',
        '    g_bTacticalStageReached[iClient] = false;',
        '    g_bTacticalPostPlantReached[iClient] = false;',
        '',
        '    g_iLastVisibleEnemy[iClient] = 0;',
        '    g_fLastVisibleEnemyAt[iClient] = 0.0;',
        '    g_fReactionLockUntil[iClient] = 0.0;',
        '    if (g_bIsProBot[iClient])'
    ) -join $newline
    $text = Replace-Once $text $spawnAnchor $spawnReset 'reaction state spawn reset'
    $text = Replace-Once $text `
        ("`tg_fReactionTime[iClient] = 0.0;" + $newline + "`tg_fAggression[iClient] = 0.0;") `
        ("`tg_fReactionTime[iClient] = 0.0;" + $newline + "`tg_fReactionLockUntil[iClient] = 0.0;" + $newline + "`tg_fLastVisibleEnemyAt[iClient] = 0.0;" + $newline + "`tg_iLastVisibleEnemy[iClient] = 0;" + $newline + "`tg_fAggression[iClient] = 0.0;") `
        'reaction state disconnect reset'
}

# Upgrade the first human-paced profile without disturbing a source that an
# administrator has already tuned independently.
if ($text.Contains('BEGIN HUMAN_REACTION_GUARD') -and -not $text.Contains('HUMAN_REACTION_PROFILE_V2')) {
    $text = Replace-Once $text `
        ("            g_fLookAngleMaxAccel[iClient] = 7000.0;" + $newline + "            g_fReactionTime[iClient] = 0.20;") `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(6000.0, 7500.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.18, 0.22);") `
        'top-bot evidence-calibrated reaction profile'
    $text = Replace-Once $text `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(3500.0, 6000.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.23, 0.38);") `
        ("            g_fLookAngleMaxAccel[iClient] = Math_GetRandomFloat(4500.0, 6500.0);" + $newline + "            g_fReactionTime[iClient] = Math_GetRandomFloat(0.22, 0.30);") `
        'other pro-bot evidence-calibrated reaction profile'
    $text = Replace-Once $text `
        '// BEGIN HUMAN_REACTION_GUARD' `
        ('// BEGIN HUMAN_REACTION_GUARD' + $newline + '// HUMAN_REACTION_PROFILE_V2') `
        'reaction profile version marker'
}

# CS:GO's native bot navigator can keep pulsing IN_JUMP after a precise
# tactical destination is reached. Suppress only that settled hold input;
# moving routes and their collision recovery remain entirely native.
if (-not $text.Contains('BEGIN BOT_JUMP_GUARD')) {
    $jumpGuard = @(
        "`t// BEGIN BOT_JUMP_GUARD",
        "`t// BOT_JUMP_GUARD_V2_SETTLED_ONLY",
        "`tif (iButtons & IN_JUMP)",
        "`t{",
        "`t`tbool bRecordedJump = BotMimic_IsPlayerMimicing(iClient);",
        "`t`tbool bNavRequiresJump = g_pCurrArea[iClient] != INVALID_NAV_AREA",
        "`t`t`t&& (g_pCurrArea[iClient].Attributes & NAV_MESH_JUMP) != 0;",
        "`t`tbool bSettledTacticalHold = bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition;",
        "`t`tbool bJumpExempt = bRecordedJump || bNavRequiresJump || GetEntityMoveType(iClient) == MOVETYPE_LADDER",
        "`t`t`t|| GetTask(iClient) == ESCAPE_FROM_FLAMES || GetTask(iClient) == ESCAPE_FROM_BOMB;",
        "`t`tif (!bJumpExempt && bSettledTacticalHold)",
        "`t`t`tiButtons &= ~IN_JUMP;",
        "`t}",
        "`t// END BOT_JUMP_GUARD",
        ""
    ) -join $newline
    $text = Replace-Once $text `
        ("`t// END CT_INITIAL_HOLD_INPUT" + $newline + $newline + "`treturn Plugin_Changed;") `
        (("`t// END CT_INITIAL_HOLD_INPUT" + $newline + $newline) + $jumpGuard + "`treturn Plugin_Changed;") `
        'bot jump input guard'

}

# Upgrade the first guard revision without retaining its route-wide cooldown.
if ($text.Contains('BEGIN BOT_JUMP_GUARD') -and -not $text.Contains('BOT_JUMP_GUARD_V2_SETTLED_ONLY')) {
    $text = $text.Replace('float g_fNextBotJumpAllowed[MAXPLAYERS+1];' + $newline, '')
    $text = $text.Replace('    g_fNextBotJumpAllowed[iClient] = 0.0;' + $newline, '')
    $text = $text.Replace("`tg_fNextBotJumpAllowed[iClient] = 0.0;" + $newline, '')
    $oldJumpGuardPattern = '(?ms)^\t// BEGIN BOT_JUMP_GUARD\r?\n.*?^\t// END BOT_JUMP_GUARD\r?\n'
    $newJumpGuard = @(
        "`t// BEGIN BOT_JUMP_GUARD",
        "`t// BOT_JUMP_GUARD_V2_SETTLED_ONLY",
        "`tif (iButtons & IN_JUMP)",
        "`t{",
        "`t`tbool bRecordedJump = BotMimic_IsPlayerMimicing(iClient);",
        "`t`tbool bNavRequiresJump = g_pCurrArea[iClient] != INVALID_NAV_AREA",
        "`t`t`t&& (g_pCurrArea[iClient].Attributes & NAV_MESH_JUMP) != 0;",
        "`t`tbool bSettledTacticalHold = bHoldInitialCTPosition || bHoldTAttackStage || bHoldTPostPlantPosition;",
        "`t`tbool bJumpExempt = bRecordedJump || bNavRequiresJump || GetEntityMoveType(iClient) == MOVETYPE_LADDER",
        "`t`t`t|| GetTask(iClient) == ESCAPE_FROM_FLAMES || GetTask(iClient) == ESCAPE_FROM_BOMB;",
        "`t`tif (!bJumpExempt && bSettledTacticalHold)",
        "`t`t`tiButtons &= ~IN_JUMP;",
        "`t}",
        "`t// END BOT_JUMP_GUARD",
        ""
    ) -join $newline
    $text = Replace-RegexOnce $text $oldJumpGuardPattern $newJumpGuard 'settled-only bot jump guard upgrade'
}

if ($text.Contains('BEGIN TACTICAL_NADE_PRIORITY') -and -not $text.Contains('BEGIN T_URGENT_OBJECTIVE_PRIORITY')) {
    $text = Replace-Once $text 'native bool BotTTactics_GetAim(int client, float lookAt[3]);' `
        ('native bool BotTTactics_GetAim(int client, float lookAt[3]);' + $newline + 'native bool BotTTactics_IsUrgentPlant();') `
        'urgent T objective native declaration'
    $text = Replace-Once $text 'MarkNativeAsOptional("BotTTactics_GetAim");' `
        ('MarkNativeAsOptional("BotTTactics_GetAim");' + $newline + '    MarkNativeAsOptional("BotTTactics_IsUrgentPlant");') `
        'optional urgent T objective native'
    $priorityAnchor = "`t// BEGIN TACTICAL_NADE_PRIORITY"
    $urgentPriority = @(
        "`t// BEGIN T_URGENT_OBJECTIVE_PRIORITY",
        "`tbool bTPlantUrgent = GetClientTeam(iClient) == CS_TEAM_T",
        "`t`t&& GetFeatureStatus(FeatureType_Native, `"BotTTactics_IsUrgentPlant`") == FeatureStatus_Available",
        "`t`t&& BotTTactics_IsUrgentPlant();",
        "`tif (bTPlantUrgent)",
        "`t{",
        "`t`tif (BotMimic_IsPlayerMimicing(iClient)) BotMimic_StopPlayerMimic(iClient);",
        "`t`tg_iDoingSmokeNum[iClient] = -1;",
        "`t}",
        "`t// END T_URGENT_OBJECTIVE_PRIORITY",
        $priorityAnchor
    ) -join $newline
    $text = Replace-Once $text $priorityAnchor $urgentPriority 'urgent T lineup cancellation'
    $text = Replace-Once $text 'GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted && !g_bTPlanting)' `
        'GetClientTeam(iClient) == CS_TEAM_T && !g_bBombPlanted && !g_bTPlanting && !bTPlantUrgent)' `
        'urgent T lineup priority guard'
    $text = Replace-Once $text '!((g_bBombPlanted || g_bTPlanting) && GetClientTeam(iClient) == CS_TEAM_T)' `
        '!((g_bBombPlanted || g_bTPlanting || bTPlantUrgent) && GetClientTeam(iClient) == CS_TEAM_T)' `
        'urgent T generic lineup guard'
}

# Give both sides an affordable primary before optional pistol/utility spending.
# This is an idempotent migration for existing installations and fresh pack
# installs; the original BetterBots source remains in ct-tactics-rollback.
if (-not $text.Contains('BEGIN BOT_PRIMARY_FALLBACK')) {
    $text = Replace-Once $text `
        'BotPurchase_EnsureArmorBeforePrimary(iClient, szWeapon, bIsFullSave);' `
        ('if (BotPurchase_EnsureArmorBeforePrimary(iClient, szWeapon, bIsFullSave))' + $newline + `
        "`t`treturn Plugin_Handled;") `
        'defer original rifle purchase after armor'

    $defuserAnchor = 'bool bOwnsPrimary = GetPlayerWeaponSlot(iClient, CS_SLOT_PRIMARY) != -1;'
    $text = Replace-Once $text $defuserAnchor `
        ('if (strcmp(szWeapon, "defuser") == 0 && BotPurchase_ShouldReservePrimary(iClient, iTeam, bIsEco))' + $newline + `
        "            return Plugin_Handled;" + $newline + '        ' + $defuserAnchor) `
        'reserve primary before defuser'

    $text = Replace-Once $text `
        'return bIsEco ? Plugin_Handled : Plugin_Continue;' `
        'return (bIsEco || BotPurchase_ShouldReservePrimary(iClient, iTeam, bIsEco)) ? Plugin_Handled : Plugin_Continue;' `
        'reserve primary before grenades'
    $text = Replace-Once $text `
        'return bIsFullSave ? Plugin_Handled : Plugin_Continue;' `
        'return (bIsFullSave || BotPurchase_ShouldReservePrimary(iClient, iTeam, bIsEco)) ? Plugin_Handled : Plugin_Continue;' `
        'reserve primary before upgraded pistols'

    $normalBuyAnchor = 'if (bHasPrimary || (BotEquipment_GetRoundPlan(iTeam) != BotEquip_Eco && iFriendsWithPrimary >= 1 && !bDefaultPistol))'
    $primaryFallback = @(
        '// BEGIN BOT_PRIMARY_FALLBACK',
        'if (!g_bFreezetimeEnd && !bHasPrimary && BotEquipment_GetRoundPlan(iTeam) != BotEquip_Eco',
        '    && BotEquipment_BuyAffordablePrimary(i))',
        '    continue;',
        '// END BOT_PRIMARY_FALLBACK',
        '',
        $normalBuyAnchor
    ) -join $newline
    $text = Replace-Once $text $normalBuyAnchor $primaryFallback 'CT/T affordable primary fallback'
}

$candidateBotSource = Join-Path $buildDir "bot_stuff.sp"
$candidateBotPlugin = Join-Path $buildDir "bot_stuff.smx"
$candidateDirectorPlugin = Join-Path $buildDir "001_bot_ct_tactics.smx"
$candidateTDirectorPlugin = Join-Path $buildDir "002_bot_t_tactics.smx"

try {
    [System.IO.File]::WriteAllText($candidateBotSource, $text, [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $compatSource -Destination (Join-Path $includeDir "bot_stuff_compile_compat.inc") -Force
    Copy-Item -LiteralPath $navmeshSource -Destination (Join-Path $includeDir "navmesh.inc") -Force
    Copy-Item -LiteralPath $rosterSource -Destination (Join-Path $includeDir "bot_team_rosters.inc") -Force
    Copy-Item -LiteralPath $purchaseSource -Destination (Join-Path $includeDir "bot_purchase_policy.inc") -Force
    Copy-Item -LiteralPath $equipmentSource -Destination (Join-Path $includeDir "bot_equipment_policy.inc") -Force
    Copy-Item -LiteralPath $anglesSource -Destination (Join-Path $includeDir "bot_tactical_angles.inc") -Force

    & $compiler "-o$candidateDirectorPlugin" $directorSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidateDirectorPlugin)) {
        throw "Failed to compile bot_ct_tactics.sp (exit code $LASTEXITCODE)."
    }
    & $compiler "-o$candidateTDirectorPlugin" $tDirectorSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidateTDirectorPlugin)) {
        throw "Failed to compile bot_t_tactics.sp (exit code $LASTEXITCODE)."
    }
    & $compiler "-o$candidateBotPlugin" $candidateBotSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $candidateBotPlugin)) {
        throw "Failed to compile the BetterBots CT tactics bridge (exit code $LASTEXITCODE)."
    }

    Copy-Item -LiteralPath $candidateBotSource -Destination $botSource -Force
    Copy-Item -LiteralPath $directorSource -Destination $installedDirectorSource -Force
    Copy-Item -LiteralPath $tDirectorSource -Destination $installedTDirectorSource -Force
    Move-Item -LiteralPath $candidateBotPlugin -Destination $botPlugin -Force
    Move-Item -LiteralPath $candidateDirectorPlugin -Destination $directorPlugin -Force
    Move-Item -LiteralPath $candidateTDirectorPlugin -Destination $tDirectorPlugin -Force

    # AutoExecConfig does not replace an existing cfg when plugin defaults
    # change. Migrate only our previous exact defaults so administrator custom
    # values remain untouched.
    $ctConfig = Join-Path $ServerDir "csgo\cfg\sourcemod\bot_ct_tactics.cfg"
    if (Test-Path -LiteralPath $ctConfig) {
        $ctConfigText = Get-Content -LiteralPath $ctConfig -Raw
        $ctConfigText = $ctConfigText -replace '(?m)^(\s*sm_bot_ct_tactics_initial_hold\s+")22\.0("\s*)$', '${1}70.0${2}'
        $ctConfigText = $ctConfigText -replace '(?m)^(\s*sm_bot_ct_tactics_initial_hold\s+")40\.0("\s*)$', '${1}70.0${2}'
        $ctConfigText = $ctConfigText -replace '(?m)^(\s*sm_bot_ct_tactics_retake_stage\s+")4\.0("\s*)$', '${1}6.0${2}'
        $ctConfigText = $ctConfigText -replace '(?m)^(\s*sm_bot_ct_tactics_retake_commit\s+")8\.0("\s*)$', '${1}14.0${2}'
        [System.IO.File]::WriteAllText($ctConfig, $ctConfigText, [System.Text.UTF8Encoding]::new($false))
    }

    # This legacy source writes profile fields directly, but the bundled cfg
    # still advertises the old instant-reaction values. Keep that reference
    # aligned without touching unrelated or administrator-customized entries.
    if (Test-Path -LiteralPath $profileConfig) {
        $profileText = Get-Content -LiteralPath $profileConfig -Raw
        $profileText = $profileText -replace '(?m)^(\s*"look_angle_max_accel"\s*)"(?:100000|7000)\.0"', '${1}"6750.0"'
        $profileText = $profileText -replace '(?m)^(\s*"reaction_time"\s*)"0\.0"', '${1}"0.20"'
        $profileText = $profileText -replace '(?m)^(\s*"look_angle_max_accel_min"\s*)"(?:3500|4000)\.0"', '${1}"4500.0"'
        $profileText = $profileText -replace '(?m)^(\s*"look_angle_max_accel_max"\s*)"(?:6000|7000)\.0"', '${1}"6500.0"'
        $profileText = $profileText -replace '(?m)^(\s*"reaction_time_min"\s*)"(?:0\.165|0\.23)"', '${1}"0.22"'
        $profileText = $profileText -replace '(?m)^(\s*"reaction_time_max"\s*)"(?:0\.325|0\.38)"', '${1}"0.30"'
        if ($profileText -ne (Get-Content -LiteralPath $profileConfig -Raw)) {
            [System.IO.File]::WriteAllText($profileConfig, $profileText, [System.Text.UTF8Encoding]::new($false))
        }
    }
}
finally {
    if (Test-Path -LiteralPath $buildDir) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
}

Write-Host "Installed reversible BetterBots CT and T tactical directors."
Write-Host "Live disable: sm_bot_ct_tactics_enable 0 / sm_bot_t_tactics_enable 0"
Write-Host "Full rollback (server stopped): .\rollback_ct_tactics.ps1 -ServerDir `"$ServerDir`""
