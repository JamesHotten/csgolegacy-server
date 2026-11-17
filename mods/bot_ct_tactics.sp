#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <bot_equipment_policy>
#include <bot_ct_watch_sectors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1.16"
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
typedef CTPathCost = function int(int area, int from, int ladder, any maxCost);
native bool NavMesh_BuildPath(int start, int goal, const float point[3], CTPathCost cost,
    any maxCost, int &closest, float maxLength, float maxStep);
native int NavMeshArea_GetCostSoFar(int area);

#include <bot_tactical_angles>
#include "include/bot_tactical_map_profiles.inc"
#include <bot_ct_entrance_watch>
#include "include/bot_ct_inferno_watch.inc"

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
ConVar g_cvClearOpeningWatch;
ConVar g_cvInfernoWatch;
bool g_infernoMap;
int g_mapProfile = -1;
ConVar g_cvInitialHold;
ConVar g_cvRetakeStage;
ConVar g_cvRetakeCommit;
ConVar g_cvRetakeStageTimeout;
ConVar g_cvRetakeClockAware;
ConVar g_cvClearSiteDefuse;
ConVar g_cvRetakeRoles;
ConVar g_cvRetakeRelay;
ConVar g_cvNukeGuardWatch;
ConVar g_cvClearWatch;
ConVar g_cvObjectiveWatch;
ConVar g_cvRouteRecovery;
bool g_nukeMap;
float g_nukeGuardAimCheckAt[MAXPLAYERS + 1];
float g_nukeGuardEye[MAXPLAYERS + 1][3];
float g_nukeGuardAim[MAXPLAYERS + 1][3];
bool g_nukeGuardAimValid[MAXPLAYERS + 1];
ConVar g_cvPairedPressure;
ConVar g_cvCoverSpacing;
ConVar g_cvInnerHolds, g_cvSingleExposure, g_cvOpeningFall;
int g_pressureUsers[2];
float g_pressureReturnAt;
float g_pressureHomes[2][3], g_pressureAims[2][3];
bool g_pressureHasAim[2];
bool g_pressureInner[2];
int g_defuserUserId;
float g_defuserHandoffUntil;
float g_nextDefuserReviewAt;
bool g_defuserUsingBomb;
int g_defuserRetiredUserId;
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
ConVar g_cvOverpassTeamwork, g_cvMirageCrossfire, g_cvNukeRoutes;
ConVar g_cvOverpassAOpening;
ConVar g_cvProfiledRelief, g_cvProfiledRetake;
int g_contactEnemy[MAXPLAYERS + 1];
float g_contactSeenAt[MAXPLAYERS + 1];
int g_miragePartner[MAXPLAYERS + 1];
float g_mirageTradeUntil[MAXPLAYERS + 1], g_mirageTradeAim[MAXPLAYERS + 1][3];
bool g_nukeDetourUsed[MAXPLAYERS + 1];
float g_nukeAlternate[MAXPLAYERS + 1][3];
bool g_nukeDetouring[MAXPLAYERS + 1], g_nukeBackfillUsed;

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
bool g_retakeUnopposed;
int g_retakeBombRef = INVALID_ENT_REFERENCE;
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
bool g_infernoPreciseOrder[MAXPLAYERS + 1];
bool g_innerOrder[MAXPLAYERS + 1];
bool g_overpassOpeningOrder[MAXPLAYERS + 1];
float g_anubisBreakableUntil[MAXPLAYERS + 1];
int g_plainFallTick[MAXPLAYERS + 1];
float g_lastRouteFallAt[MAXPLAYERS + 1], g_lastRouteFallDistance[MAXPLAYERS + 1];
bool g_combatReleased[MAXPLAYERS + 1];
float g_orderGoal[MAXPLAYERS + 1][3];
float g_orderLook[MAXPLAYERS + 1][3];

#include <bot_tactical_recovery>
#include <bot_objective_watch>
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
    CreateNative("BotCTTactics_ReportRouteDrive", Native_ReportRouteDrive);
    CreateNative("BotCTTactics_GetHoldRadius", Native_GetHoldRadius);
    CreateNative("BotCTTactics_ReportContact", Native_ReportContact);
    CreateNative("BotCTTactics_ReportBreakable", Native_ReportBreakable);

    MarkNativeAsOptional("NavMesh_Exists");
    MarkNativeAsOptional("NavMesh_GetNearestArea");
    MarkNativeAsOptional("NavMesh_CollectSurroundingAreas");
    MarkNativeAsOptional("NavMeshArea_GetCenter");
    MarkNativeAsOptional("NavMeshArea_GetClosestPointOnArea");
    MarkNativeAsOptional("NavMeshArea_GetPlace");
    MarkNativeAsOptional("NavMeshArea_GetPlaceCanonical");
    MarkNativeAsOptional("NavMesh_BuildPath");
    MarkNativeAsOptional("NavMeshArea_GetCostSoFar");
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
    g_cvEntranceWatch = CreateConVar("sm_bot_ct_entrance_watch", "1", "Use visible named entrances for standard opening holds on profiled maps.", _, true, 0.0, true, 1.0);
    g_cvEntranceWatch.AddChangeHook(OnEntranceWatchChanged);
    g_cvClearOpeningWatch = CreateConVar("sm_bot_ct_clear_opening_watch", "1", "Never lock a standard CT opening hold onto an obstructed sightline.", _, true, 0.0, true, 1.0);
    g_cvInfernoWatch = CreateConVar("sm_bot_ct_inferno_watch", "1", "Use validated Inferno opening positions and reject blocked CT watch angles.", _, true, 0.0, true, 1.0);
    g_cvInfernoWatch.AddChangeHook(OnEntranceWatchChanged);
    g_cvInitialHold = CreateConVar("sm_bot_ct_tactics_initial_hold", "70.0", "Seconds between CT setup reviews; intact anchors remain in place.", _, true, 5.0, true, 105.0);
    g_cvRetakeStage = CreateConVar("sm_bot_ct_tactics_retake_stage", "6.0", "Minimum seconds spent taking distinct retake approaches.", _, true, 0.5, true, 12.0);
    g_cvRetakeCommit = CreateConVar("sm_bot_ct_tactics_retake_commit", "14.0", "Maximum seconds to push the planted bomb after staging.", _, true, 2.0, true, 25.0);
    g_cvRetakeStageTimeout = CreateConVar("sm_bot_ct_tactics_retake_stage_timeout", "12.0", "Hard timeout before committing the retake.", _, true, 2.0, true, 20.0);
    g_cvRetakeClockAware = CreateConVar("sm_bot_ct_retake_clock_aware", "1", "Skip CT retake staging with 20 seconds or less left, or for a solo BOT, and reject vertically separated arrivals.", _, true, 0.0, true, 1.0);
    g_cvClearSiteDefuse = CreateConVar("sm_bot_ct_clear_site_defuse", "1", "Yield to native defuse AI when all attackers are eliminated.", _, true, 0.0, true, 1.0);
    g_cvRetakeRoles = CreateConVar("sm_bot_ct_retake_roles", "1", "Use named approaches and prioritize a reachable defuser on Mirage, Inferno and Nuke.", _, true, 0.0, true, 1.0);
    g_cvRetakeRelay = CreateConVar("sm_bot_ct_retake_relay", "1", "Select a reachable defuser and replace a fallen or interrupted BOT on profiled maps.", _, true, 0.0, true, 1.0);
    g_cvNukeGuardWatch = CreateConVar("sm_bot_ct_nuke_guard_clear_watch", "1", "Nuke loose-C4 guards use visible approach sightlines instead of a blind fixed aim.", _, true, 0.0, true, 1.0);
    g_cvClearWatch = CreateConVar("sm_bot_ct_clear_watch", "1", "Reject nearby obstructions from the CT BOT's actual eye before applying a tactical look.", _, true, 0.0, true, 1.0);
    g_cvObjectiveWatch = CreateConVar("sm_bot_ct_objective_watch", "1", "Prefer distinct visible map entrances around a dropped bomb.", _, true, 0.0, true, 1.0);
    g_cvRouteRecovery = CreateConVar("sm_bot_ct_route_recovery", "1", "Try one local same-lane recovery for an actively driven CT order.", _, true, 0.0, true, 1.0);
    g_cvPairedPressure = CreateConVar("sm_bot_ct_pair_pressure_chance", "0", "Mirage: chance to add a short two-BOT probe to a standard setup; 0 disables.", _, true, 0.0, true, 100.0);
    g_cvCoverSpacing = CreateConVar("sm_bot_ct_cover_spacing", "1", "Avoid overlapping generic opening positions when clear alternate holds are available.", _, true, 0.0, true, 1.0);
    g_cvInnerHolds = CreateConVar("sm_bot_ct_inner_holds", "1", "Reserve an inset bomb-zone hold on each side of the standard opening.", _, true, 0.0, true, 1.0);
    g_cvSingleExposure = CreateConVar("sm_bot_ct_single_exposure", "1", "Prefer sheltered watch positions without losing the assigned entrance.", _, true, 0.0, true, 1.0);
    g_cvOpeningFall = CreateConVar("sm_bot_ct_keep_fall_order", "1", "Do not treat a world-only fall as enemy contact during opening defense.", _, true, 0.0, true, 1.0);
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
    g_cvOverpassTeamwork = CreateConVar("sm_bot_ct_overpass_teamwork", "1", "Overpass: cover-based reinforcement and reachable named retake routes.", _, true, 0.0, true, 1.0);
    g_cvOverpassAOpening = CreateConVar("sm_bot_ct_overpass_a_crossfire", "1", "Overpass standard A opening: paired Lower Park/Restroom holds.", _, true, 0.0, true, 1.0);
    g_cvMirageCrossfire = CreateConVar("sm_bot_ct_mirage_crossfire", "1", "Mirage: opening partners cover each other and briefly support confirmed contact.", _, true, 0.0, true, 1.0);
    g_cvNukeRoutes = CreateConVar("sm_bot_ct_nuke_route_cover", "1", "Nuke: one bounded route correction and lower-site anchor backfill.", _, true, 0.0, true, 1.0);
    g_cvProfiledRelief = CreateConVar("sm_bot_ct_profiled_relief", "1", "TEN Legacy maps: route-checked cover reinforcement for standard defenses.", _, true, 0.0, true, 1.0);
    g_cvProfiledRetake = CreateConVar("sm_bot_ct_profiled_retake", "1", "TEN Legacy maps: bounded map-specific staging entrances, with generic fallback.", _, true, 0.0, true, 1.0);

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
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) SDKHook(client, SDKHook_OnTakeDamage, MarkWorldFall);
}

public void OnMapStart()
{
    char map[64];
    GetCurrentMap(map, sizeof(map));
    g_infernoMap = StrEqual(map, "de_inferno", false);
    g_nukeMap = StrEqual(map, "de_nuke", false);
    g_mapProfile = TacticalMap_Find(map);
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
    if ((InfernoWatchEnabled() || (g_cvEntranceWatch.BoolValue && g_mapProfile >= 0 && !g_infernoMap))
        && NativeAvailable("NavMeshArea_GetPlaceCanonical"))
        NavMeshArea_GetPlaceCanonical(area, place, length);
    else
        NavMeshArea_GetPlace(area, place, length);
}

bool InfernoWatchEnabled()
{
    return g_infernoMap && g_cvInfernoWatch.BoolValue;
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, MarkWorldFall);
    g_plainFallTick[client] = 0;
    g_lastRouteFallAt[client] = 0.0;
    g_innerOrder[client] = false;
    g_overpassOpeningOrder[client] = false;
    g_anubisBreakableUntil[client] = 0.0;
    g_combatReleased[client] = false;
    g_guardSlot[client] = -1;
    g_guardStalls[client] = 0;
    g_lastCombatAt[client] = -100.0;
    g_guardReleasedAt[client] = -100.0;
    g_blindUntil[client] = 0.0;
    g_hasOrder[client] = false;
    g_hasLook[client] = false;
    g_recoveryDriveAt[client] = 0.0;
    g_recoveryTried[client] = false;
    g_objectiveNamed[client] = false;
    g_miragePartner[client] = 0;
    g_mirageTradeUntil[client] = 0.0;
    g_nukeDetouring[client] = false;
    g_nukeDetourUsed[client] = false;
    g_contactEnemy[client] = 0;
    g_contactSeenAt[client] = 0.0;
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
    if (g_phase == Phase_RetakeCommit && RetakeRelayEnabled()
        && client == GetClientOfUserId(g_defuserUserId) && !g_retakeUnopposed)
    {
        float position[3];
        GetClientAbsOrigin(client, position);
        if (g_defuserUsingBomb || GetVectorDistance(position, g_bombPosition) <= 128.0)
            return false; // Native AI owns the actual use/defuse interaction.
    }
    if (g_cvClearSiteDefuse.BoolValue && g_phase == Phase_RetakeCommit && g_retakeUnopposed)
    {
        int defuser = GetClientOfUserId(g_defuserUserId);
        if ((!RetakeRolesEnabled() && !RetakeRelayEnabled()) || !IsCTBot(defuser) || client == defuser || GetGameTime() > g_defuserHandoffUntil)
            return false;
    }

    if (g_orderExpires[client] > 0.0 && GetGameTime() >= g_orderExpires[client])
    {
        g_hasOrder[client] = false;
        g_orderExpires[client] = 0.0;
        g_orderLastProgressDistance[client] = 0.0;
        g_orderLastProgressAt[client] = 0.0;
        g_orderArrived[client] = false;
        return false;
    }

    if (NukeRouteCoverEnabled() && g_phase == Phase_Initial && g_nukeDetouring[client])
        SetNativeArray(2, g_nukeAlternate[client], 3);
    else SetNativeArray(2, g_orderGoal[client], 3);
    SetNativeCellRef(3, g_orderRoute[client]);
    return true;
}

