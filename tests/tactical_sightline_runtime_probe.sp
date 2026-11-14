#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3], bool live = false);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_GetAim(int client, float look[3], bool live = false);

public Plugin myinfo = {name = "Isolated objective sightline survey", version = "1.1"};
ConVar g_on;
bool g_armed;
int g_map, g_site, g_planter, g_bomb = INVALID_ENT_REFERENCE;
float g_started;
static const char Maps[][] = {"de_inferno","de_train","de_mirage","de_nuke","de_dust2","de_overpass","de_vertigo","de_cache","de_ancient","de_anubis"};
// On this server these exact standing spots passed the earlier engine bomb-zone survey.
static const float Plant[10][2][3] = {
    {{1887.5,475.0,160.0},{475.0,2650.0,160.0}},
    {{637.5,-137.5,-217.9},{50.0,-1287.5,-286.9}},
    {{-437.5,-2200.0,-177.9},{-2100.0,187.5,-159.9}},
    {{587.5,-762.5,-399.9},{700.0,-987.5,-769.1}},
    {{1100.0,2462.5,96.0},{-1550.0,2687.5,5.9}},
    {{-2062.5,662.5,472.0},{-1100.0,50.0,98.0}},
    {{-287.5,-575.0,11775.0},{-2212.5,725.0,11744.0}},
    {{-312.5,1762.5,1686.5},{-37.5,-1250.0,1659.1}},
    {{-1425.0,825.0,53.5},{987.5,-50.0,131.0}},
    {{1262.5,1987.5,-191.9},{-950.0,625.0,-1.9}}
};

public void OnPluginStart()
{
    g_on = CreateConVar("sm_objective_angle_survey", "0", "Only on isolated loopback server.");
    HookEvent("round_freeze_end", Start, EventHookMode_PostNoCopy);
}

