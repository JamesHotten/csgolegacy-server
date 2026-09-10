#if defined _lan_economy_policy_included
	#endinput
#endif
#define _lan_economy_policy_included

enum LanEconomyRuleset
{
	LanEconomy_CsgoLegacy = 0,
	LanEconomy_Cs2Current
};

int LanEconomy_GetBombDefusedTeamAward(LanEconomyRuleset ruleset)
{
	return ruleset == LanEconomy_Cs2Current ? 600 : 800;
}

bool LanEconomy_GetKillAward(LanEconomyRuleset ruleset, const char[] weapon, int &award)
{
	if (StrEqual(weapon, "cz75a", false))
	{
		award = ruleset == LanEconomy_Cs2Current ? 300 : 100;
		return true;
	}
	if (StrEqual(weapon, "xm1014", false))
	{
		award = ruleset == LanEconomy_Cs2Current ? 600 : 900;
		return true;
	}
	if (StrEqual(weapon, "taser", false))
	{
		award = ruleset == LanEconomy_Cs2Current ? 100 : 0;
		return true;
	}
	return false;
}

int LanEconomy_GetLegacyEngineKillAward(const char[] weapon)
{
	int award;
	return LanEconomy_GetKillAward(LanEconomy_CsgoLegacy, weapon, award) ? award : 0;
}

bool LanEconomy_GetWeaponPrice(LanEconomyRuleset ruleset, const char[] weapon, int &price)
{
	bool cs2 = ruleset == LanEconomy_Cs2Current;
	if (LanEconomy_WeaponMatches(weapon, "famas"))
		price = cs2 ? 1950 : 2050;
	else if (LanEconomy_WeaponMatches(weapon, "m4a1"))
		price = cs2 ? 2900 : 3100;
	else if (LanEconomy_WeaponMatches(weapon, "mp7"))
		price = cs2 ? 1400 : 1500;
	else if (LanEconomy_WeaponMatches(weapon, "mp5sd"))
		price = cs2 ? 1400 : 1500;
	else if (LanEconomy_WeaponMatches(weapon, "bizon"))
		price = cs2 ? 1300 : 1400;
	else if (LanEconomy_WeaponMatches(weapon, "incgrenade"))
		price = cs2 ? 500 : 600;
	else
		return false;
	return true;
}

bool LanEconomy_WeaponMatches(const char[] weapon, const char[] shortName)
{
	if (StrEqual(weapon, shortName, false))
		return true;
	char className[32];
	Format(className, sizeof(className), "weapon_%s", shortName);
	return StrEqual(weapon, className, false);
}

void LanEconomy_NormalizeItem(const char[] input, char[] output, int outputLength)
{
	if (StrContains(input, "weapon_", false) == 0)
		strcopy(output, outputLength, input[7]);
	else if (StrContains(input, "item_", false) == 0)
		strcopy(output, outputLength, input[5]);
	else
		strcopy(output, outputLength, input);

	// CS_OnBuyCommand uses buy aliases while item_purchase uses entity names.
	// Canonicalizing both sides keeps armor/defuser purchases refundable.
	if (StrEqual(output, "vest", false))
		strcopy(output, outputLength, "kevlar");
	else if (StrEqual(output, "vesthelm", false))
		strcopy(output, outputLength, "assaultsuit");
	else if (StrEqual(output, "cutters", false))
		strcopy(output, outputLength, "defuser");
	else if (StrEqual(output, "mp5navy", false))
		strcopy(output, outputLength, "mp5sd");
}

bool LanEconomy_CanRefund(LanEconomyRuleset ruleset, bool inBuyZone,
	bool withinBuyTime, bool sameRound, bool ownsItem, bool itemUsed)
{
	return ruleset == LanEconomy_Cs2Current && inBuyZone && withinBuyTime &&
		sameRound && ownsItem && !itemUsed;
}

int LanEconomy_GetMaxRounds(LanEconomyRuleset ruleset)
{
	return ruleset == LanEconomy_Cs2Current ? 24 : 30;
}

int LanEconomy_GetOvertimeEnabled()
{
	return 1;
}

int LanEconomy_GetOvertimeMaxRounds()
{
	return 6;
}

int LanEconomy_GetOvertimeStartMoney()
{
	return 10000;
}
