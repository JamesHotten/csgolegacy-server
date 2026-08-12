#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>

#define PLAYER_INFO_LEN 344
#define PLAYER_INFO_XUID 8
#define PLAYER_INFO_USERID 144
#define PLAYER_INFO_STEAMID 148
#define PLAYER_INFO_ACCOUNTID 184

#define SCORE_FIELD_COUNT 5
#define SCORE_KILLS 0
#define SCORE_DEATHS 1
#define SCORE_ASSISTS 2
#define SCORE_MVPS 3
#define SCORE_CONTRIBUTION 4
#define LEGACY_OWNER_ACCOUNT_ID 1919066672
#define STEAMID64_HIGH 17825793

bool g_bIdentityPatched[MAXPLAYERS + 1];
bool g_bLanClient[MAXPLAYERS + 1];
bool g_bPatchPending[MAXPLAYERS + 1];
bool g_bIdentityFailed[MAXPLAYERS + 1];
char g_sIdentityKey[MAXPLAYERS + 1][128];
int g_iAccountId[MAXPLAYERS + 1];
int g_iPatchCycles[MAXPLAYERS + 1];
StringMap g_mScoreCache;
StringMap g_mCookieNames;
StringMap g_mCookieHandles;
Database g_hLanPrefs;
ConVar g_cvSvLan;

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
	g_mCookieHandles = new StringMap();
	g_cvSvLan = FindConVar("sv_lan");

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

	if (!SQL_FastQuery(g_hLanPrefs,
		"CREATE TABLE IF NOT EXISTS lan_identity_accounts (identity_key TEXT NOT NULL PRIMARY KEY, account_id INTEGER NOT NULL UNIQUE, updated_at INTEGER NOT NULL DEFAULT 0);"))
	{
		SQL_GetError(g_hLanPrefs, error, sizeof(error));
		SetFailState("LAN identity account table init failed: %s", error);
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
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client) && !IsFakeClient(client))
		{
			g_bIdentityPatched[client] = false;
			PrepareClient(client);
		}
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client))
		PrepareClient(client);
}

public void OnClientConnected(int client)
{
	ResetClientState(client);
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
		PrepareClient(client);
}

void PrepareClient(int client)
{
	if (g_bIdentityPatched[client] || g_bPatchPending[client] || !IsClientConnected(client) || IsFakeClient(client))
		return;

	g_bPatchPending[client] = true;
	CreateTimer(0.5, Timer_PatchLanIdentity, GetClientUserId(client), TIMER_REPEAT);
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

	ResetClientState(client);
}

void ResetClientState(int client)
{
	g_bIdentityPatched[client] = false;
	g_bLanClient[client] = false;
	g_bPatchPending[client] = false;
	g_bIdentityFailed[client] = false;
	g_sIdentityKey[client][0] = '\0';
	g_iAccountId[client] = 0;
	g_iPatchCycles[client] = 0;
}

