param(
    [Parameter(Mandatory)] [string]$Baseline,
    [Parameter(Mandatory)] [string]$Candidate
)
$ErrorActionPreference = 'Stop'
function Read-Pairs([string]$Path) {
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^CROSSFIRE_GEOMETRY map=(de_\w+) site=([01]) phase=t_postplant pairs=(\d+) overlaps=(\d+) support=(\d+)$') {
            [pscustomobject]@{ Key="$($Matches[1])/$($Matches[2])"; Overlap=[int]$Matches[4]; Support=[int]$Matches[5] }
        }
    }
}
$old = @(Read-Pairs $Baseline)
$new = @(Read-Pairs $Candidate)
if (!$old.Count -or $old.Count -ne $new.Count -or (Compare-Object ($old.Key | Sort-Object) ($new.Key | Sort-Object))) {
    throw 'The old and new geometry runs did not cover the same post-plant cases.'
}
$before = ($old | Measure-Object Overlap -Sum).Sum
$after = ($new | Measure-Object Overlap -Sum).Sum
$oldSupport = ($old | Measure-Object Support -Sum).Sum
$support = ($new | Measure-Object Support -Sum).Sum
if ($after -gt $before -or $support -lt $oldSupport -or $support -lt 1) {
    throw "Post-plant coverage regressed: overlaps $before -> $after, support $oldSupport -> $support"
}
"CROSSFIRE_GEOMETRY_PASS cases=$($new.Count) overlaps_before=$before overlaps_after=$after support_before=$oldSupport support_after=$support"
