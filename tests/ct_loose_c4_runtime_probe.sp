#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_ReportContact(int client, int enemy);
native bool BotStuff_CanSeeLooseC4(int client, int bomb);
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
    MarkNativeAsOptional("BotStuff_CanSeeLooseC4");
    return APLRes_Success;
}

// Explicitly invoked on an EMPTY test server; never installed automatically.
// Exercises the real director, event handlers and BetterBots perception bridge.
public Plugin myinfo = { name = "CT loose C4 regression probe", author = "server project", version = "1.0" };
int g_bots[MAXPLAYERS + 1], g_count, g_bombRef = INVALID_ENT_REFERENCE, g_stage, g_failures;
float g_positions[MAXPLAYERS + 1][3], g_angles[MAXPLAYERS + 1][3], g_bombPosition[3];
MoveType g_moveTypes[MAXPLAYERS + 1];
int g_savedUserId[MAXPLAYERS + 1];
bool g_running, g_faceBomb;
bool g_beforeHasOrder[MAXPLAYERS + 1];
float g_beforeGoal[MAXPLAYERS + 1][3];
ConVar g_settings[6];
ConVar g_auto;
bool g_autoPrepared;
float g_autoAfter;
int g_oldValues[6];
Handle g_nativeCanSeeLoose;

public void OnPluginStart()
{
    GameData data = new GameData("botstuff.games");
    if (data == null) SetFailState("Missing installed BOT gamedata");
    StartPrepSDKCall(SDKCall_Player);
    if (!PrepSDKCall_SetFromConf(data, SDKConf_Signature, "CCSBot::CanSeeLooseBomb"))
        SetFailState("No native loose C4 vision signature");
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
    g_nativeCanSeeLoose = EndPrepSDKCall();
    delete data;
    if (g_nativeCanSeeLoose == null) SetFailState("Cannot prepare native loose C4 vision");
    RegAdminCmd("sm_ct_guard_probe", StartProbe, ADMFLAG_ROOT);
    g_auto = CreateConVar("sm_ct_guard_probe_auto", "0", "Explicit empty-server regression probe autorun.");
    CreateTimer(1.0, AutoProbe, _, TIMER_REPEAT);
}

public Action AutoProbe(Handle timer)
{
    if (!g_auto.BoolValue) return Plugin_Continue;
    if (!g_autoPrepared)
    {
        // Never freeze a human's match, even if the test was misconfigured.
        for (int i = 1; i <= MaxClients; i++)
            if (IsClientInGame(i) && !IsFakeClient(i)) return Plugin_Stop;
        ServerCommand("bot_stop 1; bot_dont_shoot 1; mp_warmup_end; mp_restartgame 1");
        g_autoAfter = GetGameTime() + 20.0;
        g_autoPrepared = true;
    }
    if (GetGameTime() < g_autoAfter) return Plugin_Continue;
    StartProbe(0, 0);
    return g_running ? Plugin_Stop : Plugin_Continue;
}

