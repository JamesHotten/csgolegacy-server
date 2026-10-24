param(
    [string]$CoreSource = 'D:\CSGOServer\server\csgo\addons\sourcemod\scripting\bot_stuff.sp',
    [string]$InstallerSource = "$PSScriptRoot\..\mods\install_ct_tactics.ps1"
)
$ErrorActionPreference = 'Stop'
$core = Get-Content -LiteralPath $CoreSource -Raw
$callback = [regex]::Match($core, '(?s)public MRESReturn CCSBot_CanSeeLooseBomb\(.*?\n\}').Value
if (-not $callback) { throw 'Native loose C4 callback not found; review the bridge migration.' }
if ($callback -match 'hReturn\.(Value|Set)' -or $callback.Contains('MRES_Override') -or
    $callback.Contains('MRES_Supercede')) {
    throw 'Unsafe: plugin can promote a native false loose-C4 result, allowing a null C4 pointer to reach native chatter.'
}
if (-not $callback.Contains('return MRES_Ignored;') -or $callback.Contains('BotMoveTo(') -or
    $callback.Contains('FindLooseBomb(')) {
    throw 'Native loose C4 perception must be side-effect-free; the CT director owns custom guard orders.'
}
$installer = Get-Content -LiteralPath $InstallerSource -Raw
if (-not $installer.Contains('BEGIN NATIVE_LOOSE_C4_RESULT_GUARD')) {
    throw 'Reinstallation can restore the old unsafe native-result override.'
}
Write-Host 'Native loose C4 result preservation and installer migration checks passed.'
