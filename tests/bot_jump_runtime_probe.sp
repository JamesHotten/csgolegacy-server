#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

public Plugin myinfo = {name = "BOT repeated jump fixture (isolated only)", version = "1.0"};
ConVar g_enable;
bool g_armed, g_live;
int g_bot, g_phase, g_jumps[3];
float g_started, g_origin[3];
float g_secondOrigin[3];
float g_lastNatural[MAXPLAYERS + 1], g_lastPosition[MAXPLAYERS + 1][3];
int g_nearCount[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_enable = CreateConVar("sm_bot_jump_runtime_probe", "0", "Run only on an empty isolated server.");
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("player_jump", Jumped, EventHookMode_Post);
}

public void OnMapStart() { CreateTimer(8.0, Setup, _, TIMER_FLAG_NO_MAPCHANGE); }

bool Safe()
{
    if (!g_enable.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++) if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Setup(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 0; bot_dont_shoot 1; mp_do_warmup_period 0; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_ignore_round_win_conditions 1; bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    CreateTimer(5.0, EnsureLive, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action EnsureLive(Handle timer)
{
    if (!Safe() || !g_armed) return Plugin_Stop;
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void FreezeEnd(Event event, const char[] name, bool unused)
{
    if (!Safe() || !g_armed || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    g_phase = 0;
    g_live = true;
    CreateTimer(18.0, BeginFixture, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action BeginFixture(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT) { g_bot = i; break; }
    if (g_bot == 0) SetFailState("No live test BOT");
    // A flat nearby lane outside CT spawn; the probe varies local jump and
    // path-progress inputs, never fakes the engine's player_jump event.
    g_origin[0] = 460.0; g_origin[1] = -1015.0; g_origin[2] = -771.0;
    g_secondOrigin = g_origin;
    g_secondOrigin[0] += 96.0;
    FindConVar("sm_bot_ct_tactics_enable").BoolValue = false;
    FindConVar("sm_bot_t_tactics_enable").BoolValue = false;
    float stopped[3];
    TeleportEntity(g_bot, g_origin, NULL_VECTOR, stopped);
    g_phase = 1;
    g_started = GetGameTime();
    PrintToServer("JUMP_FIXTURE_BEGIN bot=%d", g_bot);
    CreateTimer(5.4, MovingFixture, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action MovingFixture(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    g_phase = 2;
    g_started = GetGameTime();
    CreateTimer(3.5, Finish, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Finish(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    PrintToServer("JUMP_FIXTURE_%s stationary=%d progressing=%d", g_jumps[1] >= 3 && g_jumps[1] <= 4 && g_jumps[2] >= 4 ? "PASS" : "FAIL", g_jumps[1], g_jumps[2]);
    g_live = false;
    return Plugin_Stop;
}

public void Jumped(Event event, const char[] name, bool unused)
{
    if (!g_live || !Safe()) return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsFakeClient(client)) return;
    if (g_phase > 0)
    {
        if (client == g_bot) g_jumps[g_phase]++;
        return;
    }
    float point[3]; GetClientAbsOrigin(client, point);
    float now = GetGameTime();
    if (now - g_lastNatural[client] <= 1.5 && GetVectorDistance(point,g_lastPosition[client]) < 64.0) g_nearCount[client]++;
    else g_nearCount[client] = 1;
    if (g_nearCount[client] == 3)
        PrintToServer("JUMP_NATURAL_REPEAT bot=%d team=%d at %.0f %.0f %.0f",client,GetClientTeam(client),point[0],point[1],point[2]);
    g_lastNatural[client] = now;
    g_lastPosition[client] = point;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float velocity[3], float angles[3])
{
    if (!g_live || g_phase == 0 || client != g_bot || !Safe()) return Plugin_Continue;
    float elapsed = GetGameTime() - g_started;
    float cycle = elapsed - float(RoundToFloor(elapsed / 0.85)) * 0.85;
    buttons = cycle < 0.10 ? IN_JUMP : 0;
    velocity[0] = velocity[1] = 0.0;
    if (g_phase == 2)
    {
        // Advance the fixture one 96-unit mark between grounded attempts;
        // tests that distance progress re-enables ordinary jumping.
        static int lastStep = -1;
        int step = RoundToFloor(elapsed/0.85);
        if (step != lastStep)
        {
            lastStep = step;
            float pos[3], stopped[3]; pos = step % 2 == 0 ? g_origin : g_secondOrigin;
            TeleportEntity(client,pos,NULL_VECTOR,stopped);
        }
    }
    return Plugin_Changed;
}
