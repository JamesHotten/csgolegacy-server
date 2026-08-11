#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLAYER_INFO_LEN 344
#define PLAYER_INFO_XUID 8
#define PLAYER_INFO_STEAMID 148
#define PLAYER_INFO_ACCOUNTID 184

bool g_bIdentityPatched[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "LAN Player Scoreboard Identity",
	author = "Codex",
	description = "Adds a temporary identity for STEAM_ID_LAN humans so their scoreboard row can render",
	version = "1.0.0"
};

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
		CreateTimer(1.0, Timer_PatchLanIdentity, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	g_bIdentityPatched[client] = false;
}

public Action Timer_PatchLanIdentity(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client == 0 || !IsClientInGame(client) || IsFakeClient(client) || g_bIdentityPatched[client])
		return Plugin_Stop;

	char authId[32];
	if (GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId)) &&
		!StrEqual(authId, "STEAM_ID_LAN", false))
	{
		return Plugin_Stop;
	}

	int table = FindStringTable("userinfo");
	if (table == INVALID_STRING_TABLE)
		return Plugin_Stop;

	char userInfo[PLAYER_INFO_LEN];
	if (!GetStringTableData(table, client - 1, userInfo, sizeof(userInfo)))
		return Plugin_Stop;

	int accountId = 1900000000 + client;
	int steamIdHighNetworkOrder = 16781313;

	userInfo[PLAYER_INFO_XUID] = steamIdHighNetworkOrder;
	userInfo[PLAYER_INFO_XUID + 1] = steamIdHighNetworkOrder >> 8;
	userInfo[PLAYER_INFO_XUID + 2] = steamIdHighNetworkOrder >> 16;
	userInfo[PLAYER_INFO_XUID + 3] = steamIdHighNetworkOrder >> 24;
	userInfo[PLAYER_INFO_XUID + 7] = accountId;
	userInfo[PLAYER_INFO_XUID + 6] = accountId >> 8;
	userInfo[PLAYER_INFO_XUID + 5] = accountId >> 16;
	userInfo[PLAYER_INFO_XUID + 4] = accountId >> 24;

	Format(userInfo[PLAYER_INFO_STEAMID], 33, "STEAM_1:%d:%d", accountId & 1, accountId / 2);
	userInfo[PLAYER_INFO_ACCOUNTID] = accountId;
	userInfo[PLAYER_INFO_ACCOUNTID + 1] = accountId >> 8;
	userInfo[PLAYER_INFO_ACCOUNTID + 2] = accountId >> 16;
	userInfo[PLAYER_INFO_ACCOUNTID + 3] = accountId >> 24;

	bool wasLocked = LockStringTables(false);
	SetStringTableData(table, client - 1, userInfo, sizeof(userInfo));
	LockStringTables(wasLocked);

	g_bIdentityPatched[client] = true;
	return Plugin_Stop;
}