public any Native_GetAim(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!g_cvEnabled.BoolValue || client < 1 || client > MaxClients || !g_hasOrder[client]
        || g_combatReleased[client] || !IsCTBot(client))
        return false;

    bool live = numParams >= 3 && GetNativeCell(3) != 0;
    if (live && NukeRouteCoverEnabled() && g_phase == Phase_Initial && g_nukeDetouring[client]) return false;
    if (live && MirageCrossfireEnabled() && g_phase == Phase_Initial && g_mirageTradeUntil[client] > GetGameTime())
    {
        float eye[3];
        GetClientEyePosition(client, eye);
        if (ObjectiveCover_Shot(eye, g_mirageTradeAim[client]))
        {
            SetNativeArray(2, g_mirageTradeAim[client], 3);
            return true;
        }
    }
    if (live && g_cvObjectiveWatch.BoolValue && g_objectiveNamed[client] && g_phase == Phase_GuardLooseBomb)
    {
        float eye[3];
        GetClientEyePosition(client, eye);
        if (GetVectorDistance(eye, g_orderLook[client]) < 150.0 || !TacticalAngles_ClearExactRay(eye, g_orderLook[client]))
            return false;
        SetNativeArray(2, g_orderLook[client], 3);
        return true;
    }
    if (live && NukeGuardWatchEnabled())
    {
        // The movement bridge stops a short distance from the nominal slot.
        // A clear ray from the slot is not proof that the BOT can see it.
        float position[3];
        GetClientAbsOrigin(client, position);
        // Match BetterBots' hold-release buffer, not only its entry radius.
        if (GetVectorDistance(position, g_orderGoal[client]) <= 256.0)
        {
            float eye[3];
            GetClientEyePosition(client, eye);
            float now = GetGameTime();
            if (now >= g_nukeGuardAimCheckAt[client] || GetVectorDistance(eye, g_nukeGuardEye[client]) > 28.0)
            {
                CopyVector(eye, g_nukeGuardEye[client]);
                g_nukeGuardAimCheckAt[client] = now + 0.5;
                g_nukeGuardAimValid[client] = g_hasLook[client] && NukeGuard_ClearRay(eye, g_orderLook[client]);
                if (g_nukeGuardAimValid[client]) CopyVector(g_orderLook[client], g_nukeGuardAim[client]);
                else g_nukeGuardAimValid[client] = NukeGuard_SelectLook(eye, g_guardSlot[client], g_nukeGuardAim[client]);
            }
            if (!g_nukeGuardAimValid[client]) return false;
            float look[3];
            CopyVector(g_nukeGuardAim[client], look);
            if (g_cvClearWatch.BoolValue && !TacticalAngles_ClipWatchRay(eye, look))
            {
                g_nukeGuardAimCheckAt[client] = 0.0;
                return false;
            }
            SetNativeArray(2, look, 3);
            return true;
        }
    }
    if (!g_hasLook[client]) return false;
    if (live && g_cvClearWatch.BoolValue)
    {
        float look[3];
        if (!TacticalAngles_SelectLiveWatch(client, g_orderGoal[client], g_orderLook[client], view_as<int>(g_phase), look))
            return false;
        SetNativeArray(2, look, 3);
        return true;
    }
    SetNativeArray(2, g_orderLook[client], 3);
    return true;
}

public any Native_ReportRouteDrive(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (g_cvRouteRecovery.BoolValue && IsCTBot(client) && g_hasOrder[client])
        TacticalRecovery_Report(client, GetNativeCell(2) != 0);
    return 0;
}

public any Native_GetHoldRadius(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return view_as<any>(GetCTHoldRadius(client));
}

float GetCTHoldRadius(int client)
{
    if (client >= 1 && client <= MaxClients && g_phase == Phase_Initial && g_hasOrder[client]
        && g_overpassOpeningOrder[client] && !g_combatReleased[client])
        return 24.0;
    if (client >= 1 && client <= MaxClients && g_phase == Phase_Initial && g_cvInnerHolds.BoolValue
        && g_hasOrder[client] && g_innerOrder[client] && !g_combatReleased[client])
        return 24.0;
    if (client >= 1 && client <= MaxClients && g_phase == Phase_Initial && InfernoWatchEnabled()
        && g_hasOrder[client] && g_hasLook[client] && g_infernoPreciseOrder[client] && !g_combatReleased[client])
        return 32.0;
    return 128.0;
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
    int site = ProfiledReliefEnabled() && g_phase == Phase_Initial ? ProfiledReliefSite(enemyPosition) : NearestSite(enemyPosition);
    ExperienceSignal("first_sight", "visible_enemy", site, spotter);
    float now = GetGameTime();
    // Refresh even when site radio is on cooldown or this bot already yielded
    // its order. Otherwise it can be pulled back into formation mid-fight.
    g_lastCombatAt[spotter] = now;
    g_contactEnemy[spotter] = GetClientUserId(enemy);
    g_contactSeenAt[spotter] = now;
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
    if (ProfiledReliefEnabled() && g_phase == Phase_Initial) credibleSite = ProfiledReliefCredible(enemyPosition, site);
    bool localTrade;
    if (credibleSite && g_phase == Phase_Initial)
    {
        if (MirageCrossfireEnabled()) localTrade = MirageSupportContact(spotter, enemyPosition, now);
        RememberSiteEnemy(site, GetClientUserId(enemy), now);
        TryReorganizeDefense(site, enemyPosition, spotter, now);
    }
    if (g_lastContactAt[site] > 0.0 && now < g_lastContactAt[site] + g_cvContactCooldown.FloatValue)
        return false;
    g_lastContactAt[site] = now;

    ReleaseOrder(spotter, "enemy spotted");
    ReportEnemy(spotter, enemyPosition, site);
    if (g_cvReinforceOnContact.BoolValue && credibleSite && !localTrade && !g_reorganizedSite[site]
        && g_phase != Phase_CarrierResponse)
    {
        if (ProfiledReliefEnabled() && g_phase == Phase_Initial && ProfiledContactHasCover(spotter, enemy, enemyPosition))
            ExperienceSignal("reinforce_skip", "already_supported", site, spotter);
        else RequestReinforcement(enemyPosition, site, spotter, "enemy contact");
    }
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
    int reinforcement = RequestReinforcement(contactPosition, site, spotter, "confirmed multi-enemy site pressure", g_lastReinforcement[site]);
    // A report with no eligible Overpass helper must not use up the site's
    // reorganization. Leave subsequent contact/casualty reports actionable.
    if ((OverpassTeamworkEnabled() || ProfiledReliefEnabled()) && reinforcement == 0) return;
    g_reorganizedSite[site] = true;
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
    g_nukeBackfillUsed = false;
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
    g_defuserUserId = 0;
    g_defuserUsingBomb = false;
    g_nextDefuserReviewAt = 0.0;
    g_defuserRetiredUserId = 0;
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
    g_retakeBombRef = EntIndexToEntRef(bomb);
    PlanRetake(false);
    return Plugin_Stop;
}

public void Event_BombBeginDefuse(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if ((RetakeRolesEnabled() || RetakeRelayEnabled()) && IsCTBot(client))
    {
        g_defuserUsingBomb = true;
        g_defuserUserId = GetClientUserId(client);
        g_defuserHandoffUntil = GetGameTime() + (GetEntProp(client, Prop_Send, "m_bHasDefuser") ? 5.5 : 10.5);
    }
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
    if (AnubisOpeningClearsBreakable(client)) return;
    if (g_phase == Phase_RetakeStage && IsCTBot(client))
        g_retakeContact = true;
    ReleaseOrder(client, "weapon contact");
}

bool AnubisOpeningClearsBreakable(int client)
{
    if (g_mapProfile != 9 || g_phase != Phase_Initial || g_plan != Plan_Standard || !IsCTBot(client)
        || !g_hasOrder[client] || !NativeAvailable("BotStuff_HasVisibleEnemy") || BotStuff_HasVisibleEnemy(client))
        return false;

    float now = GetGameTime();
    if (g_anubisBreakableUntil[client] <= now || now - g_lastCombatAt[client] < 2.0) return false;
    DebugLog("Retained %N opening order during native breakable clearing.", client);
    return true;
}

public any Native_ReportBreakable(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    // Capture the engine's intent, not the post-shot collision: the brush
    // may already be gone or the firearm may hit the wall behind it.
    if (g_mapProfile == 9 && g_roundLive && g_phase == Phase_Initial && g_plan == Plan_Standard
        && IsCTBot(client) && g_hasOrder[client])
        // A short burst can outlast the look request when the brush breaks
        // on its first shot. Real sight/damage still releases immediately.
        g_anubisBreakableUntil[client] = GetGameTime() + 2.0;
    return 0;
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
    if (g_cvOpeningFall.BoolValue && g_phase == Phase_Initial && IsCTBot(victim)
        && (attacker == 0 || attacker == victim) && g_plainFallTick[victim] == GetGameTickCount())
    {
        g_plainFallTick[victim] = 0;
        if (g_nukeMap && g_hasOrder[victim])
        {
            float foot[3], now = GetGameTime();
            GetClientAbsOrigin(victim, foot);
            float remaining = GetVectorDistance(foot, g_orderGoal[victim]);
            // One fall is not a fight; repeatedly following the same
            // multi-level route into a fall with no progress is a route failure.
            if (g_lastRouteFallAt[victim] > 0.0 && now - g_lastRouteFallAt[victim] <= 18.0
                && remaining > GetCTHoldRadius(victim) && remaining >= g_lastRouteFallDistance[victim] - 64.0)
            {
                if (NukeRouteCoverEnabled() && (g_nukeDetouring[victim] || NukeTryDetour(victim, foot))) return;
                DebugLog("Opening route for %N repeatedly returned to a fall without progress.", victim);
                ReleaseOrder(victim, "navigation stalled");
                return;
            }
            g_lastRouteFallAt[victim] = now;
            g_lastRouteFallDistance[victim] = remaining;
        }
        DebugLog("Retained %N opening hold after world fall.", victim);
        return;
    }
    if (g_phase == Phase_RetakeStage && (IsCTBot(victim) || IsCTBot(attacker)))
        g_retakeContact = true;
    ReleaseOrder(victim, "hurt");
    ReleaseOrder(attacker, "combat");
}

