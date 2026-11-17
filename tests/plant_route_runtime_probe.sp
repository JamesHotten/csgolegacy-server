#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <commandline>

native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_ShouldHoldStage(int client);
native int BotTTactics_GetAttackSite();
native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native void BotCTTactics_ReportRouteDrive(int client, bool driving, bool defuseApproach = false);
native int BotTTactics_GetUtilityLane(int client);
#include "../mods/include/bot_tactical_map_profiles.inc"

public Plugin myinfo = {name = "Plant and retake route probe (isolated only)", version = "1.0"};
ConVar g_enabled, g_targetB, g_surveyOnly, g_surveyAll, g_split, g_routeSeries, g_kit, g_stageOnly;
ConVar g_clearDelay, g_alternateSites, g_stallProbe, g_utilityProbe, g_comboProbe, g_plantStallProbe;
ConVar g_liveAll, g_replaceDefuser, g_enableContact, g_endMap, g_firstSite;
char g_pressure[12];
bool g_pressureSingle, g_pressureConnector, g_pressureStuck;
int g_pressureStuckUser;
float g_pressureStuckStart, g_pressureStuckOrigin[3];
bool g_pressureWaypointSeen;
int g_pressureStarts, g_pressureStops, g_pressureFinalDefuser, g_pressureCT, g_pressureT;
int g_pressureCTKills, g_pressureTKills, g_pressureTAtFirstUse;
int g_pressureDefenders;
float g_pressureFirstLeft, g_pressureFinishLeft;
float g_pressureNearLeft, g_pressureEligibleLeft;
int g_liveSite;
float g_maxRetakeZ;
float g_retakeStartZ[MAXPLAYERS + 1];
bool g_advancePending;
bool g_interference, g_casualty;
int g_firstDefuser;
int g_armedCombatDeaths;
int g_stallSamples, g_nativeStallSamples, g_waitSamples;
float g_lastCarrierSample[3];
int g_guardReady, g_actualSite;
bool g_armed, g_live, g_planted, g_completed;
bool g_stageSeenLive, g_stageSummarized;
float g_stageLastSample;
int g_stageReady, g_stageOrdered;
bool g_carrierStageReady;
float g_stageLastPosition[MAXPLAYERS + 1][3], g_stageGoal[MAXPLAYERS + 1][3];
bool g_stageHasGoal[MAXPLAYERS + 1];
int g_carrier, g_ct;
float g_start, g_plantedAt;
float g_siteA[3], g_siteB[3];
int g_stageSeen, g_commitSeen;
int g_stallChanges, g_stallPeerChanges;
float g_stallStarted;
float g_stallOriginal[MAXPLAYERS + 1][3];

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_plant_route_probe", "0", "Explicit isolated-server test.");
    g_targetB = CreateConVar("sm_plant_route_probe_b", "1", "Prefer B for the test.");
    g_surveyOnly = CreateConVar("sm_plant_route_probe_survey", "0", "Inspect engine plant zone at issued goals.");
    g_surveyAll = CreateConVar("sm_plant_route_probe_survey_all", "0", "Survey A and B across the ten map profiles.");
    g_split = CreateConVar("sm_plant_route_probe_split", "1", "Exercise the split selector in live cases.");
    g_routeSeries = CreateConVar("sm_plant_route_probe_series", "0", "Run Inferno B, Mirage A and Nuke B, automatically.");
    g_kit = CreateConVar("sm_plant_route_probe_kit", "1", "Give test CTs a defuse kit.");
    g_stageOnly = CreateConVar("sm_plant_route_probe_stage_only", "0", "Measure staging only, before testing actual retakes.");
    g_clearDelay = CreateConVar("sm_plant_route_probe_clear_delay", "0.0", "Delay clearing test opponents after plant.", _, true, 0.0, true, 30.0);
    g_alternateSites = CreateConVar("sm_plant_route_probe_alternate_sites", "0", "Test Mirage B and Nuke A instead of Mirage A and Nuke B.");
    g_stallProbe = CreateConVar("sm_plant_route_probe_stall", "0", "Freeze the advancing carrier and check one local retry (test only).");
    g_utilityProbe = CreateConVar("sm_plant_route_probe_utility", "0", "Give the test bots smoke and flash for actual opening throws.");
    g_comboProbe = CreateConVar("sm_plant_route_probe_combos", "0", "Exercise optional CT/T opening variants on Mirage.");
    g_plantStallProbe = CreateConVar("sm_plant_route_probe_plant_stall", "0", "Freeze only the carrier immediately after attack commit and verify native handoff.");
    g_liveAll = CreateConVar("sm_plant_route_probe_live_all", "0", "Run real plant/retake cases on both sites of all ten maps.");
    g_replaceDefuser = CreateConVar("sm_plant_route_probe_replace_defuser", "0", "Remove the first BOT that actually starts defusing; isolated only.");
    g_enableContact = CreateConVar("sm_plant_route_probe_contact", "0", "Allow an armed retake after the plant; isolated only.");
    g_endMap = CreateConVar("sm_plant_route_probe_end_map", "de_anubis", "Last map in this shard of the live matrix.");
    g_firstSite = CreateConVar("sm_plant_route_probe_first_site", "0", "Start at B on the initial map of a diagnostic shard.", _, true, 0.0, true, 1.0);
    if (FindCommandLineParam("-ctrefinelive"))
    {
        char ip[32], last[32];
        GetCommandLineParam("-ip", ip, sizeof(ip));
        if (!StrEqual(ip, "127.0.0.1")) SetFailState("CT refinement fixture is loopback-only");
        GetCommandLineParam("-ctrefineend", last, sizeof(last), "de_anubis");
        g_enabled.BoolValue = g_liveAll.BoolValue = true;
        g_endMap.SetString(last);
        g_clearDelay.FloatValue = 7.0;
        g_utilityProbe.BoolValue = true;
        GetCommandLineParam("-ctretakepressure", g_pressure, sizeof(g_pressure));
        if (g_pressure[0] != '\0')
        {
            if (!StrEqual(g_pressure, "armed") && !StrEqual(g_pressure, "relay"))
                SetFailState("Unsupported retake pressure scenario");
            g_enableContact.BoolValue = true;
            g_replaceDefuser.BoolValue = StrEqual(g_pressure, "relay");
            g_pressureSingle = FindCommandLineParam("-pressureone");
            g_pressureConnector = FindCommandLineParam("-pressureconnector");
            g_pressureStuck = g_pressureConnector && FindCommandLineParam("-pressurestuck");
            g_firstSite.IntValue = FindCommandLineParam("-pressureb") ? 1 : 0;
            if (FindCommandLineParam("-pressurenokit")) g_kit.BoolValue = false;
            char defenders[4];
            GetCommandLineParam("-pressuredefenders", defenders, sizeof(defenders), "5");
            g_pressureDefenders = StringToInt(defenders);
            if (g_pressureDefenders < 2 || g_pressureDefenders > 5) SetFailState("Pressure needs between two and five living defenders");
        }
    }
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("bomb_beginplant", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_planted", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_begindefuse", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_abortdefuse", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_defused", ObjectiveEvent, EventHookMode_Post);
    HookEvent("round_end", RoundResult, EventHookMode_Post);
    HookEvent("smokegrenade_detonate", UtilityDetonated, EventHookMode_Post);
    HookEvent("flashbang_detonate", UtilityDetonated, EventHookMode_Post);
    HookEvent("player_death", LiveCaseDeath, EventHookMode_Post);
}

