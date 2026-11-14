#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define MAX_RECORDED_EVENTS 64
#define MAX_RECORDED_SIGNALS 96

native int BotEquipment_GetBuyPlan(int team);

enum struct OpeningGear
{
    int players;
    int bots;
    int rifles;
    int snipers;
    int smgs;
    int shotguns;
    int otherPrimary;
    int pistolsOnly;
    int armored;
    int helmets;
    int kits;
    int utility;
    int smokes;
    int flashes;
    int purchasePlan;
}

enum struct RecordedEvent
{
    int kind;
    int occurredAt;
    int actorTeam;
    int actorBot;
    char actorBotName[64];
    int victimTeam;
    int victimBot;
    char victimBotName[64];
    char weapon[48];
    char site[8];
    float position[3];
}

enum struct RecordedSignal
{
    int elapsedMs;
    int team;
    int actorBot;
    char actorBotName[64];
    char kind[32];
    char detail[48];
    char site[8];
    float position[3];
}

public Plugin myinfo =
{
    name = "BetterBots Tactical Experience Recorder",
    author = "JamesHotten server project",
    description = "Records rounds and opening BOT tactics without changing decisions",
    version = "0.1.1",
    url = "https://github.com/JamesHotten/csgolegacy-server"
};

Database g_database;
ConVar g_enabled;
char g_map[64];
bool g_roundActive;
int g_startedAt;
int g_roundIndex;
int g_ctBuy;
int g_ctPlan;
int g_ctSite;
int g_ctBots;
int g_tBuy;
int g_tPlan;
int g_tSite;
int g_tBots;
RecordedEvent g_events[MAX_RECORDED_EVENTS];
int g_eventCount;
RecordedSignal g_signals[MAX_RECORDED_SIGNALS];
int g_signalCount;
float g_roundStartedGameTime;
bool g_firstDamage[4];
bool g_firstSight[4];
OpeningGear g_openingGear[4];
bool g_gearCaptured;
bool g_recordGear;
bool g_planted, g_defused;
int g_plantMs, g_defuseBeginMs, g_retakeStageMs, g_retakeCommitMs, g_kitAtDefuse;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax)
{
    RegPluginLibrary("bot_tactical_experience");
    CreateNative("BotExperience_RecordOpeningPlan", Native_RecordOpeningPlan);
    CreateNative("BotExperience_RecordSignal", Native_RecordSignal);
    MarkNativeAsOptional("BotEquipment_GetBuyPlan");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_bot_experience_record_enable", "1",
        "Record BOT tactical experience; never changes BOT decisions.", _, true, 0.0, true, 1.0);
    g_enabled.AddChangeHook(OnEnabledChanged);
    AutoExecConfig(true, "bot_tactical_experience");

    char error[256];
    g_database = SQLite_UseDatabase("bot_tactical_experience", error, sizeof(error));
    if (g_database == null)
    {
        LogError("BOT experience database unavailable: %s", error);
        return;
    }
    SQL_FastQuery(g_database, "PRAGMA journal_mode=WAL;");
    if (!SQL_FastQuery(g_database,
        "CREATE TABLE IF NOT EXISTS rounds ("
        ... "id INTEGER PRIMARY KEY, map TEXT NOT NULL, started_at INTEGER NOT NULL, "
        ... "round_index INTEGER NOT NULL, ct_buy TEXT NOT NULL, ct_plan TEXT NOT NULL, "
        ... "ct_site TEXT NOT NULL, ct_bots INTEGER NOT NULL, t_buy TEXT NOT NULL, "
        ... "t_plan TEXT NOT NULL, t_site TEXT NOT NULL, t_bots INTEGER NOT NULL, "
        ... "winner INTEGER NOT NULL, reason INTEGER NOT NULL);"))
    {
        SQL_GetError(g_database, error, sizeof(error));
        LogError("BOT experience schema initialization failed: %s", error);
        delete g_database;
        g_database = null;
        return;
    }
    if (!SQL_FastQuery(g_database,
        "CREATE TABLE IF NOT EXISTS events ("
        ... "id INTEGER PRIMARY KEY, round_id INTEGER NOT NULL, kind TEXT NOT NULL, "
        ... "occurred_at INTEGER NOT NULL, actor_team INTEGER NOT NULL, actor_is_bot INTEGER NOT NULL, "
        ... "actor_bot_name TEXT NOT NULL, victim_team INTEGER NOT NULL, victim_is_bot INTEGER NOT NULL, "
        ... "victim_bot_name TEXT NOT NULL, weapon TEXT NOT NULL, site TEXT NOT NULL, "
        ... "x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL);"))
    {
        SQL_GetError(g_database, error, sizeof(error));
        LogError("BOT experience event schema initialization failed: %s", error);
        delete g_database;
        g_database = null;
        return;
    }
    if (!SQL_FastQuery(g_database,
        "CREATE TABLE IF NOT EXISTS signals ("
        ... "id INTEGER PRIMARY KEY, round_id INTEGER NOT NULL, elapsed_ms INTEGER NOT NULL, "
        ... "team INTEGER NOT NULL, kind TEXT NOT NULL, detail TEXT NOT NULL, "
        ... "site TEXT NOT NULL, actor_is_bot INTEGER NOT NULL, "
        ... "actor_bot_name TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL);"))
    {
        SQL_GetError(g_database, error, sizeof(error));
        LogError("BOT experience signal schema initialization failed: %s", error);
        delete g_database;
        g_database = null;
        return;
    }
    g_recordGear = SQL_FastQuery(g_database,
        "CREATE TABLE IF NOT EXISTS opening_gear ("
        ... "round_id INTEGER NOT NULL, team INTEGER NOT NULL, purchase_plan TEXT NOT NULL, "
        ... "players INTEGER NOT NULL, bots INTEGER NOT NULL, rifles INTEGER NOT NULL, snipers INTEGER NOT NULL, "
        ... "smgs INTEGER NOT NULL, shotguns INTEGER NOT NULL, other_primary INTEGER NOT NULL, pistols_only INTEGER NOT NULL, "
        ... "armored INTEGER NOT NULL, helmets INTEGER NOT NULL, kits INTEGER NOT NULL, utility INTEGER NOT NULL, "
        ... "smokes INTEGER NOT NULL, flashes INTEGER NOT NULL, PRIMARY KEY (round_id, team));")
        && SQL_FastQuery(g_database,
        "CREATE TABLE IF NOT EXISTS retake_outcomes ("
        ... "round_id INTEGER PRIMARY KEY, plant_ms INTEGER NOT NULL, stage_ms INTEGER, commit_ms INTEGER, "
        ... "defuse_begin_ms INTEGER, kit_at_defuse INTEGER, defused INTEGER NOT NULL);");
    if (!g_recordGear) LogDatabaseError("initialize optional equipment and retake telemetry");
    GetCurrentMap(g_map, sizeof(g_map));
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_Post);
    HookEvent("bomb_begindefuse", Event_BombBeginDefuse, EventHookMode_Post);
    HookEvent("bomb_defused", Event_BombDefused, EventHookMode_Post);
    HookEvent("bomb_beginplant", Event_BombBeginPlant, EventHookMode_Post);
    HookEvent("bomb_abortplant", Event_BombAbortPlant, EventHookMode_Post);
    HookEventEx("grenade_thrown", Event_GrenadeThrown, EventHookMode_Post);
    HookEventEx("smokegrenade_detonate", Event_GrenadeDetonate, EventHookMode_Post);
    HookEventEx("flashbang_detonate", Event_GrenadeDetonate, EventHookMode_Post);
    HookEventEx("hegrenade_detonate", Event_GrenadeDetonate, EventHookMode_Post);
    HookEventEx("molotov_detonate", Event_GrenadeDetonate, EventHookMode_Post);
}

