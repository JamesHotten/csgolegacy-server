#define OnPluginStart BaseOpening_Start
#include "ct_opening_position_runtime_probe.sp"
#undef OnPluginStart

native void BotCTTactics_ReportBreakable(int client);
native bool BotCTTactics_ReportContact(int spotter, int enemy);
int g_expiryUser;
bool g_casesPass;

public void OnPluginStart()
{
    BaseOpening_Start();
    HookEvent("round_freeze_end", OnContactFixtureFreeze, EventHookMode_PostNoCopy);
}

public void OnContactFixtureFreeze(Event event, const char[] name, bool quiet)
{
    if (!Safe() || !StrEqual(g_mapName, "de_anubis") || GameRules_GetProp("m_bWarmupPeriod")) return;
    CreateTimer(0.40, CheckContact, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool ProbeOrder(int client)
{
    if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) return false;
    float goal[3];
    int route;
    return BotCTTactics_GetOrder(client, goal, route);
}

void EmitFire(int client)
{
    Event shot = CreateEvent("weapon_fire", true);
    if (shot == null) SetFailState("weapon_fire unavailable");
    shot.SetInt("userid", GetClientUserId(client));
    shot.SetString("weapon", "weapon_usp_silencer");
    shot.Fire();
}

public Action CheckContact(Handle timer)
{
    if (!Safe() || g_round != 1) return Plugin_Stop;
    int ct[3], count, enemy;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client)) continue;
        if (GetClientTeam(client) == CS_TEAM_CT && count < sizeof(ct) && ProbeOrder(client)) ct[count++] = client;
        if (GetClientTeam(client) == CS_TEAM_T && GetPlayerWeaponSlot(client, CS_SLOT_C4) == -1 && !enemy) enemy = client;
    }
    if (count != sizeof(ct) || !enemy)
    {
        PrintToServer("ANUBIS_CONTACT_INVALID");
        ServerCommand("quit");
        return Plugin_Stop;
    }
    EmitFire(ct[0]);
    bool gunReleased = !ProbeOrder(ct[0]);
    BotCTTactics_ReportBreakable(ct[1]);
    EmitFire(ct[1]);
    bool clearingKept = ProbeOrder(ct[1]);
    float point[3];
    TacticalMap_PlantGround(g_map, 0, point);
    TeleportEntity(enemy, point, NULL_VECTOR, NULL_VECTOR);
    bool reported = BotCTTactics_ReportContact(ct[1], enemy);
    bool sightReleased = !ProbeOrder(ct[1]);
    float away[3] = {0.0,0.0,-8950.0};
    TeleportEntity(enemy, away, NULL_VECTOR, NULL_VECTOR);
    bool expiryReady = ProbeOrder(ct[2]);
    g_expiryUser = GetClientUserId(ct[2]);
    BotCTTactics_ReportBreakable(ct[2]);
    g_casesPass = gunReleased && clearingKept && reported && sightReleased && expiryReady;
    PrintToServer("ANUBIS_CONTACT_CASE gun_released=%d clearing_kept=%d reported=%d sight_released=%d expiry_ready=%d",
        gunReleased, clearingKept, reported, sightReleased, expiryReady);
    CreateTimer(2.15, CheckExpired, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action CheckExpired(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int client = GetClientOfUserId(g_expiryUser);
    bool before = ProbeOrder(client);
    if (before) EmitFire(client);
    bool expired = before && !ProbeOrder(client);
    PrintToServer("ANUBIS_CONTACT_%s expired_shot_released=%d", (g_casesPass && expired) ? "PASS" : "FAIL", expired);
    ServerCommand("quit");
    return Plugin_Stop;
}
