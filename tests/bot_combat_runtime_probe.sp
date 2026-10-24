#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

native int NavMesh_GetNearestArea(const float pos[3], bool anyZ=false, float maxDist=10000.0, bool checkLOS=false, bool checkGround=true, int team=-2);
native bool NavMeshArea_GetCenter(int area, float result[3]);

// EMPTY-SERVER diagnostic only. Never shipped by the normal installer.
// [DEBUG-combat-1019] logs contain timings, not authentication/player IDs.
public Plugin myinfo = { name = "BOT combat timing probe", author = "server project", version = "1.0" };
int g_visibleOffset, g_enemyOffset, g_profileOffset;
int g_ct, g_t, g_trial, g_stage;
bool g_started, g_active, g_done;
float g_after, g_revealAt, g_points[2][3];
float g_seen[2], g_raw[2], g_final[2], g_fire[2], g_hit[2], g_lethal[2];
float g_shotError[2], g_shotSpeed[2], g_reaction[2];
int g_shots[2], g_damage[2], g_blocked[2];
ConVar g_auto, g_settings[7];
float g_old[7];
File g_output;
char g_outputPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
    GameData data = new GameData("botstuff.games");
    if (data == null) SetFailState("Missing installed BetterBots gamedata");
    g_visibleOffset = data.GetOffset("CCSBot::m_isEnemyVisible");
    g_enemyOffset = data.GetOffset("CCSBot::m_enemy");
    g_profileOffset = data.GetOffset("CCSBot::m_pLocalProfile");
    delete data;
    if (g_visibleOffset < 0 || g_enemyOffset < 0 || g_profileOffset < 0) SetFailState("Missing combat offsets");
    g_auto = CreateConVar("sm_combat_probe_auto", "0", "Explicit empty-server combat diagnostics.");
    HookEvent("weapon_fire", Fired);
    HookEvent("player_hurt", Hurt);
    CreateTimer(0.1, Tick, _, TIMER_REPEAT);
}

bool EmptyOfHumans()
{
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Tick(Handle timer)
{
    if (g_done || !g_auto.BoolValue) return Plugin_Continue;
    if (!EmptyOfHumans())
    {
        PrintToServer("[DEBUG-combat-1019] ABORT human connected");
        Cleanup();
        return Plugin_Stop;
    }
    if (!g_started)
    {
        if (GetGameTime() < 10.0) return Plugin_Continue;
        char names[7][48] = {"mp_ignore_round_win_conditions", "bot_stop", "bot_dont_shoot",
            "sm_bot_ct_tactics_enable", "sm_bot_t_tactics_enable", "sm_bot_experience_record_enable", "mp_freezetime"};
        for (int n = 0; n < sizeof(names); n++)
        {
            g_settings[n] = FindConVar(names[n]);
            if (g_settings[n] == null) SetFailState("Missing test cvar %s", names[n]);
            g_old[n] = g_settings[n].FloatValue;
        }
        g_started = true;
        g_settings[0].IntValue = 1;
        g_settings[1].IntValue = 0;
        g_settings[2].IntValue = 0;
        g_settings[3].IntValue = 0;
        g_settings[4].IntValue = 0;
        g_settings[5].IntValue = 0;
        g_settings[6].IntValue = 1;
        ServerCommand("mp_warmup_end; mp_restartgame 1");
        g_after = GetGameTime() + 8.0;
        return Plugin_Continue;
    }
    if (GetGameTime() < g_after) return Plugin_Continue;
    if (g_stage == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || !IsFakeClient(i)) continue;
            if (GetClientTeam(i) == CS_TEAM_CT && g_ct == 0) g_ct = i;
            if (GetClientTeam(i) == CS_TEAM_T && g_t == 0) g_t = i;
        }
        if (!g_ct || !g_t) return Plugin_Continue;
        if (!FindPair()) SetFailState("No clear NAV-supported test lane");
        BuildPath(Path_SM, g_outputPath, sizeof(g_outputPath), "data/combat-probe-1019-%d.csv", GetTime());
        g_output = OpenFile(g_outputPath, "w");
        if (g_output == null) SetFailState("Cannot create timing artifact");
        g_output.WriteLine("trial,case,team,name,profile_reaction_ms,seen_ms,raw_attack_ms,final_attack_ms,first_shot_ms,first_hit_ms,damage100_ms,shots,damage,blocked_ticks,first_shot_error_deg,first_shot_speed");
        PrintToServer("[DEBUG-combat-1019] START output=%s lane=(%.0f %.0f %.0f)-(%.0f %.0f %.0f)",
            g_outputPath, g_points[0][0], g_points[0][1], g_points[0][2], g_points[1][0], g_points[1][1], g_points[1][2]);
        g_stage = 1;
    }
    if (g_stage == 1)
    {
        if (g_trial >= 24)
        {
            PrintToServer("[DEBUG-combat-1019] COMPLETE trials=%d", g_trial);
            Cleanup();
            return Plugin_Stop;
        }
        PrepareTrial();
        g_stage = 2;
        g_after = GetGameTime() + 1.5;
    }
    else if (g_stage == 2)
    {
        g_revealAt = GetGameTime();
        for (int side = 0; side < 2; side++)
        {
            int client = side == 0 ? g_ct : g_t;
            int point = (side + g_trial % 2) % 2;
            float aim[3], angles[3], target[3];
            for (int k = 0; k < 3; k++) target[k] = g_points[1-point][k];
            target[2] += 64.0;
            float eye[3];
            for (int k = 0; k < 3; k++) eye[k] = g_points[point][k];
            eye[2] += 64.0;
            MakeVectorFromPoints(eye, target, aim);
            GetVectorAngles(aim, angles);
            TeleportEntity(client, g_points[point], angles, NULL_VECTOR);
            SetEntPropFloat(client, Prop_Send, "m_angEyeAngles[0]", angles[0]);
            SetEntPropFloat(client, Prop_Send, "m_angEyeAngles[1]", angles[1]);
        }
        g_active = true;
        g_stage = 3;
        g_after = GetGameTime() + 4.0;
    }
    else if (g_stage == 3)
    {
        g_active = false;
        for (int side = 0; side < 2; side++) WriteResult(side);
        g_output.Flush();
        g_trial++;
        g_stage = 1;
    }
    return Plugin_Continue;
}

