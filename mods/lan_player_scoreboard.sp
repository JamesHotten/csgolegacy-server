#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

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
bool g_bLanClient[MAXPLAYERS + 1];
char g_sIdentityKey[MAXPLAYERS + 1][128];
int g_iAccountId[MAXPLAYERS + 1];
StringMap g_mScoreCache;
StringMap g_mCookieNames;
Database g_hLanPrefs;

public Plugin myinfo =
{
	name = "LAN Player Identity",
	author = "Codex",
	description = "Provides stable LAN identities for scoreboards and persistent MOD data",
	version = "2.0.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorLength)
{
	CreateNative("LANClientAuthId", Native_LANClientAuthId);
	CreateNative("LANSteamAccountID", Native_LANSteamAccountID);
	CreateNative("LanCk.Make", Native_LanCookieMake);
	CreateNative("LanCk.Get", Native_LanCookieGet);
	CreateNative("LanCk.Set", Native_LanCookieSet);
	CreateNative("LANCookieMake", Native_LegacyCookieMake);
	CreateNative("LANCookieRead", Native_LegacyCookieRead);
	CreateNative("LANCookieSave", Native_LegacyCookieSave);
	RegPluginLibrary("lan_player_identity");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_mScoreCache = new StringMap();
	g_mCookieNames = new StringMap();

	char error[256];
	g_hLanPrefs = SQLite_UseDatabase("lan_identity", error, sizeof(error));
	if (g_hLanPrefs == null)
		SetFailState("LAN identity database init failed: %s", error);

	if (!SQL_FastQuery(g_hLanPrefs,
		"CREATE TABLE IF NOT EXISTS lan_cookie_values (identity TEXT NOT NULL, cookie_name TEXT NOT NULL, value TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(identity, cookie_name));"))
	{
		SQL_GetError(g_hLanPrefs, error, sizeof(error));
		SetFailState("LAN identity cookie table init failed: %s", error);
	}

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
	if (g_sIdentityKey[client][0] != '\0' || !IsClientConnected(client) || IsFakeClient(client))
		return;

	char authId[64];
	if (!GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId)))
		return;

	if (!StrEqual(authId, "STEAM_ID_LAN", false))
		return;

	g_bLanClient[client] = true;
	char baseIdentity[128];
	BuildBaseIdentityKey(client, baseIdentity, sizeof(baseIdentity));
	ResolveIdentityKey(client, baseIdentity, g_sIdentityKey[client], sizeof(g_sIdentityKey[]));
	g_iAccountId[client] = BuildUniqueAccountId(client, g_sIdentityKey[client]);
	MigrateLegacyOwnerData(client);
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
	g_bLanClient[client] = false;
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
	int accountId = g_iAccountId[client];
	if (accountId == 0)
		accountId = BuildUniqueAccountId(client, g_sIdentityKey[client]);
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

bool EnsureLanIdentity(int client)
{
	if (client < 1 || client > MaxClients || !IsClientConnected(client) || IsFakeClient(client))
		return false;

	if (g_bLanClient[client])
		return true;

	PrepareClient(client);
	return g_bLanClient[client];
}

void GetSyntheticSteamId(int client, char[] authId, int maxLength)
{
	Format(authId, maxLength, "STEAM_1:%d:%d", g_iAccountId[client] & 1, g_iAccountId[client] / 2);
}

public any Native_LANClientAuthId(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	AuthIdType authType = GetNativeCell(2);
	int maxLength = GetNativeCell(4);
	bool validate = numParams >= 5 ? view_as<bool>(GetNativeCell(5)) : true;

	if (!EnsureLanIdentity(client))
	{
		char realAuth[64];
		bool found = GetClientAuthId(client, authType, realAuth, sizeof(realAuth), validate);
		if (found)
			SetNativeString(3, realAuth, maxLength, true);
		return found;
	}

	char syntheticAuth[32];
	GetSyntheticSteamId(client, syntheticAuth, sizeof(syntheticAuth));
	SetNativeString(3, syntheticAuth, maxLength, true);
	return true;
}