public void OnMapStart()
{
    g_carrier = g_ct = 0;
    g_live = g_planted = g_completed = false;
    g_armed = false;
    g_liveSite = 0;
    g_advancePending = false;
    if (g_surveyAll.BoolValue) g_targetB.BoolValue = false;
    if (g_routeSeries.BoolValue)
    {
        char map[64];
        GetCurrentMap(map, sizeof(map));
        g_targetB.BoolValue = !StrEqual(map, "de_mirage");
        if (g_alternateSites.BoolValue && (StrEqual(map, "de_mirage") || StrEqual(map, "de_nuke")))
            g_targetB.BoolValue = !g_targetB.BoolValue;
    }
    CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool Safe()
{
    if (!g_enabled.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    if (FindCommandLineParam("-ctrefinelive")) FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    if (g_liveAll.BoolValue && !g_live) g_liveSite = g_firstSite.IntValue;
    ServerCommand("sv_cheats 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 3; mp_roundtime_defuse 1.92; mp_ignore_round_win_conditions 1; mp_c4timer 40");
    ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    if (g_liveAll.BoolValue) CreateTimer(4.0, EnsureLiveRound, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action EnsureLiveRound(Handle timer)
{
    if (!Safe() || !g_armed) return Plugin_Stop;
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_armed || !Safe() || (g_liveAll.BoolValue && GameRules_GetProp("m_bWarmupPeriod"))) return;
    g_armed = false;
    RequestFrame(Begin);
}

public void Begin(any unused)
{
    if (!Safe()) return;
    if (g_liveAll.BoolValue)
    {
        // This matrix measures each designated site. Mid-round rotation is
        // a separate behavior and must not turn a valid B finish into A evidence.
        FindConVar("sm_bot_t_mid_rotate_enable").BoolValue = false;
        g_targetB.BoolValue = g_liveSite == 1;
        g_carrier = g_ct = 0;
        g_planted = g_completed = g_interference = g_casualty = false;
        g_advancePending = false;
        g_guardReady = 0;
        g_actualSite = -1;
        g_firstDefuser = 0;
        g_armedCombatDeaths = 0;
        g_pressureStarts = g_pressureStops = g_pressureFinalDefuser = g_pressureCT = g_pressureT = 0;
        g_pressureCTKills = g_pressureTKills = 0;
        g_pressureTAtFirstUse = -1;
        g_pressureStuckUser = 0;
        g_pressureFirstLeft = g_pressureFinishLeft = -1.0;
        g_pressureNearLeft = g_pressureEligibleLeft = -1.0;
        g_stallSamples = g_nativeStallSamples = g_waitSamples = 0;
        g_maxRetakeZ = 0.0;
        char map[64];
        GetCurrentMap(map, sizeof(map));
        PrintToServer("LIVE_CASE_BEGIN map=%s site=%s", map, g_liveSite == 0 ? "A" : "B");
    }
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", g_siteA);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", g_siteB);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        if (GetClientTeam(i) == CS_TEAM_T && GetPlayerWeaponSlot(i, CS_SLOT_C4) > MaxClients) g_carrier = i;
        if (GetClientTeam(i) == CS_TEAM_CT && g_ct == 0) g_ct = i;
        if (GetClientTeam(i) == CS_TEAM_CT && !g_comboProbe.BoolValue)
        {
            if (g_liveAll.BoolValue)
            {
                // On maps like Overpass the CT spawns are inside A. Park the
                // test team outside both sites so frozen bodies do not block
                // plant travel and CTs actually have a return route to run.
                char map[32];
                GetCurrentMap(map, sizeof(map));
                if (StrEqual(map, "de_overpass", false) && g_liveSite == 0) ParkOverpassCT(i);
            }
            SetEntityMoveType(i, MOVETYPE_NONE);
        }
        if (g_utilityProbe.BoolValue && GetClientTeam(i) == CS_TEAM_T)
        {
            GivePlayerItem(i, "weapon_smokegrenade");
            GivePlayerItem(i, "weapon_flashbang");
        }
    }
    if (g_carrier == 0 || g_ct == 0) SetFailState("Missing C4 carrier or CT");
    if (g_surveyOnly.BoolValue) FindConVar("sm_bot_t_tactics_sync_enable").BoolValue = false;
    else if (g_split.BoolValue)
    {
        ServerCommand("sm_bot_t_eco_rush_chance 0; sm_bot_t_force_rush_chance 0; sm_bot_t_full_rush_chance 0; sm_bot_t_eco_split_chance 100; sm_bot_t_force_split_chance 100; sm_bot_t_full_split_chance 100");
        ServerExecute();
    }
    FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    FindConVar("sm_bot_t_tactics_debug").BoolValue = true;
    if (g_comboProbe.BoolValue)
    {
        ServerCommand("sm_bot_t_eco_rush_chance 0; sm_bot_t_force_rush_chance 0; sm_bot_t_full_rush_chance 0; sm_bot_t_eco_split_chance 0; sm_bot_t_force_split_chance 0; sm_bot_t_full_split_chance 0");
        ServerCommand("sm_ct_tactics_replan");
        ServerExecute();
    }
    bool found;
    float goal[3];
    int route;
    for (int tries = 0; tries < 18; tries++)
    {
        ServerCommand("sm_t_tactics_replan");
        ServerExecute();
        if (!BotTTactics_GetOrder(g_carrier, goal, route)) continue;
        bool b = GetFeatureStatus(FeatureType_Native, "BotTTactics_GetAttackSite") == FeatureStatus_Available
            ? BotTTactics_GetAttackSite() == 1 : GetVectorDistance(goal, g_siteB) < GetVectorDistance(goal, g_siteA);
        if (b == g_targetB.BoolValue) { found = true; break; }
    }
    if (!found) SetFailState("Did not select requested test site");
    g_live = true;
    g_start = GetGameTime();
    g_stageSeen = g_commitSeen = 0;
    g_stageSeenLive = g_stageSummarized = g_carrierStageReady = false;
    g_stageLastSample = 0.0;
    g_stageReady = g_stageOrdered = 0;
    GetClientAbsOrigin(g_carrier, g_lastCarrierSample);
    for (int i = 1; i <= MaxClients; i++) g_stageHasGoal[i] = false;
    if (g_surveyOnly.BoolValue)
    {
        PrintToServer("PLANT_GOAL %.1f %.1f %.1f", goal[0], goal[1], goal[2]);
        goal[2] += 2.0;
        TeleportEntity(g_carrier, goal, NULL_VECTOR, NULL_VECTOR);
        SetEntityMoveType(g_carrier, MOVETYPE_NONE);
        CreateTimer(0.35, Survey, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        if (g_stallProbe.BoolValue)
        {
            CreateTimer(0.2, StartStallProbe, _, TIMER_FLAG_NO_MAPCHANGE);
            return;
        }
        if (g_utilityProbe.BoolValue && GetFeatureStatus(FeatureType_Native, "BotTTactics_GetUtilityLane") == FeatureStatus_Available)
        {
            char map[32];
            GetCurrentMap(map, sizeof(map));
            if (StrEqual(map, "de_mirage", false))
            {
                int routeCounts[4];
                for (int i = 1; i <= MaxClients; i++)
                {
                    int lane = BotTTactics_GetUtilityLane(i);
                    if (lane >= 0 && lane < sizeof(routeCounts)) routeCounts[lane]++;
                }
                PrintToServer("MIRAGE_UTILITY_ROUTES site=%s carrier=%d a=%d b=%d mid=%d",
                    g_targetB.BoolValue ? "B" : "A", BotTTactics_GetUtilityLane(g_carrier), routeCounts[1], routeCounts[2], routeCounts[3]);
            }
        }
        CreateTimer(0.2, ObserveStage, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        if (!g_stageOnly.BoolValue) CreateTimer(2.0, Observe, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

void ParkOverpassCT(int client)
{
    // Lower level, out of sight of the A approach; CT must route back up.
    float pos[3] = {-1100.0, 50.0, 98.0};
    pos[1] += float(client % 5) * 40.0;
    float end[3];
    end = pos;
    pos[2] += 90.0;
    end[2] -= 100.0;
    Handle trace = TR_TraceRayFilterEx(pos, end, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, LiveWorldTrace);
    if (TR_DidHit(trace) && !TR_StartSolid(trace))
    {
        TR_GetEndPosition(pos, trace);
        pos[2] += 2.0;
        TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
    }
    delete trace;
}

public bool LiveWorldTrace(int entity, int mask, any data) { return entity > MaxClients; }

public void UtilityDetonated(Event event, const char[] name, bool dontBroadcast)
{
    if (Safe() && g_live && g_liveAll.BoolValue) g_interference = true;
    if (Safe() && g_live && g_utilityProbe.BoolValue)
        PrintToServer("MIRAGE_UTILITY actual=%s bot=%d xyz=%.0f %.0f %.0f", name, GetClientOfUserId(event.GetInt("userid")),
            event.GetFloat("x"), event.GetFloat("y"), event.GetFloat("z"));
}

public Action StartStallProbe(Handle timer)
{
    if (!Safe() || !g_live) return Plugin_Stop;
    g_stallStarted = GetGameTime();
    g_stallChanges = g_stallPeerChanges = 0;
    int route;
    for (int i = 1; i <= MaxClients; i++)
        if (BotTTactics_ShouldHoldStage(i)) BotTTactics_GetOrder(i, g_stallOriginal[i], route);
    SetEntityMoveType(g_carrier, MOVETYPE_NONE);
    CreateTimer(0.2, PollStallProbe, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action PollStallProbe(Handle timer)
{
    if (!Safe() || !g_live) return Plugin_Stop;
    for (int i = 1; i <= MaxClients; i++)
    {
        float goal[3];
        int route;
        if (!BotTTactics_ShouldHoldStage(i) || !BotTTactics_GetOrder(i, goal, route)) continue;
        if (GetVectorDistance(g_stallOriginal[i], goal) < 55.0) continue;
        g_stallOriginal[i] = goal;
        if (i == g_carrier) g_stallChanges++;
        else g_stallPeerChanges++;
    }
    if (GetGameTime() - g_stallStarted < 8.5) return Plugin_Continue;
    SetEntityMoveType(g_carrier, MOVETYPE_WALK);
    char map[64];
    GetCurrentMap(map, sizeof(map));
    PrintToServer("ROUTE_STALL_%s map=%s retries=%d peer_changes=%d", g_stallChanges == 1 && g_stallPeerChanges == 0 ? "PASS" : "FAIL",
        map, g_stallChanges, g_stallPeerChanges);
    NextRouteCase();
    return Plugin_Stop;
}

public Action ObserveStage(Handle timer)
{
    if (!Safe() || !g_live || g_completed || g_planted) return Plugin_Stop;
    bool stage;
    int ready, ordered;
    bool carrierReady;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!BotTTactics_ShouldHoldStage(i)) continue;
        stage = true;
        float pos[3], goal[3];
        int route;
        if (!BotTTactics_GetOrder(i, goal, route)) continue;
        ordered++;
        GetClientAbsOrigin(i, pos);
        g_stageLastPosition[i] = pos;
        g_stageGoal[i] = goal;
        g_stageHasGoal[i] = true;
        if (GetVectorDistance(pos, goal) <= 180.0)
        {
            ready++;
            if (i == g_carrier) carrierReady = true;
        }
        if (!g_stageSeenLive)
            PrintToServer("STAGE_GOAL bot=%d carrier=%d xyz=%.0f %.0f %.0f", i, i == g_carrier, goal[0], goal[1], goal[2]);
    }
    float elapsed = GetGameTime() - g_start;
    if (stage)
    {
        g_stageSeenLive = true;
        g_stageLastSample = elapsed;
        g_stageReady = ready;
        g_stageOrdered = ordered;
        g_carrierStageReady = carrierReady;
        return Plugin_Continue;
    }
    if (!g_stageSeenLive && elapsed < 2.0) return Plugin_Continue;
    if (!g_stageSummarized)
    {
        g_stageSummarized = true;
        char map[64];
        GetCurrentMap(map, sizeof(map));
        PrintToServer("STAGE_RESULT map=%s site=%s elapsed=%.2f ready=%d/%d carrier_ready=%d", map,
            g_targetB.BoolValue ? "B" : "A", g_stageLastSample, g_stageReady, g_stageOrdered, g_carrierStageReady);
        for (int i = 1; i <= MaxClients; i++)
            if (g_stageHasGoal[i])
                PrintToServer("STAGE_FINAL bot=%d carrier=%d pos=%.0f %.0f %.0f distance=%.0f", i, i == g_carrier,
                    g_stageLastPosition[i][0], g_stageLastPosition[i][1], g_stageLastPosition[i][2],
                    GetVectorDistance(g_stageLastPosition[i], g_stageGoal[i]));
    }
    if (g_stageOnly.BoolValue) NextRouteCase();
    else if (g_plantStallProbe.BoolValue && g_stageSeenLive && !g_planted)
    {
        float goal[3];
        int route;
        if (!BotTTactics_GetOrder(g_carrier, goal, route)) SetFailState("Missing carrier approach order before forced stall");
        SetEntityMoveType(g_carrier, MOVETYPE_NONE);
        CreateTimer(7.0, CheckPlantHandoff, GetClientUserId(g_carrier), TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Stop;
}

public Action CheckPlantHandoff(Handle timer, int userId)
{
    int client = GetClientOfUserId(userId);
    if (!Safe() || !g_live || client == 0 || !IsPlayerAlive(client)) return Plugin_Stop;
    float goal[3];
    int route;
    bool released = !BotTTactics_GetOrder(client, goal, route);
    SetEntityMoveType(client, MOVETYPE_WALK);
    PrintToServer("PLANT_HANDOFF_%s", released ? "PASS" : "FAIL");
    return Plugin_Stop;
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int length)
{
    MarkNativeAsOptional("BotTTactics_GetAttackSite");
    MarkNativeAsOptional("BotTTactics_GetUtilityLane");
    return APLRes_Success;
}

public Action Survey(Handle timer)
{
    char map[64];
    GetCurrentMap(map, sizeof(map));
    PrintToServer("PLANT_ZONE_%s map=%s site=%s", GetEntProp(g_carrier, Prop_Send, "m_bInBombZone") ? "PASS" : "FAIL",
        map, g_targetB.BoolValue ? "B" : "A");
    float point[3], ray[3];
    GetClientAbsOrigin(g_carrier, point);
    for (int i = 0; i < 3; i++) ray[i] = point[i];
    point[2] += 24.0;
    ray[2] += 25.0;
    int zone = -1;
    while ((zone=FindEntityByClassname(zone, "func_bomb_target")) != -1)
    {
        float mn[3], mx[3], origin[3];
        GetEntPropVector(zone, Prop_Send, "m_vecMins", mn);
        GetEntPropVector(zone, Prop_Send, "m_vecMaxs", mx);
        GetEntPropVector(zone, Prop_Data, "m_vecAbsOrigin", origin);
        Handle trace = TR_ClipRayToEntityEx(point, ray, MASK_ALL, RayType_EndPoint, zone);
        PrintToServer("PLANT_BRUSH id=%d origin=%.0f %.0f %.0f range=%.0f %.0f %.0f / %.0f %.0f %.0f start=%d hit=%d contents=%d", zone,
            origin[0],origin[1],origin[2],mn[0],mn[1],mn[2],mx[0],mx[1],mx[2], TR_StartSolid(trace),TR_DidHit(trace),TR_GetPointContentsEnt(zone, point));
        delete trace;
    }
    g_live = false;
    if (g_surveyAll.BoolValue)
    {
        if (!g_targetB.BoolValue)
        {
            g_targetB.BoolValue = true;
            g_carrier = g_ct = 0;
            g_armed = true;
            ServerCommand("mp_restartgame 1");
        }
        else
        {
            char next[64];
            if (TacticalMap_GetName(TacticalMap_Find(map) + 1, next, sizeof(next))) ServerCommand("changelevel %s", next);
            else PrintToServer("PLANT_SURVEY_DONE");
        }
    }
    return Plugin_Stop;
}

public Action Observe(Handle timer)
{
    if (!Safe() || !g_live || g_completed) return Plugin_Stop;
    if (!IsClientInGame(g_carrier)) return Plugin_Stop;
    float pos[3], goal[3];
    int route, ready, ordered;
    GetClientAbsOrigin(g_carrier, pos);
    bool order = BotTTactics_GetOrder(g_carrier, goal, route);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        float where[3], target[3];
        if (BotTTactics_GetOrder(i, target, route))
        {
            ordered++;
            GetClientAbsOrigin(i, where);
            if (GetVectorDistance(where, target) <= 180.0 && FloatAbs(where[2] - target[2]) <= 96.0) ready++;
        }
        if (g_planted && BotCTTactics_GetOrder(i, target, route))
        {
            if (route == 2) g_stageSeen++;
            if (route == 1) g_commitSeen++;
        }
        if (g_planted && GetClientTeam(i) == CS_TEAM_CT)
        {
            GetClientAbsOrigin(i, where);
            if (g_liveAll.BoolValue && FloatAbs(where[2] - g_retakeStartZ[i]) > g_maxRetakeZ)
                g_maxRetakeZ = FloatAbs(where[2] - g_retakeStartZ[i]);
            PrintToServer("RETAKE_TRAVEL t=%.1f ct=%d pos=%.0f %.0f %.0f move=%d", GetGameTime()-g_plantedAt,
                i, where[0],where[1],where[2],GetEntityMoveType(i));
        }
    }
    if (g_planted && ready > g_guardReady) g_guardReady = ready;
    if (g_liveAll.BoolValue && !g_planted && GetVectorDistance(g_lastCarrierSample, pos) < 42.0)
    {
        if (BotTTactics_ShouldHoldStage(g_carrier) && order && GetVectorDistance(pos, goal) <= 180.0) g_waitSamples++;
        else if (order) g_stallSamples++;
        else if (!GetEntProp(g_carrier, Prop_Send, "m_bInBombZone")) g_nativeStallSamples++;
    }
    g_lastCarrierSample = pos;
    PrintToServer("PLANT_TRAVEL t=%.1f stage=%d ready=%d/%d origin=%.0f %.0f %.0f goal=%.0f %.0f %.0f order=%d zone=%d",
        GetGameTime() - g_start, BotTTactics_ShouldHoldStage(g_carrier), ready, ordered,
        pos[0], pos[1], pos[2], goal[0], goal[1], goal[2], order, GetEntProp(g_carrier, Prop_Send, "m_bInBombZone"));
    if ((!g_planted && GetGameTime() - g_start > (g_liveAll.BoolValue ? 115.0 : 60.0)) || (g_planted && GetGameTime() - g_plantedAt > 42.0))
    {
        PrintToServer("PLANT_ROUTE_FAIL planted=%d stage=%d commit=%d", g_planted, g_stageSeen, g_commitSeen);
        if (g_liveAll.BoolValue) FinishLiveCase(g_planted ? "no_defuse" : "no_plant", 0, 0);
        NextRouteCase();
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public void ObjectiveEvent(Event event, const char[] name, bool dontBroadcast)
{
    if (!Safe() || !g_live || g_surveyOnly.BoolValue) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    PrintToServer("PLANT_OBJECTIVE %s t=%.2f bot=%d", name, GetGameTime() - g_start, client);
    if (StrEqual(name, "bomb_planted"))
    {
        g_planted = true;
        g_plantedAt = GetGameTime();
        float pos[3];
        if (client > 0 && IsClientInGame(client))
        {
            GetClientAbsOrigin(client, pos);
            g_actualSite = GetVectorDistance(pos, g_siteA) <= GetVectorDistance(pos, g_siteB) ? 0 : 1;
        }
        // CT starts at spawn and runs the engine's actual return route. Keep
        // the non-shooting opponents for an optional window of real staging.
        for (int i = 1; i <= MaxClients; i++)
            if (IsClientInGame(i) && IsPlayerAlive(i))
            {
                if (GetClientTeam(i) == CS_TEAM_T && g_clearDelay.FloatValue > 0.0 && !g_liveAll.BoolValue) SetEntityMoveType(i, MOVETYPE_NONE);
                else if (GetClientTeam(i) == CS_TEAM_CT)
                {
                    if (g_pressureConnector && g_liveSite == 0)
                    {
                        char map[32];
                        GetCurrentMap(map, sizeof(map));
                        if (StrEqual(map, "de_overpass") && i == g_ct)
                        {
                            float point[3] = {-1460.0,-773.0,36.0};
                            TeleportEntity(i, point, NULL_VECTOR, NULL_VECTOR);
                            PrintToServer("RETAKE_CONNECTOR_START uid=%d pos=%.0f,%.0f,%.0f",
                                GetClientUserId(i), point[0],point[1],point[2]);
                            if (g_pressureStuck)
                                CreateTimer(2.5, BeginPressureStall, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
                        }
                    }
                    SetEntityMoveType(i, MOVETYPE_WALK);
                    SetEntProp(i, Prop_Send, "m_bHasDefuser", g_kit.BoolValue ? 1 : 0);
                    float start[3]; GetClientAbsOrigin(i, start);
                    g_retakeStartZ[i] = start[2];
                }
            }
        if (g_pressure[0] != '\0')
        {
            if (g_pressureDefenders < 5)
            {
                // This fixture chooses a post-plant population once, before
                // shooting resumes. All selected defenders stay in play.
                PressureSelectDefenders(client);
            }
            for (int i = 1; i <= MaxClients; i++)
                if (IsClientInGame(i) && IsPlayerAlive(i))
                {
                    if (GetClientTeam(i) == CS_TEAM_CT) g_pressureCT++;
                    if (GetClientTeam(i) == CS_TEAM_T) g_pressureT++;
                }
            // Both teams keep their real weapons and can fight. No forced
            // clearing at a fixed deadline in the armed and relay scenarios.
            FindConVar("mp_ignore_round_win_conditions").BoolValue = false;
            CreateTimer(0.25, ObservePressureApproach, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        }
        else if (g_clearDelay.FloatValue > 0.0)
            CreateTimer(g_clearDelay.FloatValue, ClearTestAttackers, _, TIMER_FLAG_NO_MAPCHANGE);
        else ClearTestAttackers(null);
        if (g_enableContact.BoolValue)
        {
            FindConVar("bot_dont_shoot").BoolValue = false;
            PrintToServer("LIVE_RETAKE_CONTACT");
        }
    }
    if (g_pressure[0] != '\0' && StrEqual(name, "bomb_begindefuse"))
    {
        if (++g_pressureStarts == 1)
        {
            g_pressureFirstLeft = 40.0 - (GetGameTime() - g_plantedAt);
            g_pressureTAtFirstUse = 0;
            for (int i = 1; i <= MaxClients; i++)
                if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
                    g_pressureTAtFirstUse++;
        }
    }
    if (g_pressure[0] != '\0' && StrEqual(name, "bomb_abortdefuse")) g_pressureStops++;
    if (StrEqual(name, "bomb_begindefuse") && client > 0 && g_replaceDefuser.BoolValue && g_firstDefuser == 0)
    {
        g_firstDefuser = GetClientUserId(client);
        CreateTimer(0.15, RemoveFirstDefuser, g_firstDefuser, TIMER_FLAG_NO_MAPCHANGE);
    }
    if (StrEqual(name, "bomb_defused"))
    {
        g_completed = true;
        if (g_pressure[0] != '\0')
        {
            g_pressureFinalDefuser = client > 0 ? GetClientUserId(client) : 0;
            g_pressureFinishLeft = 40.0 - (GetGameTime() - g_plantedAt);
        }
        char map[64];
        GetCurrentMap(map, sizeof(map));
        PrintToServer("PLANT_ROUTE_PASS map=%s plant_to_defuse=%.2f stage_samples=%d commit_samples=%d",
            map, GetGameTime() - g_plantedAt, g_stageSeen, g_commitSeen);
        if (g_replaceDefuser.BoolValue)
            PrintToServer("LIVE_DEFUSER_REPLACEMENT_%s first=%d final=%d",
                g_firstDefuser != 0 && client > 0 && GetClientUserId(client) != g_firstDefuser ? "PASS" : "FAIL",
                g_firstDefuser, client > 0 ? GetClientUserId(client) : 0);
        NextRouteCase();
    }
}

public Action ObservePressureApproach(Handle timer)
{
    if (!Safe() || !g_live || !g_planted || g_completed) return Plugin_Stop;
    int bomb = FindEntityByClassname(-1, "planted_c4");
    if (bomb == -1) return Plugin_Continue;
    float timeLeft = GetEntPropFloat(bomb, Prop_Send, "m_flC4Blow") - GetGameTime();
    if (timeLeft <= 0.0 || g_pressureEligibleLeft >= 0.0) return Plugin_Continue;
    float origin[3], eye[3], target[3], foot[3];
    GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", origin);
    target = origin;
    target[2] += 8.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_CT) continue;
        GetClientAbsOrigin(i, foot);
        float distance = GetVectorDistance(foot, origin);
        if (distance > 224.0 || FloatAbs(foot[2] - origin[2]) > 66.0) continue;
        GetClientEyePosition(i, eye);
        Handle trace = TR_TraceRayFilterEx(eye, target, MASK_VISIBLE, RayType_EndPoint, PressureWorldTrace, bomb);
        bool clear = !TR_StartSolid(trace) && !TR_DidHit(trace);
        delete trace;
        if (!clear) continue;
        if (g_pressureNearLeft < 0.0) g_pressureNearLeft = timeLeft;
        if (distance <= 80.0 && timeLeft >= (GetEntProp(i, Prop_Send, "m_bHasDefuser") ? 5.5 : 10.5))
            g_pressureEligibleLeft = timeLeft;
    }
    return Plugin_Continue;
}

void PressureSelectDefenders(int planter)
{
    if (planter <= 0 || !IsClientInGame(planter) || !IsPlayerAlive(planter)) return;
    bool keep[MAXPLAYERS + 1];
    keep[planter] = true;
    float origin[3];
    GetClientAbsOrigin(planter, origin);
    for (int pick = 1; pick < g_pressureDefenders; pick++)
    {
        int chosen;
        float best = 999999.0;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (keep[client] || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T) continue;
            float position[3];
            GetClientAbsOrigin(client,position);
            float distance = GetVectorDistance(origin, position);
            if (distance < best) { chosen = client; best = distance; }
        }
        if (chosen == 0) return;
        keep[chosen] = true;
    }
    for (int client = 1; client <= MaxClients; client++)
        if (!keep[client] && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_T)
            ForcePlayerSuicide(client);
    PrintToServer("RETAKE_PRESSURE_SETUP defenders=%d", g_pressureDefenders);
}

public bool PressureWorldTrace(int entity, int mask, any bomb) { return entity > MaxClients && entity != bomb; }

public Action BeginPressureStall(Handle timer, int userid)
{
    if (!Safe() || !g_live || !g_planted) return Plugin_Stop;
    int client = GetClientOfUserId(userid);
    int route;
    float goal[3], foot[3];
    if (client <= 0 || !IsPlayerAlive(client) || !BotCTTactics_GetOrder(client, goal, route))
    {
        client = 0;
        for (int i = 1; i <= MaxClients && !client; i++)
            if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT
                && BotCTTactics_GetOrder(i, goal, route))
            {
                GetClientAbsOrigin(i, foot);
                if (FloatAbs(foot[2] - goal[2]) > 180.0) client = i;
            }
    }
    if (!client)
    {
        PrintToServer("RETAKE_STALL_INVALID reason=no_ordered_candidate");
        return Plugin_Stop;
    }
    float place[3] = {-1460.0,-773.0,36.0};
    TeleportEntity(client, place, NULL_VECTOR, NULL_VECTOR);
    g_pressureStuckUser = GetClientUserId(client);
    g_pressureStuckStart = GetGameTime();
    GetClientAbsOrigin(client, g_pressureStuckOrigin);
    SetEntityMoveType(client, MOVETYPE_NONE);
    g_pressureWaypointSeen = false;
    CreateTimer(0.10, CheckPressureStall, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action CheckPressureStall(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int client = GetClientOfUserId(g_pressureStuckUser);
    if (client <= 0 || !IsPlayerAlive(client)) return Plugin_Stop;
    float elapsed = GetGameTime() - g_pressureStuckStart;
    float goal[3];
    int route;
    if (!g_pressureWaypointSeen && BotCTTactics_GetOrder(client, goal, route)
        && GetVectorDistance(goal, g_pressureStuckOrigin) >= 130.0
        && GetVectorDistance(goal, g_pressureStuckOrigin) <= 480.0 && FloatAbs(goal[2] - g_pressureStuckOrigin[2]) < 45.0)
    {
        g_pressureWaypointSeen = true;
        SetEntityMoveType(client, MOVETYPE_WALK);
        PrintToServer("RETAKE_STALL_WAYPOINT uid=%d observed=1 after=%.2f goal=%.0f,%.0f,%.0f",
            g_pressureStuckUser, elapsed, goal[0],goal[1],goal[2]);
    }
    if (elapsed < 12.0 && g_live) return Plugin_Continue;
    SetEntityMoveType(client, MOVETYPE_WALK);
    float pos[3];
    GetClientAbsOrigin(client, pos);
    PrintToServer("RETAKE_STALL_RESULT uid=%d observed=%d traveled=%.0f", g_pressureStuckUser, g_pressureWaypointSeen,
        GetVectorDistance(pos, g_pressureStuckOrigin));
    g_pressureStuckUser = 0;
    return Plugin_Stop;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3],
    int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_pressureStuckUser || !g_live || g_pressureWaypointSeen || !IsClientInGame(client)
        || GetClientUserId(client) != g_pressureStuckUser || !Safe()) return;
    // Replay the captured task classification at the real movement input
    // seam after the bridge's pre-hook, without faking plant/defuse events.
    BotCTTactics_ReportRouteDrive(client, false, true);
}

public Action RemoveFirstDefuser(Handle timer, int userid)
{
    if (!Safe() || !g_live || !g_planted || g_completed) return Plugin_Stop;
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsPlayerAlive(client)) ForcePlayerSuicide(client);
    return Plugin_Stop;
}

public Action ClearTestAttackers(Handle timer)
{
    if (!Safe() || !g_live || !g_planted || g_completed) return Plugin_Stop;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T) ForcePlayerSuicide(i);
    FindConVar("mp_ignore_round_win_conditions").BoolValue = false;
    PrintToServer("RETAKE_TEST_CLEAR t=%.2f", GetGameTime() - g_plantedAt);
    return Plugin_Stop;
}

public void RoundResult(Event event, const char[] name, bool dontBroadcast)
{
    if (!Safe() || !g_live || (!g_planted && !g_liveAll.BoolValue)) return;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    PrintToServer("RETAKE_ROUND map=%s winner=%d reason=%d", map, event.GetInt("winner"), event.GetInt("reason"));
    if (g_liveAll.BoolValue)
        FinishLiveCase(!g_planted ? "no_plant" : (event.GetInt("reason") != 7 ? "round_ended" : (g_actualSite == g_liveSite ? "defused" : "wrong_site")),
            event.GetInt("winner"), event.GetInt("reason"));
}

public void LiveCaseDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_liveAll.BoolValue || !g_live || !g_planted || !Safe()) return;
    g_casualty = true;
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (victim > 0 && attacker > 0 && victim != attacker && GetClientTeam(victim) != GetClientTeam(attacker))
    {
        g_armedCombatDeaths++;
        if (GetClientTeam(attacker) == CS_TEAM_CT) g_pressureCTKills++;
        if (GetClientTeam(attacker) == CS_TEAM_T) g_pressureTKills++;
    }
}

void FinishLiveCase(const char[] outcome, int winner, int reason)
{
    if (g_advancePending) return;
    g_advancePending = true;
    g_completed = true;
    g_live = false;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    PrintToServer("LIVE_CASE_RESULT map=%s site=%s actual=%d outcome=%s winner=%d reason=%d guard_ready=%d retake_stage=%d retake_push=%d z_delta=%.0f casualty=%d utility=%d",
        map, g_liveSite == 0 ? "A" : "B", g_actualSite, outcome, winner, reason, g_guardReady, g_stageSeen, g_commitSeen, g_maxRetakeZ, g_casualty, g_interference);
    PrintToServer("LIVE_CASE_MOTION map=%s site=%s waiting=%d ordered_stalls=%d native_stalls=%d",
        map, g_liveSite == 0 ? "A" : "B", g_waitSamples, g_stallSamples, g_nativeStallSamples);
    if (g_enableContact.BoolValue) PrintToServer("LIVE_CASE_CONTACT enemy_kills=%d", g_armedCombatDeaths);
    if (g_pressure[0] != '\0')
        PrintToServer("RETAKE_PRESSURE map=%s site=%s mode=%s ct=%d t=%d ct_kills=%d t_kills=%d use=%d aborts=%d t_at_use=%d use_left=%.2f finish_left=%.2f first=%d final=%d",
            map, g_liveSite == 0 ? "A" : "B", g_pressure, g_pressureCT, g_pressureT, g_pressureCTKills, g_pressureTKills,
            g_pressureStarts, g_pressureStops, g_pressureTAtFirstUse, g_pressureFirstLeft, g_pressureFinishLeft, g_firstDefuser, g_pressureFinalDefuser);
    if (g_pressure[0] != '\0')
        PrintToServer("RETAKE_PRESSURE_APPROACH near_left=%.2f eligible_left=%.2f", g_pressureNearLeft, g_pressureEligibleLeft);
    CreateTimer(1.5, AdvanceLiveCase, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action AdvanceLiveCase(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    if (g_pressureSingle)
    {
        PrintToServer("LIVE_CASE_SUITE_DONE");
        ServerCommand("quit");
        return Plugin_Stop;
    }
    if (g_liveSite == 0)
    {
        g_liveSite = 1;
        g_armed = true;
        ServerCommand("bot_dont_shoot 1; mp_ignore_round_win_conditions 1; mp_restartgame 1");
        CreateTimer(4.0, EnsureLiveRound, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    char map[64], next[64], last[64];
    GetCurrentMap(map, sizeof(map));
    g_endMap.GetString(last, sizeof(last));
    g_firstSite.IntValue = 0;
    if (!StrEqual(map, last, false) && TacticalMap_GetName(TacticalMap_Find(map) + 1, next, sizeof(next)))
        ForceChangeLevel(next, "isolated live regression");
    else
    {
        PrintToServer("\nLIVE_CASE_SUITE_DONE");
        if (g_pressure[0] != '\0') ServerCommand("quit");
    }
    return Plugin_Stop;
}

void NextRouteCase()
{
    if (g_liveAll.BoolValue || !g_routeSeries.BoolValue) return;
    g_completed = true;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    if (StrEqual(map, "de_inferno")) ServerCommand("changelevel de_mirage");
    else if (StrEqual(map, "de_mirage")) ServerCommand("changelevel de_nuke");
    else PrintToServer("PLANT_ROUTE_SERIES_DONE");
}
