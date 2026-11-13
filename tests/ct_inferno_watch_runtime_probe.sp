#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3]);
native int NavMesh_GetNearestArea(const float position[3], bool anyZ=false, float maxDist=10000.0,
    bool checkLOS=false, bool checkGround=true, int team=-2);
native void NavMeshArea_GetPlaceCanonical(int area, char[] place, int length);

public Plugin myinfo = {name = "Inferno CT watch regression probe", author = "server project", version = "1.0"};
ConVar g_enabled, g_verifyArrival, g_trials;
bool g_armed, g_done, g_addedBots;
int g_finishedTrials, g_failedTrials;
float g_measureStarted, g_steadySince;
int g_arrivalSamples, g_arrivalBlocked, g_facingSamples[MAXPLAYERS + 1], g_alignedSamples[MAXPLAYERS + 1];
float g_nextTravelSample;

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_inferno_watch_probe", "0", "Run only on the isolated Inferno test server.");
    g_verifyArrival = CreateConVar("sm_inferno_watch_probe_arrival", "0", "Measure actual arrival and facing with the BetterBots bridge loaded.");
    g_trials = CreateConVar("sm_inferno_watch_probe_trials", "1", "Number of independent round starts to measure.", _, true, 1.0, true, 20.0);
    HookEvent("round_freeze_end", OnFreezeEnd, EventHookMode_PostNoCopy);
    CreateTimer(1.0, Prepare, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool HasHuman()
{
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client)) return true;
    return false;
}

public Action Prepare(Handle timer)
{
    if (!g_enabled.BoolValue || GetGameTime() < 8.0) return Plugin_Continue;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    if (!StrEqual(map, "de_inferno") || HasHuman()) return Plugin_Stop;
    if (!g_addedBots)
    {
        g_addedBots = true;
        ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick; mp_autoteambalance 0; mp_limitteams 0");
        ServerExecute();
        for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
        return Plugin_Continue;
    }
    int ct, t;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client)) continue;
        if (GetClientTeam(client) == CS_TEAM_CT) ct++;
        else if (GetClientTeam(client) == CS_TEAM_T) t++;
    }
    if (ct != 5 || t != 5)
    {
        if (GetGameTime() > 25.0)
        {
            PrintToServer("INFERNO_WATCH_SETUP_FAIL ct=%d t=%d", ct, t);
            return Plugin_Stop;
        }
        return Plugin_Continue;
    }
    FindConVar("bot_dont_shoot").BoolValue = true;
    FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    FindConVar("mp_freezetime").IntValue = 3;
    if (g_verifyArrival.BoolValue) FindConVar("mp_ignore_round_win_conditions").BoolValue = true;
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Stop;
}

public void OnFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_armed && !g_done) RequestFrame(MeasureOrders);
}

public bool TraceWorldOnly(int entity, int mask, any data)
{
    return entity > MaxClients;
}

public void MeasureOrders(any unused)
{
    if (g_done || HasHuman()) return;
    g_done = true;
    g_steadySince = 0.0;
    g_nextTravelSample = 0.0;
    g_arrivalSamples = 0;
    g_arrivalBlocked = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_facingSamples[client] = 0;
        g_alignedSamples[client] = 0;
    }
    int orders, blocked;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_CT)
            continue;
        float goal[3], look[3], eye[3];
        int route;
        if (!BotCTTactics_GetOrder(client, goal, route) || !BotCTTactics_GetAim(client, look)) continue;
        orders++;
        eye = goal;
        eye[2] += 64.0;
        Handle trace = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint, TraceWorldOnly);
        float fraction = TR_GetFraction(trace);
        bool solid = TR_StartSolid(trace);
        delete trace;
        float clear = GetVectorDistance(eye, look) * fraction;
        char place[32];
        NavMeshArea_GetPlaceCanonical(NavMesh_GetNearestArea(goal, true, 160.0, false, false, -2), place, sizeof(place));
        // A valid fixed hold must have enough clear line before the target;
        // a ray into a near wall or a partially occluded distant point fails.
        bool bad = solid || fraction < 0.90 || clear < 128.0;
        if (bad) blocked++;
        PrintToServer("INFERNO_WATCH_ORDER %N place=%s goal=%.1f %.1f %.1f aim=%.1f %.1f %.1f clear=%.1f fraction=%.3f solid=%d %s",
            client, place, goal[0], goal[1], goal[2], look[0], look[1], look[2], clear, fraction, solid, bad ? "BLOCKED" : "VISIBLE");
    }
    PrintToServer("INFERNO_WATCH_%s orders=%d blocked=%d", orders == 5 && blocked == 0 ? "PASS" : "FAIL", orders, blocked);
    if (orders != 5 || blocked != 0)
    {
        FinishTrial(false);
        return;
    }
    if (g_verifyArrival.BoolValue)
    {
        // Isolate path/hold behavior from legitimate combat releases.
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T) continue;
            int c4 = GetPlayerWeaponSlot(client, CS_SLOT_C4);
            if (c4 > MaxClients)
            {
                RemovePlayerItem(client, c4);
                RemoveEntity(c4);
            }
            ForcePlayerSuicide(client);
        }
        g_measureStarted = GetGameTime();
        CreateTimer(0.25, MeasureArrival, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    else FinishTrial(true);
}

