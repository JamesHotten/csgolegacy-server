#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <bot_equipment_policy>
#include <bot_ct_watch_sectors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1.3"
#define MAX_CANDIDATES 256
#define ANCHORS_PER_SITE 2
#define TEAM_ANY -2

// Minimal declarations for the already installed SourcePawn NavMesh parser.
// They are optional so disabling/removing navmesh safely falls back to vanilla AI.
native bool NavMesh_Exists();
native int NavMesh_GetNearestArea(const float pos[3], bool anyZ=false, float maxDist=10000.0, bool checkLOS=false, bool checkGround=true, int team=TEAM_ANY);
native void NavMesh_CollectSurroundingAreas(ArrayStack stack, int startArea, float travelDistLimit=1500.0, float maxStepUpLimit=18.0, float maxDropDownLimit=100.0);
native bool NavMeshArea_GetCenter(int areaIndex, float buffer[3]);
native void NavMeshArea_GetClosestPointOnArea(int areaIndex, const float position[3], float result[3]);
native void NavMeshArea_GetPlace(int areaIndex, char[] buffer, int maxlen);
native void NavMeshArea_GetPlaceCanonical(int areaIndex, char[] buffer, int maxlen);
native int NavMesh_WorldToGridX(float x);
native int NavMesh_WorldToGridY(float y);
native void NavMesh_GetAreasOnGrid(ArrayStack areas, int x, int y);
native void NavMeshArea_GetHidingSpots(ArrayStack stack, int areaIndex);
native void NavHidingSpot_GetPosition(int hidingSpotIndex, float buffer[3]);
native void BotExperience_RecordOpeningPlan(int team, int buy, int plan, int site, int botCount);
native void BotExperience_RecordSignal(int team, const char[] kind, const char[] detail, int site, int actor);
native bool BotStuff_CanSeeLooseC4(int client, int bomb);
native bool BotStuff_HasVisibleEnemy(int client);

#include <bot_tactical_angles>
#include <bot_ct_entrance_watch>

enum TacticalPhase
{
    Phase_Idle = 0,
    Phase_Initial,
    Phase_CarrierResponse,
    Phase_GuardLooseBomb,
    Phase_RetakeStage,
    Phase_RetakeCommit
};

enum BuyState
{
    Buy_Eco = 0,
    Buy_Force,
    Buy_Full
};

enum DefensePlan
{
    Plan_Standard = 0,
    Plan_SingleSitePush,
    Plan_ChokeStack
};

enum RouteType
{
    Route_Default = 0,
    Route_Fastest,
    Route_Safest,
    Route_Retreat
};

public Plugin myinfo =
{
    name = "BetterBots CT Tactical Director",
    author = "JamesHotten server project",
    description = "Reversible CT setup, pressure, loose-bomb defense and retake coordination",
    version = PLUGIN_VERSION,
    url = "https://github.com/JamesHotten/csgolegacy-server"
};

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvEntranceWatch;
ConVar g_cvInitialHold;
ConVar g_cvRetakeStage;
ConVar g_cvRetakeCommit;
ConVar g_cvRetakeStageTimeout;
ConVar g_cvSyncMinReady;
ConVar g_cvGuardCount;
ConVar g_cvFullPushChance;
ConVar g_cvFullStackChance;
ConVar g_cvForcePushChance;
ConVar g_cvForceStackChance;
ConVar g_cvEcoPushChance;
ConVar g_cvEcoStackChance;
ConVar g_cvReinforceOnDeath;
ConVar g_cvReinforceOnContact;
ConVar g_cvContactCooldown;
ConVar g_cvReinforceHold;
ConVar g_cvRadioReport;
ConVar g_cvNavigationStallTimeout;
ConVar g_cvMidReorganize;

TacticalPhase g_phase = Phase_Idle;
BuyState g_buyState = Buy_Full;
DefensePlan g_plan = Plan_Standard;
int g_planSite = -1;
float g_phaseStarted;
float g_siteA[3];
float g_siteB[3];
float g_tSpawn[3];
float g_bombPosition[3];
bool g_geometryReady;
bool g_bombPlanted;
bool g_roundLive;
int g_guardBombRef = INVALID_ENT_REFERENCE;
int g_guardSlot[MAXPLAYERS + 1];
int g_guardStalls[MAXPLAYERS + 1];
float g_lastCombatAt[MAXPLAYERS + 1];
float g_guardReleasedAt[MAXPLAYERS + 1];
float g_blindUntil[MAXPLAYERS + 1];
bool g_retakeContact;
float g_lastContactAt[2];
int g_siteEnemyUserId[2][4];
float g_siteEnemySeenAt[2][4];
bool g_reorganizedSite[2];
bool g_fullRotateSite[2];
float g_siteCasualtyAt[2];
int g_lastReinforcement[2];
float g_carrierLastPlanAt;
float g_carrierLastPosition[3];

bool g_hasOrder[MAXPLAYERS + 1];
bool g_hasLook[MAXPLAYERS + 1];
bool g_combatReleased[MAXPLAYERS + 1];
float g_orderGoal[MAXPLAYERS + 1][3];
float g_orderLook[MAXPLAYERS + 1][3];
int g_orderRoute[MAXPLAYERS + 1];
float g_orderExpires[MAXPLAYERS + 1];
float g_orderLastProgressDistance[MAXPLAYERS + 1];
float g_orderLastProgressAt[MAXPLAYERS + 1];
float g_orderLastProgressPosition[MAXPLAYERS + 1][3];
bool g_orderArrived[MAXPLAYERS + 1];