public Action StartProbe(int client, int args)
{
    if (g_running) return Plugin_Handled;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            ReplyToCommand(client, "CT_GUARD_PROBE_REFUSED: humans connected");
            return Plugin_Handled;
        }
    g_count = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT)
            g_bots[g_count++] = i;
    if (g_count < 4 || GameRules_GetProp("m_bWarmupPeriod") != 0 || GameRules_GetProp("m_bFreezePeriod") != 0)
    {
        ReplyToCommand(client, "CT_GUARD_PROBE_REFUSED: need >=4 alive CTs in a live round");
        return Plugin_Handled;
    }
    g_settings[0] = FindConVar("bot_stop");
    g_settings[1] = FindConVar("bot_dont_shoot");
    g_settings[2] = FindConVar("mp_ignore_round_win_conditions");
    g_settings[3] = FindConVar("sm_bot_t_tactics_enable");
    g_settings[4] = FindConVar("sm_bot_ct_tactics_navigation_stall_timeout");
    g_settings[5] = FindConVar("sm_bot_experience_record_enable");
    for (int i = 0; i < sizeof(g_settings); i++)
    {
        if (g_settings[i] == null)
        {
            if (i == 5) continue; // Recorder is optional, just as in production.
            SetFailState("Missing probe setting %d", i);
        }
        g_oldValues[i] = g_settings[i].IntValue;
        g_settings[i].IntValue = (i == 3 || i == 5) ? 0 : (i == 4 ? 8 : 1);
    }
    g_running = true;
    g_failures = 0;
    g_stage = 0;
    g_faceBomb = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_savedUserId[i] = 0;
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        g_savedUserId[i] = GetClientUserId(i);
        GetClientAbsOrigin(i, g_positions[i]);
        GetClientEyeAngles(i, g_angles[i]);
        g_moveTypes[i] = GetEntityMoveType(i);
        SetEntityMoveType(i, MOVETYPE_NONE);
    }
    int spawn = FindEntityByClassname(-1, "info_player_counterterrorist");
    if (spawn == -1) SetFailState("No CT spawn for probe");
    GetEntPropVector(spawn, Prop_Data, "m_vecOrigin", g_bombPosition);
    g_bombPosition[0] += 100.0;
    g_bombPosition[2] += 10.0;
    // Cluster CTs in this clear local area and pin their view away from C4.
    for (int n = 0; n < g_count; n++)
    {
        float position[3];
        position[0] = g_bombPosition[0] - 100.0;
        position[1] = g_bombPosition[1] + float(n) * 35.0;
        position[2] = g_bombPosition[2] - 10.0;
        TeleportEntity(g_bots[n], position, NULL_VECTOR, NULL_VECTOR);
        AimProbeBot(g_bots[n]);
    }
    // Replays the real pre-drop combat-release pattern from the captured log.
    FireContact(g_bots[0]);
    for (int n = 0; n < g_count; n++)
    {
        int route;
        g_beforeHasOrder[n] = BotCTTactics_GetOrder(g_bots[n], g_beforeGoal[n], route);
    }
    int bomb = CreateEntityByName("weapon_c4");
    if (bomb == -1) SetFailState("Cannot create probe C4");
    DispatchSpawn(bomb);
    float hidden[3];
    hidden[0] = g_bombPosition[0] + 10000.0;
    hidden[1] = g_bombPosition[1];
    hidden[2] = g_bombPosition[2];
    TeleportEntity(bomb, hidden, NULL_VECTOR, NULL_VECTOR);
    SetEntityMoveType(bomb, MOVETYPE_NONE);
    g_bombRef = EntIndexToEntRef(bomb);
    Event dropped = CreateEvent("bomb_dropped");
    dropped.Fire();
    CreateTimer(0.8, CheckProbe);
    ReplyToCommand(client, "CT_GUARD_PROBE_STARTED ct=%d", g_count);
    return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
    if (!g_running || GetClientTeam(client) != CS_TEAM_CT) return Plugin_Continue;
    float eye[3], direction[3];
    GetClientEyePosition(client, eye);
    MakeVectorFromPoints(eye, g_bombPosition, direction);
    GetVectorAngles(direction, angles);
    if (!g_faceBomb) { angles[0] = 0.0; angles[1] += 180.0; }
    buttons = 0;
    vel[0] = vel[1] = vel[2] = 0.0;
    return Plugin_Changed;
}

void AimProbeBot(int client)
{
    float eye[3], direction[3], angles[3];
    GetClientEyePosition(client, eye);
    MakeVectorFromPoints(eye, g_bombPosition, direction);
    GetVectorAngles(direction, angles);
    if (!g_faceBomb) { angles[0] = 0.0; angles[1] += 180.0; }
    TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
    SetEntPropFloat(client, Prop_Send, "m_angEyeAngles[0]", angles[0]);
    SetEntPropFloat(client, Prop_Send, "m_angEyeAngles[1]", angles[1]);
}

public void OnGameFrame()
{
    if (!g_running) return;
    for (int n = 0; n < g_count; n++) AimProbeBot(g_bots[n]);
}

int CountGuards()
{
    int count;
    for (int n = 0; n < g_count; n++)
    {
        float goal[3]; int route;
        if (BotCTTactics_GetOrder(g_bots[n], goal, route) && GetVectorDistance(goal, g_bombPosition) <= 900.0)
            count++;
    }
    return count;
}