public Action Timer_PatchLanIdentity(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client == 0)
		return Plugin_Stop;

	if (!IsClientConnected(client) || IsFakeClient(client))
	{
		g_bPatchPending[client] = false;
		return Plugin_Stop;
	}

	if (!IsClientInGame(client))
		return Plugin_Continue;

	char authId[32];
	bool hasAuth = GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
	if (hasAuth && !StrEqual(authId, "STEAM_ID_LAN", false))
	{
		g_bPatchPending[client] = false;
		return Plugin_Stop;
	}
	if (!hasAuth && (g_cvSvLan == null || !g_cvSvLan.BoolValue))
		return Plugin_Continue;

	if (!InitializeLanIdentity(client))
		return Plugin_Stop;

	int table = FindStringTable("userinfo");
	if (table == INVALID_STRING_TABLE)
		return Plugin_Continue;

	int userInfoIndex = FindClientUserInfoIndex(table, client);
	if (userInfoIndex == INVALID_STRING_INDEX)
		return Plugin_Continue;

	g_iPatchCycles[client]++;
	// Re-broadcast rapidly while the client's loading screen builds its first
	// scoreboard, then keep a low-frequency self-healing refresh.
	if (g_bIdentityPatched[client] && g_iPatchCycles[client] > 10 && (g_iPatchCycles[client] % 20) != 0)
		return Plugin_Continue;

	char userInfo[PLAYER_INFO_LEN];
	if (!GetStringTableData(table, userInfoIndex, userInfo, sizeof(userInfo)))
		return Plugin_Continue;

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
	// The userinfo string table serializes XUID in network byte order,
	// while the standalone AccountID field below is little-endian.
	// SteamID64 = 0x0110000100000000 + AccountID.
	WriteInt32BE(userInfo, PLAYER_INFO_XUID, STEAMID64_HIGH);
	WriteInt32BE(userInfo, PLAYER_INFO_XUID + 4, accountId);

	Format(userInfo[PLAYER_INFO_STEAMID], 33, "STEAM_1:%d:%d", accountId & 1, accountId / 2);
	WriteInt32LE(userInfo, PLAYER_INFO_ACCOUNTID, accountId);

	// The client can miss an update sent while its loading screen is still
	// constructing the scoreboard. Re-broadcast the complete player_info entry
	// throughout the connection; SetStringTableData is cheap at this cadence and
	// also self-heals if the engine or another plugin later overwrites it.
	bool wasLocked = LockStringTables(false);
	SetStringTableData(table, userInfoIndex, userInfo, sizeof(userInfo));
	LockStringTables(wasLocked);
	char verifiedInfo[PLAYER_INFO_LEN];
	if (!GetStringTableData(table, userInfoIndex, verifiedInfo, sizeof(verifiedInfo)) ||
		ReadInt32BE(verifiedInfo, PLAYER_INFO_XUID) != STEAMID64_HIGH ||
		ReadInt32BE(verifiedInfo, PLAYER_INFO_XUID + 4) != accountId ||
		ReadInt32LE(verifiedInfo, PLAYER_INFO_ACCOUNTID) != accountId)
	{
		return Plugin_Continue;
	}

	bool firstSuccessfulPatch = !g_bIdentityPatched[client];
	g_bIdentityPatched[client] = true;
	if (firstSuccessfulPatch)
		RestoreScore(client);
	return Plugin_Continue;
}

int FindClientUserInfoIndex(int table, int client)
{
	int userId = GetClientUserId(client);
	int count = GetStringTableNumStrings(table);
	char userInfo[PLAYER_INFO_LEN];
	for (int index = 0; index < count; index++)
	{
		if (GetStringTableData(table, index, userInfo, sizeof(userInfo)) &&
			ReadInt32BE(userInfo, PLAYER_INFO_USERID) == userId)
		{
			return index;
		}
	}

	return INVALID_STRING_INDEX;
}

void WriteInt32LE(char[] data, int offset, int value)
{
	data[offset] = value;
	data[offset + 1] = value >> 8;
	data[offset + 2] = value >> 16;
	data[offset + 3] = value >> 24;
}

void WriteInt32BE(char[] data, int offset, int value)
{
	data[offset] = value >> 24;
	data[offset + 1] = value >> 16;
	data[offset + 2] = value >> 8;
	data[offset + 3] = value;
}

int ReadInt32LE(const char[] data, int offset)
{
	return (data[offset] & 0xFF) |
		((data[offset + 1] & 0xFF) << 8) |
		((data[offset + 2] & 0xFF) << 16) |
		((data[offset + 3] & 0xFF) << 24);
}