float g_candidates[MAX_CANDIDATES][3];
int g_candidateCount;
float g_targets[MAXPLAYERS + 1][3];
int g_targetCount;
char g_anchorPlaces[2][ANCHORS_PER_SITE][32];
float g_anchorPositions[2][ANCHORS_PER_SITE][3];
bool g_anchorAttempted[2][ANCHORS_PER_SITE];
bool g_anchorResolved[2][ANCHORS_PER_SITE];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax)
{
    RegPluginLibrary("bot_ct_tactics");
    CreateNative("BotCTTactics_GetOrder", Native_GetOrder);
    CreateNative("BotCTTactics_GetAim", Native_GetAim);
    CreateNative("BotCTTactics_ReportContact", Native_ReportContact);

    MarkNativeAsOptional("NavMesh_Exists");
    MarkNativeAsOptional("NavMesh_GetNearestArea");
    MarkNativeAsOptional("NavMesh_CollectSurroundingAreas");
    MarkNativeAsOptional("NavMeshArea_GetCenter");
    MarkNativeAsOptional("NavMeshArea_GetClosestPointOnArea");
    MarkNativeAsOptional("NavMeshArea_GetPlace");
    MarkNativeAsOptional("NavMeshArea_GetPlaceCanonical");
    MarkNativeAsOptional("NavMesh_WorldToGridX");
    MarkNativeAsOptional("NavMesh_WorldToGridY");
    MarkNativeAsOptional("NavMesh_GetAreasOnGrid");
    MarkNativeAsOptional("NavMeshArea_GetHidingSpots");
    MarkNativeAsOptional("NavHidingSpot_GetPosition");
    MarkNativeAsOptional("BotExperience_RecordOpeningPlan");
    MarkNativeAsOptional("BotExperience_RecordSignal");
    MarkNativeAsOptional("BotStuff_CanSeeLooseC4");
    MarkNativeAsOptional("BotStuff_HasVisibleEnemy");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_bot_ct_tactics_enable", "1", "Enable the reversible CT tactical director.", _, true, 0.0, true, 1.0);
    g_cvDebug = CreateConVar("sm_bot_ct_tactics_debug", "0", "Log CT tactical plans and assignments.", _, true, 0.0, true, 1.0);
    g_cvEntranceWatch = CreateConVar("sm_bot_ct_entrance_watch", "1", "Use visible named entrances for standard Mirage/Dust2 opening holds; otherwise use generic angles.", _, true, 0.0, true, 1.0);
    g_cvEntranceWatch.AddChangeHook(OnEntranceWatchChanged);
    g_cvInitialHold = CreateConVar("sm_bot_ct_tactics_initial_hold", "70.0", "Seconds between CT setup reviews; intact anchors remain in place.", _, true, 5.0, true, 105.0);
    g_cvRetakeStage = CreateConVar("sm_bot_ct_tactics_retake_stage", "6.0", "Minimum seconds spent taking distinct retake approaches.", _, true, 0.5, true, 12.0);
    g_cvRetakeCommit = CreateConVar("sm_bot_ct_tactics_retake_commit", "14.0", "Maximum seconds to push the planted bomb after staging.", _, true, 2.0, true, 25.0);
    g_cvRetakeStageTimeout = CreateConVar("sm_bot_ct_tactics_retake_stage_timeout", "12.0", "Hard timeout before committing the retake.", _, true, 2.0, true, 20.0);
    g_cvSyncMinReady = CreateConVar("sm_bot_ct_tactics_sync_min_ready", "50", "Percent of active ordered CT bots required at retake staging goals.", _, true, 20.0, true, 100.0);
    g_cvGuardCount = CreateConVar("sm_bot_ct_tactics_guard_count", "0", "Dropped C4 guards: 0 = all alive CT bots; positive values cap the count.", _, true, 0.0, true, 5.0);

    g_cvFullPushChance = CreateConVar("sm_bot_ct_tactics_full_push_chance", "10", "Full-buy chance for a single-site push.", _, true, 0.0, true, 100.0);
    g_cvFullStackChance = CreateConVar("sm_bot_ct_tactics_full_stack_chance", "15", "Full-buy chance for a choke stack.", _, true, 0.0, true, 100.0);
    g_cvForcePushChance = CreateConVar("sm_bot_ct_tactics_force_push_chance", "35", "Force-buy chance for a single-site push.", _, true, 0.0, true, 100.0);
    g_cvForceStackChance = CreateConVar("sm_bot_ct_tactics_force_stack_chance", "45", "Force-buy chance for a choke stack.", _, true, 0.0, true, 100.0);
    g_cvEcoPushChance = CreateConVar("sm_bot_ct_tactics_eco_push_chance", "35", "Eco chance for a single-site push.", _, true, 0.0, true, 100.0);
    g_cvEcoStackChance = CreateConVar("sm_bot_ct_tactics_eco_stack_chance", "55", "Eco chance for a choke stack.", _, true, 0.0, true, 100.0);
    g_cvReinforceOnDeath = CreateConVar("sm_bot_ct_tactics_reinforce_on_death", "1", "Replace a fallen CT's defensive coverage.", _, true, 0.0, true, 1.0);
    g_cvReinforceOnContact = CreateConVar("sm_bot_ct_tactics_reinforce_on_contact", "1", "Send one available CT bot toward a reported contact.", _, true, 0.0, true, 1.0);
    g_cvContactCooldown = CreateConVar("sm_bot_ct_tactics_contact_cooldown", "5.0", "Minimum seconds between reports/reinforcements at the same site.", _, true, 1.0, true, 15.0);
    g_cvReinforceHold = CreateConVar("sm_bot_ct_tactics_reinforce_hold", "12.0", "Maximum seconds for an individual reinforcement order.", _, true, 3.0, true, 25.0);
    g_cvRadioReport = CreateConVar("sm_bot_ct_tactics_radio_report", "1", "Use bot radio and team chat for enemy reports.", _, true, 0.0, true, 1.0);
    g_cvNavigationStallTimeout = CreateConVar("sm_bot_ct_tactics_navigation_stall_timeout", "3.0", "Release a CT order to native AI after this many seconds without meaningful route progress.", _, true, 1.5, true, 8.0);
    g_cvMidReorganize = CreateConVar("sm_bot_ct_mid_reorganize_enable", "1", "Reinforce on two confirmed attackers; permit full rotation only against a strong confirmed execute.", _, true, 0.0, true, 1.0);

    g_cvEnabled.AddChangeHook(OnEnabledChanged);
    AutoExecConfig(true, "bot_ct_tactics");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("bomb_dropped", Event_BombDropped, EventHookMode_PostNoCopy);
    HookEvent("bomb_pickup", Event_BombPickup, EventHookMode_PostNoCopy);
    HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_PostNoCopy);
    HookEvent("bomb_begindefuse", Event_BombBeginDefuse, EventHookMode_Post);
    HookEvent("bomb_defused", Event_RoundObjectiveComplete, EventHookMode_PostNoCopy);
    HookEvent("bomb_exploded", Event_RoundObjectiveComplete, EventHookMode_PostNoCopy);
    HookEvent("weapon_fire", Event_Contact, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);

    RegAdminCmd("sm_ct_tactics_status", Command_Status, ADMFLAG_GENERIC, "Show the current CT tactical plan and active orders.");
    RegAdminCmd("sm_ct_tactics_replan", Command_Replan, ADMFLAG_GENERIC, "Rebuild the current round's CT setup.");

    CreateTimer(0.5, Timer_Update, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    ResetDirector();
    ClearCombatReleases();
    g_bombPlanted = false;
    g_roundLive = false;
    g_geometryReady = false;
    ConfigureMapAnchorProfile();
}

public void OnEntranceWatchChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ConfigureMapAnchorProfile(); // Next round/replan must not reuse the other decoding mode's cached anchors.
}

void CTWatch_GetPlace(int area, char[] place, int length)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));
    if (g_cvEntranceWatch.BoolValue && (StrEqual(map, "de_mirage") || StrEqual(map, "de_dust2"))
        && NativeAvailable("NavMeshArea_GetPlaceCanonical"))
        NavMeshArea_GetPlaceCanonical(area, place, length);
    else
        NavMeshArea_GetPlace(area, place, length);
}

public void OnClientPutInServer(int client)
{
    g_combatReleased[client] = false;
    g_guardSlot[client] = -1;
    g_guardStalls[client] = 0;
    g_lastCombatAt[client] = -100.0;
    g_guardReleasedAt[client] = -100.0;
    g_blindUntil[client] = 0.0;
    g_hasOrder[client] = false;
    g_hasLook[client] = false;
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        ResetDirector();
}

public Action Command_Status(int client, int args)
{
    int active;
    int ctBots;
    int armored;
    int primaryWithoutArmor;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_hasOrder[i])
            active++;
        if (!IsCTBot(i))
            continue;
        ctBots++;
        int armor = GetEntProp(i, Prop_Data, "m_ArmorValue");
        if (armor > 0)
            armored++;
        if (armor == 0 && GetPlayerWeaponSlot(i, CS_SLOT_PRIMARY) != -1)
            primaryWithoutArmor++;
    }

    char phase[24], buy[12], plan[24];
    GetPhaseName(g_phase, phase, sizeof(phase));
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    int syncReady, syncOrdered;
    GetOrderProgress(180.0, syncReady, syncOrdered);
    ReplyToCommand(client, "[CT Tactics] enabled=%d geometry=%d phase=%s buy=%s plan=%s active_orders=%d",
        g_cvEnabled.BoolValue, g_geometryReady, phase, buy, plan, active);
    ReplyToCommand(client, "[CT Tactics] ct_bots=%d armored=%d primary_without_armor=%d",
        ctBots, armored, primaryWithoutArmor);
    ReplyToCommand(client, "[CT Tactics] retake_ready=%d/%d contact=%d", syncReady, syncOrdered, g_retakeContact);
    int guards;
    for (int i = 1; i <= MaxClients; i++)
        if (IsCTBot(i) && g_guardSlot[i] >= 0) guards++;
    ReplyToCommand(client, "[CT Tactics] loose_c4_known=%d guard_members=%d perception=%d",
        g_guardBombRef != INVALID_ENT_REFERENCE, guards,
        NativeAvailable("BotStuff_CanSeeLooseC4") && NativeAvailable("BotStuff_HasVisibleEnemy"));
    ReplyToCommand(client, "[CT Tactics] mid_reorganize_enabled=%d reorg_A/B=%d/%d full_rotate_A/B=%d/%d",
        g_cvMidReorganize.BoolValue, g_reorganizedSite[0], g_reorganizedSite[1],
        g_fullRotateSite[0], g_fullRotateSite[1]);
    return Plugin_Handled;
}

public Action Command_Replan(int client, int args)
{
    if (!g_cvEnabled.BoolValue)
    {
        ReplyToCommand(client, "[CT Tactics] Enable sm_bot_ct_tactics_enable first.");
        return Plugin_Handled;
    }

    if (!RefreshGeometry() || !NavMeshReady())
    {
        ReplyToCommand(client, "[CT Tactics] Bombsite or navmesh data is unavailable on this map.");
        return Plugin_Handled;
    }

    PlanInitialDefense();
    char buy[12], plan[24];
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    ReplyToCommand(client, "[CT Tactics] Replanned: buy=%s plan=%s", buy, plan);
    return Plugin_Handled;
}

public any Native_GetOrder(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!g_cvEnabled.BoolValue || client < 1 || client > MaxClients || !g_hasOrder[client]
        || g_combatReleased[client] || !IsCTBot(client))
        return false;

    if (g_orderExpires[client] > 0.0 && GetGameTime() >= g_orderExpires[client])
    {
        g_hasOrder[client] = false;
        g_orderExpires[client] = 0.0;
        g_orderLastProgressDistance[client] = 0.0;
        g_orderLastProgressAt[client] = 0.0;
        g_orderArrived[client] = false;
        return false;
    }

    SetNativeArray(2, g_orderGoal[client], 3);
    SetNativeCellRef(3, g_orderRoute[client]);
    return true;
}

