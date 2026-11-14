#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_ShouldHoldStage(int client);

// Empty loopback test only. Never installed by the deployment script.
public Plugin myinfo = {name = "Tactical execution runtime probe", author = "server project", version = "1.0"};
ConVar g_auto;
ConVar g_guardOnly;
ConVar g_retakeClock;
int g_case, g_failures, g_bombRef = INVALID_ENT_REFERENCE;
bool g_armed;
float g_start[MAXPLAYERS + 1][3], g_goals[MAXPLAYERS + 1][3];
bool g_ordered[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_auto = CreateConVar("sm_tactical_execution_probe", "0", "Explicit isolated-server test.");
    g_guardOnly = CreateConVar("sm_tactical_execution_guard_only", "0", "Prepare a live 5v5 for the isolated loose C4 probe.");
    g_retakeClock = CreateConVar("sm_tactical_execution_retake_clock", "0", "1=urgent bomb; 2=normal clock with vertically separated defenders.", _, true, 0.0, true, 2.0);
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart() { CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE); }

bool Safe()
{
    if (!g_auto.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

bool AliveBot(int client, int team)
{
    return IsClientInGame(client) && IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == team;
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    PrepareBots();
    if (g_guardOnly.BoolValue) ServerCommand("sm_ct_guard_probe_auto 1");
    else
    {
        g_case = g_retakeClock.IntValue == 0 ? 0 : 2;
        g_armed = true;
    }
    return Plugin_Stop;
}

void PrepareBots()
{
    ServerCommand("sv_cheats 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_roundtime_defuse 1.92; mp_ignore_round_win_conditions 1");
    ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    ServerCommand("mp_warmup_end; mp_restartgame 1");
}

public void FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_armed || !Safe()) return;
    g_armed = false;
    RequestFrame(Begin);
}

void SetRolls(int index)
{
    char tiers[][] = {"eco", "force", "full"};
    char name[64];
    for (int i = 0; i < sizeof(tiers); i++)
    {
        Format(name, sizeof(name), "sm_bot_ct_tactics_%s_push_chance", tiers[i]);
        FindConVar(name).IntValue = index == 1 ? 100 : 0;
        Format(name, sizeof(name), "sm_bot_ct_tactics_%s_stack_chance", tiers[i]);
        FindConVar(name).IntValue = index == 2 ? 100 : 0;
        Format(name, sizeof(name), "sm_bot_t_%s_rush_chance", tiers[i]);
        FindConVar(name).IntValue = index == 1 ? 100 : 0;
        Format(name, sizeof(name), "sm_bot_t_%s_split_chance", tiers[i]);
        FindConVar(name).IntValue = index == 2 ? 100 : 0;
    }
}

public void Begin(any unused)
{
    if (!Safe()) return;
    FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    FindConVar("sm_bot_t_tactics_debug").BoolValue = true;
    // Exercise the actual non-pistol selectors, not the pistol override.
    GameRules_SetProp("m_totalRoundsPlayed", 1);
    SetRolls(g_case);
    PrintToServer("EXEC_CASE_BEGIN %d", g_case);
    ServerCommand("sm_ct_tactics_replan; sm_t_tactics_replan; sm_ct_tactics_status; sm_t_tactics_status");
    ServerExecute();
    int ct, t, carrier;
    for (int i = 1; i <= MaxClients; i++)
    {
        float goal[3];
        int route;
        if (BotCTTactics_GetOrder(i, goal, route) && route == 1) ct++;
        g_ordered[i] = BotTTactics_ShouldHoldStage(i) && BotTTactics_GetOrder(i, g_goals[i], route);
        if (!g_ordered[i]) continue;
        t++;
        GetClientAbsOrigin(i, g_start[i]);
        if (GetPlayerWeaponSlot(i, CS_SLOT_C4) > MaxClients) carrier = i;
    }
    if (ct != 5 || t != 5 || carrier == 0) g_failures++;
    PrintToServer("EXEC_OPENING case=%d ct_orders=%d t_stage=%d carrier=%d", g_case, ct, t, carrier > 0);
    CreateTimer(3.2, Travel, carrier > 0 ? GetClientUserId(carrier) : 0, TIMER_FLAG_NO_MAPCHANGE);
}

void FireContact(int client)
{
    Event event = CreateEvent("weapon_fire");
    event.SetInt("userid", GetClientUserId(client));
    event.SetString("weapon", "weapon_ak47");
    event.Fire();
}