void FinishTrial(bool passed)
{
    g_finishedTrials++;
    if (!passed) g_failedTrials++;
    if (g_finishedTrials >= g_trials.IntValue)
    {
        PrintToServer("INFERNO_TRIALS_%s trials=%d failed=%d", g_failedTrials == 0 ? "PASS" : "FAIL", g_finishedTrials, g_failedTrials);
        return;
    }
    g_done = false;
    ServerCommand("mp_restartgame 1");
}

public Action MeasureArrival(Handle timer)
{
    if (HasHuman()) return Plugin_Stop;
    float elapsed = GetGameTime() - g_measureStarted;
    bool travelSample = g_steadySince == 0.0 && elapsed >= g_nextTravelSample;
    if (travelSample) g_nextTravelSample = elapsed + 2.0;
    int arrived, blocked;
    bool aligned[MAXPLAYERS + 1];
    bool holding[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_CT) continue;
        float goal[3], aim[3], origin[3], eye[3], angles[3], forwardDir[3], desired[3];
        int route;
        GetClientAbsOrigin(client, origin);
        bool ordered = BotCTTactics_GetOrder(client, goal, route) && BotCTTactics_GetAim(client, aim);
        if (travelSample)
            PrintToServer("INFERNO_TRAVEL %N t=%.1f order=%d origin=%.1f %.1f %.1f distance=%.1f",
                client, elapsed, ordered, origin[0], origin[1], origin[2], ordered ? GetVectorDistance(origin, goal) : -1.0);
        if (!ordered) continue;
        float distance = GetVectorDistance(origin, goal);
        if (distance > 32.0) continue;
        arrived++;
        holding[client] = true;
        GetClientEyePosition(client, eye);
        Handle trace = TR_TraceRayFilterEx(eye, aim, MASK_VISIBLE, RayType_EndPoint, TraceWorldOnly);
        bool clear = !TR_StartSolid(trace) && TR_GetFraction(trace) >= 0.90;
        delete trace;
        if (!clear) blocked++;
        GetClientEyeAngles(client, angles);
        GetAngleVectors(angles, forwardDir, NULL_VECTOR, NULL_VECTOR);
        MakeVectorFromPoints(eye, aim, desired);
        NormalizeVector(desired, desired);
        float dot = GetVectorDotProduct(forwardDir, desired);
        aligned[client] = dot >= 0.94;
        if (g_steadySince > 0.0 && GetGameTime() - g_steadySince >= 1.0 && !aligned[client])
            PrintToServer("INFERNO_FACING_MISS %N t=%.1f dot=%.3f eye=%.1f %.1f %.1f", client, elapsed, dot, eye[0], eye[1], eye[2]);
    }
    // Separate travel/turning from steady hold, but enforce a finite arrival
    // deadline. A single engine glance is not a whole failed watch window.
    if (elapsed < 10.0) return Plugin_Continue;
    if (g_steadySince == 0.0)
    {
        if (arrived == 5) g_steadySince = GetGameTime();
        else if (elapsed >= 25.0)
        {
            PrintToServer("INFERNO_ARRIVAL_FAIL reached=%d deadline=25", arrived);
            FinishTrial(false);
            return Plugin_Stop;
        }
        return Plugin_Continue;
    }
    float steady = GetGameTime() - g_steadySince;
    if (steady < 1.0) return Plugin_Continue;
    g_arrivalSamples += arrived;
    g_arrivalBlocked += blocked;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!holding[client]) continue;
        g_facingSamples[client]++;
        if (aligned[client]) g_alignedSamples[client]++;
    }
    if (steady >= 5.0)
    {
        int passed, released;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!holding[client]) continue;
            PrintToServer("INFERNO_ARRIVAL_BOT %N aligned=%d/%d", client, g_alignedSamples[client], g_facingSamples[client]);
            if (g_facingSamples[client] >= 15 && g_alignedSamples[client] * 100 >= g_facingSamples[client] * 85) passed++;
            Event fire = CreateEvent("weapon_fire");
            fire.SetInt("userid", GetClientUserId(client));
            fire.SetString("weapon", "weapon_ak47");
            fire.Fire();
            float goal[3];
            int route;
            if (!BotCTTactics_GetOrder(client, goal, route)) released++;
        }
        bool passedTrial = arrived == 5 && passed == 5 && released == 5 && g_arrivalBlocked == 0;
        PrintToServer("INFERNO_ARRIVAL_%s reached=%d samples=%d blocked=%d aligned_bots=%d released=%d",
            passedTrial ? "PASS" : "FAIL",
            arrived, g_arrivalSamples, g_arrivalBlocked, passed, released);
        FinishTrial(passedTrial);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}