public any Native_GetAim(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!g_cvEnabled.BoolValue || client < 1 || client > MaxClients || !g_hasOrder[client]
        || !g_hasLook[client] || g_combatReleased[client] || !IsCTBot(client))
        return false;

    SetNativeArray(2, g_orderLook[client], 3);
    return true;
}

public any Native_ReportContact(Handle plugin, int numParams)
{
    int spotter = GetNativeCell(1);
    int enemy = GetNativeCell(2);
    if (!g_cvEnabled.BoolValue || g_bombPlanted || !g_geometryReady || !NavMeshReady()
        || !IsCTBot(spotter) || enemy < 1 || enemy > MaxClients
        || !IsClientInGame(enemy) || !IsPlayerAlive(enemy) || GetClientTeam(enemy) != CS_TEAM_T)
        return false;

    float enemyPosition[3];
    GetClientAbsOrigin(enemy, enemyPosition);
    int site = NearestSite(enemyPosition);
    ExperienceSignal("first_sight", "visible_enemy", site, spotter);
    float now = GetGameTime();
    // Refresh even when site radio is on cooldown or this bot already yielded
    // its order. Otherwise it can be pulled back into formation mid-fight.
    g_lastCombatAt[spotter] = now;
    if ((g_phase == Phase_Initial || g_phase == Phase_CarrierResponse) && IsBombCarrier(enemy))
    {
        // The spotter keeps fighting. Every other available CT abandons the
        // initial split, including the last weak-side anchor.
        ReleaseOrder(spotter, "bomb carrier spotted");
        g_combatReleased[spotter] = true;
        PlanCarrierResponse(enemyPosition);
    }
    float siteDistance = Distance2D(enemyPosition, site == 0 ? g_siteA : g_siteB);
    float otherDistance = Distance2D(enemyPosition, site == 0 ? g_siteB : g_siteA);
    bool credibleSite = siteDistance <= 900.0 && otherDistance >= siteDistance + 300.0;
    if (credibleSite && g_phase == Phase_Initial)
    {
        RememberSiteEnemy(site, GetClientUserId(enemy), now);
        TryReorganizeDefense(site, enemyPosition, spotter, now);
    }
    if (g_lastContactAt[site] > 0.0 && now < g_lastContactAt[site] + g_cvContactCooldown.FloatValue)
        return false;
    g_lastContactAt[site] = now;

    ReleaseOrder(spotter, "enemy spotted");
    ReportEnemy(spotter, enemyPosition, site);
    if (g_cvReinforceOnContact.BoolValue && credibleSite && !g_reorganizedSite[site]
        && g_phase != Phase_CarrierResponse)
        RequestReinforcement(enemyPosition, site, spotter, "enemy contact");
    return true;
}

bool IsBombCarrier(int client)
{
    if (GetPlayerWeaponSlot(client, CS_SLOT_C4) != -1)
        return true;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "weapon_c4")) != -1)
        if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
            return true;
    return false;
}

void PlanCarrierResponse(const float carrierPosition[3])
{
    float now = GetGameTime();
    if (g_phase == Phase_CarrierResponse && now < g_carrierLastPlanAt + 8.0)
        return;
    if (g_phase == Phase_CarrierResponse && Distance2D(carrierPosition, g_carrierLastPosition) < 500.0)
        return;

    int bots[MAXPLAYERS + 1];
    int count = CollectCTBots(bots);
    if (count == 0)
        return;
    g_targetCount = 0;
    BuildAround(carrierPosition, count, 250.0, 600.0, false, 0.0, 0.0);
    FillMissingTargetsAt(count, carrierPosition);
    AssignTargets(bots, count, Route_Fastest);
    g_phase = Phase_CarrierResponse;
    g_phaseStarted = now;
    g_carrierLastPlanAt = now;
    CopyVector(carrierPosition, g_carrierLastPosition);
    ExperienceSignal("carrier_rotate", "bomb_carrier_spotted", NearestSite(carrierPosition), 0);
    DebugLog("C4 carrier spotted: all available CT bots rotating to the last confirmed position.");
}

void RememberSiteEnemy(int site, int userId, float now)
{
    if (userId == 0)
        return;
    int existing = -1;
    for (int slot = 0; slot < 4; slot++)
        if (g_siteEnemyUserId[site][slot] == userId)
            existing = slot;
    if (existing < 0)
        existing = 3;
    for (int slot = existing; slot > 0; slot--)
    {
        g_siteEnemyUserId[site][slot] = g_siteEnemyUserId[site][slot - 1];
        g_siteEnemySeenAt[site][slot] = g_siteEnemySeenAt[site][slot - 1];
    }
    g_siteEnemyUserId[site][0] = userId;
    g_siteEnemySeenAt[site][0] = now;
}

void TryReorganizeDefense(int site, const float contactPosition[3], int spotter, float now)
{
    if (!g_cvMidReorganize.BoolValue || g_bombPlanted || g_plan != Plan_Standard)
        return;
    int recentEnemies;
    for (int slot = 0; slot < 4; slot++)
        if (g_siteEnemyUserId[site][slot] != 0 && now - g_siteEnemySeenAt[site][slot] <= 10.0)
            recentEnemies++;

    if (!g_fullRotateSite[0] && !g_fullRotateSite[1] && (recentEnemies >= 4
        || (recentEnemies >= 3 && g_siteCasualtyAt[site] > 0.0 && now - g_siteCasualtyAt[site] <= 10.0)))
    {
        // A confirmed hard execute is worth vacating the weak side. If its
        // last defender is already fighting, leave native combat in control.
        int rotated;
        for (int attempt = 0; attempt < MaxClients; attempt++)
        {
            if (RequestReinforcement(contactPosition, site, spotter, "confirmed hard execute", 0, true, true) == 0)
                break;
            rotated++;
        }
        if (rotated > 0)
        {
            g_fullRotateSite[site] = true;
            g_reorganizedSite[site] = true;
            ExperienceSignal("full_rotate", "confirmed_execute", site, 0);
            DebugLog("CT full rotation toward %s after strong execute evidence: %d weak-side defenders.", site == 0 ? "A" : "B", rotated);
        }
        return;
    }
    if (g_reorganizedSite[site] || recentEnemies < 2)
        return;
    g_reorganizedSite[site] = true;
    RequestReinforcement(contactPosition, site, spotter, "confirmed multi-enemy site pressure", g_lastReinforcement[site]);
    ExperienceSignal("reorganize", "multi_enemy_pressure", site, 0);
    DebugLog("Mid-round CT defense reorganized toward %s; opposite-site anchor retained.", site == 0 ? "A" : "B");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetDirector();
    g_roundLive = false;
    ClearCombatReleases();
    g_bombPlanted = false;
    g_retakeContact = false;
    g_lastContactAt[0] = 0.0;
    g_lastContactAt[1] = 0.0;
    g_carrierLastPlanAt = 0.0;
    for (int site = 0; site < 2; site++)
    {
        g_reorganizedSite[site] = false;
        g_fullRotateSite[site] = false;
        g_siteCasualtyAt[site] = 0.0;
        g_lastReinforcement[site] = 0;
        for (int slot = 0; slot < 4; slot++)
        {
            g_siteEnemyUserId[site][slot] = 0;
            g_siteEnemySeenAt[site][slot] = 0.0;
        }
    }
}

public void Event_FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_roundLive = GameRules_GetProp("m_bWarmupPeriod") == 0;
    if (!g_cvEnabled.BoolValue || !RefreshGeometry() || !NavMeshReady())
    {
        DebugLog("Initial plan skipped: geometry or navmesh unavailable.");
        return;
    }

    // Publish orders in the same frame that movement is released. Delaying
    // this allowed native BetterBots to choose a site first and visibly turn
    // around when the tactical plan arrived 0.1 seconds later.
    PlanInitialDefense();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_roundLive = false;
    ResetDirector();
    g_bombPlanted = false;
}

public void Event_BombDropped(Event event, const char[] name, bool dontBroadcast)
{
    // The global event is not CT knowledge. The existing half-second update
    // waits for an alive CT's forward, unobstructed, smoke-free view instead.
}

