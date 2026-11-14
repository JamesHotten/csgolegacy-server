#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);

public Plugin myinfo = {name = "Isolated tactical stability fixture", version = "1.0"};
ConVar g_enable;
bool g_live;
int g_rounds, g_phases;
int g_previousTeam[MAXPLAYERS + 1], g_previousUserId[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_enable = CreateConVar("sm_tactical_stability_fixture", "0", "Run short match on an isolated CS:GO Legacy server only.");
    HookEvent("round_freeze_end", OnFreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("announce_phase_end", OnPhaseEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_live = false;
    g_rounds = g_phases = 0;
    CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool Safe()
{
    if (!g_enable.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_round_restart_delay 2; mp_halftime 1; mp_maxrounds 2; mp_overtime_enable 1; mp_overtime_maxrounds 2; mp_halftime_duration 2; mp_match_can_clinch 1; mp_ignore_round_win_conditions 0; mp_do_warmup_period 0; bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    g_live = true;
    return Plugin_Stop;
}

public void OnPhaseEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (Safe() && g_live) PrintToServer("TACTICAL_MATCH_PHASE count=%d completed=%d", ++g_phases, g_rounds);
}

public void OnFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!Safe() || !g_live) return;
    g_rounds++;
    CreateTimer(0.7, Inspect, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Inspect(Handle timer)
{
    if (!Safe() || !g_live) return Plugin_Stop;
    int ct, t, ordered;
    SenseTeams(ct, t, ordered);
    int swapped;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i)) continue;
        int team = GetClientTeam(i), user = GetClientUserId(i);
        if (g_previousUserId[i] == user && g_previousTeam[i] + team == CS_TEAM_CT + CS_TEAM_T && g_previousTeam[i] != team) swapped++;
        g_previousUserId[i] = user;
        g_previousTeam[i] = team;
    }
    PrintToServer("TACTICAL_MATCH_ROUND round=%d ct=%d t=%d orders=%d ct_score=%d t_score=%d swapped=%d warmup=%d", g_rounds, ct, t, ordered,
        CS_GetTeamScore(CS_TEAM_CT), CS_GetTeamScore(CS_TEAM_T), swapped, GameRules_GetProp("m_bWarmupPeriod"));
    if (ct != 5 || t != 5) SetFailState("Isolated match lost its 5v5 slots.");
    if (g_rounds == 4)
    {
        FindConVar("sm_bot_ct_tactics_enable").BoolValue = false;
        FindConVar("sm_bot_t_tactics_enable").BoolValue = false;
        SenseTeams(ct, t, ordered);
        if (ordered != 0) SetFailState("Disabled directors continued issuing orders.");
        PrintToServer("TACTICAL_MATCH_FALLBACK orders=%d phases=%d", ordered, g_phases);
        if (swapped != 10 || g_phases < 2) SetFailState("Overtime half switch was not observed.");
    }
    if (g_rounds >= 4)
    {
        g_live = false;
        return Plugin_Stop;
    }
    // Force regulation 1:1 and advance into the genuine overtime half switch.
    // The first winner switches to T for regulation round 2, so CT must
    // win both rounds to tie the two logical teams at 1:1.
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_T)
            ForcePlayerSuicide(i);
    return Plugin_Stop;
}

void SenseTeams(int &ct, int &t, int &ordered)
{
    ct = t = ordered = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i)) continue;
        float goal[3];
        int route;
        if (GetClientTeam(i) == CS_TEAM_CT)
        {
            ct++;
            if (BotCTTactics_GetOrder(i, goal, route)) ordered++;
        }
        else if (GetClientTeam(i) == CS_TEAM_T)
        {
            t++;
            if (BotTTactics_GetOrder(i, goal, route)) ordered++;
        }
    }
}