public Action MarkWorldFall(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
    if (g_phase == Phase_Initial && IsCTBot(victim))
        g_plainFallTick[victim] = damageType == DMG_FALL
            && (attacker == 0 || attacker == victim) ? GetGameTickCount() : 0;
    return Plugin_Continue;
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
        bool lowerHandled;
        if (NukeRouteCoverEnabled() && g_cvEnabled.BoolValue && g_cvReinforceOnDeath.BoolValue
            && g_phase == Phase_Initial && !g_bombPlanted && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT)
            lowerHandled = NukeBackfillLower(client);
        if (!lowerHandled && g_cvEnabled.BoolValue && g_cvReinforceOnDeath.BoolValue && !g_bombPlanted
            && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_CT && g_geometryReady && NavMeshReady())
        {
            float deathPosition[3];
            GetClientAbsOrigin(client, deathPosition);
            bool profiled = ProfiledReliefEnabled() && g_phase == Phase_Initial;
            int deathSite = profiled ? ProfiledReliefSite(deathPosition) : NearestSite(deathPosition);
            if (!g_fullRotateSite[deathSite] && g_phase != Phase_CarrierResponse
                && (!profiled || ProfiledReliefCredible(deathPosition, deathSite)))
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
    if (g_cvClearSiteDefuse.BoolValue && g_bombPlanted
        && (g_phase == Phase_RetakeStage || g_phase == Phase_RetakeCommit) && RetakeIsUnopposed())
    {
        bool firstClear = !g_retakeUnopposed;
        g_retakeUnopposed = true;
        if (g_phase == Phase_RetakeStage) PlanRetake(true);
        if (RetakeRelayEnabled()) ReviewDefuser();
        else if (firstClear && RetakeRolesEnabled()) SelectDefuser();
        return Plugin_Continue;
    }
    g_retakeUnopposed = false;
    if (g_phase == Phase_RetakeCommit && RetakeRelayEnabled()) ReviewDefuser();
    ReviewPairedPressure();
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
            || RetakeClockUrgent()
            || (elapsed >= (OverpassTeamworkEnabled() ? FloatMin(4.0, g_cvRetakeStage.FloatValue) : g_cvRetakeStage.FloatValue)
                && OrdersMeetReadyPercent(180.0, g_cvSyncMinReady.IntValue))
            || elapsed >= (OverpassTeamworkEnabled() ? FloatMin(7.0, g_cvRetakeStageTimeout.FloatValue) : g_cvRetakeStageTimeout.FloatValue)))
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

    float infernoAims[5][3];
    bool infernoProfile = false;
    if (g_plan == Plan_Standard)
    {
        if (InfernoWatchEnabled()) infernoProfile = TryBuildInfernoOpening(count, infernoAims);
        if (!infernoProfile) BuildStandardTargets(count);
    }
    else if (g_plan == Plan_SingleSitePush)
        BuildPushTargets(count);
    else
        BuildStackTargets(count);

    FillMissingTargets(count);
    // Initial deployments are time-sensitive and must not inherit BetterBots'
    // accumulated danger weights. SAFEST_ROUTE can send an A defender through
    // B/T spawn; FASTEST_ROUTE keeps the setup on its intended side of the map.
    AssignTargets(bots, count, Route_Fastest, -1, true);
    if (infernoProfile) ApplyInfernoOpeningAims(count, infernoAims);
    g_phase = Phase_Initial;
    if (g_plan == Plan_Standard && g_mapProfile >= 0) RefineStandardHolds();
    if (g_plan == Plan_Standard && g_mapProfile == 5 && count >= 4 && g_cvOverpassAOpening.BoolValue)
        OverpassPairOpening();
    if (g_plan == Plan_Standard && MirageCrossfireEnabled()) MirageBuildCrossfire();
    g_pressureReturnAt = 0.0;
    if (g_mapProfile == 2 && g_plan == Plan_Standard && count >= 4
        && g_cvPairedPressure.IntValue > 0 && GetRandomInt(1, 100) <= g_cvPairedPressure.IntValue)
        BeginPairedPressure();
    g_phaseStarted = GetGameTime();
    ExperienceSignal("opening_orders", "initial_defense", g_planSite, 0);
    char buy[12], plan[24];
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    DebugLog("Initial CT plan: buy=%s plan=%s bots=%d", buy, plan, count);
    if (GetFeatureStatus(FeatureType_Native, "BotExperience_RecordOpeningPlan") == FeatureStatus_Available)
        BotExperience_RecordOpeningPlan(CS_TEAM_CT, view_as<int>(g_buyState), view_as<int>(g_plan), g_planSite, count);
}

void BeginPairedPressure()
{
    if (!NativeAvailable("NavMesh_BuildPath") || !NativeAvailable("NavMeshArea_GetCostSoFar")) return;
    int pair[2];
    for (int i = 1; i <= MaxClients && pair[1] == 0; i++)
    {
        if (!IsCTBot(i) || !g_hasOrder[i] || !g_hasLook[i] || NearestSite(g_orderGoal[i]) != 0) continue;
        if (!pair[0]) pair[0] = i;
        else pair[1] = i;
    }
    if (!pair[1]) return;
    float goals[2][3], pressureLook[2][3];
    for (int slot = 0; slot < 2; slot++)
    {
        int client = pair[slot];
        float direction[3], desired[3];
        MakeVectorFromPoints(g_orderGoal[client], g_orderLook[client], direction);
        direction[2] = 0.0;
        NormalizeVector(direction, direction);
        ScaleVector(direction, slot == 0 ? 190.0 : 120.0);
        AddVectors(g_orderGoal[client], direction, desired);
        int from = NavMesh_GetNearestArea(g_orderGoal[client], false, 120.0, false, true, TEAM_ANY);
        if (from < 0) return;
        ArrayStack areas = new ArrayStack();
        NavMesh_CollectSurroundingAreas(areas, from, 460.0, 18.0, 32.0);
        float best = 999999.0;
        while (!areas.Empty)
        {
            int to = areas.Pop();
            float point[3], toward[3], look[3], eye[3], other[3], fraction;
            if (to == from || !NavMeshArea_GetCenter(to, point) || NearestSite(point) != 0
                || FloatAbs(point[2] - g_orderGoal[client][2]) > 36.0) continue;
            MakeVectorFromPoints(g_orderGoal[client], point, toward);
            float move = GetVectorLength(toward), score = GetVectorDistance(point, desired);
            if (move < 65.0 || move > 380.0 || score >= best || GetVectorDotProduct(toward, direction) < 45.0) continue;
            CopyVector(g_orderLook[client], look);
            if (!TacticalAngles_RequireClearWatch(point, look)) continue;
            if (slot == 1)
            {
                float spacing = GetVectorDistance(point, goals[0]);
                if (spacing < 115.0 || spacing > 625.0) continue;
                CopyVector(point, eye);
                CopyVector(goals[0], other);
                eye[2] += 60.0;
                other[2] += 60.0;
                if (!TacticalAngles_IsVisible(eye, other, 0, fraction)) continue;
            }
            int closest;
            if (!NavMesh_BuildPath(to, from, g_orderGoal[client], RetakeTravelCost, 500, closest, 0.0, 0.0)) continue;
            best = score;
            CopyVector(point, goals[slot]);
            CopyVector(look, pressureLook[slot]);
        }
        delete areas;
        if (best >= 999999.0) return;
    }
    for (int slot = 0; slot < 2; slot++)
    {
        int client = pair[slot];
        g_pressureUsers[slot] = GetClientUserId(client);
        CopyVector(g_orderGoal[client], g_pressureHomes[slot]);
        CopyVector(g_orderLook[client], g_pressureAims[slot]);
        g_pressureHasAim[slot] = g_hasLook[client];
        g_pressureInner[slot] = g_innerOrder[client];
        CopyVector(goals[slot], g_orderGoal[client]);
        CopyVector(pressureLook[slot], g_orderLook[client]);
        g_hasLook[client] = true;
        StartOrderProgress(client);
    }
    g_pressureReturnAt = GetGameTime() + 8.0;
    ExperienceSignal("opening_pair_pressure", "mirage_a", 0, pair[0]);
    DebugLog("CT paired pressure: %N and %N", pair[0], pair[1]);
}

void ReviewPairedPressure()
{
    if (g_pressureReturnAt <= 0.0) return;
    if (g_phase != Phase_Initial || g_bombPlanted) { g_pressureReturnAt = 0.0; return; }
    bool abort = g_cvPairedPressure.IntValue == 0 || GetGameTime() >= g_pressureReturnAt;
    for (int slot = 0; slot < 2 && !abort; slot++)
    {
        int client = GetClientOfUserId(g_pressureUsers[slot]);
        if (!IsCTBot(client) || !g_hasOrder[client] || g_combatReleased[client]) abort = true;
    }
    if (!abort) return;
    g_pressureReturnAt = 0.0;
    for (int slot = 0; slot < 2; slot++)
    {
        int client = GetClientOfUserId(g_pressureUsers[slot]);
        if (!IsCTBot(client) || !g_hasOrder[client] || g_combatReleased[client]) continue;
        CopyVector(g_pressureHomes[slot], g_orderGoal[client]);
        CopyVector(g_pressureAims[slot], g_orderLook[client]);
        g_hasLook[client] = g_pressureHasAim[slot];
        StartOrderProgress(client);
        g_innerOrder[client] = g_pressureInner[slot];
    }
    DebugLog("CT paired pressure returned to original coverage.");
}

bool TryBuildInfernoOpening(int count, float aims[5][3])
{
    if (count < 1 || count > 5) return false;
    float holds[5][3];
    for (int slot = 0; slot < count; slot++)
    {
        int role = CTInferno_GetRole(slot, count);
        if (!CTInferno_GetPair(role, holds[slot], aims[slot]))
        {
            DebugLog("Inferno opening pair %d unavailable; using validated generic fallback.", role);
            return false;
        }
    }
    for (int slot = 0; slot < count; slot++) AppendTarget(holds[slot]);
    return true;
}

void ApplyInfernoOpeningAims(int count, const float aims[5][3])
{
    // AssignTargets still owns BOT selection and movement. Match the exact
    // selected position rather than duplicating team/client assignment.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_hasOrder[client]) continue;
        for (int slot = 0; slot < count; slot++)
        {
            if (GetVectorDistance(g_orderGoal[client], g_targets[slot]) > 1.0) continue;
            CopyVector(aims[slot], g_orderLook[client]);
            g_hasLook[client] = true;
            g_infernoPreciseOrder[client] = true;
            DebugLog("Inferno watch %N: role=%d", client, CTInferno_GetRole(slot, count));
            break;
        }
    }
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

bool CTInner_InTrigger(const float foot[3], const ArrayList zones)
{
    for (int zone = 0; zone < zones.Length; zone++)
        for (int height = 12; height <= 44; height += 16)
        {
            float point[3], end[3];
            CopyVector(foot, point);
            point[2] += float(height);
            CopyVector(point, end);
            end[2] += 1.0;
            Handle ray = TR_ClipRayToEntityEx(point, end, MASK_ALL, RayType_EndPoint, zones.Get(zone));
            bool inside = TR_StartSolid(ray);
            delete ray;
            if (inside) return true;
        }
    return false;
}

bool CTInner_Inset(const float foot[3], const ArrayList zones)
{
    if (!CTInner_InTrigger(foot, zones)) return false;
    // The movement tolerance must fit INSIDE the brush, not just reach an
    // endpoint that is barely inside while the actual defender stops outside.
    for (int step = 0; step < 8; step++)
    {
        float point[3], angle = float(step) * 0.785398163;
        CopyVector(foot, point);
        point[0] += 30.0 * Cosine(angle);
        point[1] += 30.0 * Sine(angle);
        if (!CTInner_InTrigger(point, zones)) return false;
    }
    return true;
}

void RefineStandardHolds()
{
    // Leave short-handed layouts and the deliberate ECO pressure/stack mixes
    // alone. Both the exterior roles and one inner role are possible with 4+.
    int count;
    for (int client = 1; client <= MaxClients; client++)
        if (g_hasOrder[client]) count++;
    for (int site = 0; site < 2; site++)
    {
        if (!g_cvInnerHolds.BoolValue && !g_cvSingleExposure.BoolValue) continue;
        float objective[3], other[3];
        TacticalMap_PlantGround(g_mapProfile, site, objective);
        TacticalMap_PlantGround(g_mapProfile, 1 - site, other);
        ArrayList lanes = ObjectiveWatch_Collect(g_mapProfile, site, false, objective);
        if (g_cvInnerHolds.BoolValue && count >= 4) CTInner_Assign(site, objective, other, lanes);
        int extraLane = -1;
        if (g_mapProfile == 4 && site == 0 && g_cvEntranceWatch.BoolValue)
        {
            int occupied;
            for (int client = 1; client <= MaxClients; client++)
                if (g_hasOrder[client] && g_hasLook[client]
                    && GetVectorDistance(g_orderGoal[client], objective) < GetVectorDistance(g_orderGoal[client], other))
                {
                    int lane = ObjectiveCover_AimLane(g_mapProfile, site, false, g_orderLook[client]);
                    if (lane >= 0) occupied |= 1 << lane;
                }
            // Dust II A: when the team already has one named lane, allow the
            // generic exterior role to take the other if the new hold is
            // safer. Never trade a named assignment for that fallback.
            if (occupied == 1 || occupied == 2) extraLane = occupied == 1 ? 1 : 0;
        }
        if (g_cvSingleExposure.BoolValue)
            for (int client = 1; client <= MaxClients; client++)
            {
                if (!g_hasOrder[client] || !g_hasLook[client] || g_innerOrder[client] || g_infernoPreciseOrder[client]
                    || GetVectorDistance(g_orderGoal[client], objective) > GetVectorDistance(g_orderGoal[client], other)
                    || GetVectorDistance(g_orderGoal[client], objective) > 900.0) continue;
                if (ObjectiveCover_Refine(client, lanes, g_mapProfile, site, false, objective, false, false, extraLane))
                {
                    StartOrderProgress(client);
                    extraLane = -1;
                }
            }
        delete lanes;
    }
}

