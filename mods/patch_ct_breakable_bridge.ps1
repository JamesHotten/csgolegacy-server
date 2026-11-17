function Add-CTBreakableBridge {
    param([Parameter(Mandatory)][string]$Source)
    if ($Source.Contains('// BEGIN CT_ROUTE_BREAKABLE_REPORT')) { return $Source }
    $newline = if ($Source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $anchors = [ordered]@{
        'native bool BotCTTactics_GetOrder(int client, float goal[3], int &routeType);' = 'native void BotCTTactics_ReportBreakable(int client);'
        'MarkNativeAsOptional("BotCTTactics_GetOrder");' = '    MarkNativeAsOptional("BotCTTactics_ReportBreakable");'
        'DHookGetParamString(hParams, 1, szDesc, sizeof(szDesc));' = (@(
            '    // BEGIN CT_ROUTE_BREAKABLE_REPORT',
            '    if (StrEqual(szDesc, "Breakable") && GetFeatureStatus(FeatureType_Native, "BotCTTactics_ReportBreakable") == FeatureStatus_Available)',
            '        BotCTTactics_ReportBreakable(iClient);',
            '    // END CT_ROUTE_BREAKABLE_REPORT'
        ) -join $newline)
    }
    foreach ($anchor in $anchors.Keys) {
        $first = $Source.IndexOf($anchor, [StringComparison]::Ordinal)
        if ($first -lt 0 -or $Source.IndexOf($anchor, $first + $anchor.Length, [StringComparison]::Ordinal) -ge 0) {
            throw "Expected one BetterBots bridge anchor: $anchor"
        }
        $Source = $Source.Insert($first + $anchor.Length, $newline + $anchors[$anchor])
    }
    return $Source
}