public void OnMapStart()
{
    GetCurrentMap(g_map, sizeof(g_map));
    g_roundActive = false;
    g_eventCount = 0;
    g_signalCount = 0;
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        g_roundActive = false;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_roundActive = g_enabled.BoolValue && g_database != null
        && GameRules_GetProp("m_bWarmupPeriod") == 0;
    if (!g_roundActive)
        return;

    g_startedAt = GetTime();
    g_roundIndex = GameRules_GetProp("m_totalRoundsPlayed") + 1;
    g_ctBuy = -1;
    g_ctPlan = -1;
    g_ctSite = -1;
    g_ctBots = 0;
    g_tBuy = -1;
    g_tPlan = -1;
    g_tSite = -1;
    g_tBots = 0;
    g_eventCount = 0;
    g_signalCount = 0;
    g_roundStartedGameTime = GetGameTime();
    g_gearCaptured = false;
    g_planted = false;
    g_defused = false;
    g_plantMs = -1;
    g_defuseBeginMs = -1;
    g_retakeStageMs = -1;
    g_retakeCommitMs = -1;
    g_kitAtDefuse = -1;
    for (int team = 0; team < 4; team++)
    {
        g_firstDamage[team] = false;
        g_firstSight[team] = false;
    }
}

int RoundElapsedMs() { return RoundToNearest((GetGameTime() - g_roundStartedGameTime) * 1000.0); }

