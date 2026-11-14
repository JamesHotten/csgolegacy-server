param(
    [Parameter(Mandatory)][string]$IsolatedServerDir,
    [Parameter(Mandatory)][string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
$target = (Resolve-Path -LiteralPath $IsolatedServerDir).ProviderPath
if ((Split-Path -Leaf $target) -notmatch 'test|isolated') { throw 'Use a dedicated isolated server directory.' }
if (![uri]::new($BaseUrl).IsLoopback) { throw 'The resource endpoint must be a loopback address.' }
$mods = Join-Path $PSScriptRoot '..\mods'
$sm = Join-Path $target 'csgo\addons\sourcemod'
$inputs = @{
    EquipmentSource = Join-Path $mods 'include\bot_equipment_policy.inc'
    RosterSource = Join-Path $mods 'include\bot_team_rosters.inc'
    PurchaseSource = Join-Path $mods 'include\bot_purchase_policy.inc'
    RecorderSource = Join-Path $mods 'bot_tactical_experience.sp'
    SideStatsSource = Join-Path $mods 'bot_side_win_stats.sp'
    AnglesSource = Join-Path $mods 'include\bot_tactical_angles.inc'
    InstallerSource = Join-Path $mods 'install_ct_tactics.ps1'
    CTDirectorSource = Join-Path $mods 'bot_ct_tactics.sp'
    TDirectorSource = Join-Path $mods 'bot_t_tactics.sp'
    CoreSource = Join-Path $sm 'scripting\bot_stuff.sp'
    NavDirectory = Join-Path $target 'csgo\maps'
    DatabasePath = Join-Path $sm 'data\sqlite\bot_tactical_experience.sq3'
    ServerDir = $target
    BaseUrl = $BaseUrl
}
$count = 0
foreach ($check in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test_*.ps1' -File | Sort-Object Name) {
    $argsForCheck = @{}
    foreach ($name in (Get-Command $check.FullName).Parameters.Keys) {
        if ($inputs.ContainsKey($name)) { $argsForCheck[$name] = $inputs[$name] }
    }
    & $check.FullName @argsForCheck
    if (!$?) { throw "Failed: $($check.Name)" }
    $count++
}
Write-Output "ISOLATED_REGRESSION_PASS checks=$count"