void CTInner_Assign(int site, const float objective[3], const float other[3], const ArrayList lanes)
{
    if (!NativeAvailable("NavMesh_BuildPath") || !NativeAvailable("NavMeshArea_GetCostSoFar")) return;
    int area = NavMesh_GetNearestArea(objective, false, 120.0, false, true, TEAM_ANY);
    if (area < 0) return;
    int owner;
    float closestHold = 950.0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_hasOrder[client] || g_innerOrder[client]) continue;
        float distance = GetVectorDistance(g_orderGoal[client], objective);
        if (distance < closestHold && distance < GetVectorDistance(g_orderGoal[client], other))
        {
            owner = client;
            closestHold = distance;
        }
    }
    if (!owner) return;
    if (site == 1 && NukeRouteCoverEnabled()) owner = NukePreferLowerOwner(owner, area, objective, other);
    float spawn[3];
    GetClientAbsOrigin(owner, spawn);
    int start = NavMesh_GetNearestArea(spawn, false, 150.0, false, true, TEAM_ANY);
    if (start < 0) return;
    ArrayList zones = new ArrayList();
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
    {
        float mins[3], maxs[3], center[3];
        GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
        GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
        GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", center);
        for (int axis = 0; axis < 3; axis++) center[axis] += (mins[axis] + maxs[axis]) * 0.5;
        if (GetVectorDistance(center, objective) <= GetVectorDistance(center, other)) zones.Push(entity);
    }
    ArrayStack areas = new ArrayStack();
    NavMesh_CollectSurroundingAreas(areas, area, 660.0, 24.0, 45.0);
    areas.Push(area);
    int preferred = g_hasLook[owner] ? ObjectiveCover_AimLane(g_mapProfile, site, false, g_orderLook[owner]) : -1;
    int covered;
    for (int client = 1; client <= MaxClients; client++)
        if (client != owner && g_hasOrder[client] && g_hasLook[client])
        {
            int lane = ObjectiveCover_AimLane(g_mapProfile, site, false, g_orderLook[client]);
            if (lane >= 0) covered |= 1 << lane;
        }
    if (preferred >= 0 && (covered & (1 << preferred))) preferred = -1;
    float best = 999999.0, bestGoal[3], bestAim[3];
    int budget = 64;
    while (!areas.Empty && zones.Length > 0 && budget > 0)
    {
        int candidate = areas.Pop();
        for (int sample = 0; sample < 2 && budget > 0; sample++)
        {
            float center[3], point[3], eye[3], look[3], targets[3][3];
            if (sample == 0)
            {
                if (!NavMeshArea_GetCenter(candidate, center)) continue;
            }
            else
            {
                if (!NativeAvailable("NavMeshArea_GetClosestPointOnArea")) continue;
                NavMeshArea_GetClosestPointOnArea(candidate, objective, center);
            }
            if (FloatAbs(center[2] - objective[2]) > 85.0 || !ObjectiveCover_Floor(center, point)
                || ObjectiveCover_Support(owner, point) < 0 || !CTInner_Inset(point, zones)) continue;
            budget--;
            int mask = ObjectiveWatch_Score(lanes, point, targets), chosen = -1;
            if (preferred >= 0)
            {
                if (!(mask & (1 << preferred))) continue; // don't abandon the only cover on this entrance
                chosen = preferred;
            }
            else
            {
                for (int lane = 0; lane < 3; lane++)
                    if ((mask & (1 << lane)) && (chosen < 0 || !(covered & (1 << lane))
                        && (covered & (1 << chosen)))) chosen = lane;
            }
            if (chosen >= 0) CopyVector(targets[chosen], look);
            else
            {
                TacticalAngles_SelectLook(owner, point, g_tSpawn, 0, look);
                if (!TacticalAngles_RequireClearWatch(point, look)) continue;
            }
            CopyVector(point, eye);
            eye[2] += 64.0;
            float plant[3];
            CopyVector(objective, plant);
            plant[2] += 42.0;
            // Cover exposure dominates distance; prefer a view of the plant
            // and a distinct entry when two equally sheltered points work.
            float score = float(ObjectiveCover_Exposure(lanes, point)) * 500.0
                + (ObjectiveCover_Shot(eye, plant) ? 0.0 : 190.0)
                + (chosen >= 0 ? ((covered & (1 << chosen)) ? 90.0 : 0.0) : 240.0)
                + GetVectorDistance(point, g_orderGoal[owner]) * 0.25;
            int reachable;
            if (score >= best || !NavMesh_BuildPath(start, candidate, point, RetakeTravelCost, 6500, reachable, 0.0, 0.0)) continue;
            best = score;
            CopyVector(point, bestGoal);
            CopyVector(look, bestAim);
        }
    }
    delete areas;
    delete zones;
    if (best >= 999999.0) return;
    CopyVector(bestGoal, g_orderGoal[owner]);
    CopyVector(bestAim, g_orderLook[owner]);
    g_hasLook[owner] = true;
    StartOrderProgress(owner);
    g_innerOrder[owner] = true;
    DebugLog("Reserved inset %s hold for %N at %.0f %.0f %.0f.",site == 0 ? "A" : "B",owner,bestGoal[0],bestGoal[1],bestGoal[2]);
}

// Two measured legacy Overpass A footprints: the inner anchor takes the
// park swing; the second player holds the restroom exit with a shared line
// into the park swing. These are only a proposal until BOTH fit the loaded
// map and are reachable; a map revision or occupied slot leaves both intact.
void OverpassPairOpening()
{
    if (!g_cvInnerHolds.BoolValue || !g_cvEntranceWatch.BoolValue
        || !NativeAvailable("NavMesh_BuildPath") || !NativeAvailable("NavMeshArea_GetCostSoFar")) return;

    float center[3], other[3];
    TacticalMap_PlantGround(5, 0, center);
    TacticalMap_PlantGround(5, 1, other);
    int pair[2], eligible;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_hasOrder[client] || !g_hasLook[client] || !IsCTBot(client)) continue;
        float dist = GetVectorDistance(center, g_orderGoal[client]);
        if (dist > 820.0 || dist >= GetVectorDistance(other, g_orderGoal[client])
            || FloatAbs(g_orderGoal[client][2] - center[2]) > 115.0) continue;
        pair[g_innerOrder[client] ? 0 : 1] = client;
        eligible++;
    }
    if (eligible != 2 || !pair[0] || !pair[1]) return;

    static const float positions[2][3] = {{-2212.5,700.0,474.2},{-2387.5,750.0,474.2}};
    static const float park[3][3] = {{-2505.0,260.0,517.0},{-2450.0,92.0,490.0},{-2487.0,269.0,522.0}};
    static const float restroom[5][3] = {{-2462.5,-187.5,496.0},{-2550.0,-175.0,496.0},
        {-2487.5,-175.0,496.0},{-2562.5,-112.5,496.0},{-2675.0,-150.0,495.4}};
    float goals[2][3], eyes[2][3], aim[2][3];
    for (int slot = 0; slot < 2; slot++)
    {
        int client = pair[slot];
        if (!ObjectiveCover_Floor(positions[slot], goals[slot])
            || GetVectorDistance(goals[slot], positions[slot]) > 12.0
            || GetVectorDistance(goals[slot], g_orderGoal[client]) > 570.0) return;
        for (int peer = 1; peer <= MaxClients; peer++)
            if (peer != pair[0] && peer != pair[1] && g_hasOrder[peer]
                && GetVectorDistance(g_orderGoal[peer], goals[slot]) < 140.0) return;

        float spawn[3];
        GetClientAbsOrigin(client, spawn);
        int start = NavMesh_GetNearestArea(spawn, false, 160.0, false, true, TEAM_ANY);
        int oldArea = NavMesh_GetNearestArea(g_orderGoal[client], false, 110.0, false, true, TEAM_ANY);
        int dest = NavMesh_GetNearestArea(goals[slot], false, 48.0, false, true, TEAM_ANY);
        int oldTravel = CTPathLength(start, oldArea, g_orderGoal[client], 6500);
        int travel = CTPathLength(start, dest, goals[slot], 6500);
        if (oldTravel < 0 || travel < 0 || travel > oldTravel + 500) return;
        CopyVector(goals[slot], eyes[slot]);
        eyes[slot][2] += 64.0;
    }
    if (GetVectorDistance(goals[0], goals[1]) < 175.0) return;

    // Keep the designated in-site role safely inside the real bomb trigger.
    ArrayList zones = new ArrayList();
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
        zones.Push(entity);
    bool inside = CTInner_Inset(goals[0], zones);
    delete zones;
    if (!inside) return;

    // Lower Park gunfight samples sit on the same approach. Distinct distant
    // entrances still use the standard cover audit (not a number of rays).
    ArrayList lanes = ObjectiveWatch_Collect(5, 0, false, center);
    bool cover = lanes.Length > 0 && ObjectiveCover_Exposure(lanes, goals[0]) <= 1
        && ObjectiveCover_Exposure(lanes, goals[1]) <= 1;
    delete lanes;
    if (!cover) return;
    int shared;
    for (int point = 0; point < sizeof(park); point++)
        if (ObjectiveCover_Shot(eyes[0], park[point]) && ObjectiveCover_Shot(eyes[1], park[point]))
        {
            if (!shared) CopyVector(park[point], aim[0]);
            shared++;
        }
    if (shared < 2) return;

    bool toilet;
    for (int point = 0; point < sizeof(restroom); point++)
        if (ObjectiveCover_Shot(eyes[1], restroom[point]))
        {
            CopyVector(restroom[point], aim[1]);
            toilet = true;
            break;
        }
    if (!toilet) return;
    for (int slot = 0; slot < 2; slot++)
    {
        int client = pair[slot];
        CopyVector(goals[slot], g_orderGoal[client]);
        CopyVector(aim[slot], g_orderLook[client]);
        StartOrderProgress(client);
        g_innerOrder[client] = slot == 0;
        g_overpassOpeningOrder[client] = true;
    }
    ExperienceSignal("opening_crossfire", "overpass_a_park_restroom", 0, pair[1]);
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
    else if (StrEqual(map, "de_cache", false) && g_cvEntranceWatch.BoolValue)
        SetAnchorProfile("BombsiteA", "Forklift", "BombsiteB", "Rafters");
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
    ArrayList watchLanes = null;
    int usedLanes;
    if (g_cvObjectiveWatch.BoolValue) watchLanes = ObjectiveWatch_Collect(g_mapProfile, RetakeSite(), false, g_bombPosition);
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
        g_objectiveNamed[selected] = watchLanes != null && ObjectiveWatch_Select(watchLanes, g_orderGoal[selected], usedLanes, g_orderLook[selected]);
        if (!g_objectiveNamed[selected] && NukeGuardWatchEnabled()) ResolveNukeGuardLook(selected);
    }
    ExperienceSignal("guard_bomb", "loose_c4_seen", NearestSite(g_bombPosition), spotter);
    DebugLog("%N saw dropped C4; reserved %d CT guard positions.", spotter, guardCount);
    if (g_cvSingleExposure.BoolValue && watchLanes != null)
    {
        // The reserved orders are not yet active. Only publish and refine after
        // ResumeLooseBombGuards has applied its normal quiet/combat checks.
        ResumeLooseBombGuards();
        for (int client = 1; client <= MaxClients; client++)
        {
            if (g_guardSlot[client] < 0 || !g_hasOrder[client] || !g_hasLook[client]) continue;
            if (ObjectiveCover_Refine(client, watchLanes, g_mapProfile, RetakeSite(), false, g_bombPosition, true, true))
                StartOrderProgress(client);
        }
    }
    delete watchLanes;
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
        if (g_hasOrder[client] || g_guardStalls[client] >= (g_cvRouteRecovery.BoolValue ? 1 : 3) || g_blindUntil[client] > now
            || now - g_lastCombatAt[client] < 2.5 || now - g_guardReleasedAt[client] < 2.5)
            continue;
        g_combatReleased[client] = false;
        g_hasOrder[client] = true;
        g_hasLook[client] = true;
        if (!g_objectiveNamed[client] && NukeGuardWatchEnabled()) ResolveNukeGuardLook(client);
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
        g_nukeGuardAimCheckAt[client] = 0.0;
        g_nukeGuardAimValid[client] = false;
    }
}

bool NukeGuardWatchEnabled()
{
    return g_nukeMap && g_cvNukeGuardWatch.BoolValue && g_phase == Phase_GuardLooseBomb;
}

void ResolveNukeGuardLook(int client)
{
    float eye[3], look[3];
    CopyVector(g_orderGoal[client], eye);
    eye[2] += 64.0;
    // Keep the nominal hold when there is no clear planned ray; the live
    // query may find one from the actual eye or yield to native scanning.
    if (NukeGuard_SelectLook(eye, g_guardSlot[client], look))
        CopyVector(look, g_orderLook[client]);
    g_nukeGuardAimCheckAt[client] = 0.0;
}

bool NukeGuard_ClearRay(const float eye[3], const float look[3])
{
    if (Distance2D(eye, look) < 150.0 || FloatAbs(eye[2] - look[2]) > 100.0) return false;
    Handle trace = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
    bool clear = !TR_StartSolid(trace) && !TR_DidHit(trace);
    delete trace;
    return clear;
}