// Use classnames, including MP5-SD and both M4 variants, independent of prices.
void CountPrimary(int entity, int secondary, OpeningGear gear)
{
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        if (secondary > MaxClients && IsValidEntity(secondary)) gear.pistolsOnly++;
        return;
    }
    char name[40];
    GetEntityClassname(entity, name, sizeof(name));
    if (StrEqual(name, "weapon_ak47") || StrEqual(name, "weapon_m4a1") || StrEqual(name, "weapon_m4a1_silencer")
        || StrEqual(name, "weapon_famas") || StrEqual(name, "weapon_galilar") || StrEqual(name, "weapon_aug")
        || StrEqual(name, "weapon_sg556")) gear.rifles++;
    else if (StrEqual(name, "weapon_awp") || StrEqual(name, "weapon_ssg08")
        || StrEqual(name, "weapon_scar20") || StrEqual(name, "weapon_g3sg1")) gear.snipers++;
    else if (StrEqual(name, "weapon_mp9") || StrEqual(name, "weapon_mac10") || StrEqual(name, "weapon_mp7")
        || StrEqual(name, "weapon_mp5sd") || StrEqual(name, "weapon_ump45")
        || StrEqual(name, "weapon_p90") || StrEqual(name, "weapon_bizon")) gear.smgs++;
    else if (StrEqual(name, "weapon_nova") || StrEqual(name, "weapon_mag7") || StrEqual(name, "weapon_sawedoff")
        || StrEqual(name, "weapon_xm1014")) gear.shotguns++;
    else gear.otherPrimary++;
}