int ReadInt32BE(const char[] data, int offset)
{
	return ((data[offset] & 0xFF) << 24) |
		((data[offset + 1] & 0xFF) << 16) |
		((data[offset + 2] & 0xFF) << 8) |
		(data[offset + 3] & 0xFF);
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
	int mappedAccountId = GetMappedAccountId(identity);
	if (mappedAccountId > 0 && mappedAccountId != LEGACY_OWNER_ACCOUNT_ID && !IsAccountIdActive(client, mappedAccountId))
		return mappedAccountId;

	char saltedIdentity[160];
	for (int salt = 0; salt <= MaxClients; salt++)
	{
		if (salt == 0)
			strcopy(saltedIdentity, sizeof(saltedIdentity), identity);
		else
			Format(saltedIdentity, sizeof(saltedIdentity), "%s|account:%d", identity, salt);

		int accountId = BuildAccountId(saltedIdentity);
		if (accountId == LEGACY_OWNER_ACCOUNT_ID)
			continue;
		if (!IsAccountIdActive(client, accountId) && !IsAccountIdPersistentlyUsed(accountId) && StoreIdentityAccount(identity, accountId))
			return accountId;
	}

	for (int accountId = 1900000001; accountId <= 1900000000 + MaxClients; accountId++)
	{
		if (accountId != LEGACY_OWNER_ACCOUNT_ID && !IsAccountIdActive(client, accountId) &&
			!IsAccountIdPersistentlyUsed(accountId) && StoreIdentityAccount(identity, accountId))
			return accountId;
	}

	LogError("Could not allocate a durable LAN account for identity '%s'.", identity);
	return 0;
}

int GetMappedAccountId(const char[] identity)
{
	char escapedIdentity[257];
	char query[384];
	SQL_EscapeString(g_hLanPrefs, identity, escapedIdentity, sizeof(escapedIdentity));
	Format(query, sizeof(query), "SELECT account_id FROM lan_identity_accounts WHERE identity_key='%s' LIMIT 1;", escapedIdentity);

	DBResultSet results = SQL_Query(g_hLanPrefs, query);
	if (results == null)
		return 0;

	int accountId = 0;
	if (results.FetchRow())
		accountId = results.FetchInt(0);
	delete results;
	return accountId;
}

bool IsAccountIdPersistentlyUsed(int accountId)
{
	char query[160];
	Format(query, sizeof(query), "SELECT 1 FROM lan_identity_accounts WHERE account_id=%d LIMIT 1;", accountId);
	DBResultSet results = SQL_Query(g_hLanPrefs, query);
	if (results == null)
		return true;

	bool used = results.FetchRow();
	delete results;
	return used;
}

bool StoreIdentityAccount(const char[] identity, int accountId)
{
	char escapedIdentity[257];
	char query[512];
	SQL_EscapeString(g_hLanPrefs, identity, escapedIdentity, sizeof(escapedIdentity));
	Format(query, sizeof(query), "INSERT OR IGNORE INTO lan_identity_accounts (identity_key, account_id, updated_at) VALUES ('%s',%d,%d);", escapedIdentity, accountId, GetTime());
	if (!SQL_FastQuery(g_hLanPrefs, query))
		return false;

	return GetMappedAccountId(identity) == accountId;
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
	if (g_bIdentityFailed[client])
		return false;

	if (g_bLanClient[client])
		return true;

	char authId[32];
	bool hasAuth = GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
	bool isLanServer = g_cvSvLan != null && g_cvSvLan.BoolValue;
	if ((hasAuth && StrEqual(authId, "STEAM_ID_LAN", false)) || (!hasAuth && isLanServer))
	{
		if (!InitializeLanIdentity(client))
			return false;

		// Persistent-data plugins call this native from their own connection
		// callbacks. Establish the database identity synchronously so their
		// first query never falls back to the shared STEAM_ID_LAN row; the
		// userinfo scoreboard patch can still retry asynchronously.
		PrepareClient(client);
		return true;
	}

	PrepareClient(client);
	return false;
}