bool NukeGuard_SelectLook(const float eye[3], int slot, float look[3])
{
    float dx = g_bombPosition[0] - eye[0], dy = g_bombPosition[1] - eye[1];
    // Let one side watch across the C4. Other offsets split the likely
    // approaches; NAV-supported endpoints keep the ray in playable space.
    Normalize2D(dx, dy);
    if (FloatAbs(dx) + FloatAbs(dy) < 0.01) dx = 1.0;
    float axisX, axisY;
    Rotate2D(dx, dy, TacticalAngles_GetSlotOffset(slot < 0 ? 0 : slot), axisX, axisY);
    float best = -999999.0;
    int start = NavMeshReady() ? NavMesh_GetNearestArea(eye, false, 160.0, false, true, TEAM_ANY) : -1;
    if (start >= 0)
    {
        ArrayStack areas = new ArrayStack();
        NavMesh_CollectSurroundingAreas(areas, start, 850.0, 26.0, 60.0);
        while (!areas.Empty)
        {
            float candidate[3];
            if (!NavMeshArea_GetCenter(areas.Pop(), candidate)) continue;
            candidate[2] += 64.0;
            float range = Distance2D(eye, candidate);
            if (range < 150.0 || range > 780.0 || FloatAbs(eye[2] - candidate[2]) > 100.0) continue;
            float alignment = ((candidate[0] - eye[0]) * axisX + (candidate[1] - eye[1]) * axisY) / range;
            float score = alignment * 200.0 - FloatAbs(range - 450.0) * 0.12;
            if (score <= best || !NukeGuard_ClearRay(eye, candidate)) continue;
            best = score;
            CopyVector(candidate, look);
        }
        delete areas;
    }
    // A narrow corridor can have a clear short lane but no usable NAV center.
    if (best > -999999.0) return true;
    for (int step = 0; step < 12; step++)
    {
        float x, y, candidate[3];
        float turn = float((step + 1) / 2) * (step % 2 != 0 ? -30.0 : 30.0);
        Rotate2D(axisX, axisY, turn, x, y);
        CopyVector(eye, candidate);
        candidate[0] += x * 175.0;
        candidate[1] += y * 175.0;
        if (!NukeGuard_ClearRay(eye, candidate)) continue;
        CopyVector(candidate, look);
        return true;
    }
    return false; // Keep the guard slot, but let native AI scan when no safe sightline exists.
}

bool RetakeIsUnopposed()
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T) return false;
    return true;
}

bool RetakeClockUrgent()
{
    if (!g_cvRetakeClockAware.BoolValue) return false;
    int bomb = EntRefToEntIndex(g_retakeBombRef);
    if (bomb == INVALID_ENT_REFERENCE || !HasEntProp(bomb, Prop_Send, "m_flC4Blow")
        || !HasEntProp(bomb, Prop_Send, "m_bBombTicking") || !GetEntProp(bomb, Prop_Send, "m_bBombTicking")) return false;
    float remaining = GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow") - GetGameTime();
    // Reserve time for the final approach and a ten-second kitless defuse.
    return remaining > 0.0 && remaining <= 20.0;
}

void PlanRetake(bool commit)
{
    int bots[MAXPLAYERS + 1];
    int count = CollectCTBots(bots);
    if (count == 0 || !NavMeshReady())
        return;

    if (!commit && g_cvRetakeClockAware.BoolValue && (count == 1 || RetakeClockUrgent()))
    {
        ExperienceSignal("retake_skip_stage", count == 1 ? "solo_bot" : "bomb_clock", NearestSite(g_bombPosition), 0);
        commit = true;
    }
    g_targetCount = 0;
    int namedLanes;
    if (commit)
        BuildAround(g_bombPosition, count, 40.0, 260.0, false, 0.0, 0.0);
    else
    {
        if (RetakeRolesEnabled() || ProfiledRetakeEnabled()) AppendRetakeEntrances(count, bots);
        if (OverpassTeamworkEnabled() || ProfiledRetakeEnabled()) namedLanes = g_targetCount;
        // Greedy matching may use the only bot able to reach a later lane.
        // Keep fallback goals for every survivor, not just unreserved slots.
        int fallback = ProfiledRetakeEnabled() ? count : count - g_targetCount;
        BuildAround(g_bombPosition, fallback, 350.0, 900.0, false, 0.0, 0.0);
    }

    int needed = count + (!commit && ProfiledRetakeEnabled() ? namedLanes : 0);
    FillMissingTargetsAt(needed <= sizeof(g_targets) ? needed : sizeof(g_targets), g_bombPosition);
    AssignTargets(bots, count, (commit || namedLanes > 0) ? Route_Fastest : Route_Safest, -1, false, namedLanes);
    g_phase = commit ? Phase_RetakeCommit : Phase_RetakeStage;
    g_phaseStarted = GetGameTime();
    ExperienceSignal(commit ? "retake_commit" : "retake_stage", "bomb_planted", NearestSite(g_bombPosition), 0);
    DebugLog(commit ? "CT retake committed to the bomb." : "CT retake staging on distinct approaches.");
}

bool RetakeRelayEnabled()
{
    return g_cvRetakeRelay.BoolValue && g_cvRetakeRoles.BoolValue && g_mapProfile >= 0
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar");
}

bool RetakeHasHumanCT()
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT) return true;
    return false;
}

void ReviewDefuser()
{
    float now = GetGameTime();
    if (RetakeHasHumanCT())
    {
        g_defuserUserId = 0;
        return;
    }
    if (now < g_nextDefuserReviewAt) return;
    int bomb = EntRefToEntIndex(g_retakeBombRef);
    if (bomb == INVALID_ENT_REFERENCE) return;
    int candidate = GetClientOfUserId(g_defuserUserId);
    if (IsCTBot(candidate))
    {
        if (HasEntProp(bomb, Prop_Send, "m_hBombDefuser")
            && GetEntPropEnt(bomb, Prop_Send, "m_hBombDefuser") == candidate) return;
        if (now < g_defuserHandoffUntil && (!g_defuserUsingBomb
            || !HasEntProp(candidate, Prop_Send, "m_bIsDefusing")
            || GetEntProp(candidate, Prop_Send, "m_bIsDefusing"))) return;
    }
    int previous = g_defuserUserId;
    g_defuserUserId = 0;
    g_defuserUsingBomb = false;
    g_nextDefuserReviewAt = now + 1.5;
    g_defuserRetiredUserId = previous;
    SelectDefuser();
    // A solo survivor still owns the chance to retry an interrupted defuse.
    if (!g_defuserUserId && IsCTBot(candidate))
    {
        g_defuserRetiredUserId = 0;
        SelectDefuser();
    }
    if (g_defuserUserId == 0) return;
    candidate = GetClientOfUserId(g_defuserUserId);
    if (!g_retakeUnopposed && g_hasOrder[candidate] && !g_combatReleased[candidate])
    {
        CopyVector(g_bombPosition, g_orderGoal[candidate]);
        g_hasLook[candidate] = false;
        g_orderRoute[candidate] = view_as<int>(Route_Fastest);
        StartOrderProgress(candidate);
    }
    if (previous != 0 && previous != g_defuserUserId)
    {
        ExperienceSignal("defuser_handoff", "candidate_unavailable", RetakeSite(), candidate);
        DebugLog("CT retake relay: %d -> %N.", previous, candidate);
    }
}

bool RetakeRolesEnabled()
{
    // Inferno, Mirage and Nuke in the shared profile order.
    return g_cvRetakeRoles.BoolValue && (g_mapProfile == 0 || g_mapProfile == 2 || g_mapProfile == 3 || OverpassTeamworkEnabled())
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar")
        && NativeAvailable("NavMeshArea_GetPlaceCanonical");
}

bool ProfiledRetakeEnabled()
{
    return g_mapProfile >= 0 && g_cvRetakeRoles.BoolValue && g_cvProfiledRetake.BoolValue
        && (g_mapProfile != 5 || OverpassTeamworkEnabled())
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar")
        && NativeAvailable("NavMeshArea_GetPlaceCanonical");
}

bool OverpassTeamworkEnabled()
{
    return g_mapProfile == 5 && g_cvOverpassTeamwork.BoolValue
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar");
}

float FloatMin(float a, float b)
{
    return a < b ? a : b;
}

int CTPathLength(int start, int goal, const float point[3], int maximum)
{
    int closest;
    if (start < 0 || goal < 0 || !NavMesh_BuildPath(start, goal, point, RetakeTravelCost, maximum, closest, 0.0, 0.0)) return -1;
    return start == goal ? 0 : NavMeshArea_GetCostSoFar(goal);
}

bool MirageCrossfireEnabled()
{
    return g_mapProfile == 2 && g_cvMirageCrossfire.BoolValue && g_cvEntranceWatch.BoolValue
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar");
}

void MirageBuildCrossfire()
{
    for (int site = 0; site < 2; site++)
    {
        float center[3], other[3];
        TacticalMap_PlantGround(2, site, center);
        TacticalMap_PlantGround(2, 1 - site, other);
        int primary, support;
        float nearest = 760.0;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!g_hasOrder[client] || !g_innerOrder[client] || !g_hasLook[client]) continue;
            float distance = GetVectorDistance(center, g_orderGoal[client]);
            if (distance < nearest && distance < GetVectorDistance(other, g_orderGoal[client]))
            { primary = client; nearest = distance; }
        }
        if (!primary) continue;
        nearest = 800.0;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!g_hasOrder[client] || !g_hasLook[client] || g_innerOrder[client] || g_miragePartner[client]) continue;
            float distance = GetVectorDistance(center, g_orderGoal[client]);
            if (distance < nearest && distance < GetVectorDistance(other, g_orderGoal[client]))
            { support = client; nearest = distance; }
        }
        if (!support) continue;
        ArrayList lanePoints = ObjectiveWatch_Collect(2, site, false, center);
        float lanes[3][3], primaryLanes[3][3];
        int anchorMask = ObjectiveWatch_Score(lanePoints, g_orderGoal[primary], primaryLanes);
        int initial = ObjectiveWatch_Score(lanePoints, g_orderGoal[support], lanes);
        int ownLane = ObjectiveCover_AimLane(2, site, false, g_orderLook[support]);
        float eye[3];
        CopyVector(g_orderGoal[primary], eye);
        eye[2] += 64.0;
        float tradeLook[3];
        bool valid = MirageTradePosition(g_orderGoal[support], eye)
            && ((initial & anchorMask) != 0 || MirageSharedShot(g_orderGoal[support], eye, center, tradeLook));
        if (!valid)
        {
            int area = NavMesh_GetNearestArea(g_orderGoal[support], false, 110.0, false, true, TEAM_ANY);
            int anchorArea = NavMesh_GetNearestArea(g_orderGoal[primary], false, 110.0, false, true, TEAM_ANY);
            float origin[3];
            GetClientAbsOrigin(support, origin);
            int start = NavMesh_GetNearestArea(origin, false, 180.0, false, true, TEAM_ANY);
            ArrayStack nearby = new ArrayStack();
            if (area >= 0) NavMesh_CollectSurroundingAreas(nearby, area, 640.0, 24.0, 60.0);
            if (anchorArea >= 0) NavMesh_CollectSurroundingAreas(nearby, anchorArea, 650.0, 24.0, 60.0);
            StringMap visited = new StringMap();
            int originalExposure = ObjectiveCover_Exposure(lanePoints, g_orderGoal[support]);
            int originalPath = CTPathLength(start, area, g_orderGoal[support], 6500);
            int scanned, checked;
            float best = 999999.0, newGoal[3], newLook[3];
            while (!nearby.Empty && scanned++ < 210 && checked < 48)
            {
                int candidate = nearby.Pop();
                char key[16];
                IntToString(candidate, key, sizeof(key));
                if (!visited.SetValue(key, 1, false)) continue;
                float raw[3], foot[3];
                if (!NavMeshArea_GetCenter(candidate, raw) || GetVectorDistance(g_orderGoal[support], raw) > 475.0
                    || FloatAbs(raw[2] - g_orderGoal[support][2]) > 85.0 || !MirageTradePosition(raw, eye)
                    || GetVectorDistance(raw, center) > GetVectorDistance(raw, other)
                    || !ObjectiveCover_Floor(raw, foot) || ObjectiveCover_Support(support, foot) < 0) continue;
                checked++;
                int mask = ObjectiveWatch_Score(lanePoints, foot, lanes);
                if ((ownLane >= 0 && !(mask & (1 << ownLane)))
                    || (!(mask & anchorMask) && !MirageSharedShot(foot, eye, center, tradeLook))) continue;
                int exposure = ObjectiveCover_Exposure(lanePoints, foot);
                if (exposure > originalExposure || exposure > 1) continue;
                int travel = CTPathLength(start, candidate, foot, 6500);
                if (travel < 0 || (originalPath >= 0 && travel > originalPath + 380)) continue;
                int aim = ownLane;
                if (aim < 0)
                    for (int lane = 0; lane < 3; lane++)
                        if ((mask & anchorMask) & (1 << lane)) { aim = lane; break; }
                float rank = float(exposure) * 190.0 + GetVectorDistance(g_orderGoal[support], foot)
                    + FloatAbs(GetVectorDistance(foot, eye) - 285.0) * 0.65;
                if (rank >= best) continue;
                best = rank;
                CopyVector(foot, newGoal);
                if (aim >= 0) CopyVector(lanes[aim], newLook);
                else CopyVector(tradeLook, newLook);
            }
            delete nearby;
            delete visited;
            if (best < 999999.0)
            {
                CopyVector(newGoal, g_orderGoal[support]);
                CopyVector(newLook, g_orderLook[support]);
                StartOrderProgress(support);
                valid = true;
            }
        }
        delete lanePoints;
        if (!valid) continue;
        g_miragePartner[primary] = GetClientUserId(support);
        g_miragePartner[support] = GetClientUserId(primary);
        ExperienceSignal("opening_crossfire", "shared_fire_sector", site, support);
        DebugLog("Mirage crossfire site=%d anchor=%N support=%N", site, primary, support);
    }
}