bool FindPair()
{
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    if (manager == -1) return false;
    float site[3];
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", site);
    int area = NavMesh_GetNearestArea(site, false, 600.0, false, true, -2);
    if (area < 0 || !NavMeshArea_GetCenter(area, g_points[0])) return false;
    for (int step = 0; step < 24; step++)
    {
        float desired[3], angle = float(step) * 15.0;
        desired[0] = g_points[0][0] + Cosine(DegToRad(angle)) * 650.0;
        desired[1] = g_points[0][1] + Sine(DegToRad(angle)) * 650.0;
        desired[2] = g_points[0][2];
        area = NavMesh_GetNearestArea(desired, false, 220.0, false, true, -2);
        if (area < 0 || !NavMeshArea_GetCenter(area, g_points[1])) continue;
        float distance = GetVectorDistance(g_points[0], g_points[1]);
        if (distance < 450.0 || distance > 850.0 || FloatAbs(g_points[0][2] - g_points[1][2]) > 48.0) continue;
        float a[3], b[3];
        for (int k = 0; k < 3; k++) { a[k] = g_points[0][k]; b[k] = g_points[1][k]; }
        a[2] += 64.0; b[2] += 64.0;
        Handle trace = TR_TraceRayFilterEx(a,b,MASK_SHOT,RayType_EndPoint,IgnorePlayers);
        bool clear = !TR_DidHit(trace);
        delete trace;
        if (clear) { g_points[0][2] += 4.0; g_points[1][2] += 4.0; return true; }
    }
    return false;
}
public bool IgnorePlayers(int entity, int mask) { return entity > MaxClients; }

void PrepareTrial()
{
    g_active = false;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || GetClientTeam(i) < CS_TEAM_T) continue;
        if (!IsPlayerAlive(i) || i == g_ct || i == g_t) CS_RespawnPlayer(i);
        SetEntityMoveType(i, MOVETYPE_NONE);
        float isolated[3] = {0.0, 0.0, -10000.0};
        isolated[0] = float(i) * 512.0;
        if (i == g_ct || i == g_t)
        {
            // Separate real spawns provide world occlusion during reset.
            // Off-map void positions can see one another and pre-trigger AI.
            int spawn = FindEntityByClassname(-1, i == g_ct ? "info_player_counterterrorist" : "info_player_terrorist");
            if (spawn == -1) SetFailState("No reset spawn");
            GetEntPropVector(spawn, Prop_Data, "m_vecOrigin", isolated);
            isolated[2] += 4.0;
        }
        TeleportEntity(i, isolated, NULL_VECTOR, NULL_VECTOR);
        SetEntityHealth(i, 10000);
        SetEntProp(i, Prop_Data, "m_takedamage", 2);
    }
    for (int side = 0; side < 2; side++)
    {
        int client = side == 0 ? g_ct : g_t;
        for (int slot = 0; slot <= 5; slot++)
        {
            int weapon;
            while ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
            { RemovePlayerItem(client, weapon); RemoveEntity(weapon); }
        }
        int mode = g_trial / 8;
        char classname[32];
        strcopy(classname, sizeof(classname), mode == 1 ? "weapon_ak47" : (mode == 2 ? "weapon_m4a1" : (side == 0 ? "weapon_m4a1" : "weapon_ak47")));
        int primary = GivePlayerItem(client, classname);
        if (primary <= MaxClients) SetFailState("Cannot give probe rifle");
        EquipPlayerWeapon(client, primary);
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", primary);
        SetEntProp(client, Prop_Data, "m_ArmorValue", 100);
        SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
        SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime());
        g_seen[side] = g_raw[side] = g_final[side] = g_fire[side] = g_hit[side] = g_lethal[side] = -1.0;
        g_shots[side] = g_damage[side] = g_blocked[side] = 0;
        g_shotError[side] = g_shotSpeed[side] = -1.0;
        Address profile = view_as<Address>(GetEntData(client, g_profileOffset));
        g_reaction[side] = view_as<float>(LoadFromAddress(profile + view_as<Address>(84), NumberType_Int32));
    }
}

