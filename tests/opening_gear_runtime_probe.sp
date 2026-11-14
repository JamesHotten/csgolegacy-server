#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native int BotEquipment_GetBuyPlan(int team);
public Plugin myinfo = {name = "Opening Gear and Retake Telemetry Probe", author = "server project", version = "1.0"};
ConVar g_enabled;
ConVar g_noKit;
bool g_armed;
int g_ct, g_t;

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_opening_gear_probe", "0", "Explicit isolated-server test.");
    g_noKit = CreateConVar("sm_opening_gear_probe_no_kit", "0", "Test the no-kit defuse telemetry variant.");
    HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", FreezeEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart() { CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE); }

bool Safe()
{
    if (!g_enabled.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public Action Prepare(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 4; mp_roundtime_defuse 1.92; mp_ignore_round_win_conditions 1");
    ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Stop;
}

public void RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (g_armed && Safe()) CreateTimer(2.8, Equip, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Equip(Handle timer)
{
    if (!g_armed || !Safe()) return Plugin_Stop;
    char ctWeapons[][] = {"weapon_famas", "weapon_awp", "weapon_p90", "weapon_xm1014", ""};
    char tWeapons[][] = {"weapon_ak47", "weapon_galilar", "weapon_mac10", "", ""};
    int counts[4];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || !IsFakeClient(i)) continue;
        int team = GetClientTeam(i);
        if (team != CS_TEAM_CT && team != CS_TEAM_T) continue;
        int slot = counts[team]++;
        if (slot >= 5) continue;
        for (int index = 0; index < GetEntPropArraySize(i, Prop_Send, "m_hMyWeapons"); index++)
        {
            int weapon = GetEntPropEnt(i, Prop_Send, "m_hMyWeapons", index);
            if (weapon <= MaxClients || !IsValidEntity(weapon)) continue;
            char classname[32];
            GetEntityClassname(weapon, classname, sizeof(classname));
            if (StrEqual(classname, "weapon_c4") || StrContains(classname, "knife") != -1) continue;
            if (RemovePlayerItem(i, weapon)) RemoveEntity(weapon);
        }
        GivePlayerItem(i, team == CS_TEAM_CT ? "weapon_usp_silencer" : "weapon_glock");
        if (team == CS_TEAM_CT && ctWeapons[slot][0] != '\0') GivePlayerItem(i, ctWeapons[slot]);
        if (team == CS_TEAM_T && tWeapons[slot][0] != '\0') GivePlayerItem(i, tWeapons[slot]);
        SetEntProp(i, Prop_Send, "m_iAccount", 0);
        SetEntProp(i, Prop_Data, "m_ArmorValue", slot < 4 ? 100 : 0);
        SetEntProp(i, Prop_Send, "m_bHasHelmet", slot < 3 ? 1 : 0);
        SetEntProp(i, Prop_Send, "m_bHasDefuser", team == CS_TEAM_CT && slot == 0 && !g_noKit.BoolValue ? 1 : 0);
        // Strip reserve ammo left by the prior pistol buy, then give two
        // flashes and a smoke to exactly one defender.
        for (int ammo = 0; ammo < GetEntPropArraySize(i, Prop_Send, "m_iAmmo"); ammo++)
            SetEntProp(i, Prop_Send, "m_iAmmo", 0, 4, ammo);
        if (team == CS_TEAM_CT && slot == 0)
        {
            g_ct = i;
            int flash = GivePlayerItem(i, "weapon_flashbang");
            if (flash <= MaxClients) SetFailState("Could not create fixture flashbang");
            int ammo = GetEntProp(flash, Prop_Send, "m_iPrimaryAmmoType");
            SetEntProp(i, Prop_Send, "m_iAmmo", 2, 4, ammo);
            GivePlayerItem(i, "weapon_smokegrenade");
        }
        if (team == CS_TEAM_T && slot == 0) g_t = i;
    }
    PrintToServer("GEAR_FIXTURE ct=%d t=%d plans=%d/%d", counts[3], counts[2], BotEquipment_GetBuyPlan(3), BotEquipment_GetBuyPlan(2));
    return Plugin_Stop;
}

public void FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_armed || !Safe()) return;
    g_armed = false;
    if (g_ct == 0 || g_t == 0) SetFailState("Incomplete equipment fixture");
    CreateTimer(0.5, Plant, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Plant(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    float position[3];
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", position);
    int bomb = CreateEntityByName("planted_c4");
    DispatchSpawn(bomb);
    TeleportEntity(bomb, position, NULL_VECTOR, NULL_VECTOR);
    SetEntProp(bomb, Prop_Send, "m_bBombTicking", 1);
    SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + 18.0);
    Event event = CreateEvent("bomb_planted");
    event.SetInt("userid", GetClientUserId(g_t));
    event.Fire();
    CreateTimer(0.85, Complete, EntIndexToEntRef(bomb), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Complete(Handle timer, any reference)
{
    if (!Safe()) return Plugin_Stop;
    Event event = CreateEvent("bomb_begindefuse");
    event.SetInt("userid", GetClientUserId(g_ct));
    event.Fire();
    event = CreateEvent("bomb_defused");
    event.SetInt("userid", GetClientUserId(g_ct));
    event.Fire();
    event = CreateEvent("round_end");
    event.SetInt("winner", CS_TEAM_CT);
    event.SetInt("reason", 7);
    event.Fire();
    int bomb = EntRefToEntIndex(reference);
    if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
    PrintToServer("GEAR_FIXTURE_WRITTEN");
    return Plugin_Stop;
}
