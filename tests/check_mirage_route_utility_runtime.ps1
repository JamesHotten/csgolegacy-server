param([Parameter(Mandatory)] [string]$Log)
$ErrorActionPreference = 'Stop'
$lines = Get-Content -LiteralPath $Log
if (!($lines -match '^MIRAGE_UTILITY_ROUTES site=A carrier=0 a=[1-9]\d* b=0 mid=0$') -or
    !($lines -match '^MIRAGE_UTILITY_ROUTES site=B carrier=0 a=0 b=[1-9]\d* mid=[1-9]\d*$') -or
    !($lines -match '^MIRAGE_UTILITY assigned bot=\d+ lane=3 replay=.*Window Smoke') -or
    !($lines -match '^MIRAGE_UTILITY timeout bot=\d+ lane=3$') -or
    !($lines -match '^LIVE_CASE_RESULT map=de_mirage site=A .*outcome=defused .*utility=1$') -or
    !($lines -match '^LIVE_CASE_RESULT map=de_mirage site=B .*outcome=defused .*utility=1$')) {
    throw 'Missing Mirage direct, mid or real objective/utility evidence.'
}
if ($lines -match '^MIRAGE_UTILITY assigned bot=\d+ lane=[12] replay=.*Window Smoke') {
    throw 'A non-mid lane received a window smoke.'
}
$lines -match '^MIRAGE_UTILITY timeout'
'MIRAGE_ROUTE_UTILITY_PASS'