public void Event_FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_roundActive || !g_recordGear || g_gearCaptured) return;
    g_gearCaptured = true;
    for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
    {
        OpeningGear gear;
        gear.purchasePlan = GetFeatureStatus(FeatureType_Native, "BotEquipment_GetBuyPlan") == FeatureStatus_Available
            ? BotEquipment_GetBuyPlan(team) : -1;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != team) continue;
            gear.players++;
            if (IsFakeClient(client)) gear.bots++;
            CountPrimary(GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY), GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY), gear);
            if (GetEntProp(client, Prop_Data, "m_ArmorValue") > 0) gear.armored++;
            if (GetEntProp(client, Prop_Send, "m_bHasHelmet")) gear.helmets++;
            if (team == CS_TEAM_CT && GetEntProp(client, Prop_Send, "m_bHasDefuser")) gear.kits++;
            if (!HasEntProp(client, Prop_Send, "m_iAmmo") || !HasEntProp(client, Prop_Send, "m_hMyWeapons")) continue;
            // Inventory contains one entity per grenade type; ammo includes
            // the second flash, so count the type only once.
            bool counted[32];
            for (int index = 0; index < GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons"); index++)
            {
                int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", index);
                if (weapon <= MaxClients || !IsValidEntity(weapon)) continue;
                char classname[32];
                GetEntityClassname(weapon, classname, sizeof(classname));
                bool smoke = StrEqual(classname, "weapon_smokegrenade");
                bool flash = StrEqual(classname, "weapon_flashbang");
                if (!smoke && !flash && !StrEqual(classname, "weapon_hegrenade")
                    && !StrEqual(classname, "weapon_molotov") && !StrEqual(classname, "weapon_incgrenade")
                    && !StrEqual(classname, "weapon_decoy")) continue;
                int ammo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
                if (ammo < 0 || ammo >= sizeof(counted) || counted[ammo]) continue;
                counted[ammo] = true;
                if (ammo >= GetEntPropArraySize(client, Prop_Send, "m_iAmmo")) continue;
                int amount = GetEntProp(client, Prop_Send, "m_iAmmo", 4, ammo);
                if (amount < 1) continue;
                gear.utility += amount;
                if (smoke) gear.smokes += amount;
                if (flash) gear.flashes += amount;
            }
        }
        g_openingGear[team] = gear;
    }
}

public void Event_BombBeginDefuse(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_roundActive || !g_planted || g_defuseBeginMs >= 0) return;
    g_defuseBeginMs = RoundElapsedMs();
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsClientInGame(client)) g_kitAtDefuse = GetEntProp(client, Prop_Send, "m_bHasDefuser") ? 1 : 0;
}

public void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    if (g_roundActive && g_planted) g_defused = true;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_roundActive)
        return;
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker))
        return;
    int team = GetClientTeam(attacker);
    if ((team != CS_TEAM_CT && team != CS_TEAM_T) || g_firstDamage[team])
        return;
    g_firstDamage[team] = true;
    RecordSignal(team, "first_damage", "player_hurt", -1, attacker);
}

public void Event_BombBeginPlant(Event event, const char[] name, bool dontBroadcast)
{
    int planter = GetClientOfUserId(event.GetInt("userid"));
    RecordSignal(CS_TEAM_T, "plant_begin", "bomb_beginplant", -1, planter);
}

public void Event_BombAbortPlant(Event event, const char[] name, bool dontBroadcast)
{
    int planter = GetClientOfUserId(event.GetInt("userid"));
    RecordSignal(CS_TEAM_T, "plant_abort", "bomb_abortplant", -1, planter);
}

public void Event_GrenadeThrown(Event event, const char[] name, bool dontBroadcast)
{
    int actor = GetClientOfUserId(event.GetInt("userid"));
    if (actor < 1 || actor > MaxClients || !IsClientInGame(actor))
        return;
    char weapon[48];
    event.GetString("weapon", weapon, sizeof(weapon));
    RecordSignal(GetClientTeam(actor), "grenade_thrown", weapon, -1, actor);
}

