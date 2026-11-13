#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include "../mods/include/bot_tactical_map_profiles.inc"

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3]);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_ShouldHoldStage(int client);
native bool NavMesh_Exists();
native int NavMesh_GetNearestArea(const float position[3], bool anyZ=false, float maxDist=10000.0,
    bool checkLOS=false, bool checkGround=true, int team=-2);
native void NavMeshArea_GetPlaceCanonical(int area, char[] place, int length);

ConVar g_enabled;
bool g_armed;
int g_passed, g_failed;
public Plugin myinfo = {name = "Tactical map smoke test (isolated only)", author = "server project", version = "1.0"};

public void OnPluginStart()
{
    g_enabled = CreateConVar("sm_tactical_maps_probe", "0", "Run only on an isolated bot test server.");
    HookEvent("round_freeze_end", OnFreezeEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_armed = false;
    CreateTimer(8.0, Prepare, _, TIMER_FLAG_NO_MAPCHANGE);
}

bool HasHuman()
{
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientConnected(client) && !IsFakeClient(client)) return true;
    return false;
}

public Action Prepare(Handle timer)
{
    if (!g_enabled.BoolValue || HasHuman()) return Plugin_Stop;
    ServerCommand("bot_join_after_player 0; bot_quota_mode normal; bot_quota 0; bot_kick; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_roundtime_defuse 1.92; sv_cheats 1; bot_dont_shoot 1");
    ServerExecute();
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Stop;
}

public void OnFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_armed)
    {
        g_armed = false;
        RequestFrame(Measure);
    }
}

public bool TraceWorldOnly(int entity, int mask, any data) { return entity > MaxClients; }

