param(
    [Parameter(Mandatory)][string]$OverpassRelief,
    [Parameter(Mandatory)][string]$OverpassBefore,
    [Parameter(Mandatory)][string]$OverpassRetake,
    [Parameter(Mandatory)][string]$MirageBefore,
    [Parameter(Mandatory)][string]$MirageAfter,
    [Parameter(Mandatory)][string]$NukeBefore,
    [Parameter(Mandatory)][string]$NukeAfter,
    [Parameter(Mandatory)][string]$NukeOpening
)
$ErrorActionPreference = 'Stop'
function Require([string]$Path, [string[]]$Needed, [string]$Forbidden = '^REFINE_FAIL|Exception reported|Engine Error') {
    $lines = Get-Content -LiteralPath $Path
    if ($lines -match $Forbidden) { throw "Invalid diagnostic output: $Path" }
    foreach ($pattern in $Needed) {
        if (!($lines -match $pattern)) { throw "Missing validation: $pattern (log: $Path)" }
    }
}
Require $OverpassRelief @('^REFINE_RELIEF changed=1 weak_anchor=1 contact=1$', '^REFINE_PASS map=de_overpass ')
Require $OverpassBefore @('^LIVE_CASE_RESULT map=de_overpass site=A actual=0 outcome=defused winner=3 reason=7 ', '^LIVE_CASE_RESULT map=de_overpass site=B actual=1 outcome=defused winner=3 reason=7 ') 'CT retake lane|Exception reported|Engine Error'
Require $OverpassRetake @('CT retake lane (BackofA|UnderA|Stairs) site=0', 'CT retake lane (Construction|Bridge|Water) site=1',
    '^LIVE_CASE_RESULT map=de_overpass site=A actual=0 outcome=defused winner=3 reason=7 ', '^LIVE_CASE_RESULT map=de_overpass site=B actual=1 outcome=defused winner=3 reason=7 ')
Require $MirageBefore @('^REFINE_CROSSFIRE links=\d+ partner_responded=0$', '^REFINE_FAIL map=de_mirage ') '^REFINE_PASS|Exception reported|Engine Error'
Require $MirageAfter @('Mirage crossfire site=[01]', '^REFINE_CROSSFIRE links=[1-9]\d* partner_responded=1$', '^REFINE_PASS map=de_mirage ')
Require $NukeBefore @('^REFINE_NUKE_REPLACEMENT filled=0 ', '^REFINE_NUKE_WAYPOINT issued=0$', '^REFINE_FAIL map=de_nuke ') '^REFINE_PASS|Exception reported|Engine Error'
Require $NukeAfter @('^REFINE_NUKE_REPLACEMENT filled=1 upper_kept=1$', '^REFINE_NUKE_WAYPOINT issued=1$', '^REFINE_NUKE_RESUME original=1$', '^REFINE_PASS map=de_nuke ')
Require $NukeOpening @('^CT_SITE_DISTRIBUTION map=de_nuke round=1 calibration=3 .* target_in=[1-9],[1-9]$',
    '^CT_SITE_OCCUPANCY map=de_nuke round=1 samples=52 occupied=[1-9]\d*,[1-9]\d* .* final_mask=3$', '^CT_SITE_SURVEY_DONE$')
'CT_MAP_REFINEMENT_PASS overpass_relief=1 overpass_live_sites=2 mirage_partner=1 nuke_backfill=1 nuke_detour=1 nuke_opening_both=1'