public void Event_GrenadeDetonate(Event event, const char[] name, bool dontBroadcast)
{
    int actor = GetClientOfUserId(event.GetInt("userid"));
    if (actor < 1 || actor > MaxClients || !IsClientInGame(actor))
        return;
    int before = g_signalCount;
    RecordSignal(GetClientTeam(actor), "grenade_detonate", name, -1, actor);
    if (g_signalCount == before)
        return;
    g_signals[before].position[0] = event.GetFloat("x");
    g_signals[before].position[1] = event.GetFloat("y");
    g_signals[before].position[2] = event.GetFloat("z");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_roundActive || g_eventCount >= MAX_RECORDED_EVENTS)
        return;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim < 1 || victim > MaxClients || !IsClientInGame(victim))
        return;

    int slot = g_eventCount++;
    g_events[slot].kind = 1;
    g_events[slot].occurredAt = GetTime();
    g_events[slot].victimTeam = GetClientTeam(victim);
    g_events[slot].victimBot = IsFakeClient(victim) ? 1 : 0;
    g_events[slot].victimBotName[0] = '\0';
    if (g_events[slot].victimBot != 0)
        GetClientName(victim, g_events[slot].victimBotName, 64);

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    g_events[slot].actorTeam = 0;
    g_events[slot].actorBot = 0;
    g_events[slot].actorBotName[0] = '\0';
    if (attacker >= 1 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        g_events[slot].actorTeam = GetClientTeam(attacker);
        g_events[slot].actorBot = IsFakeClient(attacker) ? 1 : 0;
        if (g_events[slot].actorBot != 0)
            GetClientName(attacker, g_events[slot].actorBotName, 64);
    }
    event.GetString("weapon", g_events[slot].weapon, 48);
    strcopy(g_events[slot].site, 8, "none");
    GetClientAbsOrigin(victim, g_events[slot].position);
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (g_roundActive && !g_planted)
    {
        g_planted = true;
        g_plantMs = RoundElapsedMs();
    }
    if (!g_roundActive || g_eventCount >= MAX_RECORDED_EVENTS)
        return;
    int planter = GetClientOfUserId(event.GetInt("userid"));
    if (planter < 1 || planter > MaxClients || !IsClientInGame(planter))
        return;

    int slot = g_eventCount++;
    g_events[slot].kind = 2;
    g_events[slot].occurredAt = GetTime();
    g_events[slot].actorTeam = GetClientTeam(planter);
    g_events[slot].actorBot = IsFakeClient(planter) ? 1 : 0;
    g_events[slot].actorBotName[0] = '\0';
    if (g_events[slot].actorBot != 0)
        GetClientName(planter, g_events[slot].actorBotName, 64);
    g_events[slot].victimTeam = 0;
    g_events[slot].victimBot = 0;
    g_events[slot].victimBotName[0] = '\0';
    g_events[slot].weapon[0] = '\0';
    GetClientAbsOrigin(planter, g_events[slot].position);
    GetPlantSite(g_events[slot].position, g_events[slot].site, 8);
}

void GetPlantSite(const float position[3], char[] site, int length)
{
    strcopy(site, length, "none");
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    if (manager == -1 || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterA")
        || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterB"))
        return;
    float a[3], b[3];
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", a);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", b);
    if (GetVectorDistance(a, b) < 100.0)
        return;
    strcopy(site, length, GetVectorDistance(position, a) <= GetVectorDistance(position, b) ? "A" : "B");
}

public any Native_RecordOpeningPlan(Handle plugin, int numParams)
{
    if (!g_roundActive || numParams != 5)
        return 0;

    int team = GetNativeCell(1);
    int buy = GetNativeCell(2);
    int plan = GetNativeCell(3);
    int site = GetNativeCell(4);
    int botCount = GetNativeCell(5);
    if (buy < 0 || buy > 2 || plan < 0 || plan > 2 || site < -1 || site > 1
        || botCount < 1 || botCount > MaxClients)
        return 0;

    // Preserve the opening selection when an admin requests a later replan.
    if (team == CS_TEAM_CT && g_ctPlan == -1)
    {
        g_ctBuy = buy;
        g_ctPlan = plan;
        g_ctSite = site;
        g_ctBots = botCount;
    }
    else if (team == CS_TEAM_T && g_tPlan == -1)
    {
        g_tBuy = buy;
        g_tPlan = plan;
        g_tSite = site;
        g_tBots = botCount;
    }
    return 0;
}