bool MirageSharedShot(const float feet[3], const float anchorEye[3], const float center[3], float aim[3])
{
    float eye[3];
    CopyVector(feet, eye);
    eye[2] += 64.0;
    // Two complementary holds can trade as an attacker enters the site,
    // even if each only shows one independent deep entrance from cover.
    for (int sample = 0; sample < 5; sample++)
    {
        CopyVector(center, aim);
        if (sample == 1) aim[0] += 112.0;
        if (sample == 2) aim[0] -= 112.0;
        if (sample == 3) aim[1] += 112.0;
        if (sample == 4) aim[1] -= 112.0;
        float floor[3];
        if (!ObjectiveCover_Floor(aim, floor)) continue;
        CopyVector(floor, aim);
        aim[2] += 50.0;
        if (GetVectorDistance(eye, aim) >= 132.0 && GetVectorDistance(anchorEye, aim) >= 75.0
            && ObjectiveCover_Shot(eye, aim) && ObjectiveCover_Shot(anchorEye, aim)) return true;
    }
    return false;
}

bool MirageTradePosition(const float foot[3], const float anchorEye[3])
{
    float eye[3];
    CopyVector(foot, eye);
    eye[2] += 64.0;
    float distance = GetVectorDistance(eye, anchorEye);
    // Two partners may be on opposite sides of a crate. A common enemy
    // lane is required, not the ability to shoot the teammate's own model.
    return distance >= 145.0 && distance <= 570.0 && FloatAbs(eye[2] - anchorEye[2]) <= 80.0;
}

bool MirageSupportContact(int spotter, const float enemy[3], float now)
{
    int partner = GetClientOfUserId(g_miragePartner[spotter]);
    if (!IsCTBot(partner) || !g_hasOrder[partner] || g_combatReleased[partner] || g_blindUntil[partner] > now
        || g_orderExpires[partner] > now || g_mirageTradeUntil[partner] > now || now - g_lastCombatAt[partner] < 2.5) return false;
    float eye[3], from[3], aim[3];
    GetClientEyePosition(partner, eye);
    GetClientAbsOrigin(spotter, from);
    CopyVector(enemy, aim);
    aim[2] += 54.0;
    if (!MirageTradePosition(from, eye) || GetVectorDistance(eye, aim) > 1150.0 || !ObjectiveCover_Shot(eye, aim)) return false;
    g_mirageTradeUntil[partner] = now + 2.0;
    CopyVector(aim, g_mirageTradeAim[partner]);
    ExperienceSignal("opening_trade", "partner_contact", NearestSite(from), partner);
    return true;
}

bool NukeRouteCoverEnabled()
{
    return g_nukeMap && g_cvNukeRoutes.BoolValue && NativeAvailable("NavMesh_BuildPath")
        && NativeAvailable("NavMeshArea_GetCostSoFar");
}

int NukePreferLowerOwner(int owner, int goalArea, const float goal[3], const float upper[3])
{
    float pos[3];
    GetClientAbsOrigin(owner, pos);
    int best = CTPathLength(NavMesh_GetNearestArea(pos, false, 175.0, false, true, TEAM_ANY), goalArea, goal, 7500);
    int chosen = owner;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client == owner || !g_hasOrder[client] || g_innerOrder[client]
            || GetVectorDistance(g_orderGoal[client], goal) >= GetVectorDistance(g_orderGoal[client], upper)) continue;
        GetClientAbsOrigin(client, pos);
        int cost = CTPathLength(NavMesh_GetNearestArea(pos, false, 175.0, false, true, TEAM_ANY), goalArea, goal, 7500);
        if (cost >= 0 && (best < 0 || cost + 140 < best)) { best = cost; chosen = client; }
    }
    return chosen;
}

bool NukeTryDetour(int client, const float from[3])
{
    if (g_nukeDetourUsed[client] || g_combatReleased[client] || g_blindUntil[client] > GetGameTime()
        || (NativeAvailable("BotStuff_HasVisibleEnemy") && BotStuff_HasVisibleEnemy(client))) return false;
    int start = NavMesh_GetNearestArea(from, false, 145.0, false, true, TEAM_ANY);
    int home = NavMesh_GetNearestArea(g_orderGoal[client], false, 135.0, false, true, TEAM_ANY);
    if (start < 0 || home < 0) return false;
    ArrayStack areas = new ArrayStack();
    NavMesh_CollectSurroundingAreas(areas, start, 545.0, 23.0, 35.0);
    float best = 999999.0, chosen[3];
    int scanned, checked;
    while (!areas.Empty && scanned++ < 115 && checked < 20)
    {
        int area = areas.Pop();
        float raw[3], foot[3];
        if (area == start || area == home || !NavMeshArea_GetCenter(area, raw)
            || GetVectorDistance(raw, from) < 145.0 || GetVectorDistance(raw, from) > 470.0
            || FloatAbs(raw[2] - from[2]) > 42.0 || !ObjectiveCover_Floor(raw, foot)) continue;
        checked++;
        int local = CTPathLength(start, area, foot, 680);
        int onward = CTPathLength(area, home, g_orderGoal[client], 6600);
        if (local < 0 || onward < 0) continue;
        float rank = float(local) * 1.6 + float(onward) * 0.20;
        if (rank >= best) continue;
        best = rank;
        CopyVector(foot, chosen);
    }
    delete areas;
    if (best >= 999999.0) return false;
    g_nukeDetourUsed[client] = g_nukeDetouring[client] = true;
    CopyVector(chosen, g_nukeAlternate[client]);
    g_orderLastProgressAt[client] = GetGameTime();
    ExperienceSignal("route_retry", "nuke_local_waypoint", NearestSite(g_orderGoal[client]), client);
    DebugLog("Nuke local detour bot=%N waypoint=%.0f %.0f %.0f", client, chosen[0], chosen[1], chosen[2]);
    return true;
}

bool NukeBackfillLower(int casualty)
{
    // This hook only handles the designated inner lower defender. A victim
    // in the same XY column on the upper floor is not a B casualty.
    float upper[3], lower[3];
    TacticalMap_PlantGround(3, 0, upper);
    TacticalMap_PlantGround(3, 1, lower);
    if (!g_innerOrder[casualty] || GetVectorDistance(g_orderGoal[casualty], lower) >= GetVectorDistance(g_orderGoal[casualty], upper)) return false;
    if (g_nukeBackfillUsed) return true;
    float home[3];
    CopyVector(g_orderGoal[casualty], home);
    int goal = NavMesh_GetNearestArea(home, false, 110.0, false, true, TEAM_ANY);
    if (goal < 0) return true;
    int chosen, best = 999999;
    float now = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client == casualty || !IsCTBot(client) || g_combatReleased[client] || g_innerOrder[client]
            || !g_hasOrder[client] || now - g_lastCombatAt[client] < 2.5 || g_blindUntil[client] > now
            || (NativeAvailable("BotStuff_HasVisibleEnemy") && BotStuff_HasVisibleEnemy(client))) continue;
        float from[3];
        GetClientAbsOrigin(client, from);
        bool lowerSupport = GetVectorDistance(g_orderGoal[client], lower) < GetVectorDistance(g_orderGoal[client], upper);
        // Move the lower support/nearby rotator first; don't pull a distant
        // A player through the vent simply because the sites overlap on XY.
        if (!lowerSupport && (from[2] > upper[2] - 80.0 || GetVectorDistance(from, lower) > 950.0)) continue;
        int cost = CTPathLength(NavMesh_GetNearestArea(from, false, 160.0, false, true, TEAM_ANY), goal, home, 3200);
        if (cost < 0 || cost >= best) continue;
        best = cost;
        chosen = client;
    }
    if (!chosen) return true;
    g_nukeBackfillUsed = true;
    CopyVector(home, g_orderGoal[chosen]);
    CopyVector(g_orderLook[casualty], g_orderLook[chosen]);
    g_hasLook[chosen] = g_hasLook[casualty];
    g_orderRoute[chosen] = view_as<int>(Route_Fastest);
    g_orderExpires[chosen] = 0.0;
    StartOrderProgress(chosen);
    g_innerOrder[chosen] = true;
    ExperienceSignal("reinforce", "nuke_lower_anchor", 1, chosen);
    DebugLog("Nuke lower backfill bot=%N", chosen);
    return true;
}

int RetakeSite()
{
    return GetVectorDistance(g_bombPosition, g_siteA) <= GetVectorDistance(g_bombPosition, g_siteB) ? 0 : 1;
}

void AppendRetakeEntrances(int count, const int bots[MAXPLAYERS + 1])
{
    int site = RetakeSite();
    int bombArea = NavMesh_GetNearestArea(g_bombPosition, false, 180.0, false, true, TEAM_ANY);
    if (bombArea < 0) return;
    char lanes[3][32];
    bool bounded = OverpassTeamworkEnabled() || ProfiledRetakeEnabled();
    if (bounded)
    {
        if (g_mapProfile == 7)
        {
            // Cache's embedded NAV exposes closer CT-side entries than the
            // T post-plant watch list. Do not retune that independent list.
            strcopy(lanes[0], sizeof(lanes[]), site == 0 ? "Truck" : "Rafters");
            strcopy(lanes[1], sizeof(lanes[]), site == 0 ? "ARamp" : "Back");
            strcopy(lanes[2], sizeof(lanes[]), site == 0 ? "Catwalk" : "CTSpawn");
        }
        else for (int lane = 0; lane < 3; lane++) TacticalMap_GetWatchPlace(g_mapProfile, site, lane, true, lanes[lane], sizeof(lanes[]));
    }
    else if (g_mapProfile == 2)
    {
        strcopy(lanes[0], sizeof(lanes[]), site == 0 ? "TicketBooth" : "Shop");
        strcopy(lanes[1], sizeof(lanes[]), site == 0 ? "Jungle" : "Catwalk");
        strcopy(lanes[2], sizeof(lanes[]), site == 0 ? "Connector" : "Truck");
    }
    else if (g_mapProfile == 3)
    {
        strcopy(lanes[0], sizeof(lanes[]), site == 0 ? "Mini" : "Ramp");
        strcopy(lanes[1], sizeof(lanes[]), site == 0 ? "Heaven" : "Decon");
        strcopy(lanes[2], sizeof(lanes[]), site == 0 ? "Hut" : "Secret");
    }
    else
    {
        strcopy(lanes[0], sizeof(lanes[]), site == 0 ? "Library" : "Ruins");
        strcopy(lanes[1], sizeof(lanes[]), site == 0 ? "Arch" : "Banana");
        strcopy(lanes[2], sizeof(lanes[]), site == 0 ? "Pit" : "CTSpawn");
    }
    ArrayStack areas = new ArrayStack();
    if (NativeAvailable("NavMesh_WorldToGridX") && NativeAvailable("NavMesh_WorldToGridY") && NativeAvailable("NavMesh_GetAreasOnGrid"))
    {
        // Some ramps/vents are directed edges. Search the local grid, then
        // prove entrance -> site, rather than requiring site -> entrance.
        for (int x = NavMesh_WorldToGridX(g_bombPosition[0] - 1200.0); x <= NavMesh_WorldToGridX(g_bombPosition[0] + 1200.0); x++)
            for (int y = NavMesh_WorldToGridY(g_bombPosition[1] - 1200.0); y <= NavMesh_WorldToGridY(g_bombPosition[1] + 1200.0); y++)
                NavMesh_GetAreasOnGrid(areas, x, y);
    }
    else
        NavMesh_CollectSurroundingAreas(areas, bombArea, 1850.0, 22.0, 100.0);
    StringMap seen = new StringMap();
    float goals[3][3], scores[3] = {999999.0, 999999.0, 999999.0};
    int starts[MAXPLAYERS + 1], direct[MAXPLAYERS + 1];
    if (bounded)
        for (int b = 0; b < count; b++)
        {
            float from[3];
            GetClientAbsOrigin(bots[b], from);
            starts[b] = NavMesh_GetNearestArea(from, false, 200.0, false, true, TEAM_ANY);
            direct[b] = CTPathLength(starts[b], bombArea, g_bombPosition, 4300);
        }
    while (!areas.Empty)
    {
        int area = areas.Pop();
        char key[16];
        IntToString(area, key, sizeof(key));
        if (!seen.SetValue(key, 1, false)) continue;
        float point[3];
        if (!NavMeshArea_GetCenter(area, point)) continue;
        float distance = GetVectorDistance(point, g_bombPosition);
        if (distance < 190.0 || distance > 1200.0) continue;
        char place[32];
        NavMeshArea_GetPlaceCanonical(area, place, sizeof(place));
        for (int lane = 0; lane < 3; lane++)
        {
            float score = FloatAbs(distance - 510.0);
            if (score >= scores[lane] || !StrEqual(place, lanes[lane], false)) continue;
            int closest;
            if (!NavMesh_BuildPath(area, bombArea, g_bombPosition, RetakeTravelCost, 2200, closest, 0.0, 0.0)) continue;
            if (bounded)
            {
                float foot[3];
                if (!ObjectiveCover_Floor(point, foot)) continue;
                int finish = NavMeshArea_GetCostSoFar(bombArea), bestVia = 999999;
                for (int b = 0; b < count; b++)
                {
                    int approach = CTPathLength(starts[b], area, foot, 3400);
                    if (approach < 0 || direct[b] < 0 || approach + finish > direct[b] + 560) continue;
                    if (approach + finish < bestVia) bestVia = approach + finish;
                }
                if (bestVia == 999999) continue;
                score += float(bestVia) * 0.22;
                if (score >= scores[lane]) continue;
                CopyVector(foot, point);
            }
            scores[lane] = score;
            CopyVector(point, goals[lane]);
        }
    }
    delete areas;
    delete seen;
    for (int lane = 0; lane < 3 && g_targetCount < count; lane++)
        if (scores[lane] < 999999.0)
        {
            AppendTarget(goals[lane]);
            DebugLog("CT retake lane %s site=%d", lanes[lane], site);
        }
}

