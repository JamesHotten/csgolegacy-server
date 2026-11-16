#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <commandline>
#include "../mods/include/bot_tactical_map_profiles.inc"

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3], bool live = false);
native float BotCTTactics_GetHoldRadius(int client);
native int NavMesh_GetNearestArea(const float pos[3], bool anyZ = false, float maxDist = 10000.0,
    bool checkLOS = false, bool checkGround = true, int team = -2);
native void NavMeshArea_GetPlaceCanonical(int area, char[] name, int length);

public Plugin myinfo = { name = "CT opening placement audit (isolated)", version = "1.0" };
ConVar g_enabled, g_last, g_rounds, g_seconds, g_debug;
int g_map, g_round, g_zoneCount, g_zones[32], g_zoneSite[32], g_uid[6], g_role[6], g_targetIn[6], g_atGoal[6], g_clearaim[6], g_reassigned[6];
float g_centers[2][3], g_goal[6][3], g_radius[6], g_nearest[6], g_started;
int g_liveInside[2], g_longest[2], g_tail[2], g_roster, g_ticks, g_cal;
bool g_armed;
char g_mapName[32];

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_ct_opening_position_probe", "0");
    g_last = CreateConVar("sm_ct_opening_position_end", "de_anubis");
    g_rounds = CreateConVar("sm_ct_opening_position_rounds", "1", _, _, true, 1.0, true, 3.0);
    g_seconds = CreateConVar("sm_ct_opening_position_seconds", "18", _, _, true, 8.0, true, 38.0);
    g_debug = CreateConVar("sm_ct_opening_position_debug", "0", "Include tactical routing details in isolated audit.");
    if (FindCommandLineParam("-ctrefineopening"))
    {
        char ip[32], last[32];
        GetCommandLineParam("-ip", ip, sizeof(ip));
        if (!StrEqual(ip, "127.0.0.1")) SetFailState("CT refinement fixture is loopback-only");
        GetCommandLineParam("-ctrefineend", last, sizeof(last), "de_anubis");
        g_enabled.BoolValue = true;
        g_last.SetString(last);
        g_seconds.FloatValue = 26.0;
    }
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("weapon_fire", TraceFire, EventHookMode_Post);
}

bool Safe()
{
    if (!g_enabled.BoolValue) return false;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client)) return false;
    return true;
}