public void Measure(any unused)
{
    if (!g_enabled.BoolValue || HasHuman()) return;
    char map[64];
    GetCurrentMap(map, sizeof(map));
    int profile = TacticalMap_Find(map);
    if (profile < 0) return;
    FindConVar("sm_bot_ct_tactics_debug").BoolValue = true;
    FindConVar("sm_bot_t_tactics_debug").BoolValue = true;
    FindConVar("sm_bot_t_eco_rush_chance").IntValue = 0;
    FindConVar("sm_bot_t_eco_split_chance").IntValue = 100;
    FindConVar("sm_bot_t_force_rush_chance").IntValue = 0;
    FindConVar("sm_bot_t_force_split_chance").IntValue = 100;
    FindConVar("sm_bot_t_full_rush_chance").IntValue = 0;
    FindConVar("sm_bot_t_full_split_chance").IntValue = 100;
    ServerCommand("sm_ct_tactics_replan");
    ServerExecute();
    int ctOrders, ctAims, blocked, carrier;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client)) continue;
        if (GetClientTeam(client) == CS_TEAM_T && GetPlayerWeaponSlot(client, CS_SLOT_C4) > MaxClients) carrier = client;
        float goal[3], aim[3];
        int route;
        if (!BotCTTactics_GetOrder(client, goal, route)) continue;
        ctOrders++;
        if (!BotCTTactics_GetAim(client, aim)) continue;
        ctAims++;
        goal[2] += 64.0;
        Handle trace = TR_TraceRayFilterEx(goal, aim, MASK_VISIBLE, RayType_EndPoint, TraceWorldOnly);
        if (TR_StartSolid(trace) || TR_GetFraction(trace) < 0.98) blocked++;
        delete trace;
    }
    int sites, splitSites, orderFailures, committed;
    if (carrier > 0 && NavMesh_Exists())
    {
        for (int attempt = 0; attempt < 16 && sites != 3; attempt++)
        {
            ServerCommand("sm_t_tactics_replan");
            ServerExecute();
            float goal[3];
            int route;
            if (!BotTTactics_ShouldHoldStage(carrier) || !BotTTactics_GetOrder(carrier, goal, route)) { orderFailures++; continue; }
            char place[32], main[32], wing[32];
            int area = NavMesh_GetNearestArea(goal, true, 100.0, false, false, -2);
            if (area < 0) continue;
            NavMeshArea_GetPlaceCanonical(area, place, sizeof(place));
            for (int site = 0; site < 2; site++)
            {
                TacticalMap_GetPlace(profile, site, 4, wing, sizeof(wing));
                if (!TacticalMap_GetPlace(profile, site, 3, main, sizeof(main))
                    || (!StrEqual(main, place, false) && !StrEqual(wing, place, false))) continue;
                int ordered, mainCount, wingCount;
                for (int client = 1; client <= MaxClients; client++)
                {
                    if (!BotTTactics_GetOrder(client, goal, route)) continue;
                    ordered++;
                    area = NavMesh_GetNearestArea(goal, true, 100.0, false, false, -2);
                    if (area < 0) continue;
                    NavMeshArea_GetPlaceCanonical(area, place, sizeof(place));
                    if (StrEqual(main, place, false)) mainCount++;
                    else if (wing[0] != '\0' && StrEqual(wing, place, false)) wingCount++;
                }
                if (ordered == 5 && mainCount + wingCount >= 1) sites |= 1 << site;
                if (mainCount > 0 && wingCount > 0) splitSites |= 1 << site;
                break;
            }
        }
    }
    if (carrier > 0)
    {
        // A gun-contact event bypasses the ready gate; all quiet escort
        // orders should now converge and the carrier should get a plant site.
        Event fire = CreateEvent("weapon_fire");
        fire.SetInt("userid", GetClientUserId(carrier));
        fire.SetString("weapon", "weapon_glock");
        fire.Fire();
        DataPack state = new DataPack();
        state.WriteString(map);
        state.WriteCell(profile);
        state.WriteCell(ctOrders);
        state.WriteCell(ctAims);
        state.WriteCell(blocked);
        state.WriteCell(sites);
        state.WriteCell(splitSites);
        state.WriteCell(orderFailures);
        state.WriteCell(GetClientUserId(carrier));
        CreateTimer(0.65, MeasureCommit, state, TIMER_DATA_HNDL_CLOSE | TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    FinishMap(map, profile, ctOrders, ctAims, blocked, sites, splitSites, orderFailures, committed);
}

public Action MeasureCommit(Handle timer, DataPack state)
{
    if (HasHuman()) return Plugin_Stop;
    state.Reset();
    char map[64];
    state.ReadString(map, sizeof(map));
    int profile = state.ReadCell(), ctOrders = state.ReadCell(), ctAims = state.ReadCell(), blocked = state.ReadCell();
    int sites = state.ReadCell(), splitSites = state.ReadCell(), orderFailures = state.ReadCell();
    int carrier = GetClientOfUserId(state.ReadCell());
    float goal[3], a[3], b[3];
    int route, committed;
    int manager = FindEntityByClassname(-1, "cs_player_manager");
    if (manager > 0 && carrier > 0 && !BotTTactics_ShouldHoldStage(carrier) && BotTTactics_GetOrder(carrier, goal, route))
    {
        GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", a);
        GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", b);
        if (GetVectorDistance(goal, a) <= 280.0 || GetVectorDistance(goal, b) <= 280.0)
            committed = 1;
    }
    FinishMap(map, profile, ctOrders, ctAims, blocked, sites, splitSites, orderFailures, committed);
    return Plugin_Stop;
}

void FinishMap(const char[] map, int profile, int ctOrders, int ctAims, int blocked, int sites,
    int splitSites, int orderFailures, int committed)
{
    bool passed = ctOrders == 5 && ctAims >= 2 && blocked == 0 && sites == 3 && orderFailures == 0 && committed == 1;
    if (passed) g_passed++;
    else g_failed++;
    PrintToServer("TACTICAL_MAP_%s %s ct=%d aimed=%d blocked=%d t_sites=%d split_sites=%d order_failures=%d commit=%d",
        passed ? "PASS" : "FAIL", map, ctOrders, ctAims, blocked, sites, splitSites, orderFailures, committed);
    char next[64];
    if (TacticalMap_GetName(profile + 1, next, sizeof(next)))
        ServerCommand("changelevel %s", next);
    else
        PrintToServer("TACTICAL_MAPS_DONE pass=%d fail=%d", g_passed, g_failed);
}