public int RetakeTravelCost(int area, int from, int ladder, any maxCost)
{
    if (from < 0) return 0;
    float a[3], b[3];
    if (!NavMeshArea_GetCenter(from, a) || !NavMeshArea_GetCenter(area, b)) return -1;
    int cost = NavMeshArea_GetCostSoFar(from) + RoundToCeil(GetVectorDistance(a, b));
    return cost <= maxCost ? cost : -1;
}

void SelectDefuser()
{
    // Leave native arbitration untouched if a human CT is present.
    if (RetakeHasHumanCT()) return;
    int bomb = EntRefToEntIndex(g_retakeBombRef);
    int goal = NavMesh_GetNearestArea(g_bombPosition, false, 180.0, false, true, TEAM_ANY);
    if (bomb == INVALID_ENT_REFERENCE || goal < 0) return;
    float now = GetGameTime(), left = GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow") - now;
    float best = left;
    int chosen;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsCTBot(client) || (RetakeRelayEnabled() && GetClientUserId(client) == g_defuserRetiredUserId)
            || (RetakeRelayEnabled() && !g_retakeUnopposed
            && (!g_hasOrder[client] || g_combatReleased[client]))) continue;
        float position[3];
        GetClientAbsOrigin(client, position);
        int start = NavMesh_GetNearestArea(position, false, 160.0, false, true, TEAM_ANY);
        int closest;
        if (start < 0 || !NavMesh_BuildPath(start, goal, g_bombPosition, RetakeTravelCost, 6500, closest, 0.0, 0.0)) continue;
        float distance = start == goal ? GetVectorDistance(position, g_bombPosition) : float(NavMeshArea_GetCostSoFar(goal));
        float eta = distance / 200.0 + (GetEntProp(client, Prop_Send, "m_bHasDefuser") ? 5.0 : 10.0) + 1.5;
        if (eta < best) { best = eta; chosen = client; }
    }
    if (chosen == 0) return;
    g_defuserUserId = GetClientUserId(chosen);
    float travel = best - (GetEntProp(chosen, Prop_Send, "m_bHasDefuser") ? 5.0 : 10.0);
    g_defuserHandoffUntil = RetakeRelayEnabled() ? now + travel + 2.5 : now + (best + 2.0 < 8.0 ? best + 2.0 : 8.0);
    DebugLog("CT retake lead %N estimated finish %.1f s", chosen, best);
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

void AssignTargets(const int bots[MAXPLAYERS + 1], int botCount, RouteType route, int targetLimit = -1, bool siteLocalWatch = false, int namedRetake = 0)
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

    int retreatArea = namedRetake > 0 ? NavMesh_GetNearestArea(g_bombPosition, false, 180.0, false, true, TEAM_ANY) : -1;
    for (int target = 0; target < limit; target++)
    {
        int bestIndex = -1;
        float bestDistance = 99999999.0;
        int goalArea = target < namedRetake ? NavMesh_GetNearestArea(g_targets[target], false, 100.0, false, true, TEAM_ANY) : -1;
        int onward = target < namedRetake ? CTPathLength(goalArea, retreatArea, g_bombPosition, 2200) : -1;
        for (int index = 0; index < botCount; index++)
        {
            if (used[index] || g_combatReleased[bots[index]] || !IsCTBot(bots[index]))
                continue;

            float position[3];
            GetClientAbsOrigin(bots[index], position);
            float distance = GetVectorDistance(position, g_targets[target]);
            if (target < namedRetake)
            {
                int start = NavMesh_GetNearestArea(position, false, 200.0, false, true, TEAM_ANY);
                int path = CTPathLength(start, goalArea, g_targets[target], 3400);
                int directPath = CTPathLength(start, retreatArea, g_bombPosition, 4300);
                if (path < 0 || onward < 0 || directPath < 0 || path + onward > directPath + 560) continue;
                distance = float(path) + distance * 0.08;
            }
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
                bool namedWatch = g_cvEntranceWatch.BoolValue && g_mapProfile >= 0 && (!g_infernoMap || InfernoWatchEnabled());
                if (siteLocalWatch && g_plan == Plan_Standard && g_cvEntranceWatch.BoolValue && namedWatch)
                {
                    char entrance[32];
                    float look[3];
                    bool selected;
                    if (g_infernoMap)
                        selected = CTEntrance_SelectLook(client, g_mapProfile, g_orderGoal[client], site, usedEntrances[site], look, entrance, sizeof(entrance));
                    else
                        selected = CTEntrance_ResolveWatch(client, g_mapProfile, g_orderGoal[client], site, usedEntrances[site],
                            look, entrance, sizeof(entrance), g_targets, g_targetCount, target);
                    if (selected)
                    {
                        if (!g_infernoMap) CopyVector(g_orderGoal[client], g_targets[target]);
                        CopyVector(look, g_orderLook[client]);
                        DebugLog("Watch %N: site=%s entrance=%s", client, site == 0 ? "A" : "B", entrance);
                    }
                }
                if (siteLocalWatch && InfernoWatchEnabled())
                {
                    float eye[3];
                    CopyVector(g_orderGoal[client], eye);
                    eye[2] += 64.0;
                    // Keep navigation, but never publish an occluded fixed
                    // direction for an Inferno opening fallback/pressure order.
                    g_hasLook[client] = CTInferno_ClearSight(eye, g_orderLook[client]);
                }
                else if (siteLocalWatch && g_plan == Plan_Standard && g_cvClearOpeningWatch.BoolValue)
                    g_hasLook[client] = TacticalAngles_RequireClearWatch(g_orderGoal[client], g_orderLook[client]);
            }
            g_orderRoute[client] = view_as<int>(route);
            g_orderExpires[client] = 0.0;
            StartOrderProgress(client);
            if (target < namedRetake)
            {
                char lane[32];
                NavMeshArea_GetPlaceCanonical(goalArea, lane, sizeof(lane));
                DebugLog("CT profiled retake assigned site=%d lane=%s bot=%N", RetakeSite(), lane, client);
                ExperienceSignal("retake_lane_assigned", lane, RetakeSite(), client);
            }
            DebugLog("Assigned %N to %.0f %.0f %.0f", client, g_orderGoal[client][0], g_orderGoal[client][1], g_orderGoal[client][2]);
        }
    }
    // A prior lane may have used the only BOT able to reach this lane.
    // Give remaining CTs the native retake instead of issuing an invalid order.
    if (siteLocalWatch && g_plan == Plan_Standard && g_cvCoverSpacing.BoolValue && (g_mapProfile == 2 || g_mapProfile == 3))
        SeparateOpeningCoverage();
}

void SeparateOpeningCoverage()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_hasOrder[client] || !g_hasLook[client] || !IsCTBot(client)) continue;
        int neighbor, duplicate;
        int site = NearestSite(g_orderGoal[client]);
        for (int peer = 1; peer < client; peer++)
        {
            if (!g_hasOrder[peer] || !IsCTBot(peer)) continue;
            if (GetVectorDistance(g_orderGoal[client], g_orderGoal[peer]) < 105.0) neighbor = peer;
            if (g_hasLook[peer] && NearestSite(g_orderGoal[peer]) == site
                && GetVectorDistance(g_orderLook[client], g_orderLook[peer]) < 250.0) duplicate = peer;
        }
        if (duplicate && g_mapProfile >= 0 && g_cvEntranceWatch.BoolValue)
        {
            for (int sector = 1; sector < 3; sector++)
            {
                int used = 0x7 & ~(1 << sector);
                char entrance[32];
                float look[3];
                if (!CTEntrance_SelectLook(client, g_mapProfile, g_orderGoal[client], site, used, look, entrance, sizeof(entrance))
                    || !TacticalAngles_RequireClearWatch(g_orderGoal[client], look)
                    || GetVectorDistance(look, g_orderLook[duplicate]) < 250.0) continue;
                CopyVector(look, g_orderLook[client]);
                DebugLog("CT alternate opening angle for %N: %s", client, entrance);
                break;
            }
        }
        if (!neighbor) continue;
        int start = NavMesh_GetNearestArea(g_orderGoal[client], false, 110.0, false, true, TEAM_ANY);
        if (start < 0) continue;
        ArrayStack list = new ArrayStack();
        NavMesh_CollectSurroundingAreas(list, start, 210.0, 18.0, 32.0);
        float best = 999999.0, chosen[3], chosenLook[3];
        while (!list.Empty)
        {
            float candidate[3], look[3];
            if (!NavMeshArea_GetCenter(list.Pop(), candidate) || NearestSite(candidate) != NearestSite(g_orderGoal[client])) continue;
            float move = GetVectorDistance(candidate, g_orderGoal[client]);
            if (move < 48.0 || move > 185.0 || move >= best || FloatAbs(candidate[2] - g_orderGoal[client][2]) > 26.0) continue;
            bool spaced = true;
            for (int peer = 1; peer <= MaxClients; peer++)
                if (peer != client && g_hasOrder[peer] && GetVectorDistance(candidate, g_orderGoal[peer]) < 105.0)
                { spaced = false; break; }
            if (!spaced) continue;
            CopyVector(g_orderLook[client], look);
            if (!TacticalAngles_RequireClearWatch(candidate, look)) continue;
            float foot[3], mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0};
            CopyVector(candidate, foot);
            foot[2] += 3.0;
            Handle hull = TR_TraceHullFilterEx(foot, foot, mins, maxs, MASK_PLAYERSOLID, TacticalAngles_TraceFilter, client);
            bool clear = !TR_DidHit(hull) && !TR_StartSolid(hull);
            delete hull;
            if (!clear) continue;
            best = move;
            CopyVector(candidate, chosen);
            CopyVector(look, chosenLook);
        }
        delete list;
        if (best >= 999999.0) continue;
        CopyVector(chosen, g_orderGoal[client]);
        CopyVector(chosenLook, g_orderLook[client]);
        StartOrderProgress(client);
        DebugLog("CT overlapping coverage separated for %N", client);
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

bool ProfiledReliefEnabled()
{
    return g_mapProfile >= 0 && g_plan == Plan_Standard && g_cvProfiledRelief.BoolValue
        && (g_mapProfile != 5 || OverpassTeamworkEnabled())
        && NativeAvailable("NavMesh_BuildPath") && NativeAvailable("NavMeshArea_GetCostSoFar")
        && NativeAvailable("NavMeshArea_GetPlaceCanonical");
}

int ProfiledReliefSite(const float position[3])
{
    float a[3], b[3];
    TacticalMap_PlantGround(g_mapProfile, 0, a);
    TacticalMap_PlantGround(g_mapProfile, 1, b);
    return GetVectorDistance(position, a) <= GetVectorDistance(position, b) ? 0 : 1;
}

bool ProfiledReliefCredible(const float position[3], int site)
{
    float anchor[3], other[3];
    TacticalMap_PlantGround(g_mapProfile, site, anchor);
    TacticalMap_PlantGround(g_mapProfile, 1 - site, other);
    float near = GetVectorDistance(position, anchor);
    return near <= 940.0 && FloatAbs(position[2] - anchor[2]) < 230.0
        && GetVectorDistance(position, other) >= near + 220.0;
}