public void Event_BombPickup(Event event, const char[] name, bool dontBroadcast)
{
    if (g_phase == Phase_GuardLooseBomb)
        ResetDirector();
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    ClearLooseBombGuard();
    g_bombPlanted = true;
    g_retakeContact = false;
    // A CT that fought during the site take must still receive the new retake
    // plan after the bomb is planted.
    ClearCombatReleases();
    if (g_cvEnabled.BoolValue)
        CreateTimer(0.15, Timer_PlanRetake, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlanRetake(Handle timer)
{
    int bomb = FindEntityByClassname(-1, "planted_c4");
    if (bomb == -1)
        return Plugin_Stop;

    GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", g_bombPosition);
    PlanRetake(false);
    return Plugin_Stop;
}

public void Event_BombBeginDefuse(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    ReleaseOrder(client, "defusing");
}

public void Event_RoundObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
    g_roundLive = false;
    ResetDirector();
    g_bombPlanted = false;
}

public void Event_Contact(Event event, const char[] name, bool dontBroadcast)
{
    if (IsUtilityWeaponFire(event))
        return; // Utility use must not release an otherwise valid CT position.
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (g_phase == Phase_RetakeStage && IsCTBot(client))
        g_retakeContact = true;
    ReleaseOrder(client, "weapon contact");
}

bool IsUtilityWeaponFire(Event event)
{
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    ReplaceString(weapon, sizeof(weapon), "weapon_", "", false);
    return StrEqual(weapon, "smokegrenade", false)
        || StrEqual(weapon, "flashbang", false)
        || StrEqual(weapon, "hegrenade", false)
        || StrEqual(weapon, "molotov", false)
        || StrEqual(weapon, "incgrenade", false)
        || StrEqual(weapon, "decoy", false)
        || StrEqual(weapon, "tagrenade", false);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (g_phase == Phase_RetakeStage && (IsCTBot(victim) || IsCTBot(attacker)))
        g_retakeContact = true;
    ReleaseOrder(victim, "hurt");
    ReleaseOrder(attacker, "combat");
}

public void Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client >= 1 && client <= MaxClients)
        g_blindUntil[client] = GetGameTime() + event.GetFloat("blind_duration");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client >= 1 && client <= MaxClients)
    {
        int attacker = GetClientOfUserId(event.GetInt("attacker"));
        if (g_phase == Phase_Initial && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT
            && attacker >= 1 && IsClientInGame(attacker) && GetClientTeam(attacker) == CS_TEAM_T)
        {
            float casualtyPosition[3];
            GetClientAbsOrigin(client, casualtyPosition);
            int casualtySite = NearestSite(casualtyPosition);
            float siteDistance = Distance2D(casualtyPosition, casualtySite == 0 ? g_siteA : g_siteB);
            float otherDistance = Distance2D(casualtyPosition, casualtySite == 0 ? g_siteB : g_siteA);
            if (siteDistance <= 900.0 && otherDistance >= siteDistance + 300.0)
            {
                g_siteCasualtyAt[casualtySite] = GetGameTime();
                TryReorganizeDefense(casualtySite, casualtyPosition, client, GetGameTime());
            }
        }
        if (g_cvEnabled.BoolValue && g_cvReinforceOnDeath.BoolValue && !g_bombPlanted
            && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT && g_geometryReady && NavMeshReady())
        {
            float deathPosition[3];
            GetClientAbsOrigin(client, deathPosition);
            int deathSite = NearestSite(deathPosition);
            if (!g_fullRotateSite[deathSite] && g_phase != Phase_CarrierResponse)
                RequestReinforcement(deathPosition, deathSite, client, "CT casualty");
        }
        g_hasOrder[client] = false;
        g_orderExpires[client] = 0.0;
        g_orderArrived[client] = false;
        g_guardSlot[client] = -1;
    }
}

public Action Timer_Update(Handle timer)
{
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;

    UpdateLooseBombGuard();
    if (g_phase == Phase_Idle)
        return Plugin_Continue;
    ReleaseStalledOrders();
    float elapsed = GetGameTime() - g_phaseStarted;
    if (g_phase == Phase_Initial && elapsed >= g_cvInitialHold.FloatValue)
    {
        // Reviewing the setup must not remove every anchor before a late
        // execute. Contact and casualties still trigger targeted support.
        g_phaseStarted = GetGameTime();
        DebugLog("CT setup reviewed; surviving anchors retained.");
    }
    else if (g_phase == Phase_RetakeStage
        && (g_retakeContact
            || (elapsed >= g_cvRetakeStage.FloatValue && OrdersMeetReadyPercent(180.0, g_cvSyncMinReady.IntValue))
            || elapsed >= g_cvRetakeStageTimeout.FloatValue))
    {
        PlanRetake(true);
    }
    else if (g_phase == Phase_RetakeCommit && elapsed >= g_cvRetakeCommit.FloatValue)
    {
        DebugLog("Retake commit expired; returning remaining bots to native AI.");
        ResetDirector();
    }
    return Plugin_Continue;
}

void PlanInitialDefense()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectCTBots(bots);
    if (count == 0)
        return;

    // An administrator can explicitly replan mid-round; do not retain loose
    // C4 membership/cache while publishing an unrelated opening formation.
    ClearLooseBombGuard();
    g_buyState = ClassifyCTBuy();
    // A pistol round has the same low equipment profile as an eco, but it is
    // not an eco strategy round. Keep both regulation pistol rounds on the
    // balanced 2A/2B/rotator setup; reserve pressure/stack rolls for actual
    // eco and force-buy rounds.
    g_plan = IsRegulationPistolRound() ? Plan_Standard : ChooseDefensePlan(g_buyState);
    g_planSite = -1;
    g_targetCount = 0;

    if (g_plan == Plan_Standard)
        BuildStandardTargets(count);
    else if (g_plan == Plan_SingleSitePush)
        BuildPushTargets(count);
    else
        BuildStackTargets(count);

    FillMissingTargets(count);
    // Initial deployments are time-sensitive and must not inherit BetterBots'
    // accumulated danger weights. SAFEST_ROUTE can send an A defender through
    // B/T spawn; FASTEST_ROUTE keeps the setup on its intended side of the map.
    AssignTargets(bots, count, Route_Fastest, -1, true);
    g_phase = Phase_Initial;
    g_phaseStarted = GetGameTime();
    ExperienceSignal("opening_orders", "initial_defense", g_planSite, 0);
    char buy[12], plan[24];
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    DebugLog("Initial CT plan: buy=%s plan=%s bots=%d", buy, plan, count);
    if (GetFeatureStatus(FeatureType_Native, "BotExperience_RecordOpeningPlan") == FeatureStatus_Available)
        BotExperience_RecordOpeningPlan(CS_TEAM_CT, view_as<int>(g_buyState), view_as<int>(g_plan), g_planSite, count);
}

void BuildStandardTargets(int count)
{
    int countA = count / 2;
    int countB = count / 2;
    int rotators = count - countA - countB;

    BuildDefensiveSiteTargets(0, countA, true);
    BuildDefensiveSiteTargets(1, countB, true);

    if (rotators > 0)
    {
        float middle[3];
        for (int axis = 0; axis < 3; axis++)
            middle[axis] = (g_siteA[axis] + g_siteB[axis]) * 0.5;
        AppendProjectedTarget(middle);
    }
}

void BuildPushTargets(int count)
{
    bool pushA = GetRandomInt(0, 1) == 0;
    g_planSite = pushA ? 0 : 1;
    float pushSite[3], otherSite[3];
    if (pushA)
    {
        CopyVector(g_siteA, pushSite);
        CopyVector(g_siteB, otherSite);
    }
    else
    {
        CopyVector(g_siteB, pushSite);
        CopyVector(g_siteA, otherSite);
    }

    int pushCount = count >= 5 ? 2 : 1;

    float dirX = g_tSpawn[0] - pushSite[0];
    float dirY = g_tSpawn[1] - pushSite[1];
    Normalize2D(dirX, dirY);
    BuildAround(pushSite, pushCount, 450.0, 950.0, true, dirX, dirY);

    int remaining = count - pushCount;
    int otherCount = remaining >= 2 ? 2 : remaining;
    BuildDefensiveSiteTargets(pushA ? 1 : 0, otherCount, false);

    int rotators = remaining - otherCount;
    if (rotators > 0)
    {
        float middle[3];
        for (int axis = 0; axis < 3; axis++)
            middle[axis] = (pushSite[axis] + otherSite[axis]) * 0.5;
        while (rotators-- > 0)
            AppendProjectedTarget(middle);
    }

    DebugLog("Single-site pressure selected for site %s.", pushA ? "A" : "B");
}

void BuildStackTargets(int count)
{
    bool stackA = GetRandomInt(0, 1) == 0;
    g_planSite = stackA ? 0 : 1;
    float stackSite[3], otherSite[3];
    if (stackA)
    {
        CopyVector(g_siteA, stackSite);
        CopyVector(g_siteB, otherSite);
    }
    else
    {
        CopyVector(g_siteB, stackSite);
        CopyVector(g_siteA, otherSite);
    }

    int stackCount = count >= 5 ? 3 : count - 1;
    if (stackCount < 1)
        stackCount = 1;
    float dirX = g_tSpawn[0] - stackSite[0];
    float dirY = g_tSpawn[1] - stackSite[1];
    Normalize2D(dirX, dirY);
    BuildAround(stackSite, stackCount, 250.0, 700.0, true, dirX, dirY);

    int otherCount = count - stackCount;
    BuildDefensiveSiteTargets(stackA ? 1 : 0, otherCount, false);

    DebugLog("Choke stack selected for site %s.", stackA ? "A" : "B");
}

