function Add-CTRetakeTravelBridge {
    param([Parameter(Mandatory)][string]$Source)
    if ($Source.Contains('// CT_RETAKE_APPROACH_DRIVE')) { return $Source }
    $newline = if ($Source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $signature='native void BotCTTactics_ReportRouteDrive(int client, bool driving);'
    $drive='BotCTTactics_ReportRouteDrive(iClient, bRecoveryDrive);'
    $changed=(@(
        'BotCTTactics_ReportRouteDrive(iClient, bRecoveryDrive, // CT_RETAKE_APPROACH_DRIVE',
        '                bRecoveryMayDrive && g_bBombPlanted && GetTask(iClient) == DEFUSE_BOMB',
        '                && !GetEntProp(iClient, Prop_Send, "m_bIsDefusing"));'
    ) -join $newline)
    $pattern='(?m)^(\s*)bool bRecoveryDrive = bTacticalTravel(.+\r?\n(?:.*\r?\n)*?\s*&& \(GetTask\(iClient\) != PLANT_BOMB \|\| bManagedPlantApproach\))\r?\n\s*&& GetTask\(iClient\) != DEFUSE_BOMB;'
    $matches=[regex]::Matches($Source,$pattern)
    if($matches.Count -ne 1){throw 'Expected one tactical route-drive policy'}
    $m=$matches[0]
    $drivePolicy=$m.Groups[1].Value+'bool bRecoveryMayDrive = bTacticalTravel'+$m.Groups[2].Value+';'+$newline+
        $m.Groups[1].Value+'bool bRecoveryDrive = bRecoveryMayDrive && GetTask(iClient) != DEFUSE_BOMB;'
    foreach($anchor in $signature,$drive){
        if([regex]::Matches($Source,[regex]::Escape($anchor)).Count -ne 1){throw "Expected one route bridge anchor: $anchor"}
    }
    return $Source.Replace($m.Value,$drivePolicy).Replace($signature,
        'native void BotCTTactics_ReportRouteDrive(int client, bool driving, bool defuseApproach = false);').Replace($drive,$changed)
}
