param(
    [string]$CoreSource,
    [string]$GearFixtureDatabase,
    [ValidateSet('de_nuke','de_overpass')][string]$FixtureMap = 'de_nuke',
    [ValidateSet(0,1)][int]$ExpectedKit = 1
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$recorder = Get-Content -LiteralPath (Join-Path $root 'mods/bot_tactical_experience.sp') -Raw
$policy = Get-Content -LiteralPath (Join-Path $root 'mods/include/bot_equipment_policy.inc') -Raw
$installer = Get-Content -LiteralPath (Join-Path $root 'mods/install_ct_tactics.ps1') -Raw
foreach ($token in @('MarkNativeAsOptional("BotEquipment_GetBuyPlan")', 'HookEvent("round_freeze_end"',
    'CREATE TABLE IF NOT EXISTS opening_gear', 'CREATE TABLE IF NOT EXISTS retake_outcomes',
    'SAVEPOINT opening_telemetry', 'ROLLBACK TO opening_telemetry', 'bomb_begindefuse', 'bomb_defused',
    'weapon_p90', 'weapon_xm1014', 'weapon_mp5sd', 'weapon_m4a1_silencer')) {
    if (!$recorder.Contains($token)) { throw "Missing gear telemetry wiring: $token" }
}
if ($recorder -match 'CS_GetWeaponPrice|FakeClientCommand|BotEquipment_BeginRound|SetEntProp\(') {
    throw 'Recorder must not classify by price or mutate purchases and equipment.'
}
if (!$policy.Contains('return g_BotEquipmentPlanLabel[team];') -or
    !$installer.Contains('CreateNative("BotEquipment_GetBuyPlan", Native_BotEquipment_GetBuyPlan);')) {
    throw 'Purchase-plan read-only native is not installed.'
}
if ($CoreSource -and ([regex]::Matches((Get-Content -LiteralPath $CoreSource -Raw), 'CreateNative\("BotEquipment_GetBuyPlan"').Count -ne 1)) {
    throw 'Expected exactly one installed plan telemetry native.'
}
if ($GearFixtureDatabase) {
    $sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
    $query = @"
WITH latest AS (SELECT max(id) id FROM rounds WHERE map='$FixtureMap')
SELECT count(*) FROM latest l
JOIN opening_gear c ON c.round_id=l.id AND c.team=3
JOIN opening_gear t ON t.round_id=l.id AND t.team=2
JOIN retake_outcomes o ON o.round_id=l.id
WHERE c.purchase_plan='reset' AND t.purchase_plan='reset'
  AND c.players=5 AND c.bots=5 AND c.rifles=1 AND c.snipers=1 AND c.smgs=1 AND c.shotguns=1
  AND c.pistols_only=1 AND c.armored=4 AND c.helmets=3 AND c.kits=$ExpectedKit
  AND c.utility=3 AND c.smokes=1 AND c.flashes=2
  AND t.rifles=2 AND t.smgs=1 AND t.pistols_only=2 AND t.kits=0
  AND o.stage_ms IS NULL AND o.commit_ms>=o.plant_ms AND o.commit_ms-o.plant_ms<500
  AND o.defuse_begin_ms>=o.commit_ms AND o.kit_at_defuse=$ExpectedKit AND o.defused=1;
"@
    $sqliteQuery = $query -replace '\r?\n', ' '
    $actual = & $sqlite -readonly -noheader $GearFixtureDatabase $sqliteQuery
    if ($LASTEXITCODE -ne 0 -or [string]$actual -ne '1') { throw "Fixture equipment or retake telemetry differs on $FixtureMap." }
    Write-Host "Verified $FixtureMap equipment and retake telemetry (kit=$ExpectedKit)."
}
Write-Host 'Opening buy-plan and actual equipment telemetry checks passed.'