void ConfigureMapAnchorProfile()
{
    for (int site = 0; site < 2; site++)
    {
        for (int slot = 0; slot < ANCHORS_PER_SITE; slot++)
        {
            g_anchorPlaces[site][slot][0] = '\0';
            g_anchorAttempted[site][slot] = false;
            g_anchorResolved[site][slot] = false;
        }
    }

    char map[64];
    GetCurrentMap(map, sizeof(map));
    if (StrEqual(map, "de_inferno", false))
        SetAnchorProfile("BombsiteA", "Pit", "BombsiteB", "Ruins");
    else if (StrEqual(map, "de_train", false))
        SetAnchorProfile("BombsiteA", "Connector", "BombsiteB", "BPlatform");
    else if (StrEqual(map, "de_mirage", false))
        SetAnchorProfile("BombsiteA", "Stairs", "BombsiteB", "Shop");
    else if (StrEqual(map, "de_nuke", false))
        SetAnchorProfile("BombsiteA", "Heaven", "BombsiteB", "Decon");
    else if (StrEqual(map, "de_dust2", false))
        SetAnchorProfile("BombsiteA", "LongA", "BombsiteB", "BDoors");
    else if (StrEqual(map, "de_overpass", false))
        SetAnchorProfile("BombsiteA", "BackofA", "BombsiteB", "Construction");
    else if (StrEqual(map, "de_vertigo", false))
        SetAnchorProfile("BombsiteA", "BackofA", "BombsiteB", "BackofB");
    else if (StrEqual(map, "de_ancient", false))
        SetAnchorProfile("BombsiteA", "SideHall", "BombsiteB", "Ruins");
    else if (StrEqual(map, "de_anubis", false))
        SetAnchorProfile("BombsiteA", "Heaven", "BombsiteB", "BackofB");
}

void SetAnchorProfile(const char[] aPrimary, const char[] aSecondary,
    const char[] bPrimary, const char[] bSecondary)
{
    strcopy(g_anchorPlaces[0][0], 32, aPrimary);
    strcopy(g_anchorPlaces[0][1], 32, aSecondary);
    strcopy(g_anchorPlaces[1][0], 32, bPrimary);
    strcopy(g_anchorPlaces[1][1], 32, bSecondary);
}

void BuildDefensiveSiteTargets(int site, int wanted, bool directional)
{
    if (wanted <= 0)
        return;

    int before = g_targetCount;
    for (int slot = 0; slot < ANCHORS_PER_SITE && g_targetCount - before < wanted; slot++)
        TryAppendNamedAnchor(site, slot);

    int missing = wanted - (g_targetCount - before);
    if (missing <= 0)
        return;

    float sitePosition[3];
    CopyVector(site == 0 ? g_siteA : g_siteB, sitePosition);
    float dirX = g_tSpawn[0] - sitePosition[0];
    float dirY = g_tSpawn[1] - sitePosition[1];
    Normalize2D(dirX, dirY);
    BuildAround(sitePosition, missing, 180.0, directional ? 650.0 : 600.0,
        directional, dirX, dirY);
}

bool TryAppendNamedAnchor(int site, int slot)
{
    if (g_anchorPlaces[site][slot][0] == '\0')
        return false;
    if (!g_anchorAttempted[site][slot])
        ResolveNamedAnchor(site, slot);
    if (!g_anchorResolved[site][slot])
        return false;

    for (int target = 0; target < g_targetCount; target++)
    {
        if (GetVectorDistance(g_anchorPositions[site][slot], g_targets[target]) < 150.0)
            return false;
    }
    AppendTarget(g_anchorPositions[site][slot]);
    return true;
}

void ResolveNamedAnchor(int site, int slot)
{
    g_anchorAttempted[site][slot] = true;
    float sitePosition[3];
    CopyVector(site == 0 ? g_siteA : g_siteB, sitePosition);
    int startArea = NavMesh_GetNearestArea(sitePosition, false, 600.0, false, true, TEAM_ANY);
    if (startArea < 0)
        return;

    ArrayStack areas = new ArrayStack();
    areas.Push(startArea);
    NavMesh_CollectSurroundingAreas(areas, startArea, 1250.0, 18.0, 100.0);
    float bestScore = -999999.0;
    float bestPosition[3];
    while (!areas.Empty)
    {
        int area = areas.Pop();
        char place[32];
        CTWatch_GetPlace(area, place, sizeof(place));
        if (!StrEqual(place, g_anchorPlaces[site][slot], false))
            continue;

        float center[3];
        if (NavMeshArea_GetCenter(area, center))
            ConsiderAnchorCandidate(sitePosition, center, slot == 0, bestScore, bestPosition);
        ArrayStack spots = new ArrayStack();
        NavMeshArea_GetHidingSpots(spots, area);
        while (!spots.Empty)
        {
            float position[3];
            NavHidingSpot_GetPosition(spots.Pop(), position);
            ConsiderAnchorCandidate(sitePosition, position, slot == 0, bestScore, bestPosition);
        }
        delete spots;
    }
    delete areas;

    if (bestScore <= -999999.0)
    {
        DebugLog("No valid %s site anchor at NAV place %s; using generic setup.",
            site == 0 ? "A" : "B", g_anchorPlaces[site][slot]);
        return;
    }
    CopyVector(bestPosition, g_anchorPositions[site][slot]);
    g_anchorResolved[site][slot] = true;
    DebugLog("Resolved %s site anchor %s at %.0f %.0f %.0f.",
        site == 0 ? "A" : "B", g_anchorPlaces[site][slot],
        bestPosition[0], bestPosition[1], bestPosition[2]);
}

void ConsiderAnchorCandidate(const float sitePosition[3], const float position[3],
    bool primary, float &bestScore, float bestPosition[3])
{
    if (FloatAbs(position[2] - sitePosition[2]) > 250.0)
        return;
    float distance = Distance2D(sitePosition, position);
    if (distance > 850.0)
        return;
    float preferredDistance = primary ? 230.0 : 430.0;
    float score = -FloatAbs(distance - preferredDistance);
    if (score > bestScore)
    {
        bestScore = score;
        CopyVector(position, bestPosition);
    }
}

void UpdateLooseBombGuard()
{
    if (!g_roundLive || g_bombPlanted || !g_geometryReady || !NavMeshReady())
        return;
    // Fail closed when BetterBots is absent: never invent visual knowledge.
    if (!NativeAvailable("BotStuff_CanSeeLooseC4") || !NativeAvailable("BotStuff_HasVisibleEnemy"))
    {
        if (g_phase == Phase_GuardLooseBomb) ResetDirector();
        return;
    }
    int bomb = FindLooseC4();
    if (g_phase == Phase_GuardLooseBomb && (bomb == -1 || EntRefToEntIndex(g_guardBombRef) != bomb))
        ResetDirector();
    if (bomb == -1) return;

    float position[3];
    GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", position);
    // A sliding C4 only changes the shared objective after another real sight;
    // retain the last confirmed position if it moves out of view.
    bool needsPlan = g_phase != Phase_GuardLooseBomb || GetVectorDistance(position, g_bombPosition) >= 128.0;
    if (needsPlan)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_CT
                || g_blindUntil[client] > GetGameTime() || !BotStuff_CanSeeLooseC4(client, bomb))
                continue;
            PlanLooseBombGuard(bomb, client);
            break;
        }
    }
    if (g_phase == Phase_GuardLooseBomb) ResumeLooseBombGuards();
}

