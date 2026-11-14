#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_ShouldHoldStage(int client);
native int BotTTactics_GetAttackSite();
native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
#include "../mods/include/bot_tactical_map_profiles.inc"

public Plugin myinfo = {name = "Plant and retake route probe (isolated only)", version = "1.0"};
ConVar g_enabled, g_targetB, g_surveyOnly, g_surveyAll, g_split, g_routeSeries;
bool g_armed, g_live, g_planted, g_completed;
int g_carrier, g_ct;
float g_start, g_plantedAt;
float g_siteA[3], g_siteB[3];
int g_stageSeen, g_commitSeen;

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_plant_route_probe", "0", "Explicit isolated-server test.");
    g_targetB = CreateConVar("sm_plant_route_probe_b", "1", "Prefer B for the test.");
    g_surveyOnly = CreateConVar("sm_plant_route_probe_survey", "0", "Inspect engine plant zone at issued goals.");
    g_surveyAll = CreateConVar("sm_plant_route_probe_survey_all", "0", "Survey A and B across the ten map profiles.");
    g_split = CreateConVar("sm_plant_route_probe_split", "1", "Exercise the split selector in live cases.");
    g_routeSeries = CreateConVar("sm_plant_route_probe_series", "0", "Run Inferno B, Mirage A and Nuke B, automatically.");
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("bomb_beginplant", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_planted", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_begindefuse", ObjectiveEvent, EventHookMode_Post);
    HookEvent("bomb_defused", ObjectiveEvent, EventHookMode_Post);
}

public void OnMapStart()
{
    g_carrier = g_ct = 0;
    g_live = g_planted = g_completed = false;
    if (g_surveyAll.BoolValue) g_targetB.BoolValue = false;
    if (g_routeSeries.BoolValue)
    {
        char map[64];
        GetCurrentMap(map, sizeof(map));
        g_targetB.BoolValue = !StrEqual(map, "de_mirage");
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
    ServerCommand("sv_cheats 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 3; mp_roundtime_defuse 1.92; mp_ignore_round_win_conditions 1; mp_c4timer 40");
    ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Stop;
}

public void FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_armed || !Safe()) return;
    g_armed = false;
    RequestFrame(Begin);
}

public void Begin(any unused)
{
    if (!Safe()) return;
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", g_siteA);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", g_siteB);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        if (GetClientTeam(i) == CS_TEAM_T && GetPlayerWeaponSlot(i, CS_SLOT_C4) > MaxClients) g_carrier = i;
        if (GetClientTeam(i) == CS_TEAM_CT && g_ct == 0) g_ct = i;
        if (GetClientTeam(i) == CS_TEAM_CT) SetEntityMoveType(i, MOVETYPE_NONE);
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
    if (g_surveyOnly.BoolValue)
    {
        PrintToServer("PLANT_GOAL %.1f %.1f %.1f", goal[0], goal[1], goal[2]);
        goal[2] += 2.0;
        TeleportEntity(g_carrier, goal, NULL_VECTOR, NULL_VECTOR);
        SetEntityMoveType(g_carrier, MOVETYPE_NONE);
        CreateTimer(0.35, Survey, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else CreateTimer(2.0, Observe, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int length)
{
    MarkNativeAsOptional("BotTTactics_GetAttackSite");
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
            PrintToServer("RETAKE_TRAVEL t=%.1f ct=%d pos=%.0f %.0f %.0f move=%d", GetGameTime()-g_plantedAt,
                i, where[0],where[1],where[2],GetEntityMoveType(i));
        }
    }
    PrintToServer("PLANT_TRAVEL t=%.1f stage=%d ready=%d/%d origin=%.0f %.0f %.0f goal=%.0f %.0f %.0f order=%d zone=%d",
        GetGameTime() - g_start, BotTTactics_ShouldHoldStage(g_carrier), ready, ordered,
        pos[0], pos[1], pos[2], goal[0], goal[1], goal[2], order, GetEntProp(g_carrier, Prop_Send, "m_bInBombZone"));
    if ((!g_planted && GetGameTime() - g_start > 60.0) || (g_planted && GetGameTime() - g_plantedAt > 42.0))
    {
        PrintToServer("PLANT_ROUTE_FAIL planted=%d stage=%d commit=%d", g_planted, g_stageSeen, g_commitSeen);
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
        // Remove opponents without faking an objective event. CT starts
        // from its spawn and has to actually path and defuse in the engine.
        // Resume CT first so T suicides cannot leave a fake motion state.
        for (int i = 1; i <= MaxClients; i++)
            if (IsClientInGame(i) && IsPlayerAlive(i))
            {
                if (GetClientTeam(i) == CS_TEAM_T) ForcePlayerSuicide(i);
                else if (GetClientTeam(i) == CS_TEAM_CT)
                {
                    SetEntityMoveType(i, MOVETYPE_WALK);
                    SetEntProp(i, Prop_Send, "m_bHasDefuser", 1);
                }
            }
    }
    if (StrEqual(name, "bomb_defused"))
    {
        g_completed = true;
        char map[64];
        GetCurrentMap(map, sizeof(map));
        PrintToServer("PLANT_ROUTE_PASS map=%s plant_to_defuse=%.2f stage_samples=%d commit_samples=%d",
            map, GetGameTime() - g_plantedAt, g_stageSeen, g_commitSeen);
        NextRouteCase();
    }
}

void NextRouteCase()
{
    if (!g_routeSeries.BoolValue) return;
    g_completed = true;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    if (StrEqual(map, "de_inferno")) ServerCommand("changelevel de_mirage");
    else if (StrEqual(map, "de_mirage")) ServerCommand("changelevel de_nuke");
    else PrintToServer("PLANT_ROUTE_SERIES_DONE");
}