public any Native_LANSteamAccountID(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool validate = numParams >= 2 ? view_as<bool>(GetNativeCell(2)) : true;
	if (EnsureLanIdentity(client))
		return g_iAccountId[client];
	return GetSteamAccountID(client, validate);
}

public any Native_LanCookieMake(Handle plugin, int numParams)
{
	return RegisterLanCookie(1, 2, view_as<CookieAccess>(GetNativeCell(3)));
}

public any Native_LegacyCookieMake(Handle plugin, int numParams)
{
	return RegisterLanCookie(1, 2, view_as<CookieAccess>(GetNativeCell(3)));
}

int RegisterLanCookie(int nameParam, int descriptionParam, CookieAccess access)
{
	char name[COOKIE_MAX_NAME_LENGTH];
	char description[256];
	GetNativeString(nameParam, name, sizeof(name));
	GetNativeString(descriptionParam, description, sizeof(description));
	Cookie cookie = RegClientCookie(name, description, access);

	char handleKey[16];
	IntToString(view_as<int>(cookie), handleKey, sizeof(handleKey));
	g_mCookieNames.SetString(handleKey, name);
	return view_as<int>(cookie);
}

public any Native_LanCookieGet(Handle plugin, int numParams)
{
	ReadLanCookie(GetNativeCell(2), view_as<Cookie>(GetNativeCell(1)), 3, GetNativeCell(4));
	return 0;
}

public any Native_LegacyCookieRead(Handle plugin, int numParams)
{
	ReadLanCookie(GetNativeCell(1), view_as<Cookie>(GetNativeCell(2)), 3, GetNativeCell(4));
	return 0;
}

public any Native_LanCookieSet(Handle plugin, int numParams)
{
	WriteLanCookie(GetNativeCell(2), view_as<Cookie>(GetNativeCell(1)), 3);
	return 0;
}

public any Native_LegacyCookieSave(Handle plugin, int numParams)
{
	WriteLanCookie(GetNativeCell(1), view_as<Cookie>(GetNativeCell(2)), 3);
	return 0;
}

bool GetLanCookieName(Cookie cookie, char[] name, int maxLength)
{
	char handleKey[16];
	IntToString(view_as<int>(cookie), handleKey, sizeof(handleKey));
	return g_mCookieNames.GetString(handleKey, name, maxLength);
}

void ReadLanCookie(int client, Cookie cookie, int outputParam, int maxLength)
{
	if (!EnsureLanIdentity(client))
	{
		char value[256];
		GetClientCookie(client, cookie, value, sizeof(value));
		SetNativeString(outputParam, value, maxLength, true);
		return;
	}

	char cookieName[COOKIE_MAX_NAME_LENGTH];
	char identity[32];
	char escapedIdentity[65];
	char escapedCookie[COOKIE_MAX_NAME_LENGTH * 2 + 1];
	char query[256];
	char value[256];
	value[0] = '\0';

	if (!GetLanCookieName(cookie, cookieName, sizeof(cookieName)))
	{
		SetNativeString(outputParam, value, maxLength, true);
		return;
	}

	GetSyntheticSteamId(client, identity, sizeof(identity));
	SQL_EscapeString(g_hLanPrefs, identity, escapedIdentity, sizeof(escapedIdentity));
	SQL_EscapeString(g_hLanPrefs, cookieName, escapedCookie, sizeof(escapedCookie));
	Format(query, sizeof(query), "SELECT value FROM lan_cookie_values WHERE identity='%s' AND cookie_name='%s' LIMIT 1;", escapedIdentity, escapedCookie);

	DBResultSet results = SQL_Query(g_hLanPrefs, query);
	if (results != null)
	{
		if (results.FetchRow())
			results.FetchString(0, value, sizeof(value));
		delete results;
	}

	// The old shared LAN cookie data belongs to the explicitly retained profile.
	if (value[0] == '\0' && IsLegacyOwner(client))
	{
		GetClientCookie(client, cookie, value, sizeof(value));
		if (value[0] != '\0')
			SaveLanCookie(identity, cookieName, value);
	}

	SetNativeString(outputParam, value, maxLength, true);
}