bool Safe()
{
    if (!g_on.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++) if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public void OnMapStart()
{
    g_map = -1;
    g_site = 0;
    g_armed = false;
    g_bomb = INVALID_ENT_REFERENCE;
    char map[32];
    GetCurrentMap(map,sizeof(map));
    for (int i = 0; i < sizeof(Maps); i++) if (StrEqual(Maps[i],map)) g_map = i;
    CreateTimer(7.0, Prep, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Prep(Handle timer)
{
    if (!Safe() || g_map < 0) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    g_started = GetGameTime();
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    CreateTimer(5.0, CheckStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action CheckStart(Handle timer)
{
    if (!Safe() || !g_armed) return Plugin_Stop;
    if (GetGameTime() - g_started > 18.0)
    {
        PrintToServer("ANGLE_SKIP map=%s site=%d no_freeze_end", Maps[g_map], g_site);
        NextMap();
        return Plugin_Stop;
    }
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void Start(Event event, const char[] name, bool noBroadcast)
{
    if (!Safe() || !g_armed || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    CreateTimer(0.30, Cover, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Cover(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    Measure("ct_open", true);
    g_planter = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && GetPlayerWeaponSlot(i, CS_SLOT_C4) > MaxClients) {g_planter=i; break;}
    if (!g_planter)
    {
        PrintToServer("ANGLE_SKIP map=%s site=%d no_carrier", Maps[g_map], g_site);
        NextSite();
        return Plugin_Stop;
    }
    float point[3];
    point = Plant[g_map][g_site];
    point[2] += 2.0;
    TeleportEntity(g_planter,point,NULL_VECTOR,NULL_VECTOR);
    Event event = CreateEvent("bomb_beginplant");
    event.SetInt("userid", GetClientUserId(g_planter));
    event.Fire();
    Measure("t_cover", false);
    CreateTimer(0.25, Planted, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Planted(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int bomb = CreateEntityByName("planted_c4");
    if (bomb == -1) SetFailState("Test bomb allocation failed");
    DispatchSpawn(bomb);
    TeleportEntity(bomb,Plant[g_map][g_site],NULL_VECTOR,NULL_VECTOR);
    SetEntProp(bomb, Prop_Send, "m_bBombTicking", 1);
    SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + 40.0);
    g_bomb = EntIndexToEntRef(bomb);
    Event event = CreateEvent("bomb_planted");
    event.SetInt("userid", GetClientUserId(g_planter));
    event.Fire();
    CreateTimer(0.4, RetakeStage, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action RetakeStage(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    Measure("t_postplant", false);
    Measure("ct_retake_stage", true, 2);
    for (int i = 1; i <= MaxClients; i++)
    {
        float goal[3]; int route;
        if (!BotCTTactics_GetOrder(i, goal, route) || route != 2) continue;
        Event event = CreateEvent("weapon_fire");
        event.SetInt("userid",GetClientUserId(i));
        event.SetString("weapon","usp_silencer");
        event.Fire();
        break;
    }
    CreateTimer(0.75, RetakeCommit, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action RetakeCommit(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    Measure("ct_retake_commit", true, 1);
    int bomb = EntRefToEntIndex(g_bomb);
    if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
    g_bomb = INVALID_ENT_REFERENCE;
    NextSite();
    return Plugin_Stop;
}

void NextSite()
{
    if (++g_site < 2)
    {
        g_armed = true;
        g_started = GetGameTime();
        ServerCommand("mp_restartgame 1");
        CreateTimer(5.0, CheckStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    NextMap();
}

void NextMap()
{
    g_armed = false;
    if (g_map + 1 < sizeof(Maps)) ServerCommand("changelevel %s", Maps[g_map + 1]);
    else PrintToServer("ANGLE_SURVEY_DONE");
}

public bool World(int entity, int mask, any unused) { return entity > MaxClients; }

float WallDist(const float eye[3], const float look[3])
{
    Handle ray = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint, World);
    float result = TR_StartSolid(ray) ? 0.0 : (TR_DidHit(ray) ? GetVectorDistance(eye,look)*TR_GetFraction(ray) : -1.0);
    delete ray;
    return result;
}

void Measure(const char[] phase, bool ct, int onlyRoute = -1)
{
    int orders, aims, close, samples, offsetClose;
    float minGoal = 99999.0, minOffset = 99999.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != (ct ? CS_TEAM_CT : CS_TEAM_T)) continue;
        float goal[3], original[3], feet[3]; int route;
        bool got = ct ? BotCTTactics_GetOrder(i,goal,route) : BotTTactics_GetOrder(i,goal,route);
        if (!got || (onlyRoute != -1 && route != onlyRoute)) continue;
        orders++;
        GetClientAbsOrigin(i, original);
        if (SafeFloor(goal, feet))
        {
            samples++;
            if (MeasureAt(i, ct, feet, minGoal, aims)) close++;
        }
        for (int step = 0; step < 8; step++)
        {
            float point[3];
            point = goal;
            point[0] += 64.0 * Cosine(float(step) * 0.785398163);
            point[1] += 64.0 * Sine(float(step) * 0.785398163);
            if (!SafeFloor(point, feet)) continue;
            samples++;
            if (MeasureAt(i, ct, feet, minOffset, aims)) offsetClose++;
        }
        TeleportEntity(i, original, NULL_VECTOR, NULL_VECTOR);
    }
    PrintToServer("ANGLE_SUMMARY map=%s site=%d phase=%s orders=%d aims=%d near=%d samples=%d offset_near=%d min=%.1f offset_min=%.1f",Maps[g_map],g_site,phase,orders,aims,close,samples,offsetClose,minGoal,minOffset);
}
bool SafeFloor(const float point[3], float feet[3])
{
    float mins[3] = {-16.0,-16.0,0.0}, maxs[3] = {16.0,16.0,72.0}, below[3];
    feet = point;
    feet[2] += 3.0;
    below = feet;
    below[2] -= 21.0;
    Handle floor = TR_TraceHullFilterEx(feet, below, mins, maxs, MASK_PLAYERSOLID, World);
    bool clear = TR_DidHit(floor) && !TR_StartSolid(floor);
    if (clear) TR_GetEndPosition(feet, floor);
    delete floor;
    return clear;
}

bool MeasureAt(int client, bool ct, const float feet[3], float &nearestWall, int &aims)
{
    TeleportEntity(client, feet, NULL_VECTOR, NULL_VECTOR);
    float eye[3], look[3];
    if (!(ct ? BotCTTactics_GetAim(client, look, true) : BotTTactics_GetAim(client, look, true))) return false;
    GetClientEyePosition(client, eye);
    aims++;
    float distance = WallDist(eye, look);
    if (distance < 0.0 || distance >= 128.0) return false;
    if (distance < nearestWall) nearestWall = distance;
    return true;
}