void PlanLooseBombGuard(int bomb, int spotter)
{
    int bots[MAXPLAYERS + 1];
    int count = CollectCTBots(bots);
    if (count == 0 || !NavMeshReady())
        return;

    int guardCount = g_cvGuardCount.IntValue;
    if (guardCount == 0 || guardCount > count)
        guardCount = count;

    ClearOrders();
    ClearLooseBombGuard();
    g_guardBombRef = EntIndexToEntRef(bomb);
    GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", g_bombPosition);
    g_phase = Phase_GuardLooseBomb;
    g_phaseStarted = GetGameTime();
    g_targetCount = 0;
    BuildAround(g_bombPosition, guardCount, 160.0, 620.0, false, 0.0, 0.0);
    FillMissingTargetsAt(guardCount, g_bombPosition);
    // Reserve a stable slot for EVERY guard, including bots currently fighting
    // and those released earlier in the round. Publish only after combat ends.
    bool used[MAXPLAYERS + 1];
    for (int target = 0; target < guardCount; target++)
    {
        int selected;
        float bestDistance = 99999999.0;
        for (int index = 0; index < count; index++)
        {
            int client = bots[index];
            if (used[client]) continue;
            float position[3];
            GetClientAbsOrigin(client, position);
            float distance = GetVectorDistance(position, g_targets[target]);
            if (distance < bestDistance) { selected = client; bestDistance = distance; }
        }
        if (selected == 0) continue;
        used[selected] = true;
        g_guardSlot[selected] = target;
        CopyVector(g_targets[target], g_orderGoal[selected]);
        SetOrderLook(selected, g_tSpawn, target);
    }
    ExperienceSignal("guard_bomb", "loose_c4_seen", NearestSite(g_bombPosition), spotter);
    DebugLog("%N saw dropped C4; reserved %d CT guard positions.", spotter, guardCount);
}

void ResumeLooseBombGuards()
{
    float now = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || g_guardSlot[client] < 0) continue;
        if (BotStuff_HasVisibleEnemy(client))
        {
            ReleaseOrder(client, "enemy spotted");
            continue;
        }
        if (g_hasOrder[client] || g_guardStalls[client] >= 3 || g_blindUntil[client] > now
            || now - g_lastCombatAt[client] < 2.5 || now - g_guardReleasedAt[client] < 2.5)
            continue;
        g_combatReleased[client] = false;
        g_hasOrder[client] = true;
        g_hasLook[client] = true;
        g_orderRoute[client] = view_as<int>(Route_Fastest);
        g_orderExpires[client] = 0.0;
        StartOrderProgress(client);
        ExperienceSignal("guard_resume", "quiet_after_contact", NearestSite(g_bombPosition), client);
    }
}

void ClearLooseBombGuard()
{
    g_guardBombRef = INVALID_ENT_REFERENCE;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_guardSlot[client] = -1;
        g_guardStalls[client] = 0;
        g_guardReleasedAt[client] = -100.0;
    }
}

void PlanRetake(bool commit)
{
    int bots[MAXPLAYERS + 1];
    int count = CollectCTBots(bots);
    if (count == 0 || !NavMeshReady())
        return;

    g_targetCount = 0;
    if (commit)
        BuildAround(g_bombPosition, count, 40.0, 260.0, false, 0.0, 0.0);
    else
        BuildAround(g_bombPosition, count, 350.0, 900.0, false, 0.0, 0.0);

    FillMissingTargetsAt(count, g_bombPosition);
    AssignTargets(bots, count, commit ? Route_Fastest : Route_Safest);
    g_phase = commit ? Phase_RetakeCommit : Phase_RetakeStage;
    g_phaseStarted = GetGameTime();
    ExperienceSignal(commit ? "retake_commit" : "retake_stage", "bomb_planted", NearestSite(g_bombPosition), 0);
    DebugLog(commit ? "CT retake committed to the bomb." : "CT retake staging on distinct approaches.");
}

void BuildAround(const float origin[3], int wanted, float minRadius, float maxRadius, bool directional, float dirX, float dirY)
{
    if (wanted <= 0)
        return;

    CollectCandidates(origin, minRadius, maxRadius);
    float baseAngle = GetRandomFloat(0.0, 360.0);
    float targetRadius = (minRadius + maxRadius) * 0.5;

    for (int slot = 0; slot < wanted && g_targetCount < MAXPLAYERS + 1; slot++)
    {
        float wantedX, wantedY;
        if (directional)
        {
            float spread = (float(slot) - (float(wanted - 1) * 0.5)) * 32.0;
            Rotate2D(dirX, dirY, spread, wantedX, wantedY);
        }
        else
        {
            float angle = baseAngle + (360.0 * float(slot) / float(wanted));
            wantedX = Cosine(DegToRad(angle));
            wantedY = Sine(DegToRad(angle));
        }

        int best = FindBestCandidate(origin, wantedX, wantedY, targetRadius);
        if (best != -1)
            AppendTarget(g_candidates[best]);
        else
        {
            float fallback[3];
            fallback[0] = origin[0] + wantedX * targetRadius;
            fallback[1] = origin[1] + wantedY * targetRadius;
            fallback[2] = origin[2];
            AppendProjectedTarget(fallback);
        }
    }
}

void CollectCandidates(const float origin[3], float minRadius, float maxRadius)
{
    g_candidateCount = 0;
    int startArea = NavMesh_GetNearestArea(origin, false, 1500.0, false, true, TEAM_ANY);
    if (startArea < 0)
        return;

    ArrayStack areas = new ArrayStack();
    areas.Push(startArea);
    NavMesh_CollectSurroundingAreas(areas, startArea, maxRadius + 400.0, 18.0, 100.0);

    while (!areas.Empty && g_candidateCount < MAX_CANDIDATES)
    {
        int area = areas.Pop();
        ArrayStack spots = new ArrayStack();
        NavMeshArea_GetHidingSpots(spots, area);
        int addedFromArea;

        while (!spots.Empty && addedFromArea < 3 && g_candidateCount < MAX_CANDIDATES)
        {
            float position[3];
            NavHidingSpot_GetPosition(spots.Pop(), position);
            if (CandidateInRange(origin, position, minRadius, maxRadius))
            {
                AddCandidate(position);
                addedFromArea++;
            }
        }
        delete spots;

        if (addedFromArea == 0)
        {
            float center[3];
            if (NavMeshArea_GetCenter(area, center) && CandidateInRange(origin, center, minRadius, maxRadius))
                AddCandidate(center);
        }
    }
    delete areas;
}

bool CandidateInRange(const float origin[3], const float position[3], float minRadius, float maxRadius)
{
    if (FloatAbs(position[2] - origin[2]) > 450.0)
        return false;
    float distance = Distance2D(origin, position);
    return distance >= minRadius && distance <= maxRadius;
}

void AddCandidate(const float position[3])
{
    for (int i = 0; i < g_candidateCount; i++)
    {
        if (Distance2D(g_candidates[i], position) < 72.0)
            return;
    }
    CopyVector(position, g_candidates[g_candidateCount]);
    g_candidateCount++;
}

int FindBestCandidate(const float origin[3], float wantedX, float wantedY, float targetRadius)
{
    int best = -1;
    float bestScore = -999999.0;

    for (int i = 0; i < g_candidateCount; i++)
    {
        float dx = g_candidates[i][0] - origin[0];
        float dy = g_candidates[i][1] - origin[1];
        float distance = SquareRoot(dx * dx + dy * dy);
        if (distance < 1.0)
            continue;

        float alignment = (dx / distance) * wantedX + (dy / distance) * wantedY;
        float score = alignment * 900.0 - FloatAbs(distance - targetRadius) * 0.35;
        for (int target = 0; target < g_targetCount; target++)
        {
            float separation = Distance2D(g_candidates[i], g_targets[target]);
            if (separation < 140.0)
                score -= (140.0 - separation) * 12.0;
        }

        if (score > bestScore)
        {
            bestScore = score;
            best = i;
        }
    }
    return best;
}

void AppendProjectedTarget(const float position[3])
{
    int area = NavMesh_GetNearestArea(position, true, 1200.0, false, true, TEAM_ANY);
    float projected[3];
    if (area >= 0 && NavMeshArea_GetCenter(area, projected))
        AppendTarget(projected);
    else
        AppendTarget(position);
}

void AppendTarget(const float position[3])
{
    if (g_targetCount >= MAXPLAYERS + 1)
        return;
    CopyVector(position, g_targets[g_targetCount]);
    g_targetCount++;
}

void FillMissingTargetsAt(int wanted, const float fallback[3])
{
    while (g_targetCount < wanted)
        AppendProjectedTarget(fallback);
}