void WriteLanCookie(int client, Cookie cookie, int valueParam)
{
	char value[256];
	GetNativeString(valueParam, value, sizeof(value));

	if (!EnsureLanIdentity(client))
	{
		SetClientCookie(client, cookie, value);
		return;
	}

	char cookieName[COOKIE_MAX_NAME_LENGTH];
	char identity[32];
	if (!GetLanCookieName(cookie, cookieName, sizeof(cookieName)))
		return;

	GetSyntheticSteamId(client, identity, sizeof(identity));
	SaveLanCookie(identity, cookieName, value);
}

void SaveLanCookie(const char[] identity, const char[] cookieName, const char[] value)
{
	char escapedIdentity[65];
	char escapedCookie[COOKIE_MAX_NAME_LENGTH * 2 + 1];
	char escapedValue[513];
	char query[768];
	SQL_EscapeString(g_hLanPrefs, identity, escapedIdentity, sizeof(escapedIdentity));
	SQL_EscapeString(g_hLanPrefs, cookieName, escapedCookie, sizeof(escapedCookie));
	SQL_EscapeString(g_hLanPrefs, value, escapedValue, sizeof(escapedValue));
	Format(query, sizeof(query), "REPLACE INTO lan_cookie_values (identity, cookie_name, value, updated_at) VALUES ('%s','%s','%s',%d);", escapedIdentity, escapedCookie, escapedValue, GetTime());
	SQL_FastQuery(g_hLanPrefs, query);
}

bool IsLegacyOwner(int client)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	return StrEqual(name, "James_Hotten", true);
}

void MigrateLegacyOwnerData(int client)
{
	if (!IsLegacyOwner(client))
		return;

	char identity[32];
	GetSyntheticSteamId(client, identity, sizeof(identity));
	MigrateDatabaseKey("rankme", "UPDATE rankme SET steam='%s' WHERE steam='STEAM_ID_LAN' AND name='James_Hotten';", identity);
	MigrateDatabaseKey("weapons", "UPDATE weapons SET steamid='%s' WHERE steamid='STEAM_ID_LAN';", identity);
	MigrateDatabaseKey("weapons", "UPDATE weapons_timestamps SET steamid='%s' WHERE steamid='STEAM_ID_LAN';", identity);
	MigrateDatabaseKey("gloves", "UPDATE gloves SET steamid='%s' WHERE steamid='STEAM_ID_LAN';", identity);
	MigrateDatabaseKey("csgo_weaponstickers", "UPDATE csgo_weaponstickers SET steamid='%s' WHERE steamid='STEAM_ID_LAN';", identity);
	MigrateDatabaseKey("agents", "UPDATE csgo_agentschooser SET steam_id='%s' WHERE steam_id='STEAM_ID_LAN';", identity);
}

void MigrateDatabaseKey(const char[] databaseName, const char[] queryTemplate, const char[] identity)
{
	char error[256];
	Database database = SQL_Connect(databaseName, true, error, sizeof(error));
	if (database == null)
	{
		LogError("LAN identity migration could not connect to %s: %s", databaseName, error);
		return;
	}

	char escapedIdentity[65];
	char query[512];
	SQL_EscapeString(database, identity, escapedIdentity, sizeof(escapedIdentity));
	Format(query, sizeof(query), queryTemplate, escapedIdentity);

	if (!SQL_FastQuery(database, query))
	{
		SQL_GetError(database, error, sizeof(error));
		LogError("LAN identity migration failed for %s: %s", databaseName, error);
	}
	delete database;
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
