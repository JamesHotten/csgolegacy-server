#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);

public Plugin myinfo = {name = "Isolated CT/T route recovery probe", version = "1.0"};
ConVar g_enable, g_team;
bool g_started, g_armed, g_moved;
int g_bot, g_frozenUserId, g_retries;
float g_goal[3], g_first[3], g_frozen[3], g_retryAt, g_start;
bool g_peerOrdered[MAXPLAYERS + 1];
float g_peerGoals[MAXPLAYERS + 1][3];
int g_peerChanges;

public void OnPluginStart()
{
    g_enable = CreateConVar("sm_ct_route_recovery_probe", "0", "Only on isolated loopback server.");
    g_team = CreateConVar("sm_route_recovery_probe_team", "3", "CT=3, T=2.", _, true, 2.0, true, 3.0);
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
}

bool Safe()
{
    if (!g_enable.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public void OnMapStart()
{
    g_started = g_armed = g_moved = false;
    g_bot = g_frozenUserId = g_retries = 0;
    g_peerChanges = 0;
    for (int i = 1; i <= MaxClients; i++) g_peerOrdered[i] = false;
    g_retryAt = 0.0;
    CreateTimer(7.0, Setup, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Setup(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 0; bot_dont_shoot 1; bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1");
    ServerExecute();
    for (int n = 0; n < 5; n++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    CreateTimer(5.0, EnsureRound, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action EnsureRound(Handle timer)
{
    if (g_started || !Safe()) return Plugin_Stop;
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void FreezeEnd(Event event, const char[] name, bool unused)
{
    if (!Safe() || !g_armed || g_started || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_started = true;
    CreateTimer(0.4, Begin, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Begin(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    float best;
    for (int i = 1; i <= MaxClients; i++)
    {
        int route;
        float goal[3], pos[3];
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != g_team.IntValue
            || !GetRecoveryOrder(i, goal, route)) continue;
        g_peerOrdered[i] = true;
        g_peerGoals[i] = goal;
        GetClientAbsOrigin(i, pos);
        float distance = GetVectorDistance(pos, goal);
        if (distance <= best) continue;
        best = distance;
        g_bot = i;
        g_goal = goal;
        g_first = goal;
        g_frozen = pos;
    }
    if (g_bot == 0 || best < 420.0) SetFailState("Missing distant tactical order for recovery fixture");
    g_frozenUserId = GetClientUserId(g_bot);
    g_start = GetGameTime();
    PrintToServer("ROUTE_RECOVERY_BEGIN team=%d client=%d distance=%.1f", g_team.IntValue, g_bot, best);
    CreateTimer(0.15, Observe, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Observe(Handle timer)
{
    if (!Safe()) { g_frozenUserId = 0; return Plugin_Stop; }
    int route;
    float goal[3], pos[3];
    bool hasOrder = GetRecoveryOrder(g_bot, goal, route);
    float now = GetGameTime();
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i == g_bot || !g_peerOrdered[i] || !GetRecoveryOrder(i, pos, route)) continue;
        if (GetVectorDistance(g_peerGoals[i], pos) <= 50.0) continue;
        g_peerChanges++;
        g_peerOrdered[i] = false;
    }
    if (hasOrder && GetVectorDistance(goal, g_goal) > 50.0)
    {
        g_retries++;
        g_goal = goal;
        g_retryAt = now;
        g_frozenUserId = 0;
    }
    GetClientAbsOrigin(g_bot, pos);
    if (GetVectorDistance(pos, g_frozen) >= 120.0) g_moved = true;
    float offset = GetVectorDistance(g_goal, g_first);
    if (g_retryAt > 0.0 && now - g_retryAt < 3.0) return Plugin_Continue;
    if (now - g_start < 9.0 && (!g_moved || g_retryAt <= 0.0)) return Plugin_Continue;
    PrintToServer("ROUTE_RECOVERY_%s team=%d retries=%d offset=%.1f moved=%d peer_changes=%d",
        g_retries == 1 && offset <= 310.0 && g_moved && g_peerChanges == 0 ? "PASS" : "FAIL",
        g_team.IntValue, g_retries, offset, g_moved, g_peerChanges);
    g_frozenUserId = 0;
    return Plugin_Stop;
}

bool GetRecoveryOrder(int client, float goal[3], int &route)
{
    return g_team.IntValue == CS_TEAM_CT ? BotCTTactics_GetOrder(client, goal, route) : BotTTactics_GetOrder(client, goal, route);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float velocity[3], float angles[3])
{
    if (client != g_bot || !g_frozenUserId || GetClientOfUserId(g_frozenUserId) != client || !Safe())
        return Plugin_Continue;
    float stop[3];
    TeleportEntity(client, g_frozen, NULL_VECTOR, stop);
    velocity[0] = velocity[1] = velocity[2] = 0.0;
    return Plugin_Changed;
}