void Observe(int client, int buttons, bool pre)
{
    if (!g_active || (client != g_ct && client != g_t)) return;
    int side = client == g_ct ? 0 : 1;
    int enemy = side == 0 ? g_t : g_ct;
    float now = GetGameTime() - g_revealAt;
    bool visible = GetEntData(client, g_visibleOffset) != 0 && GetEntDataEnt2(client, g_enemyOffset) == enemy;
    if (visible && g_seen[side] < 0.0) g_seen[side] = now;
    if (buttons & IN_ATTACK)
    {
        if (pre && g_raw[side] < 0.0) g_raw[side] = now;
        if (!pre && g_final[side] < 0.0) g_final[side] = now;
    }
    if (pre && buttons & IN_ATTACK) g_blocked[side]++;
    if (!pre && buttons & IN_ATTACK) g_blocked[side]--;
}
public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) { Observe(client, buttons, true); }
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) { Observe(client, buttons, false); }

public void Fired(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!g_active || (client != g_ct && client != g_t)) return;
    int side = client == g_ct ? 0 : 1;
    g_shots[side]++;
    if (g_fire[side] >= 0.0) return;
    g_fire[side] = GetGameTime() - g_revealAt;
    float eye[3], target[3], direction[3], aim[3], angles[3], velocity[3];
    GetClientEyePosition(client, eye);
    GetClientEyePosition(side == 0 ? g_t : g_ct, target);
    MakeVectorFromPoints(eye, target, direction);
    NormalizeVector(direction, direction);
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, aim, NULL_VECTOR, NULL_VECTOR);
    float dot = GetVectorDotProduct(direction, aim);
    g_shotError[side] = RadToDeg(ArcCosine(FloatClamp(dot, -1.0, 1.0)));
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    g_shotSpeed[side] = GetVectorLength(velocity);
}
float FloatClamp(float value, float low, float high) { return value < low ? low : (value > high ? high : value); }
public void Hurt(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!g_active || (client != g_ct && client != g_t) || victim != (client == g_ct ? g_t : g_ct)) return;
    int side = client == g_ct ? 0 : 1;
    float now = GetGameTime() - g_revealAt;
    if (g_hit[side] < 0.0) g_hit[side] = now;
    g_damage[side] += event.GetInt("dmg_health");
    if (g_damage[side] >= 100 && g_lethal[side] < 0.0) g_lethal[side] = now;
}
void WriteResult(int side)
{
    char name[64];
    GetClientName(side == 0 ? g_ct : g_t, name, sizeof(name));
    ReplaceString(name, sizeof(name), ",", "_");
    g_output.WriteLine("%d,%d,%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%.2f,%.1f",
        g_trial+1, g_trial/8, side == 0 ? "CT" : "T", name, g_reaction[side]*1000.0,
        g_seen[side]*1000.0, g_raw[side]*1000.0, g_final[side]*1000.0, g_fire[side]*1000.0,
        g_hit[side]*1000.0, g_lethal[side]*1000.0, g_shots[side], g_damage[side], g_blocked[side], g_shotError[side], g_shotSpeed[side]);
    PrintToServer("[DEBUG-combat-1019] trial=%d case=%d %s visible=%.0f shot=%.0f hit=%.0f damage100=%.0f profile=%.0f raw=%.0f",
        g_trial+1,g_trial/8,side==0?"CT":"T",g_seen[side]*1000.0,g_fire[side]*1000.0,g_hit[side]*1000.0,g_lethal[side]*1000.0,g_reaction[side]*1000.0,g_raw[side]*1000.0);
}
void Cleanup()
{
    if (g_done) return;
    g_active = false;
    g_done = true;
    if (g_started)
        for (int n = 0; n < sizeof(g_settings); n++)
            if (g_settings[n] != null) g_settings[n].FloatValue = g_old[n];
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) >= CS_TEAM_T)
            SetEntityMoveType(i, MOVETYPE_WALK);
    delete g_output;
    if (g_started) ServerCommand("mp_restartgame 1");
}
public void OnPluginEnd() { Cleanup(); }
public void OnClientPutInServer(int client) { if (g_started && !IsFakeClient(client)) Cleanup(); }