bool InitializeLanIdentity(int client)
{
	if (g_bLanClient[client])
		return true;

	g_bLanClient[client] = true;
	char baseIdentity[128];
	BuildBaseIdentityKey(client, baseIdentity, sizeof(baseIdentity));
	ResolveIdentityKey(client, baseIdentity, g_sIdentityKey[client], sizeof(g_sIdentityKey[]));
	if (IsLegacyOwner(client) && !IsAccountIdActive(client, LEGACY_OWNER_ACCOUNT_ID))
		g_iAccountId[client] = LEGACY_OWNER_ACCOUNT_ID;
	else
		g_iAccountId[client] = BuildUniqueAccountId(client, g_sIdentityKey[client]);
	if (g_iAccountId[client] <= 0)
	{
		LogError("LAN identity account allocation failed for client %d; refusing shared AccountID 0.", client);
		KickClient(client, "LAN identity allocation failed. Please reconnect after the server database is repaired.");
		ResetClientState(client);
		g_bIdentityFailed[client] = true;
		return false;
	}

	if (MigrateLegacyOwnerData(client))
		return true;

	SetFailState("LAN identity migration failed; stop the server, check SourceMod errors, and restart to retry safely.");
	return false;
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
		if (client >= 1 && client <= MaxClients && g_bIdentityFailed[client])
			return ThrowNativeError(SP_ERROR_NATIVE, "LAN identity initialization failed for client %d; shared STEAM_ID_LAN is blocked.", client);

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
	if (client >= 1 && client <= MaxClients && g_bIdentityFailed[client])
		return ThrowNativeError(SP_ERROR_NATIVE, "LAN identity initialization failed for client %d; AccountID 0 is blocked.", client);
	return GetSteamAccountID(client, validate);
}

public any Native_LanCookieMake(Handle plugin, int numParams)
{
	return RegisterLanCookie(plugin, 1, 2, view_as<CookieAccess>(GetNativeCell(3)));
}

public any Native_LegacyCookieMake(Handle plugin, int numParams)
{
	return RegisterLanCookie(plugin, 1, 2, view_as<CookieAccess>(GetNativeCell(3)));
}