public Action CheckProbe(Handle timer)
{
    if (!g_running) return Plugin_Stop;
    if (g_stage == 0)
    {
        // C4 starts outside every CT's sight range, independent of native
        // AI turning the bots' heads despite pinned movement/input.
        bool unchanged = true;
        for (int n = 0; n < g_count; n++)
        {
            float goal[3]; int route;
            bool ordered = BotCTTactics_GetOrder(g_bots[n], goal, route);
            if (ordered != g_beforeHasOrder[n] || (ordered && GetVectorDistance(goal, g_beforeGoal[n]) > 1.0))
                unchanged = false;
        }
        Check("unseen_drop_does_not_replan", unchanged);
        // Reproduce the crash precursor without invoking the unsafe engine
        // consumer: a synthetic loose weapon is NOT the native manager's C4.
        // Native AI is stopped throughout this fixture. Never force it to
        // consume a positive result with a missing native-manager object.
        Check("native_loose_c4_false_not_promoted", !SDKCall(g_nativeCanSeeLoose, g_bots[0]));
        if (GetFeatureStatus(FeatureType_Native, "BotStuff_CanSeeLooseC4") == FeatureStatus_Available)
        {
            int seen;
            for (int n = 0; n < g_count; n++)
                if (BotStuff_CanSeeLooseC4(g_bots[n], EntRefToEntIndex(g_bombRef))) seen++;
            Check("out_of_sight_range", seen == 0);
        }
        TeleportEntity(EntRefToEntIndex(g_bombRef), g_bombPosition, NULL_VECTOR, NULL_VECTOR);
        g_faceBomb = true;
        for (int n = 0; n < g_count; n++) AimProbeBot(g_bots[n]);
        g_stage++;
        CreateTimer(3.3, CheckProbe);
    }
    else if (g_stage == 1)
    {
        int count = CountGuards();
        int bomb = EntRefToEntIndex(g_bombRef);
        float position[3];
        if (bomb != INVALID_ENT_REFERENCE) GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", position);
        PrintToServer("CT_GUARD_PROBE c4=%d at %.0f %.0f %.0f", bomb, position[0], position[1], position[2]);
        PrintToServer("CT_GUARD_PROBE guards=%d expected=%d", count, g_count);
        Check("all_alive_cts_include_previously_released_bot", count == g_count);
        CheckReinforcementPriority();
        FireContact(g_bots[0]);
        float goal[3]; int route;
        Check("combat_immediately_releases_position", !BotCTTactics_GetOrder(g_bots[0], goal, route));
        g_stage++;
        CreateTimer(1.6, CheckProbe);
    }
    else if (g_stage == 2)
    {
        FireContact(g_bots[0]); // Further shots after the order was released.
        g_stage++;
        CreateTimer(1.2, CheckProbe);
    }
    else if (g_stage == 3)
    {
        float goal[3]; int route;
        Check("repeated_combat_extends_quiet_window", !BotCTTactics_GetOrder(g_bots[0], goal, route));
        g_stage++;
        CreateTimer(1.8, CheckProbe);
    }
    else if (g_stage == 4)
    {
        Check("quiet_bot_rejoins_guard", CountGuards() == g_count);
        int bomb = EntRefToEntIndex(g_bombRef);
        if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
        g_bombRef = INVALID_ENT_REFERENCE;
        g_stage++;
        CreateTimer(0.8, CheckProbe);
    }
    else
    {
        Check("missing_c4_clears_guard_orders", CountGuards() == 0);
        PrintToServer("CT_GUARD_PROBE_%s failures=%d", g_failures == 0 ? "PASS" : "FAIL", g_failures);
        Cleanup();
    }
    return Plugin_Stop;
}

void CheckReinforcementPriority()
{
    int enemy;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T) { enemy = i; break; }
    if (enemy == 0) { Check("site_contact_preserves_other_guard_goals", false); return; }
    float before[MAXPLAYERS + 1][3], original[3], site[3];
    for (int n = 0; n < g_count; n++)
    {
        int route;
        BotCTTactics_GetOrder(g_bots[n], before[n], route);
    }
    GetClientAbsOrigin(enemy, original);
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", site);
    TeleportEntity(enemy, site, NULL_VECTOR, NULL_VECTOR);
    BotCTTactics_ReportContact(g_bots[1], enemy);
    TeleportEntity(enemy, original, NULL_VECTOR, NULL_VECTOR);
    bool preserved = true;
    for (int n = 0; n < g_count; n++)
    {
        if (n == 1) continue; // Spotter must yield to combat immediately.
        float goal[3]; int route;
        if (!BotCTTactics_GetOrder(g_bots[n], goal, route) || GetVectorDistance(before[n], goal) > 1.0)
            preserved = false;
    }
    Check("site_contact_preserves_other_guard_goals", preserved);
}

void Check(const char[] name, bool success)
{
    PrintToServer("CT_GUARD_PROBE %s %s", name, success ? "PASS" : "FAIL");
    if (!success) g_failures++;
}

void FireContact(int client)
{
    Event fired = CreateEvent("weapon_fire");
    fired.SetInt("userid", GetClientUserId(client));
    fired.SetString("weapon", "ak47");
    fired.Fire();
}

void Cleanup()
{
    if (!g_running) return;
    g_running = false;
    int bomb = EntRefToEntIndex(g_bombRef);
    if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
    g_bombRef = INVALID_ENT_REFERENCE;
    for (int i = 0; i < sizeof(g_settings); i++)
        if (g_settings[i] != null) g_settings[i].IntValue = g_oldValues[i];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientUserId(i) != g_savedUserId[i]) continue;
        SetEntityMoveType(i, g_moveTypes[i]);
        TeleportEntity(i, g_positions[i], g_angles[i], NULL_VECTOR);
    }
}
public void OnPluginEnd() { Cleanup(); }
public void OnClientPutInServer(int client)
{
    if (g_running && !IsFakeClient(client))
    {
        PrintToServer("CT_GUARD_PROBE_ABORT: human joined");
        Cleanup();
    }
}