bool ProfiledContactHasCover(int spotter, int enemy, const float enemyPosition[3])
{
    if (!NativeAvailable("BotStuff_HasVisibleEnemy")) return false;
    float from[3], shot[3];
    GetClientAbsOrigin(spotter, from);
    CopyVector(enemyPosition, shot);
    shot[2] += 54.0;
    float now = GetGameTime();
    int reportedEnemy = GetClientUserId(enemy);
    for (int client = 1; client <= MaxClients; client++)
    {
        // Seeing some enemy is not enough to withhold support. The nearby
        // teammate must also have independently reported this same player.
        if (client == spotter || g_contactEnemy[client] != reportedEnemy || now - g_contactSeenAt[client] > 1.5
            || !IsCTBot(client) || g_blindUntil[client] > now || !BotStuff_HasVisibleEnemy(client)) continue;
        float eye[3], foot[3];
        GetClientAbsOrigin(client, foot);
        if (GetVectorDistance(from, foot) > 480.0 || FloatAbs(foot[2] - from[2]) > 110.0) continue;
        GetClientEyePosition(client, eye);
        if (GetVectorDistance(eye, shot) <= 1150.0 && ObjectiveCover_Shot(eye, shot)) return true;
    }
    return false;
}

int ProfiledReinforce(const float contact[3], int site, int excluded, const char[] reason,
    int additionalExcluded, bool allowEmptyOther, bool onlyOther)
{
    float anchor[3], weak[3], shot[3];
    TacticalMap_PlantGround(g_mapProfile, site, anchor);
    TacticalMap_PlantGround(g_mapProfile, 1 - site, weak);
    CopyVector(contact, shot);
    shot[2] += 50.0;
    int base = NavMesh_GetNearestArea(anchor, false, 150.0, false, true, TEAM_ANY);
    if (base < 0) return 0;
    int donors[MAXPLAYERS + 1], starts[MAXPLAYERS + 1], donorCount, weakCount;
    bool weakSide[MAXPLAYERS + 1];
    float origins[MAXPLAYERS + 1][3], now = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client == excluded || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_CT) continue;
        GetClientAbsOrigin(client, origins[client]);
        float assignment[3];
        CopyVector(g_hasOrder[client] ? g_orderGoal[client] : origins[client], assignment);
        weakSide[client] = GetVectorDistance(assignment, weak) < GetVectorDistance(assignment, anchor)
            && GetVectorDistance(assignment, weak) < 860.0;
        if (weakSide[client]) weakCount++;
        if (!IsFakeClient(client) || client == additionalExcluded || g_combatReleased[client] || g_orderExpires[client] > now
            || now - g_lastCombatAt[client] < 2.5 || g_blindUntil[client] > now || (onlyOther && !weakSide[client])
            || (g_innerOrder[client] && (!allowEmptyOther || !weakSide[client]))
            || (NativeAvailable("BotStuff_HasVisibleEnemy") && BotStuff_HasVisibleEnemy(client))) continue;
        int start = NavMesh_GetNearestArea(origins[client], false, 165.0, false, true, TEAM_ANY);
        if (start < 0) continue;
        starts[client] = start;
        donors[donorCount++] = client;
    }
    if (!donorCount) return 0;

    ArrayList lanes = ObjectiveWatch_Collect(g_mapProfile, site, false, anchor);
    ArrayStack areas = new ArrayStack();
    NavMesh_CollectSurroundingAreas(areas, base, 720.0, 24.0, 48.0);
    int selected, visited, tested;
    float best = 999999.0, bestGoal[3], bestLook[3];
    while (!areas.Empty && visited++ < 180 && tested < 32)
    {
        int area = areas.Pop();
        float raw[3], foot[3], eye[3], look[3];
        if (!NavMeshArea_GetCenter(area, raw) || FloatAbs(raw[2] - anchor[2]) > 95.0
            || GetVectorDistance(raw, anchor) > 570.0 || GetVectorDistance(raw, weak) < GetVectorDistance(raw, anchor)
            || GetVectorDistance(raw, contact) < 255.0 || !ObjectiveCover_Floor(raw, foot)) continue;
        CopyVector(foot, eye);
        eye[2] += 64.0;
        int used;
        bool actual = GetVectorDistance(eye, shot) > 140.0 && ObjectiveCover_Shot(eye, shot);
        if (actual) CopyVector(shot, look);
        else if (!ObjectiveWatch_Select(lanes, foot, used, look)) continue;
        int exposure = ObjectiveCover_Exposure(lanes, foot);
        if (exposure > 1) continue;
        tested++;
        for (int b = 0; b < donorCount; b++)
        {
            int client = donors[b];
            if (weakSide[client] && weakCount <= 1 && !allowEmptyOther) continue;
            int support = ObjectiveCover_Support(client, foot, true);
            if (support < 0 || GetVectorDistance(foot, origins[client]) < 135.0) continue;
            float rank = (actual ? 0.0 : 215.0) + float(exposure) * 125.0 - float(support) * 105.0
                + (weakSide[client] ? 150.0 : 0.0) + GetVectorDistance(foot, anchor) * 0.20;
            int travel = CTPathLength(starts[client], area, foot, 2500);
            if (travel < 0 || rank + float(travel) >= best) continue;
            best = rank + float(travel);
            selected = client;
            CopyVector(foot, bestGoal);
            CopyVector(look, bestLook);
        }
    }
    delete areas;
    delete lanes;
    if (!selected) return 0;
    CopyVector(bestGoal, g_orderGoal[selected]);
    CopyVector(bestLook, g_orderLook[selected]);
    g_hasOrder[selected] = g_hasLook[selected] = true;
    g_orderRoute[selected] = view_as<int>(Route_Fastest);
    g_orderExpires[selected] = now + g_cvReinforceHold.FloatValue;
    g_lastReinforcement[site] = selected;
    StartOrderProgress(selected);
    ExperienceSignal("reinforce", reason, site, selected);
    DebugLog("CT profiled relief site=%d bot=%N goal=%.0f %.0f %.0f", site, selected, bestGoal[0], bestGoal[1], bestGoal[2]);
    return selected;
}

int RequestReinforcement(const float contactPosition[3], int site, int excludedClient, const char[] reason,
    int additionalExcluded = 0, bool allowEmptyOtherSite = false, bool onlyOtherSite = false)
{
    // Once loose C4 is confirmed, site reports/casualties must not overwrite
    // its cached guard goals. Individual combat still releases immediately.
    if (g_phase == Phase_GuardLooseBomb) return 0;
    if ((OverpassTeamworkEnabled() || ProfiledReliefEnabled()) && g_phase == Phase_Initial)
        return ProfiledReinforce(contactPosition, site, excludedClient, reason, additionalExcluded, allowEmptyOtherSite, onlyOtherSite);
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
        g_infernoPreciseOrder[client] = false;
        g_innerOrder[client] = false;
        g_overpassOpeningOrder[client] = false;
        g_anubisBreakableUntil[client] = 0.0;
        g_lastRouteFallAt[client] = 0.0;
        g_orderExpires[client] = 0.0;
        g_orderLastProgressDistance[client] = 0.0;
        g_orderLastProgressAt[client] = 0.0;
        g_orderArrived[client] = false;
        g_objectiveNamed[client] = false;
        g_recoveryTried[client] = false;
        g_recoveryDriveAt[client] = 0.0;
        g_miragePartner[client] = 0;
        g_mirageTradeUntil[client] = 0.0;
        g_nukeDetouring[client] = false;
        g_nukeDetourUsed[client] = false;
    }
    g_recoverySearchAt = 0.0;
}

void StartOrderProgress(int client)
{
    g_infernoPreciseOrder[client] = false;
    g_innerOrder[client] = false;
    g_overpassOpeningOrder[client] = false;
    g_anubisBreakableUntil[client] = 0.0;
    g_lastRouteFallAt[client] = 0.0;
    g_nukeDetouring[client] = false;
    g_mirageTradeUntil[client] = 0.0;
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
        if (NukeRouteCoverEnabled() && g_phase == Phase_Initial && g_nukeDetouring[client])
        {
            if (GetVectorDistance(position, g_nukeAlternate[client]) <= 105.0
                && FloatAbs(position[2] - g_nukeAlternate[client][2]) < 72.0)
            {
                bool inner = g_innerOrder[client];
                StartOrderProgress(client);
                g_innerOrder[client] = inner;
                DebugLog("Nuke detour reached: %N resumes original hold.", client);
            }
            else if (now - g_orderLastProgressAt[client] >= 6.0)
            {
                g_nukeDetouring[client] = false;
                ReleaseOrder(client, "navigation stalled");
            }
            continue;
        }
        float holdRadius = GetCTHoldRadius(client);
        bool precise = holdRadius < 128.0;
        float distance = (precise || g_cvRouteRecovery.BoolValue) ? GetVectorDistance(position, g_orderGoal[client]) : Distance2D(position, g_orderGoal[client]);
        float displacement = Distance2D(position, g_orderLastProgressPosition[client]);
        if (g_cvRouteRecovery.BoolValue && !TacticalRecovery_Driving(client, now))
        {
            g_orderLastProgressAt[client] = now;
            g_orderLastProgressDistance[client] = distance;
            CopyVector(position, g_orderLastProgressPosition[client]);
        }
        if (distance <= holdRadius)
        {
            if (!g_orderArrived[client])
                ExperienceSignal("order_arrived", holdRadius < 32.0 ? "within_24" : (precise ? "within_32" : "within_128"), g_geometryReady ? NearestSite(g_orderGoal[client]) : -1, client);
            g_orderArrived[client] = true;
            g_orderLastProgressDistance[client] = distance;
            g_orderLastProgressAt[client] = now;
            CopyVector(position, g_orderLastProgressPosition[client]);
            continue;
        }

        // Do not release a settled initial defender merely because the
        // engine's idle movement displaced it a few steps from its cover.
        if ((g_phase == Phase_Initial || g_phase == Phase_GuardLooseBomb) && g_orderArrived[client]
            && distance <= (holdRadius < 32.0 ? holdRadius : holdRadius * 2.0))
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
        float progressStep = precise && distance <= 128.0 ? 12.0 : 48.0;
        float displacementStep = precise ? 32.0 : 64.0;
        if (distance <= g_orderLastProgressDistance[client] - progressStep || displacement >= displacementStep)
        {
            g_orderLastProgressDistance[client] = distance;
            g_orderLastProgressAt[client] = now;
            CopyVector(position, g_orderLastProgressPosition[client]);
            continue;
        }

        // Inferno's A route can turn tightly around a doorway or queue briefly
        // behind another defender. Still relinquish genuinely stalled orders.
        float timeout = g_cvNavigationStallTimeout.FloatValue;
        if (precise && timeout < 5.0) timeout = 5.0;
        if (now - g_orderLastProgressAt[client] < timeout) continue;
        if (NukeRouteCoverEnabled() && g_phase == Phase_Initial && NukeTryDetour(client, position)) continue;
        if (g_cvRouteRecovery.BoolValue && !g_innerOrder[client] && !g_recoveryTried[client] && g_phase != Phase_RetakeCommit
            && !(NukeRouteCoverEnabled() && g_phase == Phase_Initial && g_nukeDetourUsed[client])
            && client != GetClientOfUserId(g_defuserUserId))
        {
            if (now < g_recoverySearchAt) continue;
            g_recoverySearchAt = now + 0.30;
            g_recoveryTried[client] = true;
            float alternate[3];
            if (TacticalRecovery_Find(client, position, alternate))
            {
                CopyVector(alternate, g_orderGoal[client]);
                g_orderLastProgressDistance[client] = GetVectorDistance(position, alternate);
                g_orderLastProgressAt[client] = now;
                CopyVector(position, g_orderLastProgressPosition[client]);
                ExperienceSignal("route_retry", "same_lane", NearestSite(alternate), client);
                DebugLog("CT route retry: bot=%N same lane", client);
                continue;
            }
        }
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
        bool retake = g_cvRetakeClockAware.BoolValue && (g_phase == Phase_RetakeStage || g_phase == Phase_RetakeCommit);
        float distance = retake ? GetVectorDistance(position, g_orderGoal[client]) : Distance2D(position, g_orderGoal[client]);
        if (distance <= distanceLimit && (!retake || FloatAbs(position[2] - g_orderGoal[client][2]) <= 96.0))
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
        g_contactEnemy[client] = 0;
        g_contactSeenAt[client] = 0.0;
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
    g_retakeUnopposed = false;
    g_retakeBombRef = INVALID_ENT_REFERENCE;
    g_defuserUserId = 0;
    g_defuserHandoffUntil = 0.0;
    g_nextDefuserReviewAt = 0.0;
    g_defuserUsingBomb = false;
    g_defuserRetiredUserId = 0;
    g_pressureReturnAt = 0.0;
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