public any Native_RecordSignal(Handle plugin, int numParams)
{
    if (numParams != 5)
        return 0;
    int team = GetNativeCell(1);
    char kind[32], detail[48];
    GetNativeString(2, kind, sizeof(kind));
    GetNativeString(3, detail, sizeof(detail));
    int site = GetNativeCell(4);
    int actor = GetNativeCell(5);
    if ((team != CS_TEAM_CT && team != CS_TEAM_T) || kind[0] == '\0'
        || site < -1 || site > 1)
        return 0;
    if (g_roundActive && g_planted && team == CS_TEAM_CT)
    {
        if (StrEqual(kind, "retake_stage") && g_retakeStageMs < 0) g_retakeStageMs = RoundElapsedMs();
        if (StrEqual(kind, "retake_commit") && g_retakeCommitMs < 0) g_retakeCommitMs = RoundElapsedMs();
    }
    if (StrEqual(kind, "first_sight"))
    {
        if (g_firstSight[team])
            return 0;
        g_firstSight[team] = true;
    }
    RecordSignal(team, kind, detail, site, actor);
    return 0;
}

void RecordSignal(int team, const char[] kind, const char[] detail, int site, int actor)
{
    if (!g_roundActive || (team != CS_TEAM_CT && team != CS_TEAM_T)
        || g_signalCount >= MAX_RECORDED_SIGNALS)
        return;
    int slot = g_signalCount++;
    g_signals[slot].elapsedMs = RoundToNearest((GetGameTime() - g_roundStartedGameTime) * 1000.0);
    if (g_signals[slot].elapsedMs < 0)
        g_signals[slot].elapsedMs = 0;
    g_signals[slot].team = team;
    strcopy(g_signals[slot].kind, 32, kind);
    strcopy(g_signals[slot].detail, 48, detail);
    GetSiteLabel(site, false, g_signals[slot].site, 8);
    g_signals[slot].actorBot = 0;
    g_signals[slot].actorBotName[0] = '\0';
    g_signals[slot].position[0] = 0.0;
    g_signals[slot].position[1] = 0.0;
    g_signals[slot].position[2] = 0.0;
    if (actor >= 1 && actor <= MaxClients && IsClientInGame(actor))
    {
        g_signals[slot].actorBot = IsFakeClient(actor) ? 1 : 0;
        if (g_signals[slot].actorBot != 0)
            GetClientName(actor, g_signals[slot].actorBotName, 64);
        GetClientAbsOrigin(actor, g_signals[slot].position);
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_roundActive)
        return;
    g_roundActive = false;
    int winner = event.GetInt("winner");
    if (GameRules_GetProp("m_bWarmupPeriod") != 0
        || (winner != CS_TEAM_CT && winner != CS_TEAM_T))
        return;

    char escapedMap[128];
    SQL_EscapeString(g_database, g_map, escapedMap, sizeof(escapedMap));
    char ctBuy[12], ctPlan[24], ctSite[8], tBuy[12], tPlan[24], tSite[8];
    GetBuyLabel(g_ctBuy, ctBuy, sizeof(ctBuy));
    GetPlanLabel(CS_TEAM_CT, g_ctPlan, ctPlan, sizeof(ctPlan));
    GetSiteLabel(g_ctSite, g_ctPlan == 0, ctSite, sizeof(ctSite));
    GetBuyLabel(g_tBuy, tBuy, sizeof(tBuy));
    GetPlanLabel(CS_TEAM_T, g_tPlan, tPlan, sizeof(tPlan));
    GetSiteLabel(g_tSite, false, tSite, sizeof(tSite));

    char query[1024];
    Format(query, sizeof(query),
        "INSERT INTO rounds (map,started_at,round_index,ct_buy,ct_plan,ct_site,ct_bots,"
        ... "t_buy,t_plan,t_site,t_bots,winner,reason) "
        ... "VALUES ('%s',%d,%d,'%s','%s','%s',%d,'%s','%s','%s',%d,%d,%d);",
        escapedMap, g_startedAt, g_roundIndex, ctBuy, ctPlan, ctSite, g_ctBots,
        tBuy, tPlan, tSite, g_tBots, winner, event.GetInt("reason"));
    if (!SQL_FastQuery(g_database, "BEGIN IMMEDIATE;"))
    {
        LogDatabaseError("begin round transaction");
        return;
    }
    if (!SQL_FastQuery(g_database, query))
    {
        LogDatabaseError("save round");
        SQL_FastQuery(g_database, "ROLLBACK;");
        return;
    }
    int roundId = SQL_GetInsertId(g_database);
    for (int index = 0; index < g_eventCount; index++)
    {
        if (!InsertEvent(roundId, index))
        {
            SQL_FastQuery(g_database, "ROLLBACK;");
            return;
        }
    }
    for (int index = 0; index < g_signalCount; index++)
    {
        if (!InsertSignal(roundId, index))
        {
            SQL_FastQuery(g_database, "ROLLBACK;");
            return;
        }
    }
    if (g_recordGear && SQL_FastQuery(g_database, "SAVEPOINT opening_telemetry;"))
    {
        // A telemetry write failure must not lose the existing match data.
        bool saved = InsertOpeningTelemetry(roundId);
        if ((!saved && !SQL_FastQuery(g_database, "ROLLBACK TO opening_telemetry;"))
            || !SQL_FastQuery(g_database, "RELEASE opening_telemetry;"))
        {
            LogDatabaseError("close opening telemetry savepoint");
            SQL_FastQuery(g_database, "ROLLBACK;");
            return;
        }
    }
    else if (g_recordGear) LogDatabaseError("begin opening telemetry savepoint");
    if (!SQL_FastQuery(g_database, "COMMIT;"))
    {
        LogDatabaseError("commit round transaction");
        SQL_FastQuery(g_database, "ROLLBACK;");
    }
}

