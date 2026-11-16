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
native bool BotCTTactics_ReportContact(int spotter, int enemy);

public Plugin myinfo = {name = "CT map-specific round probe (loopback)", version = "1.0"};

bool g_armed, g_before[MAXPLAYERS + 1];
float g_home[MAXPLAYERS + 1][3], g_a[3], g_b[3];
int g_map, g_aGuard, g_bGuard, g_runner, g_replacement;
char g_name[32], g_case[48];

public void OnPluginStart()
{
    GetCommandLineParam("-ctrefinefixture", g_case, sizeof(g_case));
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
}

bool Safe()
{
    char ip[32];
    GetCommandLineParam("-ip", ip, sizeof(ip));
    if (!g_case[0] || !StrEqual(ip, "127.0.0.1")) return false;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client)) return false;
    return true;
}

public void OnMapStart()
{
    GetCurrentMap(g_name, sizeof(g_name));
    g_map = TacticalMap_Find(g_name);
    if (g_map == 2 || g_map == 3 || g_map == 5)
    {
        TacticalMap_PlantGround(g_map, 0, g_a);
        TacticalMap_PlantGround(g_map, 1, g_b);
        CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 3; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1; sm_bot_t_tactics_enable 0; sm_bot_ct_tactics_debug 1; mp_warmup_end; mp_restartgame 1");
    g_armed = true;
    return Plugin_Stop;
}

public void FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_armed || !Safe() || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    CreateTimer(0.35, Check, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool IsSide(int client, int side)
{
    return client > 0 && IsClientInGame(client) && IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == side;
}

int Site(const float point[3])
{
    return GetVectorDistance(point, g_a) <= GetVectorDistance(point, g_b) ? 0 : 1;
}

public Action Check(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int orders, noncarrier, attackers, route;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSide(client, CS_TEAM_T))
        {
            attackers++;
            if (!noncarrier && GetPlayerWeaponSlot(client, CS_SLOT_C4) == -1) noncarrier = client;
        }
        if (!IsSide(client, CS_TEAM_CT) || !BotCTTactics_GetOrder(client, g_home[client], route)) continue;
        g_before[client] = true;
        orders++;
        if (BotCTTactics_GetHoldRadius(client) > 25.0) continue;
        if (Site(g_home[client]) == 0) g_aGuard = client;
        else g_bGuard = client;
    }
    PrintToServer("REFINE_SETUP map=%s ct_orders=%d t=%d a=%d b=%d", g_name, orders, attackers, g_aGuard, g_bGuard);
    if (orders != 5 || attackers != 5 || !g_aGuard || !g_bGuard || !noncarrier) { Done(false); return Plugin_Stop; }
    if (g_map == 3 || g_map == 5)
        for (int client = 1; client <= MaxClients; client++)
            if (g_before[client]) TeleportEntity(client, g_home[client], NULL_VECTOR, NULL_VECTOR);
    if (g_map == 5)
    {
        TeleportEntity(noncarrier, g_b, NULL_VECTOR, NULL_VECTOR);
        bool acknowledged = BotCTTactics_ReportContact(g_bGuard, noncarrier);
        int moved, preserved;
        float point[3], aim[3];
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!g_before[client] || !BotCTTactics_GetOrder(client, point, route)) continue;
            if (client == g_aGuard && GetVectorDistance(point, g_home[client]) < 2.0) preserved++;
            if (GetVectorDistance(point, g_home[client]) < 30.0) continue;
            if (Site(point) == 1 && FloatAbs(point[2] - g_b[2]) <= 95.0
                && BotCTTactics_GetAim(client, aim)) moved++;
        }
        PrintToServer("REFINE_RELIEF changed=%d weak_anchor=%d contact=%d", moved, preserved, acknowledged);
        Done(moved == 1 && preserved == 1);
    }
    else if (g_map == 2)
    {
        // Test actual common fire, not whether two defenders can expose their
        // bodies to one another through the cover between them.
        for (int client = 1; client <= MaxClients; client++)
            if (g_before[client]) TeleportEntity(client, g_home[client], NULL_VECTOR, NULL_VECTOR);
        int links, responder;
        for (int site = 0; site < 2; site++)
        {
            int anchor = site == 0 ? g_aGuard : g_bGuard;
            float anchorEye[3]; GetClientEyePosition(anchor, anchorEye);
            for (int client = 1; client <= MaxClients; client++)
            {
                if (!g_before[client] || client == g_aGuard || client == g_bGuard || Site(g_home[client]) != site) continue;
                float distance = GetVectorDistance(g_home[client], g_home[anchor]);
                if (distance < 145.0 || distance > 570.0 || FloatAbs(g_home[client][2]-g_home[anchor][2]) > 80.0) continue;
                float point[3], eye[3]; GetClientEyePosition(client, eye);
                if (!CommonSector(site, anchorEye, eye, point)) continue;
                links++;
                if (responder) continue;
                TeleportEntity(noncarrier, point, NULL_VECTOR, NULL_VECTOR);
                BotCTTactics_ReportContact(anchor, noncarrier);
                float expected[3], result[3];
                GetClientAbsOrigin(noncarrier, expected); expected[2] += 54.0;
                if (BotCTTactics_GetAim(client, result, true) && GetVectorDistance(result, expected) < 1.0)
                    responder = client;
            }
        }
        PrintToServer("REFINE_CROSSFIRE links=%d partner_responded=%d", links, responder > 0);
        Done(links >= 1 && responder > 0);
    }
    else
    {
        ForcePlayerSuicide(g_bGuard);
        float goal[3];
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!g_before[client] || !BotCTTactics_GetOrder(client, goal, route)) continue;
            if (client != g_aGuard && Site(g_home[client]) == 0) g_runner = client;
            if (GetVectorDistance(goal, g_home[g_bGuard]) < 2.0 && BotCTTactics_GetHoldRadius(client) <= 25.0)
                g_replacement = client;
        }
        bool same = BotCTTactics_GetOrder(g_aGuard, goal, route) && GetVectorDistance(goal, g_home[g_aGuard]) < 2.0;
        PrintToServer("REFINE_NUKE_REPLACEMENT filled=%d upper_kept=%d", g_replacement > 0, same);
        if (!g_runner) { Done(false); return Plugin_Stop; }
        float blocked[3] = {1160.0, -447.0, -410.0};
        TeleportEntity(g_runner, blocked, NULL_VECTOR, NULL_VECTOR);
        SDKHooks_TakeDamage(g_runner, 0, 0, 8.0, DMG_FALL, -1, NULL_VECTOR, NULL_VECTOR, false);
        CreateTimer(0.35, SecondFall, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Stop;
}

