#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include "../mods/lan_economy_policy.inc"

public Plugin myinfo =
{
	name = "LAN Economy Policy Self-Test",
	author = "Codex",
	description = "Executable public-policy regression tests",
	version = "1.0.0"
};

public void OnPluginStart()
{
	AssertEqual("CS:GO planted-but-defused team award",
		LanEconomy_GetBombDefusedTeamAward(LanEconomy_CsgoLegacy), 800);
	AssertEqual("CS2 planted-but-defused team award",
		LanEconomy_GetBombDefusedTeamAward(LanEconomy_Cs2Current), 600);
	AssertKillAward("CS:GO CZ75 kill award", LanEconomy_CsgoLegacy, "cz75a", 100);
	AssertKillAward("CS2 CZ75 kill award", LanEconomy_Cs2Current, "cz75a", 300);
	AssertKillAward("CS:GO XM1014 kill award", LanEconomy_CsgoLegacy, "xm1014", 900);
	AssertKillAward("CS2 XM1014 kill award", LanEconomy_Cs2Current, "xm1014", 600);
	AssertKillAward("CS:GO Zeus kill award", LanEconomy_CsgoLegacy, "taser", 0);
	AssertKillAward("CS2 Zeus kill award", LanEconomy_Cs2Current, "taser", 100);
	AssertEqual("CS:GO engine CZ75 baseline", LanEconomy_GetLegacyEngineKillAward("cz75a"), 100);
	AssertPrice("CS:GO FAMAS price", LanEconomy_CsgoLegacy, "weapon_famas", 2050);
	AssertPrice("CS2 FAMAS price", LanEconomy_Cs2Current, "weapon_famas", 1950);
	AssertPrice("CS:GO M4A4 price", LanEconomy_CsgoLegacy, "weapon_m4a1", 3100);
	AssertPrice("CS2 M4A4 price", LanEconomy_Cs2Current, "weapon_m4a1", 2900);
	AssertPrice("CS:GO MP7 price", LanEconomy_CsgoLegacy, "weapon_mp7", 1500);
	AssertPrice("CS2 MP7 price", LanEconomy_Cs2Current, "weapon_mp7", 1400);
	AssertPrice("CS:GO MP5-SD price", LanEconomy_CsgoLegacy, "weapon_mp5sd", 1500);
	AssertPrice("CS2 MP5-SD price", LanEconomy_Cs2Current, "weapon_mp5sd", 1400);
	AssertPrice("CS:GO Bizon price", LanEconomy_CsgoLegacy, "weapon_bizon", 1400);
	AssertPrice("CS2 Bizon price", LanEconomy_Cs2Current, "weapon_bizon", 1300);
	AssertPrice("CS:GO incendiary price", LanEconomy_CsgoLegacy, "weapon_incgrenade", 600);
	AssertPrice("CS2 incendiary price", LanEconomy_Cs2Current, "weapon_incgrenade", 500);
	AssertNormalizedItem("vest buy alias", "vest", "kevlar");
	AssertNormalizedItem("helmet buy alias", "vesthelm", "assaultsuit");
	AssertNormalizedItem("defuser buy alias", "cutters", "defuser");
	AssertNormalizedItem("MP5 entity alias", "weapon_mp5navy", "mp5sd");
	AssertRefundEligibility();
	AssertEqual("CS:GO maximum rounds", LanEconomy_GetMaxRounds(LanEconomy_CsgoLegacy), 30);
	AssertEqual("CS2 maximum rounds", LanEconomy_GetMaxRounds(LanEconomy_Cs2Current), 24);
	AssertEqual("CS:GO overtime disabled", LanEconomy_GetOvertimeEnabled(LanEconomy_CsgoLegacy), 0);
	AssertEqual("CS2 overtime enabled", LanEconomy_GetOvertimeEnabled(LanEconomy_Cs2Current), 1);
	AssertEqual("CS2 overtime rounds", LanEconomy_GetOvertimeMaxRounds(LanEconomy_Cs2Current), 6);
	AssertEqual("CS2 overtime start money", LanEconomy_GetOvertimeStartMoney(LanEconomy_Cs2Current), 10000);
	LogMessage("LAN_ECONOMY_POLICY_SELFTEST_OK");
}

void AssertNormalizedItem(const char[] behavior, const char[] input, const char[] expected)
{
	char actual[32];
	LanEconomy_NormalizeItem(input, actual, sizeof(actual));
	if (!StrEqual(actual, expected, false))
		SetFailState("%s: expected %s, got %s", behavior, expected, actual);
}

void AssertRefundEligibility()
{
	if (!LanEconomy_CanRefund(LanEconomy_Cs2Current, true, true, true, true, false))
		SetFailState("CS2 unused current-round purchase in the buy zone must be refundable");
	if (LanEconomy_CanRefund(LanEconomy_CsgoLegacy, true, true, true, true, false))
		SetFailState("CS:GO purchases must not be refundable");
	if (LanEconomy_CanRefund(LanEconomy_Cs2Current, false, true, true, true, false) ||
		LanEconomy_CanRefund(LanEconomy_Cs2Current, true, false, true, true, false) ||
		LanEconomy_CanRefund(LanEconomy_Cs2Current, true, true, false, true, false) ||
		LanEconomy_CanRefund(LanEconomy_Cs2Current, true, true, true, false, false) ||
		LanEconomy_CanRefund(LanEconomy_Cs2Current, true, true, true, true, true))
	{
		SetFailState("Refund eligibility accepted an out-of-zone, expired, stale, missing, or used purchase");
	}
}

void AssertPrice(const char[] behavior, LanEconomyRuleset ruleset,
	const char[] weapon, int expected)
{
	int actual;
	if (!LanEconomy_GetWeaponPrice(ruleset, weapon, actual))
		SetFailState("%s: policy did not provide a price", behavior);
	AssertEqual(behavior, actual, expected);
}

void AssertKillAward(const char[] behavior, LanEconomyRuleset ruleset,
	const char[] weapon, int expected)
{
	int actual;
	if (!LanEconomy_GetKillAward(ruleset, weapon, actual))
		SetFailState("%s: policy did not provide an award", behavior);
	AssertEqual(behavior, actual, expected);
}

void AssertEqual(const char[] behavior, int actual, int expected)
{
	if (actual != expected)
		SetFailState("%s: expected %d, got %d", behavior, expected, actual);
}
