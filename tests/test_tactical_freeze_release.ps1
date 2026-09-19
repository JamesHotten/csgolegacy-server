param(
    [Parameter(Mandatory = $true)][string]$CTDirectorSource,
    [Parameter(Mandatory = $true)][string]$TDirectorSource
)

$ErrorActionPreference = 'Stop'

function Assert-ImmediateInitialPlan {
    param(
        [string]$Path,
        [string]$PlanCall,
        [string]$Side
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $freeze = [regex]::Match($text, '(?s)public void Event_FreezeEnd\(.*?\n\}').Value
    if ([string]::IsNullOrWhiteSpace($freeze)) {
        throw "$Side freeze-end handler was not found."
    }
    if ($freeze.Contains('CreateTimer(') -or -not $freeze.Contains($PlanCall)) {
        throw "$Side must publish its initial tactical orders synchronously at freeze end."
    }
}

Assert-ImmediateInitialPlan -Path $CTDirectorSource -PlanCall 'PlanInitialDefense();' -Side 'CT'
Assert-ImmediateInitialPlan -Path $TDirectorSource -PlanCall 'PlanInitialAttack();' -Side 'T'

Write-Host 'CT/T freeze-release planning regression checks passed.'