bool InsertOpeningTelemetry(int roundId)
{
    char query[768];
    if (g_gearCaptured)
    {
        for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
        {
            OpeningGear gear;
            gear = g_openingGear[team];
            char plan[12];
            if (gear.purchasePlan == 3) strcopy(plan, sizeof(plan), "reset");
            else if (gear.purchasePlan == 4) strcopy(plan, sizeof(plan), "must_buy");
            else if (gear.purchasePlan < 0) strcopy(plan, sizeof(plan), "unknown");
            else GetBuyLabel(gear.purchasePlan, plan, sizeof(plan));
            Format(query, sizeof(query),
                "INSERT INTO opening_gear (round_id,team,purchase_plan,players,bots,rifles,snipers,smgs,shotguns,"
                ... "other_primary,pistols_only,armored,helmets,kits,utility,smokes,flashes) "
                ... "VALUES (%d,%d,'%s',%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d);",
                roundId, team, plan, gear.players, gear.bots, gear.rifles, gear.snipers, gear.smgs, gear.shotguns,
                gear.otherPrimary, gear.pistolsOnly, gear.armored, gear.helmets, gear.kits, gear.utility, gear.smokes, gear.flashes);
            if (!SQL_FastQuery(g_database, query)) { LogDatabaseError("save opening gear"); return false; }
        }
    }
    if (g_planted)
    {
        char stage[16], commit[16], began[16], kit[16];
        OptionalInteger(g_retakeStageMs, stage, sizeof(stage));
        OptionalInteger(g_retakeCommitMs, commit, sizeof(commit));
        OptionalInteger(g_defuseBeginMs, began, sizeof(began));
        OptionalInteger(g_kitAtDefuse, kit, sizeof(kit));
        Format(query, sizeof(query),
            "INSERT INTO retake_outcomes (round_id,plant_ms,stage_ms,commit_ms,defuse_begin_ms,kit_at_defuse,defused) "
            ... "VALUES (%d,%d,%s,%s,%s,%s,%d);", roundId, g_plantMs, stage, commit, began, kit, g_defused);
        if (!SQL_FastQuery(g_database, query)) { LogDatabaseError("save retake outcome"); return false; }
    }
    return true;
}

