#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "LAN Economy Runtime Probe",
	author = "Codex",
	description = "Validates live economy cvars and SourceMod weapon prices",
	version = "1.0.0"
};

public void OnPluginStart()
{
	RegServerCmd("sm_economy_runtime_probe", Command_RuntimeProbe);
	RegServerCmd("sm_economy_kill_probe", Command_KillProbe);
	HookEvent("player_death", Event_ProbePlayerDeath, EventHookMode_Post);
}

public void Event_ProbePlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	char weapon[32];
	event.GetString("weapon", weapon, sizeof(weapon));
	PrintToServer("LAN_ECONOMY_KILL_PROBE_EVENT|weapon=%s|attacker=%d|victim=%d",
		weapon, event.GetInt("attacker"), event.GetInt("userid"));
}

public Action Command_KillProbe(int args)
{
	char weapon[24];
	GetCmdArg(1, weapon, sizeof(weapon));
	int expected;
	bool cs2 = FindConVar("sm_lan_economy_ruleset").IntValue == 1;
	if (StrEqual(weapon, "cz75a"))
		expected = cs2 ? 300 : 100;
	else if (StrEqual(weapon, "xm1014"))
		expected = cs2 ? 600 : 900;
	else if (StrEqual(weapon, "taser"))
		expected = cs2 ? 100 : 0;
	else
		SetFailState("Unsupported kill probe weapon: %s", weapon);

	int attacker, victim, terrorists;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsFakeClient(client))
			continue;
		if (GetClientTeam(client) == CS_TEAM_CT && attacker == 0)
			attacker = client;
		else if (GetClientTeam(client) == CS_TEAM_T)
		{
			terrorists++;
			if (victim == 0)
				victim = client;
		}
	}
	if (attacker == 0 || victim == 0 || terrorists < 2)
		SetFailState("Kill probe requires one CT bot and at least two T bots");

	CS_RespawnPlayer(attacker);
	CS_RespawnPlayer(victim);
	char className[32];
	Format(className, sizeof(className), "weapon_%s", weapon);
	RemoveOwnedClass(attacker, className);
	int entity = GivePlayerItem(attacker, className);
	if (entity <= MaxClients)
		SetFailState("Could not give %s to kill probe attacker", className);
	EquipPlayerWeapon(attacker, entity);
	SetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon", entity);
	SetEntProp(attacker, Prop_Send, "m_iAccount", 1000);
	SDKHooks_TakeDamage(victim, attacker, attacker, 500.0, DMG_BULLET, entity);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(attacker));
	pack.WriteCell(1000 + expected);
	pack.WriteString(weapon);
	CreateTimer(0.2, Timer_CheckKillAward, pack, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

void RemoveOwnedClass(int client, const char[] className)
{
	char entityClass[64];
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_hOwnerEntity") ||
			GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") != client)
		{
			continue;
		}
		GetEntityClassname(entity, entityClass, sizeof(entityClass));
		if (!StrEqual(entityClass, className, false))
			continue;
		RemovePlayerItem(client, entity);
		AcceptEntityInput(entity, "Kill");
	}
}

public Action Timer_CheckKillAward(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int expected = pack.ReadCell();
	char weapon[24];
	pack.ReadString(weapon, sizeof(weapon));
	delete pack;
	if (client == 0)
		SetFailState("Kill probe attacker disconnected");
	AssertEqual(weapon, GetEntProp(client, Prop_Send, "m_iAccount"), expected);
	PrintToServer("LAN_ECONOMY_KILL_PROBE_OK|weapon=%s|balance=%d", weapon, expected);
	return Plugin_Stop;
}

public Action Command_RuntimeProbe(int args)
{
	ConVar ruleset = FindConVar("sm_lan_economy_ruleset");
	ConVar bombAward = FindConVar("cash_team_planted_bomb_but_defused");
	if (ruleset == null || bombAward == null)
		SetFailState("Economy policy cvars are unavailable");
	bool cs2 = ruleset.IntValue == 1;
	AssertEqual("planted-but-defused award", bombAward.IntValue, cs2 ? 600 : 800);

	int client;
	for (int candidate = 1; candidate <= MaxClients; candidate++)
	{
		if (IsClientInGame(candidate))
		{
			client = candidate;
			break;
		}
	}
	if (client == 0)
		SetFailState("Runtime price probe requires one connected player or bot");

	AssertPrice(client, "FAMAS", CSWeapon_FAMAS, cs2 ? 1950 : 2050);
	AssertPrice(client, "M4A4", CSWeapon_M4A1, cs2 ? 2900 : 3100);
	AssertPrice(client, "MP7", CSWeapon_MP7, cs2 ? 1400 : 1500);
	AssertPrice(client, "MP5-SD", CSWeapon_MP5NAVY, cs2 ? 1400 : 1500);
	AssertPrice(client, "Bizon", CSWeapon_BIZON, cs2 ? 1300 : 1400);
	AssertPrice(client, "incendiary", CSWeapon_INCGRENADE, cs2 ? 500 : 600);
	PrintToServer("LAN_ECONOMY_RUNTIME_PROBE_OK|ruleset=%d", ruleset.IntValue);
	return Plugin_Handled;
}

void AssertPrice(int client, const char[] item, CSWeaponID weapon, int expected)
{
	AssertEqual(item, CS_GetWeaponPrice(client, weapon), expected);
}

void AssertEqual(const char[] behavior, int actual, int expected)
{
	if (actual != expected)
		SetFailState("%s: expected %d, got %d", behavior, expected, actual);
}