public Action Travel(Handle timer, any userId)
{
    if (!Safe()) return Plugin_Stop;
    int moving;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!g_ordered[i] || !AliveBot(i, CS_TEAM_T)) continue;
        float position[3];
        GetClientAbsOrigin(i, position);
        if (GetVectorDistance(g_start[i], position) >= 64.0) moving++;
    }
    int carrier = GetClientOfUserId(userId);
    bool stage = carrier > 0 && BotTTactics_ShouldHoldStage(carrier);
    if (moving < 3 || carrier == 0) g_failures++;
    PrintToServer("EXEC_TRAVEL case=%d moved=%d still_staging=%d", g_case, moving, stage);
    if (stage) FireContact(carrier);
    CreateTimer(0.8, Committed, userId, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Committed(Handle timer, any userId)
{
    if (!Safe()) return Plugin_Stop;
    int carrier = GetClientOfUserId(userId), route;
    float goal[3], a[3], b[3];
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", a);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", b);
    bool commit = carrier > 0 && !BotTTactics_ShouldHoldStage(carrier) && BotTTactics_GetOrder(carrier, goal, route)
        && route == 1 && (GetVectorDistance(goal, a) < 285.0 || GetVectorDistance(goal, b) < 285.0);
    if (!commit) g_failures++;
    PrintToServer("EXEC_COMMIT case=%d carrier_to_site=%d", g_case, commit);
    if (++g_case < 3)
    {
        g_armed = true;
        ServerCommand("mp_restartgame 1");
    }
    else
    {
        int bomb = CreateEntityByName("planted_c4");
        if (bomb == -1) SetFailState("No planted C4 entity");
        DispatchSpawn(bomb);
        TeleportEntity(bomb, a, NULL_VECTOR, NULL_VECTOR);
        if (g_retakeClock.IntValue != 0)
        {
            SetEntProp(bomb, Prop_Send, "m_bBombTicking", 1);
            SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + (g_retakeClock.IntValue == 1 ? 18.0 : 40.0));
        }
        g_bombRef = EntIndexToEntRef(bomb);
        Event event = CreateEvent("bomb_planted");
        if (carrier > 0) event.SetInt("userid", GetClientUserId(carrier));
        event.Fire();
        CreateTimer(0.4, RetakeStage, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Stop;
}

int CountCTRoute(int expected, int &sample)
{
    int count;
    for (int i = 1; i <= MaxClients; i++)
    {
        float goal[3];
        int route;
        if (BotCTTactics_GetOrder(i, goal, route) && route == expected) { count++; sample = i; }
    }
    return count;
}

public Action RetakeStage(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int sample;
    int count = CountCTRoute(2, sample);
    if (g_retakeClock.IntValue == 1)
    {
        int committed = CountCTRoute(1, sample);
        PrintToServer("EXEC_RETAKE_URGENT_%s staged=%d committed=%d",
            count == 0 && committed == 5 ? "PASS" : "FAIL", count, committed);
        FinishBomb();
        return Plugin_Stop;
    }
    if (g_retakeClock.IntValue == 2)
    {
        FindConVar("sm_bot_ct_tactics_retake_stage").FloatValue = 0.5;
        FindConVar("sm_bot_ct_tactics_retake_stage_timeout").FloatValue = 12.0;
        FindConVar("sm_bot_ct_tactics_sync_min_ready").IntValue = 50;
        FindConVar("bot_stop").BoolValue = true;
        for (int i = 1; i <= MaxClients; i++)
        {
            float goal[3];
            int route;
            if (!BotCTTactics_GetOrder(i, goal, route)) continue;
            goal[2] += 300.0;
            SetEntityMoveType(i, MOVETYPE_NONE);
            TeleportEntity(i, goal, NULL_VECTOR, NULL_VECTOR);
        }
        CreateTimer(1.2, CheckVertical, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    if (count < 4) g_failures++;
    PrintToServer("EXEC_RETAKE_STAGE safest_orders=%d", count);
    ServerCommand("sm_ct_tactics_status");
    if (sample > 0) FireContact(sample);
    CreateTimer(0.8, RetakeCommit, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action CheckVertical(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int sample;
    int staged = CountCTRoute(2, sample), committed = CountCTRoute(1, sample);
    PrintToServer("EXEC_RETAKE_VERTICAL_%s staged=%d committed=%d",
        staged == 5 && committed == 0 ? "PASS" : "FAIL", staged, committed);
    FinishBomb();
    return Plugin_Stop;
}

void FinishBomb()
{
    int bomb = EntRefToEntIndex(g_bombRef);
    if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
}

public Action RetakeCommit(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int sample;
    int count = CountCTRoute(1, sample);
    if (count < 3) g_failures++;
    PrintToServer("EXEC_RETAKE_COMMIT fastest_orders=%d", count);
    ServerCommand("sm_ct_tactics_status");
    bool released;
    if (sample > 0)
    {
        Event event = CreateEvent("bomb_begindefuse");
        event.SetInt("userid", GetClientUserId(sample));
        event.Fire();
        float goal[3];
        int route;
        released = !BotCTTactics_GetOrder(sample, goal, route);
    }
    if (!released) g_failures++;
    PrintToServer("EXEC_RETAKE_DEFUSE_RELEASE released=%d", released);
    FinishBomb();
    PrintToServer("TACTICAL_EXEC_%s failures=%d", g_failures == 0 ? "PASS" : "FAIL", g_failures);
    return Plugin_Stop;
}
