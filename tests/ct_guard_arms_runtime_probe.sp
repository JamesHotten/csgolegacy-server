#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3], bool live = false);

public Plugin myinfo = {name = "Isolated CT guard weapon and fall probe", version = "1.0"};
ConVar g_run, g_repeatFall;
int g_stage, g_user, g_attackerUser, g_safe, g_rifle, g_pistol, g_knife, g_bad, g_checks;
float g_since, g_goal[3];

public void OnPluginStart()
{
    g_run = CreateConVar("sm_ct_guard_arms_probe", "0", "Run only on an empty loopback test server.");
    g_repeatFall = CreateConVar("sm_ct_guard_arms_repeat_fall", "0", "Nuke-only stalled-route case.");
    GameData data = new GameData("botstuff.games");
    g_safe = data.GetOffset("CCSBot::m_safeTime");
    delete data;
    if (g_safe < 0) SetFailState("Missing BetterBots safe-time offset");
    CreateTimer(0.1, Tick, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool Safe()
{
    if (!g_run.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Tick(Handle timer)
{
    if (!Safe()) return Plugin_Continue;
    if (g_stage == 0)
    {
        if (GetGameTime() < 10.0) return Plugin_Continue;
        // This legacy fixture deliberately verifies the native-release
        // fallback. The map refinement probe independently tests the detour.
        ConVar nukeCover = FindConVar("sm_bot_ct_nuke_route_cover");
        if (g_repeatFall.BoolValue && nukeCover != null) nukeCover.BoolValue = false;
        ServerCommand("bot_dont_shoot 1; sm_bot_t_tactics_enable 0; sm_bot_experience_record_enable 0; mp_ignore_round_win_conditions 1; mp_freezetime 1; mp_warmup_end; mp_restartgame 1");
        g_since = GetGameTime();
        g_stage++;
        return Plugin_Continue;
    }
    if (g_stage == 1)
    {
        if (GetGameTime() - g_since < 2.5 || GameRules_GetProp("m_bFreezePeriod")) return Plugin_Continue;
        int route, client, attacker;
        float look[3];
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i)) continue;
            if (GetClientTeam(i) == CS_TEAM_T)
            {
                int c4 = GetPlayerWeaponSlot(i, CS_SLOT_C4);
                if (c4 > MaxClients && RemovePlayerItem(i, c4)) RemoveEntity(c4);
                SetEntityMoveType(i, MOVETYPE_NONE);
                attacker = i;
                continue;
            }
            if (!client && GetClientTeam(i) == CS_TEAM_CT && BotCTTactics_GetOrder(i, g_goal, route)
                && BotCTTactics_GetAim(i, look)) client = i;
        }
        if (!client || !attacker)
        {
            if (GetGameTime() - g_since > 12.0) SetFailState("No ordered CT with living T opponents");
            return Plugin_Continue;
        }
        g_user = GetClientUserId(client);
        g_attackerUser = GetClientUserId(attacker);
        if (g_repeatFall.BoolValue)
        {
            char map[32];
            float foot[3];
            GetCurrentMap(map, sizeof(map));
            GetClientAbsOrigin(client, foot);
            if (!StrEqual(map, "de_nuke") || GetVectorDistance(foot, g_goal) < 150.0)
                SetFailState("Repeat fall requires a Nuke BOT still far from its hold");
            SetEntityMoveType(client, MOVETYPE_NONE);
            SDKHooks_TakeDamage(client, 0, 0, 8.0, DMG_FALL, -1, NULL_VECTOR, NULL_VECTOR, false);
            PrintToServer("CT_ARMS_%s check=world_fall_keeps_route",
                BotCTTactics_GetOrder(client, g_goal, route) ? "PASS" : "FAIL");
            CreateTimer(0.1, RepeatFall, _, TIMER_FLAG_NO_MAPCHANGE);
            return Plugin_Stop;
        }
        g_goal[2] += 4.0;
        TeleportEntity(client, g_goal, NULL_VECTOR, NULL_VECTOR);
        g_rifle = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
        if (g_rifle <= MaxClients) g_rifle = GivePlayerItem(client, "weapon_famas");
        g_pistol = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
        g_knife = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
        if (g_rifle <= MaxClients || g_knife <= MaxClients || g_pistol <= MaxClients)
            SetFailState("Missing rifle, pistol or knife");
        SetEntDataFloat(client, g_safe, 30.0);
        SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", g_knife);
        g_since = GetGameTime();
        g_stage++;
        return Plugin_Continue;
    }
    int bot = GetClientOfUserId(g_user), route;
    float goal[3], look[3], position[3];
    if (!bot || !IsPlayerAlive(bot)) SetFailState("Probe BOT was lost");
    GetClientAbsOrigin(bot, position);
    bool held = BotCTTactics_GetOrder(bot, goal, route) && BotCTTactics_GetAim(bot, look, true)
        && GetVectorDistance(position, g_goal) <= 32.0;
    float elapsed = GetGameTime() - g_since;
    if (elapsed > 0.8)
    {
        int active = GetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon");
        g_checks++;
        if (!held || active != (g_stage == 2 ? g_rifle : g_pistol)) g_bad++;
    }
    if (elapsed < 1.9) return Plugin_Continue;
    PrintToServer("CT_ARMS_%s check=%s samples=%d bad=%d", g_checks >= 6 && !g_bad ? "PASS" : "FAIL",
        g_stage == 2 ? "rifle_from_knife" : "pistol_from_knife", g_checks, g_bad);
    if (g_stage == 2)
    {
        if (IsValidEntity(g_rifle)) SetEntProp(g_rifle, Prop_Send, "m_iClip1", 0);
        SetEntPropEnt(bot, Prop_Send, "m_hActiveWeapon", g_knife);
        g_since = GetGameTime();
        g_checks = g_bad = 0;
        g_stage++;
        return Plugin_Continue;
    }
    int health = GetClientHealth(bot);
    SDKHooks_TakeDamage(bot, 0, 0, 8.0, DMG_FALL, -1, NULL_VECTOR, NULL_VECTOR, false);
    bool fall = GetClientHealth(bot) < health && BotCTTactics_GetOrder(bot, goal, route);
    PrintToServer("CT_ARMS_%s check=world_fall_keeps_order", fall ? "PASS" : "FAIL");
    int attacker = GetClientOfUserId(g_attackerUser);
    SDKHooks_TakeDamage(bot, attacker, attacker, 5.0, DMG_BULLET, -1, NULL_VECTOR, NULL_VECTOR, false);
    bool released = !BotCTTactics_GetOrder(bot, goal, route);
    PrintToServer("CT_ARMS_%s check=enemy_damage_releases_order", released ? "PASS" : "FAIL");
    PrintToServer("CT_ARMS_DONE");
    return Plugin_Stop;
}

public Action RepeatFall(Handle timer)
{
    int client = GetClientOfUserId(g_user), route;
    float goal[3];
    if (!Safe() || !client || !IsPlayerAlive(client)) return Plugin_Stop;
    bool held = BotCTTactics_GetOrder(client, goal, route);
    SDKHooks_TakeDamage(client, 0, 0, 8.0, DMG_FALL, -1, NULL_VECTOR, NULL_VECTOR, false);
    PrintToServer("CT_ARMS_%s check=repeated_stationary_fall_exits_route",
        held && !BotCTTactics_GetOrder(client, goal, route) ? "PASS" : "FAIL");
    PrintToServer("CT_ARMS_DONE");
    return Plugin_Stop;
}