void AssignTargets(const int bots[MAXPLAYERS + 1], int botCount, RouteType route, int targetLimit = -1, bool siteLocalWatch = false)
{
    ClearOrders();
    bool used[MAXPLAYERS + 1];
    int limit = targetLimit == -1 ? g_targetCount : targetLimit;
    if (limit > g_targetCount)
        limit = g_targetCount;
    int siteSlots[2], siteCounts[2], usedEntrances[2];
    if (siteLocalWatch)
        for (int target = 0; target < limit; target++)
            siteCounts[NearestSite(g_targets[target])]++;

    for (int target = 0; target < limit; target++)
    {
        int bestIndex = -1;
        float bestDistance = 99999999.0;
        for (int index = 0; index < botCount; index++)
        {
            if (used[index] || g_combatReleased[bots[index]] || !IsCTBot(bots[index]))
                continue;

            float position[3];
            GetClientAbsOrigin(bots[index], position);
            float distance = GetVectorDistance(position, g_targets[target]);
            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestIndex = index;
            }
        }

        if (bestIndex != -1)
        {
            int client = bots[bestIndex];
            used[bestIndex] = true;
            g_hasOrder[client] = true;
            CopyVector(g_targets[target], g_orderGoal[client]);
            if (g_bombPlanted)
                SetOrderLook(client, g_bombPosition, target);
            else
            {
                int site = NearestSite(g_orderGoal[client]);
                int sector = siteLocalWatch ? CTWatch_GetSector(siteSlots[site]++, siteCounts[site]) : target;
                SetOrderLook(client, g_tSpawn, sector, siteLocalWatch);
                // No new movement/order lifecycle: refine only the cached aim
                // of a standard opening hold, retaining generic fallback.
                if (siteLocalWatch && g_plan == Plan_Standard && g_cvEntranceWatch.BoolValue)
                {
                    char entrance[32];
                    float look[3];
                    if (CTEntrance_SelectLook(client, g_orderGoal[client], site, usedEntrances[site], look, entrance, sizeof(entrance)))
                    {
                        CopyVector(look, g_orderLook[client]);
                        DebugLog("Watch %N: site=%s entrance=%s", client, site == 0 ? "A" : "B", entrance);
                    }
                }
            }
            g_orderRoute[client] = view_as<int>(route);
            g_orderExpires[client] = 0.0;
            StartOrderProgress(client);
            DebugLog("Assigned %N to %.0f %.0f %.0f", client, g_orderGoal[client][0], g_orderGoal[client][1], g_orderGoal[client][2]);
        }
    }
}

BuyState ClassifyCTBuy()
{
    BotEquipmentTier tier = BotEquipment_ClassifyTeam(CS_TEAM_CT);
    if (tier == BotEquip_Full)
        return Buy_Full;
    if (tier == BotEquip_Force)
        return Buy_Force;
    return Buy_Eco;
}

bool IsRegulationPistolRound()
{
    int roundsPlayed = GameRules_GetProp("m_totalRoundsPlayed");
    if (roundsPlayed == 0)
        return true;

    ConVar maxRounds = FindConVar("mp_maxrounds");
    int regulationRounds = maxRounds == null ? 0 : maxRounds.IntValue;
    return regulationRounds >= 2 && roundsPlayed == regulationRounds / 2;
}

DefensePlan ChooseDefensePlan(BuyState buy)
{
    int pushChance;
    int stackChance;
    if (buy == Buy_Full)
    {
        pushChance = g_cvFullPushChance.IntValue;
        stackChance = g_cvFullStackChance.IntValue;
    }
    else if (buy == Buy_Force)
    {
        pushChance = g_cvForcePushChance.IntValue;
        stackChance = g_cvForceStackChance.IntValue;
    }
    else
    {
        pushChance = g_cvEcoPushChance.IntValue;
        stackChance = g_cvEcoStackChance.IntValue;
    }

    if (pushChance + stackChance > 100)
        stackChance = 100 - pushChance;

    int roll = GetRandomInt(1, 100);
    if (roll <= pushChance)
        return Plan_SingleSitePush;
    if (roll <= pushChance + stackChance)
        return Plan_ChokeStack;
    return Plan_Standard;
}

bool RefreshGeometry()
{
    if (CountBombTargets() < 2)
    {
        g_geometryReady = false;
        return false;
    }

    int manager = FindEntityByClassname(-1, "cs_player_manager");
    if (manager == -1 || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterA") || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterB"))
    {
        g_geometryReady = false;
        return false;
    }

    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", g_siteA);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", g_siteB);
    if (GetVectorDistance(g_siteA, g_siteB) < 100.0 || !GetSpawnCenter("info_player_terrorist", g_tSpawn))
    {
        g_geometryReady = false;
        return false;
    }

    g_geometryReady = true;
    return true;
}

int CountBombTargets()
{
    int count;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
        count++;
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "info_bomb_target")) != -1)
        count++;
    return count;
}

bool GetSpawnCenter(const char[] classname, float result[3])
{
    result[0] = 0.0;
    result[1] = 0.0;
    result[2] = 0.0;
    int entity = -1;
    int count;
    while ((entity = FindEntityByClassname(entity, classname)) != -1)
    {
        float origin[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        AddVectors(result, origin, result);
        count++;
    }

    if (count == 0)
        return false;
    ScaleVector(result, 1.0 / float(count));
    return true;
}

bool NavMeshReady()
{
    return NativeAvailable("NavMesh_Exists")
        && NativeAvailable("NavMesh_GetNearestArea")
        && NativeAvailable("NavMesh_CollectSurroundingAreas")
        && NativeAvailable("NavMeshArea_GetCenter")
        && NativeAvailable("NavMeshArea_GetHidingSpots")
        && NativeAvailable("NavHidingSpot_GetPosition")
        && NavMesh_Exists();
}

bool NativeAvailable(const char[] name)
{
    return GetFeatureStatus(FeatureType_Native, name) == FeatureStatus_Available;
}

int CollectCTBots(int clients[MAXPLAYERS + 1])
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsCTBot(client))
            clients[count++] = client;
    }
    return count;
}

bool IsCTBot(int client)
{
    return client >= 1 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client)
        && IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_CT;
}

int FindLooseC4()
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "weapon_c4")) != -1)
    {
        if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") <= 0)
            return entity;
    }
    return -1;
}

int NearestSite(const float position[3])
{
    return Distance2D(position, g_siteA) <= Distance2D(position, g_siteB) ? 0 : 1;
}

void ReportEnemy(int spotter, const float enemyPosition[3], int site)
{
    if (!g_cvRadioReport.BoolValue)
        return;

    FakeClientCommand(spotter, "playerradio Radio.EnemySpotted \"Enemy spotted\"");

    char location[64];
    int area = NavMesh_GetNearestArea(enemyPosition, true, 1000.0, false, true, TEAM_ANY);
    if (area >= 0 && NativeAvailable("NavMeshArea_GetPlace"))
        NavMeshArea_GetPlace(area, location, sizeof(location));
    if (location[0] == '\0')
        strcopy(location, sizeof(location), site == 0 ? "A site" : "B site");

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == CS_TEAM_CT)
            PrintToChat(client, "\x04[CT Tactics]\x01 %N reported enemies near %s.", spotter, location);
    }
    DebugLog("%N reported enemy contact near %s.", spotter, location);
}

int RequestReinforcement(const float contactPosition[3], int site, int excludedClient, const char[] reason,
    int additionalExcluded = 0, bool allowEmptyOtherSite = false, bool onlyOtherSite = false)
{
    // Once loose C4 is confirmed, site reports/casualties must not overwrite
    // its cached guard goals. Individual combat still releases immediately.
    if (g_phase == Phase_GuardLooseBomb) return 0;
    float sitePosition[3], otherSite[3];
    if (site == 0)
    {
        CopyVector(g_siteA, sitePosition);
        CopyVector(g_siteB, otherSite);
    }
    else
    {
        CopyVector(g_siteB, sitePosition);
        CopyVector(g_siteA, otherSite);
    }

    int otherDefenders;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || client == excludedClient)
            continue;
        float position[3];
        GetClientAbsOrigin(client, position);
        if ((g_hasOrder[client] && Distance2D(g_orderGoal[client], otherSite) <= 850.0)
            || (!g_hasOrder[client] && Distance2D(position, otherSite) <= 850.0))
            otherDefenders++;
    }

    int selected;
    float bestDistance = 99999999.0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || client == excludedClient || client == additionalExcluded || g_combatReleased[client])
            continue;
        float position[3];
        GetClientAbsOrigin(client, position);
        float contactDistance = Distance2D(position, contactPosition);
        if (contactDistance < 450.0)
            continue;
        bool protectsOtherSite = (g_hasOrder[client] && Distance2D(g_orderGoal[client], otherSite) <= 850.0)
            || (!g_hasOrder[client] && Distance2D(position, otherSite) <= 850.0);
        if (onlyOtherSite && !protectsOtherSite)
            continue;
        if (protectsOtherSite && otherDefenders <= 1 && !allowEmptyOtherSite)
            continue;
        if (contactDistance < bestDistance)
        {
            bestDistance = contactDistance;
            selected = client;
        }
    }

    if (selected == 0)
    {
        DebugLog("No safe CT reinforcement available for %s.", reason);
        return 0;
    }

    float dirX = contactPosition[0] - sitePosition[0];
    float dirY = contactPosition[1] - sitePosition[1];
    Normalize2D(dirX, dirY);
    float desired[3];
    desired[0] = sitePosition[0] + dirX * 360.0;
    desired[1] = sitePosition[1] + dirY * 360.0;
    desired[2] = sitePosition[2];
    int area = NavMesh_GetNearestArea(desired, true, 900.0, false, true, TEAM_ANY);
    if (area >= 0 && NavMeshArea_GetCenter(area, g_orderGoal[selected]))
    {
        g_hasOrder[selected] = true;
        CopyVector(contactPosition, g_orderLook[selected]);
        g_hasLook[selected] = true;
        g_orderRoute[selected] = view_as<int>(Route_Fastest);
        g_orderExpires[selected] = GetGameTime() + g_cvReinforceHold.FloatValue;
        g_lastReinforcement[site] = selected;
        StartOrderProgress(selected);
        ExperienceSignal("reinforce", reason, site, selected);
        DebugLog("Assigned %N to reinforce %s for %s.", selected, site == 0 ? "A" : "B", reason);
        return selected;
    }
    return 0;
}