public void OnMapStart()
{
    GetCurrentMap(g_mapName, sizeof(g_mapName));
    g_map = TacticalMap_Find(g_mapName);
    g_round = 0;
    g_armed = false;
    CreateTimer(5.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Prepare(Handle timer)
{
    if (!Safe() || g_map < 0) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 0; bot_dont_shoot 1; bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1; sm_bot_t_tactics_enable 0; sm_bot_experience_record_enable 0");
    ServerExecute();
    if (g_debug.BoolValue) FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    for (int client = 0; client < 5; client++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    Restart();
    return Plugin_Stop;
}

void Restart()
{
    g_armed = true;
    g_started = GetGameTime();
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    CreateTimer(5.0, Watchdog, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Watchdog(Handle timer)
{
    if (!g_armed || !Safe()) return Plugin_Stop;
    if (GetGameTime() - g_started > 18.0)
    {
        PrintToServer("CT_SITE_INVALID map=%s reason=no_freeze_end", g_mapName);
        NextMap();
        return Plugin_Stop;
    }
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void FreezeEnd(Event event, const char[] name, bool noBroadcast)
{
    if (!g_armed || !Safe() || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client)) continue;
        if (GetClientTeam(client) != CS_TEAM_T)
        {
            if (g_debug.BoolValue) SDKHook(client, SDKHook_OnTakeDamage, TraceDamage);
            continue;
        }
        if (g_debug.BoolValue)
        {
            int c4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
            if (c4 > MaxClients && RemovePlayerItem(client,c4)) RemoveEntity(c4);
        }
        float away[3] = {0.0, 0.0, -8900.0};
        away[0] = float(client) * 128.0;
        SetEntityMoveType(client, MOVETYPE_NONE);
        TeleportEntity(client, away, NULL_VECTOR, NULL_VECTOR);
    }
    CreateTimer(0.20, RecordPlan, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TraceDamage(int victim, int &attacker, int &inflictor, float &damage, int &type)
{
    PrintToServer("CT_SITE_DAMAGE victim=%N attacker=%d type=%d fall=%d damage=%.0f",victim,attacker,type,(type & DMG_FALL)!=0,damage);
    return Plugin_Continue;
}

public void TraceFire(Event event,const char[] name,bool noBroadcast)
{
    if (!g_debug.BoolValue || !g_enabled.BoolValue || g_armed || g_round < 1) return;
    int client=GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || GetClientTeam(client)!=CS_TEAM_CT) return;
    char weapon[32];event.GetString("weapon",weapon,sizeof(weapon));
    PrintToServer("CT_SITE_FIRE bot=%N weapon=%s",client,weapon);
}

int SiteFor(const float pos[3], bool horizontal)
{
    float a[3], b[3];
    a = g_centers[0]; b = g_centers[1];
    if (horizontal) { a[2] = pos[2]; b[2] = pos[2]; }
    return GetVectorDistance(pos, a) <= GetVectorDistance(pos, b) ? 0 : 1;
}

void SetupZones()
{
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", g_centers[0]);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", g_centers[1]);
    g_zoneCount = 0;
    int zone = -1;
    while (g_zoneCount < sizeof(g_zones) && (zone = FindEntityByClassname(zone, "func_bomb_target")) != -1)
    {
        float mn[3], mx[3], center[3];
        GetEntPropVector(zone, Prop_Send, "m_vecMins", mn);
        GetEntPropVector(zone, Prop_Send, "m_vecMaxs", mx);
        GetEntPropVector(zone, Prop_Data, "m_vecAbsOrigin", center);
        for (int i = 0; i < 3; i++) center[i] += (mn[i] + mx[i]) * 0.5;
        g_zones[g_zoneCount] = zone;
        g_zoneSite[g_zoneCount++] = SiteFor(center, false);
    }
    g_cal = 0;
    for (int site = 0; site < 2; site++)
    {
        float reference[3];
        TacticalMap_PlantGround(g_map, site, reference);
        if (InZone(reference) & (1 << site)) g_cal |= 1 << site;
    }
}

int InZone(const float pos[3])
{
    int mask;
    for (int i = 0; i < g_zoneCount; i++)
    {
        int site = g_zoneSite[i];
        if (mask & (1 << site)) continue;
        for (int height = 8; height <= 48; height += 8)
        {
            float from[3], to[3];
            from = pos; from[2] += float(height);
            to = from; to[2] += 1.0;
            Handle clip = TR_ClipRayToEntityEx(from, to, MASK_ALL, RayType_EndPoint, g_zones[i]);
            bool inside = TR_StartSolid(clip);
            delete clip;
            if (inside) { mask |= 1 << site; break; }
        }
        if (mask & (1 << site)) continue;
        float base[3], mins[3] = {-12.0,-12.0,0.0}, maxs[3] = {12.0,12.0,56.0};
        base = pos; base[2] += 2.0;
        Handle hull = TR_ClipRayHullToEntityEx(base, base, mins, maxs, MASK_ALL, g_zones[i]);
        if (TR_StartSolid(hull)) mask |= 1 << site;
        delete hull;
    }
    return mask;
}

public bool World(int ent, int contents, any ignored) { return ent > MaxClients; }

bool ClearAim(const float foot[3], const float aim[3])
{
    float eye[3]; eye = foot; eye[2] += 64.0;
    Handle trace = TR_TraceRayFilterEx(eye, aim, MASK_VISIBLE, RayType_EndPoint, World);
    bool clear = !TR_StartSolid(trace) && GetVectorDistance(eye,aim) * TR_GetFraction(trace) >= 128.0;
    delete trace;
    return clear;
}

bool CanSeePlant(const float foot[3], int site, float eyeHeight = 64.0)
{
    float eye[3], spot[3];
    eye = foot; eye[2] += eyeHeight;
    TacticalMap_PlantGround(g_map, site, spot);
    spot[2] += 42.0;
    Handle trace = TR_TraceRayFilterEx(eye, spot, MASK_SHOT, RayType_EndPoint, World);
    bool visible = !TR_StartSolid(trace) && !TR_DidHit(trace);
    delete trace;
    return visible;
}

void NavName(const float pos[3], char[] name, int length)
{
    int area = NavMesh_GetNearestArea(pos, false, 110.0, false, true);
    if (area >= 0) NavMeshArea_GetPlaceCanonical(area, name, length);
    if (!name[0]) strcopy(name, length, "-");
}

int Lane(const float pos[3], int site)
{
    char name[32], lane[32];
    NavName(pos, name, sizeof(name));
    for (int i = 0; i < 3; i++)
        if (TacticalMap_GetWatchPlace(g_map, site, i, false, lane, sizeof(lane)) && StrEqual(name,lane,false)) return 1 << i;
    return 0;
}

public Action RecordPlan(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    SetupZones();
    g_roster = 0; g_ticks = 0;
    for (int site = 0; site < 2; site++) { g_liveInside[site] = 0; g_longest[site] = 0; g_tail[site] = 0; }
    int planned[2], inZone[2], lanes[2], aimOk[2], plantLos[2];
    g_round++;
    ServerCommand("sm_ct_tactics_status");
    ServerExecute();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client)
            || GetClientTeam(client) != CS_TEAM_CT) continue;
        float goal[3], aim[3];
        int route;
        if (g_roster >= sizeof(g_uid) || !BotCTTactics_GetOrder(client, goal, route)) continue;
        int row = g_roster++, site = SiteFor(goal, true), actualZone = InZone(goal);
        planned[site]++;
        for (int j = 0; j < 2; j++) if (CanSeePlant(goal,j)) plantLos[j]++;
        for (int j = 0; j < 2; j++) if (actualZone & (1 << j)) inZone[j]++;
        g_uid[row] = GetClientUserId(client); g_goal[row] = goal; g_role[row] = site;
        g_targetIn[row] = actualZone; g_radius[row] = BotCTTactics_GetHoldRadius(client);
        g_atGoal[row] = 0; g_clearaim[row] = 0; g_reassigned[row] = 0; g_nearest[row] = 999999.0;
        char place[32], watch[32] = "-";
        NavName(goal,place,sizeof(place));
        if (BotCTTactics_GetAim(client,aim) && ClearAim(goal,aim))
        {
            aimOk[site]++;
            aim[2] -= 64.0;
            watch[0] = '\0';
            NavName(aim,watch,sizeof(watch));
            lanes[site] |= Lane(aim,site);
        }
        PrintToServer("CT_SITE_PLAN map=%s round=%d slot=%d site=%s zone=%d goal=%.0f,%.0f,%.0f hold=%.0f place=%s aim=%s",
            g_mapName,g_round,row,site == 0 ? "A" : "B",actualZone,goal[0],goal[1],goal[2],g_radius[row],place,watch);
    }
    PrintToServer("CT_SITE_DISTRIBUTION map=%s round=%d calibration=%d orders=%d,%d aim_ok=%d,%d named_mask=%d,%d target_in=%d,%d",
        g_mapName,g_round,g_cal,planned[0],planned[1],aimOk[0],aimOk[1],lanes[0],lanes[1],inZone[0],inZone[1]);
    PrintToServer("CT_SITE_PLANT_LOS map=%s round=%d phase=planned visible=%d,%d",g_mapName,g_round,plantLos[0],plantLos[1]);
    CreateTimer(0.5, Observe, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Observe(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int occupied, plantLos[2];
    int samples = 2 * g_seconds.IntValue;
    for (int row = 0; row < g_roster; row++)
    {
        int client = GetClientOfUserId(g_uid[row]), route;
        if (client <= 0 || !IsPlayerAlive(client)) continue;
        float pos[3], current[3], aim[3];
        GetClientAbsOrigin(client,pos);
        float dist = GetVectorDistance(pos,g_goal[row]);
        if (dist < g_nearest[row]) g_nearest[row] = dist;
        if (!BotCTTactics_GetOrder(client,current,route) || GetVectorDistance(current,g_goal[row]) > 55.0) g_reassigned[row]++;
        if (dist <= g_radius[row] + 8.0)
        {
            g_atGoal[row]++;
            if (BotCTTactics_GetAim(client,aim,true) && ClearAim(pos,aim)) g_clearaim[row]++;
        }
        occupied |= InZone(pos);
        if (g_ticks == samples - 1)
        {
            float eye[3]; GetClientEyePosition(client,eye);
            for (int site = 0; site < 2; site++) if (CanSeePlant(pos,site,eye[2]-pos[2])) plantLos[site]++;
            char place[32]; NavName(pos,place,sizeof(place));
            PrintToServer("CT_SITE_ARRIVAL map=%s round=%d slot=%d site=%s target_in=%d final_in=%d nearest=%.0f final_dist=%.0f at=%d live_aim=%d order_changes=%d final=%.0f,%.0f,%.0f place=%s",
                g_mapName,g_round,row,g_role[row]==0?"A":"B",g_targetIn[row],InZone(pos),g_nearest[row],dist,g_atGoal[row],g_clearaim[row],g_reassigned[row],pos[0],pos[1],pos[2],place);
        }
    }
    for (int site = 0; site < 2; site++)
    {
        if (occupied & (1 << site)) { g_liveInside[site]++; g_tail[site]++; }
        else g_tail[site] = 0;
        if (g_tail[site] > g_longest[site]) g_longest[site] = g_tail[site];
    }
    if (++g_ticks < samples) return Plugin_Continue;
    PrintToServer("CT_SITE_OCCUPANCY map=%s round=%d samples=%d occupied=%d,%d longest=%d,%d final_mask=%d",
        g_mapName,g_round,g_ticks,g_liveInside[0],g_liveInside[1],g_longest[0],g_longest[1],occupied);
    PrintToServer("CT_SITE_PLANT_LOS map=%s round=%d phase=actual visible=%d,%d",g_mapName,g_round,plantLos[0],plantLos[1]);
    if (g_round < g_rounds.IntValue) Restart();
    else NextMap();
    return Plugin_Stop;
}

void NextMap()
{
    g_armed = false;
    char last[32], next[32];
    g_last.GetString(last,sizeof(last));
    if (!StrEqual(last,g_mapName,false) && TacticalMap_GetName(g_map+1,next,sizeof(next))) ServerCommand("changelevel %s",next);
    else PrintToServer("CT_SITE_SURVEY_DONE");
}