void OptionalInteger(int value, char[] buffer, int length)
{
    if (value < 0) strcopy(buffer, length, "NULL");
    else IntToString(value, buffer, length);
}

bool InsertSignal(int roundId, int index)
{
    char kind[64], detail[96], actorName[128];
    SQL_EscapeString(g_database, g_signals[index].kind, kind, sizeof(kind));
    SQL_EscapeString(g_database, g_signals[index].detail, detail, sizeof(detail));
    SQL_EscapeString(g_database, g_signals[index].actorBotName, actorName, sizeof(actorName));
    char query[768];
    Format(query, sizeof(query),
        "INSERT INTO signals (round_id,elapsed_ms,team,kind,detail,site,actor_is_bot,actor_bot_name,x,y,z) "
        ... "VALUES (%d,%d,%d,'%s','%s','%s',%d,'%s',%.3f,%.3f,%.3f);",
        roundId, g_signals[index].elapsedMs, g_signals[index].team,
        kind, detail, g_signals[index].site, g_signals[index].actorBot,
        actorName, g_signals[index].position[0], g_signals[index].position[1],
        g_signals[index].position[2]);
    if (SQL_FastQuery(g_database, query))
        return true;
    LogDatabaseError("save signal");
    return false;
}

bool InsertEvent(int roundId, int index)
{
    char actorName[128], victimName[128], weapon[96];
    SQL_EscapeString(g_database, g_events[index].actorBotName, actorName, sizeof(actorName));
    SQL_EscapeString(g_database, g_events[index].victimBotName, victimName, sizeof(victimName));
    SQL_EscapeString(g_database, g_events[index].weapon, weapon, sizeof(weapon));
    char kind[8];
    strcopy(kind, sizeof(kind), g_events[index].kind == 2 ? "plant" : "kill");
    char query[1024];
    Format(query, sizeof(query),
        "INSERT INTO events (round_id,kind,occurred_at,actor_team,actor_is_bot,actor_bot_name,"
        ... "victim_team,victim_is_bot,victim_bot_name,weapon,site,x,y,z) VALUES "
        ... "(%d,'%s',%d,%d,%d,'%s',%d,%d,'%s','%s','%s',%.3f,%.3f,%.3f);",
        roundId, kind, g_events[index].occurredAt, g_events[index].actorTeam,
        g_events[index].actorBot, actorName, g_events[index].victimTeam,
        g_events[index].victimBot, victimName, weapon, g_events[index].site,
        g_events[index].position[0], g_events[index].position[1], g_events[index].position[2]);
    if (SQL_FastQuery(g_database, query))
        return true;
    LogDatabaseError("save event");
    return false;
}

void LogDatabaseError(const char[] action)
{
    char error[256];
    SQL_GetError(g_database, error, sizeof(error));
    LogError("BOT experience could not %s: %s", action, error);
}

void GetBuyLabel(int buy, char[] label, int length)
{
    if (buy == 0) strcopy(label, length, "eco");
    else if (buy == 1) strcopy(label, length, "force");
    else if (buy == 2) strcopy(label, length, "full");
    else strcopy(label, length, "none");
}

void GetPlanLabel(int team, int plan, char[] label, int length)
{
    if (plan < 0) strcopy(label, length, "none");
    else if (team == CS_TEAM_CT && plan == 0) strcopy(label, length, "standard");
    else if (team == CS_TEAM_CT && plan == 1) strcopy(label, length, "push");
    else if (team == CS_TEAM_CT) strcopy(label, length, "stack");
    else if (plan == 0) strcopy(label, length, "default");
    else if (plan == 1) strcopy(label, length, "rush");
    else strcopy(label, length, "split");
}

void GetSiteLabel(int site, bool both, char[] label, int length)
{
    if (both) strcopy(label, length, "both");
    else if (site == 0) strcopy(label, length, "A");
    else if (site == 1) strcopy(label, length, "B");
    else strcopy(label, length, "none");
}
