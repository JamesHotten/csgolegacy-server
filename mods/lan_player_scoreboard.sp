#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLAYER_INFO_LEN 344
#define PLAYER_INFO_XUID 8
#define PLAYER_INFO_STEAMID 148
#define PLAYER_INFO_ACCOUNTID 184

#define SCORE_FIELD_COUNT 5
#define SCORE_KILLS 0
#define SCORE_DEATHS 1
#define SCORE_ASSISTS 2
#define SCORE_MVPS 3
#define SCORE_CONTRIBUTION 4

bool g_bIdentityPatched[MAXPLAYERS + 1];
char g_sIdentityKey[MAXPLAYERS + 1][128];
int g_iAccountId[MAXPLAYERS + 1];
StringMap g_mScoreCache;

public Plugin myinfo =
{
	name = "LAN Player Scoreboard Identity",
	author = "Codex",
	description = "Adds stable LAN identities and restores same-match scoreboard stats after reconnect",
	version = "1.1.0"
};

public void OnPluginStart()
{
	g_mScoreCache = new StringMap();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
			PrepareClient(client);
	}
}

public void OnMapStart()
{
	g_mScoreCache.Clear();
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
		PrepareClient(client);
}

void PrepareClient(int client)
{
	char baseIdentity[128];
	BuildBaseIdentityKey(client, baseIdentity, sizeof(baseIdentity));
	ResolveIdentityKey(client, baseIdentity, g_sIdentityKey[client], sizeof(g_sIdentityKey[]));
	CreateTimer(1.0, Timer_PatchLanIdentity, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	if (g_bIdentityPatched[client] && g_sIdentityKey[client][0] != '\0' && IsClientInGame(client))
	{
		int score[SCORE_FIELD_COUNT];
		score[SCORE_KILLS] = GetClientFrags(client);
		score[SCORE_DEATHS] = GetClientDeaths(client);
		score[SCORE_ASSISTS] = CS_GetClientAssists(client);
		score[SCORE_MVPS] = CS_GetMVPCount(client);
		score[SCORE_CONTRIBUTION] = CS_GetClientContributionScore(client);
		g_mScoreCache.SetArray(g_sIdentityKey[client], score, sizeof(score));
	}

	g_bIdentityPatched[client] = false;
	g_sIdentityKey[client][0] = '\0';
	g_iAccountId[client] = 0;
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

	if (g_sIdentityKey[client][0] == '\0')
	{
		char baseIdentity[128];
		BuildBaseIdentityKey(client, baseIdentity, sizeof(baseIdentity));
		ResolveIdentityKey(client, baseIdentity, g_sIdentityKey[client], sizeof(g_sIdentityKey[]));
	}

	// Stable across reconnects while remaining unique among connected players.
	int accountId = BuildUniqueAccountId(client, g_sIdentityKey[client]);
	g_iAccountId[client] = accountId;
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
	RestoreScore(client);
	return Plugin_Stop;
}

void BuildBaseIdentityKey(int client, char[] key, int maxLength)
{
	char ip[64];
	char name[MAX_NAME_LENGTH];
	GetClientIP(client, ip, sizeof(ip), true);
	GetClientName(client, name, sizeof(name));
	Format(key, maxLength, "%s|%s", ip, name);
}

void ResolveIdentityKey(int client, const char[] baseIdentity, char[] identity, int maxLength)
{
	char candidate[128];
	char firstAvailable[128];
	int cachedScore[SCORE_FIELD_COUNT];
	firstAvailable[0] = '\0';

	for (int suffix = 0; suffix <= MaxClients; suffix++)
	{
		if (suffix == 0)
			strcopy(candidate, sizeof(candidate), baseIdentity);
		else
			Format(candidate, sizeof(candidate), "%s#%d", baseIdentity, suffix);

		if (IsIdentityKeyActive(client, candidate))
			continue;

		if (firstAvailable[0] == '\0')
			strcopy(firstAvailable, sizeof(firstAvailable), candidate);

		if (g_mScoreCache.GetArray(candidate, cachedScore, sizeof(cachedScore)))
		{
			strcopy(identity, maxLength, candidate);
			return;
		}
	}

	strcopy(identity, maxLength, firstAvailable);
}

bool IsIdentityKeyActive(int client, const char[] identity)
{
	for (int other = 1; other <= MaxClients; other++)
	{
		if (other != client && g_sIdentityKey[other][0] != '\0' && StrEqual(g_sIdentityKey[other], identity))
			return true;
	}

	return false;
}

int BuildUniqueAccountId(int client, const char[] identity)
{
	char saltedIdentity[160];
	for (int salt = 0; salt <= MaxClients; salt++)
	{
		if (salt == 0)
			strcopy(saltedIdentity, sizeof(saltedIdentity), identity);
		else
			Format(saltedIdentity, sizeof(saltedIdentity), "%s|account:%d", identity, salt);

		int accountId = BuildAccountId(saltedIdentity);
		if (!IsAccountIdActive(client, accountId))
			return accountId;
	}

	for (int accountId = 1900000001; accountId <= 1900000000 + MaxClients; accountId++)
	{
		if (!IsAccountIdActive(client, accountId))
			return accountId;
	}

	return 1900000000 + client;
}

bool IsAccountIdActive(int client, int accountId)
{
	for (int other = 1; other <= MaxClients; other++)
	{
		if (other != client && g_iAccountId[other] == accountId)
			return true;
	}

	return false;
}

int BuildAccountId(const char[] key)
{
	int hash = 5381;
	for (int i = 0; key[i] != '\0'; i++)
		hash = ((hash << 5) + hash) ^ key[i];

	hash &= 0x07FFFFFF;
	return 1900000000 + (hash % 200000000);
}

void RestoreScore(int client)
{
	int score[SCORE_FIELD_COUNT];
	if (!g_mScoreCache.GetArray(g_sIdentityKey[client], score, sizeof(score)))
		return;

	SetEntProp(client, Prop_Data, "m_iFrags", score[SCORE_KILLS]);
	SetEntProp(client, Prop_Data, "m_iDeaths", score[SCORE_DEATHS]);
	CS_SetClientAssists(client, score[SCORE_ASSISTS]);
	CS_SetMVPCount(client, score[SCORE_MVPS]);
	CS_SetClientContributionScore(client, score[SCORE_CONTRIBUTION]);
}