void ReleaseOrder(int client, const char[] reason)
{
    if (IsCTBot(client) && !StrEqual(reason, "navigation stalled") && !StrEqual(reason, "defusing"))
        g_lastCombatAt[client] = GetGameTime();
    if (client < 1 || client > MaxClients || !g_hasOrder[client] || !IsClientInGame(client) || !IsFakeClient(client))
        return;
    if (g_phase == Phase_GuardLooseBomb && g_guardSlot[client] >= 0)
    {
        g_guardReleasedAt[client] = GetGameTime();
        // Bounded retries preserve native anti-stuck behavior; do not oscillate
        // forever toward a bad NAV target if it fails three separate times.
        if (StrEqual(reason, "navigation stalled")) g_guardStalls[client]++;
    }
    ExperienceSignal("order_release", reason, g_geometryReady ? NearestSite(g_orderGoal[client]) : -1, client);
    g_hasOrder[client] = false;
    g_hasLook[client] = false;
    g_orderExpires[client] = 0.0;
    g_orderLastProgressDistance[client] = 0.0;
    g_orderLastProgressAt[client] = 0.0;
    g_orderArrived[client] = false;
    g_combatReleased[client] = true;
    DebugLog("Released %N to native combat AI: %s", client, reason);
}

void ClearOrders()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_hasOrder[client] = false;
        g_hasLook[client] = false;
        g_orderExpires[client] = 0.0;
        g_orderLastProgressDistance[client] = 0.0;
        g_orderLastProgressAt[client] = 0.0;
        g_orderArrived[client] = false;
    }
}

void StartOrderProgress(int client)
{
    float position[3];
    GetClientAbsOrigin(client, position);
    g_orderLastProgressDistance[client] = Distance2D(position, g_orderGoal[client]);
    g_orderLastProgressAt[client] = GetGameTime();
    g_orderArrived[client] = false;
    CopyVector(position, g_orderLastProgressPosition[client]);
}

void ReleaseStalledOrders()
{
    float now = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || !g_hasOrder[client] || g_combatReleased[client])
            continue;

        float position[3];
        GetClientAbsOrigin(client, position);
        float distance = Distance2D(position, g_orderGoal[client]);
        float displacement = Distance2D(position, g_orderLastProgressPosition[client]);
        if (distance <= 128.0)
        {
            if (!g_orderArrived[client])
                ExperienceSignal("order_arrived", "within_128", g_geometryReady ? NearestSite(g_orderGoal[client]) : -1, client);
            g_orderArrived[client] = true;
            g_orderLastProgressDistance[client] = distance;
            g_orderLastProgressAt[client] = now;
            CopyVector(position, g_orderLastProgressPosition[client]);
            continue;
        }

        // Do not release a settled initial defender merely because the
        // engine's idle movement displaced it a few steps from its cover.
        if ((g_phase == Phase_Initial || g_phase == Phase_GuardLooseBomb) && g_orderArrived[client] && distance <= 256.0)
        {
            g_orderLastProgressDistance[client] = distance;
            g_orderLastProgressAt[client] = now;
            CopyVector(position, g_orderLastProgressPosition[client]);
            continue;
        }
        g_orderArrived[client] = false;

        // A valid NAV route can temporarily move sideways or away from the
        // destination. Count real displacement as progress as well as a direct
        // reduction in distance, while stationary turning satisfies neither.
        if (distance <= g_orderLastProgressDistance[client] - 48.0 || displacement >= 64.0)
        {
            g_orderLastProgressDistance[client] = distance;
            g_orderLastProgressAt[client] = now;
            CopyVector(position, g_orderLastProgressPosition[client]);
            continue;
        }

        if (now - g_orderLastProgressAt[client] >= g_cvNavigationStallTimeout.FloatValue)
            ReleaseOrder(client, "navigation stalled");
    }
}

void ExperienceSignal(const char[] kind, const char[] detail, int site, int actor)
{
    if (GetFeatureStatus(FeatureType_Native, "BotExperience_RecordSignal") == FeatureStatus_Available)
        BotExperience_RecordSignal(CS_TEAM_CT, kind, detail, site, actor);
}

void SetOrderLook(int client, const float threat[3], int slot, bool constrainSector = false)
{
    TacticalAngles_SelectLook(client, g_orderGoal[client], threat, slot, g_orderLook[client], constrainSector);
    g_hasLook[client] = true;
}

void GetOrderProgress(float distanceLimit, int &ready, int &ordered)
{
    ready = 0;
    ordered = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || !g_hasOrder[client] || g_combatReleased[client])
            continue;
        ordered++;
        float position[3];
        GetClientAbsOrigin(client, position);
        if (Distance2D(position, g_orderGoal[client]) <= distanceLimit)
            ready++;
    }
}

bool OrdersMeetReadyPercent(float distanceLimit, int requiredPercent)
{
    int ready, ordered;
    GetOrderProgress(distanceLimit, ready, ordered);
    return ordered == 0 || ready * 100 >= ordered * requiredPercent;
}

void ClearCombatReleases()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_combatReleased[client] = false;
        g_lastCombatAt[client] = -100.0;
        g_blindUntil[client] = 0.0;
    }
}

void ResetDirector()
{
    ClearOrders();
    ClearLooseBombGuard();
    g_phase = Phase_Idle;
    g_phaseStarted = 0.0;
    g_targetCount = 0;
    g_retakeContact = false;
}

void FillMissingTargets(int wanted)
{
    float middle[3];
    for (int axis = 0; axis < 3; axis++)
        middle[axis] = (g_siteA[axis] + g_siteB[axis]) * 0.5;
    FillMissingTargetsAt(wanted, middle);
}

float Distance2D(const float first[3], const float second[3])
{
    float dx = first[0] - second[0];
    float dy = first[1] - second[1];
    return SquareRoot(dx * dx + dy * dy);
}

void Normalize2D(float &x, float &y)
{
    float length = SquareRoot(x * x + y * y);
    if (length < 1.0)
    {
        x = 1.0;
        y = 0.0;
        return;
    }
    x /= length;
    y /= length;
}

void Rotate2D(float x, float y, float degrees, float &outX, float &outY)
{
    float radians = DegToRad(degrees);
    float cosine = Cosine(radians);
    float sine = Sine(radians);
    outX = x * cosine - y * sine;
    outY = x * sine + y * cosine;
}

void CopyVector(const float source[3], float destination[3])
{
    destination[0] = source[0];
    destination[1] = source[1];
    destination[2] = source[2];
}

void GetPhaseName(TacticalPhase phase, char[] buffer, int maxLength)
{
    switch (phase)
    {
        case Phase_Initial: strcopy(buffer, maxLength, "initial");
        case Phase_CarrierResponse: strcopy(buffer, maxLength, "carrier-response");
        case Phase_GuardLooseBomb: strcopy(buffer, maxLength, "guard-c4");
        case Phase_RetakeStage: strcopy(buffer, maxLength, "retake-stage");
        case Phase_RetakeCommit: strcopy(buffer, maxLength, "retake-commit");
        default: strcopy(buffer, maxLength, "idle");
    }
}

void GetBuyName(BuyState buy, char[] buffer, int maxLength)
{
    switch (buy)
    {
        case Buy_Eco: strcopy(buffer, maxLength, "eco");
        case Buy_Force: strcopy(buffer, maxLength, "force");
        default: strcopy(buffer, maxLength, "full");
    }
}

void GetPlanName(DefensePlan plan, char[] buffer, int maxLength)
{
    switch (plan)
    {
        case Plan_SingleSitePush: strcopy(buffer, maxLength, "single-site-push");
        case Plan_ChokeStack: strcopy(buffer, maxLength, "choke-stack");
        default: strcopy(buffer, maxLength, "standard");
    }
}

void DebugLog(const char[] format, any ...)
{
    if (!g_cvDebug.BoolValue)
        return;

    char message[256];
    VFormat(message, sizeof(message), format, 2);
    LogMessage("[CT Tactics] %s", message);
}
