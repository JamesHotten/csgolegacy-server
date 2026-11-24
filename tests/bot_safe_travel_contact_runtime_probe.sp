#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <commandline>

public Plugin myinfo = {name = "Isolated BOT safe-travel contact regression", version = "1.0"};
int g_visible, g_enemy, g_nearby, g_safe, g_client, g_opponent, g_rifle, g_knife;
int g_attempts, g_quietKnives, g_contactKnives, g_nearbyKnives, g_contactOther;
bool g_enabled, g_started, g_sample;
float g_next, g_until;

public void OnPluginStart()
{
    if (GetCommandLineParamInt("-botcontactprobe") != 1) return;
    char ip[32];
    GetCommandLineParam("-ip", ip, sizeof(ip));
    if (!StrEqual(ip, "127.0.0.1")) SetFailState("Probe requires a loopback test server");
    GameData data = new GameData("botstuff.games");
    if (data == null) SetFailState("BetterBots gamedata missing");
    g_visible = data.GetOffset("CCSBot::m_isEnemyVisible");
    g_enemy = data.GetOffset("CCSBot::m_enemy");
    g_nearby = data.GetOffset("CCSBot::m_nearbyEnemyCount");
    g_safe = data.GetOffset("CCSBot::m_safeTime");
    delete data;
    if (g_visible < 0 || g_enemy < 0 || g_nearby < 0 || g_safe < 0) SetFailState("BetterBots probe offsets missing");
    g_enabled = true;
    CreateTimer(0.25, Prepare, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client)
{
    if (g_enabled && !IsFakeClient(client)) {
        g_enabled = false;
        PrintToServer("[DEBUG-contact] ABORT human connected");
    }
}

public Action Prepare(Handle timer)
{
    if (!g_enabled) return Plugin_Stop;
    float now = GetGameTime();
    if (now < 8.0) return Plugin_Continue;
    if (!g_started) {
        g_started = true;
        // Disable directors for the predicate differential: both cases must
        // start out of a hold, with the safe-travel timer still active.
        ServerCommand("bot_dont_shoot 1; sm_bot_ct_tactics_enable 0; sm_bot_t_tactics_enable 0; sm_bot_experience_record_enable 0; mp_ignore_round_win_conditions 1; mp_freezetime 1; mp_warmup_end; mp_restartgame 1");
        g_next = now + 4.0;
        g_until = now + 25.0;
    }
    if (now > g_until) {
        g_enabled = false;
        PrintToServer("[DEBUG-contact] ABORT incomplete attempts=%d", g_attempts);
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_enabled || !g_started || GetGameTime() < g_next || GetClientTeam(client) != CS_TEAM_CT
        || !IsFakeClient(client) || !IsPlayerAlive(client) || GameRules_GetProp("m_bFreezePeriod")
        || GameRules_GetProp("m_bWarmupPeriod") || (g_client && client != g_client)) return;
    if (!g_client) {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T) {
                g_opponent = i;
                break;
            }
        }
        if (!g_opponent) return;
        g_client = client;
        g_rifle = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
        if (g_rifle <= MaxClients) g_rifle = GivePlayerItem(client, "weapon_m4a1");
        g_knife = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
        if (g_rifle <= MaxClients || g_knife <= MaxClients) SetFailState("Need a rifle and knife");
    }
    if (!IsClientInGame(g_opponent) || !IsPlayerAlive(g_opponent)) return;
    // One-tick engine-input fixture. Quiet control proves the plugin is
    // loaded and knife switching is possible for this BOT and rifle.
    int scenario = g_attempts % 3;
    bool contact = scenario == 1;
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", g_rifle);
    SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime());
    SetEntDataFloat(client, g_safe, 240.0);
    SetEntDataEnt2(client, g_enemy, contact ? g_opponent : -1);
    SetEntData(client, g_visible, contact ? 1 : 0, 1);
    SetEntData(client, g_nearby, scenario == 2 ? 1 : 0);
    g_sample = true;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_sample || client != g_client) return;
    g_sample = false;
    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int scenario = g_attempts % 3;
    if (scenario == 0) {
        if (active == g_knife) g_quietKnives++;
    } else if (active == g_knife) {
        if (scenario == 1) g_contactKnives++;
        else g_nearbyKnives++;
    } else if (active != g_rifle) {
        g_contactOther++;
    }
    g_attempts++;
    g_next = GetGameTime() + 0.1;
    if (g_attempts < 24) return;
    PrintToServer("[DEBUG-contact] RESULT quiet_knife=%d/8 contact_knife=%d/8 nearby_unseen_knife=%d/8 threat_other=%d/16",
        g_quietKnives, g_contactKnives, g_nearbyKnives, g_contactOther);
    g_enabled = false;
}