int RegisterLanCookie(Handle owner, int nameParam, int descriptionParam, CookieAccess access)
{
	char name[COOKIE_MAX_NAME_LENGTH];
	char description[256];
	GetNativeString(nameParam, name, sizeof(name));
	GetNativeString(descriptionParam, description, sizeof(description));
	Cookie internalCookie = RegClientCookie(name, description, access);
	Cookie callerCookie = view_as<Cookie>(CloneHandle(internalCookie, owner));

	char handleKey[16];
	IntToString(view_as<int>(callerCookie), handleKey, sizeof(handleKey));
	g_mCookieNames.SetString(handleKey, name);
	g_mCookieHandles.SetValue(handleKey, view_as<int>(internalCookie));
	return view_as<int>(callerCookie);
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

bool GetInternalCookie(Cookie callerCookie, Cookie &internalCookie)
{
	char handleKey[16];
	int handleValue;
	IntToString(view_as<int>(callerCookie), handleKey, sizeof(handleKey));
	if (!g_mCookieHandles.GetValue(handleKey, handleValue))
		return false;

	internalCookie = view_as<Cookie>(handleValue);
	return true;
}

void ReadLanCookie(int client, Cookie cookie, int outputParam, int maxLength)
{
	Cookie internalCookie;
	if (!GetInternalCookie(cookie, internalCookie))
	{
		char empty[1];
		SetNativeString(outputParam, empty, maxLength, true);
		return;
	}

	if (!EnsureLanIdentity(client))
	{
		char value[256];
		value[0] = '\0';
		if (client >= 1 && client <= MaxClients && g_bIdentityFailed[client])
		{
			SetNativeString(outputParam, value, maxLength, true);
			return;
		}
		GetClientCookie(client, internalCookie, value, sizeof(value));
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
	if (value[0] == '\0' && IsLegacyOwnerProfile(client))
	{
		GetClientCookie(client, internalCookie, value, sizeof(value));
		if (value[0] != '\0')
			SaveLanCookie(identity, cookieName, value);
	}

	SetNativeString(outputParam, value, maxLength, true);
}

void WriteLanCookie(int client, Cookie cookie, int valueParam)
{
	char value[256];
	GetNativeString(valueParam, value, sizeof(value));

	Cookie internalCookie;
	if (!GetInternalCookie(cookie, internalCookie))
		return;

	if (!EnsureLanIdentity(client))
	{
		if (client >= 1 && client <= MaxClients && g_bIdentityFailed[client])
			return;
		SetClientCookie(client, internalCookie, value);
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

bool IsLegacyOwnerProfile(int client)
{
	return IsLegacyOwner(client) && g_iAccountId[client] == LEGACY_OWNER_ACCOUNT_ID;
}

bool MigrateLegacyOwnerData(int client)
{
	if (!IsLegacyOwnerProfile(client))
		return true;

	char identity[32];
	GetSyntheticSteamId(client, identity, sizeof(identity));
	bool success = true;
	success = MigrateDatabaseKey("rankme", "rankme", "steam", " AND name='James_Hotten'", "target.name=rankme.name", identity) && success;
	success = MigrateDatabaseKey("weapons", "weapons", "steamid", "", "1=1", identity) && success;
	success = MigrateDatabaseKey("weapons", "weapons_timestamps", "steamid", "", "1=1", identity) && success;
	success = MigrateDatabaseKey("gloves", "gloves", "steamid", "", "1=1", identity) && success;
	success = MigrateDatabaseKey("csgo_weaponstickers", "csgo_weaponstickers", "steamid", "", "target.weaponindex=csgo_weaponstickers.weaponindex AND target.team=csgo_weaponstickers.team", identity) && success;
	success = MigrateDatabaseKey("agents", "csgo_agentschooser", "steam_id", "", "1=1", identity) && success;
	return success;
}

bool MigrateDatabaseKey(const char[] databaseName, const char[] tableName, const char[] keyColumn, const char[] sourceFilter, const char[] conflictMatch, const char[] identity)
{
	char error[256];
	Database database = SQL_Connect(databaseName, true, error, sizeof(error));
	if (database == null)
	{
		LogError("LAN identity migration could not connect to %s: %s", databaseName, error);
		return false;
	}

	char escapedIdentity[65];
	char query[1024];
	SQL_EscapeString(database, identity, escapedIdentity, sizeof(escapedIdentity));

	char driver[16];
	char beginQuery[32];
	SQL_GetDriverIdent(SQL_ReadDriver(database), driver, sizeof(driver));
	if (StrEqual(driver, "sqlite", false))
		strcopy(beginQuery, sizeof(beginQuery), "BEGIN IMMEDIATE;");
	else
		strcopy(beginQuery, sizeof(beginQuery), "START TRANSACTION;");
	if (!SQL_FastQuery(database, beginQuery))
	{
		SQL_GetError(database, error, sizeof(error));
		LogError("LAN identity migration could not start a transaction for %s: %s", databaseName, error);
		delete database;
		return false;
	}

	Format(query, sizeof(query), "DELETE FROM %s WHERE %s='STEAM_ID_LAN'%s AND EXISTS (SELECT 1 FROM %s AS target WHERE target.%s='%s' AND %s);", tableName, keyColumn, sourceFilter, tableName, keyColumn, escapedIdentity, conflictMatch);

	if (!SQL_FastQuery(database, query))
	{
		SQL_GetError(database, error, sizeof(error));
		LogError("LAN identity migration failed for %s: %s", databaseName, error);
		SQL_FastQuery(database, "ROLLBACK;");
		delete database;
		return false;
	}

	Format(query, sizeof(query), "UPDATE %s SET %s='%s' WHERE %s='STEAM_ID_LAN'%s;", tableName, keyColumn, escapedIdentity, keyColumn, sourceFilter);
	if (!SQL_FastQuery(database, query))
	{
		SQL_GetError(database, error, sizeof(error));
		LogError("LAN identity migration failed for %s: %s", databaseName, error);
		SQL_FastQuery(database, "ROLLBACK;");
		delete database;
		return false;
	}
	if (!SQL_FastQuery(database, "COMMIT;"))
	{
		SQL_GetError(database, error, sizeof(error));
		LogError("LAN identity migration commit failed for %s: %s", databaseName, error);
		SQL_FastQuery(database, "ROLLBACK;");
		delete database;
		return false;
	}
	delete database;
	return true;
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