public bool World(int ent, int mask, any ignored) { return ent == 0 || ent > MaxClients; }

bool Shot(const float from[3], const float to[3])
{
    Handle ray = TR_TraceRayFilterEx(from, to, MASK_SHOT, RayType_EndPoint, World);
    bool clear = !TR_StartSolid(ray) && !TR_DidHit(ray);
    delete ray;
    return clear;
}

bool CommonSector(int site, const float a[3], const float b[3], float foot[3])
{
    for (int n = 0; n < 9; n++)
    {
        TacticalMap_PlantGround(g_map, site, foot);
        if (n > 0) { foot[0] += 112.0 * Cosine(float(n-1) * 0.78539816); foot[1] += 112.0 * Sine(float(n-1) * 0.78539816); }
        float point[3]; point = foot; point[2] += 54.0;
        if (GetVectorDistance(b, point) > 135.0 && Shot(a, point) && Shot(b, point)) return true;
    }
    return false;
}

public Action SecondFall(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    SDKHooks_TakeDamage(g_runner, 0, 0, 8.0, DMG_FALL, -1, NULL_VECTOR, NULL_VECTOR, false);
    float waypoint[3]; int route;
    bool detour = BotCTTactics_GetOrder(g_runner, waypoint, route) && GetVectorDistance(waypoint, g_home[g_runner]) > 100.0;
    PrintToServer("REFINE_NUKE_WAYPOINT issued=%d", detour);
    if (!detour) { Done(false); return Plugin_Stop; }
    // Deterministic arrival handoff. Live A/B runs separately exercise actual
    // movement; this isolates whether the original role is preserved.
    TeleportEntity(g_runner, waypoint, NULL_VECTOR, NULL_VECTOR);
    CreateTimer(0.85, Resumed, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Resumed(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    float goal[3]; int route;
    bool home = BotCTTactics_GetOrder(g_runner, goal, route) && GetVectorDistance(goal, g_home[g_runner]) < 2.0;
    PrintToServer("REFINE_NUKE_RESUME original=%d", home);
    Done(home && g_replacement > 0);
    return Plugin_Stop;
}

void Done(bool pass)
{
    PrintToServer("REFINE_%s map=%s case=%s", pass ? "PASS" : "FAIL", g_name, g_case);
    ServerCommand("quit");
}
