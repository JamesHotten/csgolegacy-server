#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <commandline>
#include "../mods/include/bot_tactical_map_profiles.inc"

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float aim[3], bool live = false);
native float BotCTTactics_GetHoldRadius(int client);
native bool BotCTTactics_ReportContact(int spotter, int enemy);

public Plugin myinfo = {name="Legacy CT teamwork contact fixture (loopback)", version="1.0"};
char g_maps[10][32], g_map[32];
int g_count, g_index, g_mapProfile, g_site;
bool g_enabled, g_armed;

public void OnPluginStart()
{
    char ip[32], maps[256];
    GetCommandLineParam("-ip", ip, sizeof(ip));
    GetCommandLineParam("-auditmaps", maps, sizeof(maps));
    g_enabled = StrEqual(ip, "127.0.0.1") && maps[0] != '\0';
    g_count = ExplodeString(maps, ",", g_maps, sizeof(g_maps), sizeof(g_maps[]));
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
}

bool Safe()
{
    if (!g_enabled) return false;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client)) return false;
    return true;
}

public void OnMapStart()
{
    g_site = 0;
    g_armed = false;
    GetCurrentMap(g_map, sizeof(g_map));
    g_mapProfile = TacticalMap_Find(g_map);
    if (g_enabled && (g_mapProfile < 0 || g_index >= g_count || !StrEqual(g_map, g_maps[g_index])))
        SetFailState("Unexpected teamwork fixture map");
    if (g_enabled) CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1; sm_bot_t_tactics_enable 0; sm_bot_ct_tactics_debug 1; bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int k = 0; k < 5; k++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    Restart();
    return Plugin_Stop;
}

void Restart()
{
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
}

public void FreezeEnd(Event event, const char[] name, bool silent)
{
    if (!g_armed || !Safe() || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    CreateTimer(0.35, Probe, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool OnTeam(int client, int team)
{
    return IsClientInGame(client) && IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == team;
}

public Action Probe(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    // A map change can still bring the automatic warmup restart up against
    // the test's restart timer. Publish the real opening plan in this frame,
    // after the roster is ready, so the controlled contact sees live orders.
    ServerCommand("sm_ct_tactics_replan");
    ServerExecute();
    float center[3], reserve[3], original[MAXPLAYERS + 1][3];
    bool hadOrder[MAXPLAYERS + 1];
    TacticalMap_PlantGround(g_mapProfile, g_site, center);
    TacticalMap_PlantGround(g_mapProfile, 1 - g_site, reserve);
    int orders, route, spotter, enemy, weakAnchor;
    float nearest = 99999.0, weakNearest = 99999.0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (OnTeam(client, CS_TEAM_T) && !enemy && GetPlayerWeaponSlot(client, CS_SLOT_C4) == -1) enemy = client;
        if (!OnTeam(client, CS_TEAM_CT) || !BotCTTactics_GetOrder(client, original[client], route)) continue;
        hadOrder[client] = true;
        orders++;
        float near = GetVectorDistance(original[client], center), other = GetVectorDistance(original[client], reserve);
        if (near < other && near < nearest) { nearest = near; spotter = client; }
        if (other < near && other < weakNearest) { weakNearest = other; weakAnchor = client; }
    }
    if (orders != 5 || !spotter || !weakAnchor || !enemy || nearest > 850.0 || weakNearest > 850.0)
    {
        PrintToServer("TEAMWORK_INVALID map=%s site=%d orders=%d spotter=%d enemy=%d weak=%d", g_map, g_site, orders, spotter, enemy, weakAnchor);
        ServerCommand("quit");
        return Plugin_Stop;
    }
    // Snapshot an established formation, then feed exactly one non-carrier
    // contact through the real CT report native; no shots or fake kill stats.
    for (int client = 1; client <= MaxClients; client++)
        if (hadOrder[client]) TeleportEntity(client, original[client], NULL_VECTOR, NULL_VECTOR);
    TeleportEntity(enemy, center, NULL_VECTOR, NULL_VECTOR);
    bool reported = BotCTTactics_ReportContact(spotter, enemy);
    int moved, valid, weakKept;
    float goal[3], aim[3];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!hadOrder[client] || !BotCTTactics_GetOrder(client, goal, route)) continue;
        float difference = GetVectorDistance(goal, original[client]);
        if (client == weakAnchor && difference < 2.0) weakKept++;
        if (difference < 30.0) continue;
        moved++;
        if (GetVectorDistance(goal, center) < GetVectorDistance(goal, reserve) && FloatAbs(goal[2] - center[2]) <= 96.0
            && BotCTTactics_GetAim(client, aim) && Clear(goal, aim)) valid++;
    }
    PrintToServer("TEAMWORK_CONTACT map=%s site=%d reported=%d moved=%d valid=%d weak_kept=%d", g_map, g_site, reported, moved, valid, weakKept);
    if (++g_site < 2) Restart();
    else if (++g_index < g_count) ForceChangeLevel(g_maps[g_index], "CT contact coverage matrix");
    else { PrintToServer("TEAMWORK_SUITE_DONE maps=%d", g_count); ServerCommand("quit"); }
    return Plugin_Stop;
}

public bool World(int entity, int mask, any unused) { return entity == 0 || entity > MaxClients; }

bool Clear(const float foot[3], const float aim[3])
{
    float eye[3]; eye = foot; eye[2] += 64.0;
    Handle ray = TR_TraceRayFilterEx(eye, aim, MASK_SHOT, RayType_EndPoint, World);
    bool clear = !TR_StartSolid(ray) && !TR_DidHit(ray);
    delete ray;
    return clear;
}
