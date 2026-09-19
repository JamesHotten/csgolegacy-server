#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <bot_equipment_policy>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.1.0"
#define MAX_CANDIDATES 256
#define TEAM_ANY -2

native bool NavMesh_Exists();
native int NavMesh_GetNearestArea(const float pos[3], bool anyZ=false, float maxDist=10000.0, bool checkLOS=false, bool checkGround=true, int team=TEAM_ANY);
native void NavMesh_CollectSurroundingAreas(ArrayStack stack, int startArea, float travelDistLimit=1500.0, float maxStepUpLimit=18.0, float maxDropDownLimit=100.0);
native bool NavMeshArea_GetCenter(int areaIndex, float buffer[3]);
native void NavMeshArea_GetHidingSpots(ArrayStack stack, int areaIndex);
native void NavHidingSpot_GetPosition(int hidingSpotIndex, float buffer[3]);

#include <bot_tactical_angles>

enum TPhase
{
    TPhase_Idle = 0,
    TPhase_AttackStage,
    TPhase_AttackCommit,
    TPhase_RecoverBomb,
    TPhase_PostPlant
};

enum TBuyState
{
    TBuy_Eco = 0,
    TBuy_Force,
    TBuy_Full
};

enum TAttackPlan
{
    TPlan_Default = 0,
    TPlan_Rush,
    TPlan_Split
};

enum RouteType
{
    Route_Default = 0,
    Route_Fastest,
    Route_Safest,
    Route_Retreat
};

public Plugin myinfo =
{
    name = "BetterBots T Tactical Director",
    author = "JamesHotten server project",
    description = "Reversible T attack, bomb escort/recovery and post-plant coordination",
    version = PLUGIN_VERSION,
    url = "https://github.com/JamesHotten/csgolegacy-server"
};

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvInitialHold;
ConVar g_cvSyncEnabled;
ConVar g_cvSyncStageMin;
ConVar g_cvSyncStageTimeout;
ConVar g_cvSyncMinReady;
ConVar g_cvPostPlantHold;
ConVar g_cvEscortCount;
ConVar g_cvFullRushChance;
ConVar g_cvFullSplitChance;
ConVar g_cvForceRushChance;
ConVar g_cvForceSplitChance;
ConVar g_cvEcoRushChance;
ConVar g_cvEcoSplitChance;

TPhase g_phase = TPhase_Idle;
TBuyState g_buyState = TBuy_Full;
TAttackPlan g_plan = TPlan_Default;
float g_phaseStarted;
float g_siteA[3];
float g_siteB[3];
float g_tSpawn[3];
float g_ctSpawn[3];
float g_bombPosition[3];
bool g_geometryReady;
bool g_attackA;
bool g_attackContact;

bool g_hasOrder[MAXPLAYERS + 1];
bool g_hasLook[MAXPLAYERS + 1];
bool g_combatReleased[MAXPLAYERS + 1];
float g_orderGoal[MAXPLAYERS + 1][3];
float g_orderLook[MAXPLAYERS + 1][3];
int g_orderRoute[MAXPLAYERS + 1];

float g_candidates[MAX_CANDIDATES][3];
int g_candidateCount;
float g_targets[MAXPLAYERS + 1][3];
int g_targetCount;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax)
{
    RegPluginLibrary("bot_t_tactics");
    CreateNative("BotTTactics_GetOrder", Native_GetOrder);
    CreateNative("BotTTactics_GetAim", Native_GetAim);
    CreateNative("BotTTactics_ShouldHoldStage", Native_ShouldHoldStage);
    MarkNativeAsOptional("NavMesh_Exists");
    MarkNativeAsOptional("NavMesh_GetNearestArea");
    MarkNativeAsOptional("NavMesh_CollectSurroundingAreas");
    MarkNativeAsOptional("NavMeshArea_GetCenter");
    MarkNativeAsOptional("NavMeshArea_GetHidingSpots");
    MarkNativeAsOptional("NavHidingSpot_GetPosition");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("sm_bot_t_tactics_enable", "1", "Enable the reversible T tactical director.", _, true, 0.0, true, 1.0);
    g_cvDebug = CreateConVar("sm_bot_t_tactics_debug", "0", "Log T tactical plans and assignments.", _, true, 0.0, true, 1.0);
    g_cvInitialHold = CreateConVar("sm_bot_t_tactics_initial_hold", "28.0", "Maximum seconds to maintain the initial T attack.", _, true, 8.0, true, 60.0);
    g_cvSyncEnabled = CreateConVar("sm_bot_t_tactics_sync_enable", "1", "Stage before committing the T attack.", _, true, 0.0, true, 1.0);
    g_cvSyncStageMin = CreateConVar("sm_bot_t_tactics_sync_stage_min", "3.0", "Minimum staging time before a synchronized attack.", _, true, 0.0, true, 10.0);
    g_cvSyncStageTimeout = CreateConVar("sm_bot_t_tactics_sync_stage_timeout", "10.0", "Hard timeout before committing even when teammates are delayed.", _, true, 2.0, true, 20.0);
    g_cvSyncMinReady = CreateConVar("sm_bot_t_tactics_sync_min_ready", "60", "Percent of active ordered T bots required at staging goals.", _, true, 20.0, true, 100.0);
    g_cvPostPlantHold = CreateConVar("sm_bot_t_tactics_postplant_hold", "35.0", "Maximum seconds to maintain post-plant positions.", _, true, 5.0, true, 45.0);
    g_cvEscortCount = CreateConVar("sm_bot_t_tactics_bomb_escort_count", "2", "Maximum number of T escorts used during dropped-bomb recovery.", _, true, 0.0, true, 4.0);
    g_cvFullRushChance = CreateConVar("sm_bot_t_full_rush_chance", "10", "Full-buy chance for a site rush.", _, true, 0.0, true, 100.0);
    g_cvFullSplitChance = CreateConVar("sm_bot_t_full_split_chance", "45", "Full-buy chance for a split attack.", _, true, 0.0, true, 100.0);
    g_cvForceRushChance = CreateConVar("sm_bot_t_force_rush_chance", "40", "Force-buy chance for a site rush.", _, true, 0.0, true, 100.0);
    g_cvForceSplitChance = CreateConVar("sm_bot_t_force_split_chance", "30", "Force-buy chance for a split attack.", _, true, 0.0, true, 100.0);
    g_cvEcoRushChance = CreateConVar("sm_bot_t_eco_rush_chance", "65", "Eco chance for a site rush.", _, true, 0.0, true, 100.0);
    g_cvEcoSplitChance = CreateConVar("sm_bot_t_eco_split_chance", "10", "Eco chance for a split attack.", _, true, 0.0, true, 100.0);

    g_cvEnabled.AddChangeHook(OnEnabledChanged);
    AutoExecConfig(true, "bot_t_tactics");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_FreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("bomb_dropped", Event_BombDropped, EventHookMode_PostNoCopy);
    HookEvent("bomb_pickup", Event_BombPickup, EventHookMode_PostNoCopy);
    HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_PostNoCopy);
    HookEvent("bomb_defused", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("bomb_exploded", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("weapon_fire", Event_Contact, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    RegAdminCmd("sm_t_tactics_status", Command_Status, ADMFLAG_GENERIC, "Show the current T tactical plan and active orders.");
    RegAdminCmd("sm_t_tactics_replan", Command_Replan, ADMFLAG_GENERIC, "Build a new T attack for the current round.");
    CreateTimer(0.5, Timer_Update, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    ResetDirector();
    ClearCombatReleases();
    g_geometryReady = false;
}

public void OnClientPutInServer(int client)
{
    g_combatReleased[client] = false;
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        ResetDirector();
}

public any Native_GetOrder(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!g_cvEnabled.BoolValue || client < 1 || client > MaxClients || !g_hasOrder[client]
        || g_combatReleased[client] || !IsTBot(client))
        return false;
    SetNativeArray(2, g_orderGoal[client], 3);
    SetNativeCellRef(3, g_orderRoute[client]);
    return true;
}

public any Native_ShouldHoldStage(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return g_cvEnabled.BoolValue && g_phase == TPhase_AttackStage
        && client >= 1 && client <= MaxClients && g_hasOrder[client]
        && !g_combatReleased[client] && IsTBot(client);
}

public any Native_GetAim(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!g_cvEnabled.BoolValue || client < 1 || client > MaxClients || !g_hasOrder[client]
        || !g_hasLook[client] || g_combatReleased[client] || !IsTBot(client))
        return false;
    SetNativeArray(2, g_orderLook[client], 3);
    return true;
}

public Action Command_Status(int client, int args)
{
    int active;
    int tBots;
    int armored;
    int primaryWithoutArmor;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_hasOrder[i])
            active++;
        if (!IsTBot(i))
            continue;
        tBots++;
        int armor = GetEntProp(i, Prop_Data, "m_ArmorValue");
        if (armor > 0)
            armored++;
        if (armor == 0 && GetPlayerWeaponSlot(i, CS_SLOT_PRIMARY) != -1)
            primaryWithoutArmor++;
    }
    char phase[20], buy[12], plan[16];
    GetPhaseName(g_phase, phase, sizeof(phase));
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    int syncReady, syncOrdered;
    GetOrderProgress(180.0, syncReady, syncOrdered);
    ReplyToCommand(client, "[T Tactics] enabled=%d geometry=%d phase=%s buy=%s plan=%s site=%s active_orders=%d",
        g_cvEnabled.BoolValue, g_geometryReady, phase, buy, plan, g_attackA ? "A" : "B", active);
    ReplyToCommand(client, "[T Tactics] sync=%d ready=%d/%d contact=%d",
        g_cvSyncEnabled.BoolValue, syncReady, syncOrdered, g_attackContact);
    ReplyToCommand(client, "[T Tactics] t_bots=%d armored=%d primary_without_armor=%d",
        tBots, armored, primaryWithoutArmor);
    return Plugin_Handled;
}

public Action Command_Replan(int client, int args)
{
    if (!g_cvEnabled.BoolValue || !RefreshGeometry() || !NavMeshReady())
    {
        ReplyToCommand(client, "[T Tactics] Enable the plugin and use a bomb map with valid NAV data.");
        return Plugin_Handled;
    }
    PlanInitialAttack();
    ReplyToCommand(client, "[T Tactics] Attack replanned.");
    return Plugin_Handled;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetDirector();
    ClearCombatReleases();
    g_attackContact = false;
}

public void Event_FreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_cvEnabled.BoolValue)
        CreateTimer(0.1, Timer_PlanInitial, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlanInitial(Handle timer)
{
    if (g_cvEnabled.BoolValue && RefreshGeometry() && NavMeshReady())
        PlanInitialAttack();
    else
        DebugLog("Initial attack skipped: geometry or navmesh unavailable.");
    return Plugin_Stop;
}

public void Event_Reset(Event event, const char[] name, bool dontBroadcast)
{
    ResetDirector();
}

public void Event_BombDropped(Event event, const char[] name, bool dontBroadcast)
{
    if (g_cvEnabled.BoolValue)
        CreateTimer(0.2, Timer_PlanRecovery, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlanRecovery(Handle timer)
{
    int c4 = FindLooseC4();
    if (c4 != -1)
    {
        GetEntPropVector(c4, Prop_Send, "m_vecOrigin", g_bombPosition);
        PlanBombRecovery();
    }
    return Plugin_Stop;
}

public void Event_BombPickup(Event event, const char[] name, bool dontBroadcast)
{
    if (g_phase == TPhase_RecoverBomb)
        ResetDirector();
}

public void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    if (g_cvEnabled.BoolValue)
        CreateTimer(0.15, Timer_PlanPostPlant, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_PlanPostPlant(Handle timer)
{
    int bomb = FindEntityByClassname(-1, "planted_c4");
    if (bomb != -1)
    {
        GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", g_bombPosition);
        PlanPostPlant();
    }
    return Plugin_Stop;
}

public void Event_Contact(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (g_phase == TPhase_AttackStage && IsTBot(client))
        g_attackContact = true;
    ReleaseOrder(client, "weapon contact");
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (g_phase == TPhase_AttackStage && (IsTBot(victim) || IsTBot(attacker)))
        g_attackContact = true;
    ReleaseOrder(victim, "hurt");
    ReleaseOrder(attacker, "combat");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client >= 1 && client <= MaxClients)
    {
        if (g_phase == TPhase_AttackStage && IsClientInGame(client) && GetClientTeam(client) == CS_TEAM_T)
            g_attackContact = true;
        g_hasOrder[client] = false;
    }
}

public Action Timer_Update(Handle timer)
{
    if (!g_cvEnabled.BoolValue || g_phase == TPhase_Idle)
        return Plugin_Continue;
    float elapsed = GetGameTime() - g_phaseStarted;
    if (g_phase == TPhase_AttackStage
        && (g_attackContact
            || (elapsed >= g_cvSyncStageMin.FloatValue && OrdersMeetReadyPercent(180.0, g_cvSyncMinReady.IntValue))
            || elapsed >= g_cvSyncStageTimeout.FloatValue))
        PlanAttackCommit();
    else if (g_phase == TPhase_AttackCommit && elapsed >= g_cvInitialHold.FloatValue)
        ResetDirector();
    else if (g_phase == TPhase_RecoverBomb && FindLooseC4() == -1)
        ResetDirector();
    else if (g_phase == TPhase_PostPlant && elapsed >= g_cvPostPlantHold.FloatValue)
        ResetDirector();
    return Plugin_Continue;
}

void PlanInitialAttack()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectTBots(bots);
    if (count == 0) return;
    g_buyState = ClassifyTBuy();
    g_plan = ChooseAttackPlan(g_buyState);
    g_attackA = GetRandomInt(0, 1) == 0;
    g_attackContact = false;

    if (g_cvSyncEnabled.BoolValue)
        PlanAttackStage();
    else
        PlanAttackCommit();

    char buy[12], plan[16];
    GetBuyName(g_buyState, buy, sizeof(buy));
    GetPlanName(g_plan, plan, sizeof(plan));
    DebugLog("Initial T attack: buy=%s plan=%s site=%s bots=%d sync=%d", buy, plan,
        g_attackA ? "A" : "B", count, g_cvSyncEnabled.BoolValue);
}

void PlanAttackStage()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectTBots(bots);
    if (count == 0)
        return;

    float site[3];
    CopyVector(g_attackA ? g_siteA : g_siteB, site);
    float dirX = g_tSpawn[0] - site[0];
    float dirY = g_tSpawn[1] - site[1];
    Normalize2D(dirX, dirY);

    g_targetCount = 0;
    // AssignTargets reserves target 0 for the C4 carrier. Give that player
    // the central approach, not the leftmost flank of a five-player fan.
    BuildAround(site, 1, 520.0, 900.0, true, dirX, dirY);
    if (g_plan == TPlan_Rush)
        BuildAround(site, count - 1, 520.0, 900.0, true, dirX, dirY);
    else if (g_plan == TPlan_Split)
        BuildAround(site, count - 1, 500.0, 1050.0, true, dirX, dirY);
    else
        BuildAround(site, count - 1, 520.0, 950.0, true, dirX, dirY);
    FillMissingTargetsAt(count, g_tSpawn);
    AssignTargets(bots, count, Route_Fastest, FindBombCarrier(), count);
    g_phase = TPhase_AttackStage;
    g_phaseStarted = GetGameTime();
    DebugLog("T attack staging started for %d bots.", count);
}

void PlanAttackCommit()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectTBots(bots);
    if (count == 0)
        return;

    float site[3], otherSite[3];
    CopyVector(g_attackA ? g_siteA : g_siteB, site);
    CopyVector(g_attackA ? g_siteB : g_siteA, otherSite);
    g_targetCount = 0;
    AppendProjectedTarget(site); // Reserved for the bomb carrier when present.

    float dirX = g_tSpawn[0] - site[0];
    float dirY = g_tSpawn[1] - site[1];
    Normalize2D(dirX, dirY);
    if (g_plan == TPlan_Rush)
    {
        BuildAround(site, count - 1, 120.0, 520.0, true, dirX, dirY);
    }
    else if (g_plan == TPlan_Split)
    {
        // A circular random spread can pick positions behind the site on the
        // CT side, causing attackers to path through the wrong entry.
        BuildAround(site, count - 1, 320.0, 850.0, true, dirX, dirY);
    }
    else
    {
        int mainCount = count >= 4 ? count - 2 : count - 1;
        BuildAround(site, mainCount, 220.0, 650.0, true, dirX, dirY);
        if (g_targetCount < count)
        {
            float middle[3];
            for (int axis = 0; axis < 3; axis++) middle[axis] = (g_siteA[axis] + g_siteB[axis]) * 0.5;
            AppendProjectedTarget(middle);
        }
        if (g_targetCount < count) AppendProjectedTarget(otherSite);
    }
    FillMissingTargetsAt(count, site);
    AssignTargets(bots, count, Route_Fastest, FindBombCarrier(), count);
    g_phase = TPhase_AttackCommit;
    g_phaseStarted = GetGameTime();
    DebugLog("Synchronized T attack committed with %d bots still available for orders.", count);
}

void PlanBombRecovery()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectTBots(bots);
    if (count == 0 || !NavMeshReady()) return;
    int ordered = g_cvEscortCount.IntValue + 1;
    if (ordered > count) ordered = count;
    g_targetCount = 0;
    AppendProjectedTarget(g_bombPosition);
    BuildAround(g_bombPosition, ordered - 1, 100.0, 420.0, false, 0.0, 0.0);
    FillMissingTargetsAt(ordered, g_bombPosition);
    AssignTargets(bots, count, Route_Fastest, 0, ordered);
    g_phase = TPhase_RecoverBomb;
    g_phaseStarted = GetGameTime();
    DebugLog("Assigned %d T bots to recover the dropped C4.", ordered);
}

void PlanPostPlant()
{
    int bots[MAXPLAYERS + 1];
    int count = CollectTBots(bots);
    if (count == 0 || !NavMeshReady()) return;
    g_targetCount = 0;
    BuildAround(g_bombPosition, count, 220.0, 720.0, false, 0.0, 0.0);
    FillMissingTargetsAt(count, g_bombPosition);
    AssignTargets(bots, count, Route_Safest, 0, count, true);
    g_phase = TPhase_PostPlant;
    g_phaseStarted = GetGameTime();
    DebugLog("Assigned %d T bots to post-plant positions.", count);
}

void AssignTargets(const int bots[MAXPLAYERS + 1], int botCount, RouteType route, int preferredClient, int targetLimit, bool postPlantAim = false)
{
    ClearOrders();
    bool used[MAXPLAYERS + 1];
    int firstTarget;
    if (preferredClient > 0 && IsTBot(preferredClient) && !g_combatReleased[preferredClient] && targetLimit > 0)
    {
        g_hasOrder[preferredClient] = true;
        CopyVector(g_targets[0], g_orderGoal[preferredClient]);
        if (postPlantAim) SetPostPlantLook(preferredClient, 0);
        g_orderRoute[preferredClient] = view_as<int>(route);
        for (int index = 0; index < botCount; index++)
            if (bots[index] == preferredClient) used[index] = true;
        firstTarget = 1;
    }

    for (int target = firstTarget; target < targetLimit && target < g_targetCount; target++)
    {
        int bestIndex = -1;
        float bestDistance = 99999999.0;
        for (int index = 0; index < botCount; index++)
        {
            int client = bots[index];
            if (used[index] || g_combatReleased[client] || !IsTBot(client)) continue;
            float position[3];
            GetClientAbsOrigin(client, position);
            float distance = GetVectorDistance(position, g_targets[target]);
            if (distance < bestDistance) { bestDistance = distance; bestIndex = index; }
        }
        if (bestIndex != -1)
        {
            int client = bots[bestIndex];
            used[bestIndex] = true;
            g_hasOrder[client] = true;
            CopyVector(g_targets[target], g_orderGoal[client]);
            if (postPlantAim) SetPostPlantLook(client, target);
            g_orderRoute[client] = view_as<int>(route);
        }
    }
}

void SetPostPlantLook(int client, int slot)
{
    TacticalAngles_SelectLook(client, g_orderGoal[client], g_ctSpawn, slot, g_orderLook[client]);
    g_hasLook[client] = true;
}

void BuildAround(const float origin[3], int wanted, float minRadius, float maxRadius, bool directional, float dirX, float dirY)
{
    if (wanted <= 0) return;
    CollectCandidates(origin, minRadius, maxRadius);
    float baseAngle = GetRandomFloat(0.0, 360.0);
    float targetRadius = (minRadius + maxRadius) * 0.5;
    for (int slot = 0; slot < wanted && g_targetCount < MAXPLAYERS + 1; slot++)
    {
        float wantedX, wantedY;
        if (directional)
            Rotate2D(dirX, dirY, (float(slot) - float(wanted - 1) * 0.5) * 34.0, wantedX, wantedY);
        else
        {
            float angle = baseAngle + 360.0 * float(slot) / float(wanted);
            wantedX = Cosine(DegToRad(angle));
            wantedY = Sine(DegToRad(angle));
        }
        int best = FindBestCandidate(origin, wantedX, wantedY, targetRadius);
        if (best != -1) AppendTarget(g_candidates[best]);
        else
        {
            float fallback[3];
            fallback[0] = origin[0] + wantedX * targetRadius;
            fallback[1] = origin[1] + wantedY * targetRadius;
            fallback[2] = origin[2];
            AppendProjectedTarget(fallback);
        }
    }
}

void CollectCandidates(const float origin[3], float minRadius, float maxRadius)
{
    g_candidateCount = 0;
    int startArea = NavMesh_GetNearestArea(origin, false, 1500.0, false, true, TEAM_ANY);
    if (startArea < 0) return;
    ArrayStack areas = new ArrayStack();
    areas.Push(startArea);
    NavMesh_CollectSurroundingAreas(areas, startArea, maxRadius + 400.0, 18.0, 100.0);
    while (!areas.Empty && g_candidateCount < MAX_CANDIDATES)
    {
        int area = areas.Pop();
        ArrayStack spots = new ArrayStack();
        NavMeshArea_GetHidingSpots(spots, area);
        int added;
        while (!spots.Empty && added < 3 && g_candidateCount < MAX_CANDIDATES)
        {
            float position[3];
            NavHidingSpot_GetPosition(spots.Pop(), position);
            if (FloatAbs(position[2] - origin[2]) <= 450.0)
            {
                float distance = Distance2D(origin, position);
                if (distance >= minRadius && distance <= maxRadius) { AddCandidate(position); added++; }
            }
        }
        delete spots;
        if (added == 0)
        {
            float center[3];
            if (NavMeshArea_GetCenter(area, center))
            {
                float distance = Distance2D(origin, center);
                if (distance >= minRadius && distance <= maxRadius) AddCandidate(center);
            }
        }
    }
    delete areas;
}

void AddCandidate(const float position[3])
{
    for (int i = 0; i < g_candidateCount; i++)
        if (Distance2D(g_candidates[i], position) < 72.0) return;
    CopyVector(position, g_candidates[g_candidateCount++]);
}

int FindBestCandidate(const float origin[3], float wantedX, float wantedY, float targetRadius)
{
    int best = -1;
    float bestScore = -999999.0;
    for (int i = 0; i < g_candidateCount; i++)
    {
        float dx = g_candidates[i][0] - origin[0], dy = g_candidates[i][1] - origin[1];
        float distance = SquareRoot(dx * dx + dy * dy);
        if (distance < 1.0) continue;
        float score = ((dx / distance) * wantedX + (dy / distance) * wantedY) * 900.0 - FloatAbs(distance - targetRadius) * 0.35;
        for (int target = 0; target < g_targetCount; target++)
        {
            float separation = Distance2D(g_candidates[i], g_targets[target]);
            if (separation < 140.0) score -= (140.0 - separation) * 12.0;
        }
        if (score > bestScore) { bestScore = score; best = i; }
    }
    return best;
}

void AppendProjectedTarget(const float position[3])
{
    int area = NavMesh_GetNearestArea(position, true, 1200.0, false, true, TEAM_ANY);
    float projected[3];
    if (area >= 0 && NavMeshArea_GetCenter(area, projected)) AppendTarget(projected);
    else AppendTarget(position);
}

void AppendTarget(const float position[3])
{
    if (g_targetCount < MAXPLAYERS + 1) CopyVector(position, g_targets[g_targetCount++]);
}

void FillMissingTargetsAt(int wanted, const float fallback[3])
{
    while (g_targetCount < wanted) AppendProjectedTarget(fallback);
}

TBuyState ClassifyTBuy()
{
    BotEquipmentTier tier = BotEquipment_ClassifyTeam(CS_TEAM_T);
    if (tier == BotEquip_Full) return TBuy_Full;
    if (tier == BotEquip_Force) return TBuy_Force;
    return TBuy_Eco;
}

TAttackPlan ChooseAttackPlan(TBuyState buy)
{
    int rush, split;
    if (buy == TBuy_Full) { rush = g_cvFullRushChance.IntValue; split = g_cvFullSplitChance.IntValue; }
    else if (buy == TBuy_Force) { rush = g_cvForceRushChance.IntValue; split = g_cvForceSplitChance.IntValue; }
    else { rush = g_cvEcoRushChance.IntValue; split = g_cvEcoSplitChance.IntValue; }
    if (rush + split > 100) split = 100 - rush;
    int roll = GetRandomInt(1, 100);
    if (roll <= rush) return TPlan_Rush;
    if (roll <= rush + split) return TPlan_Split;
    return TPlan_Default;
}

bool RefreshGeometry()
{
    if (CountBombTargets() < 2)
    {
        g_geometryReady = false;
        return false;
    }

    int manager = FindEntityByClassname(-1, "cs_player_manager");
    if (manager == -1 || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterA") || !HasEntProp(manager, Prop_Send, "m_bombsiteCenterB")) return false;
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterA", g_siteA);
    GetEntPropVector(manager, Prop_Send, "m_bombsiteCenterB", g_siteB);
    g_geometryReady = GetVectorDistance(g_siteA, g_siteB) >= 100.0
        && GetSpawnCenter("info_player_terrorist", g_tSpawn)
        && GetSpawnCenter("info_player_counterterrorist", g_ctSpawn);
    return g_geometryReady;
}

int CountBombTargets()
{
    int count;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_bomb_target")) != -1)
        count++;
    entity = -1;
    while ((entity = FindEntityByClassname(entity, "info_bomb_target")) != -1)
        count++;
    return count;
}

bool GetSpawnCenter(const char[] classname, float result[3])
{
    result[0] = result[1] = result[2] = 0.0;
    int entity = -1, count;
    while ((entity = FindEntityByClassname(entity, classname)) != -1)
    {
        float origin[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        AddVectors(result, origin, result);
        count++;
    }
    if (count == 0) return false;
    ScaleVector(result, 1.0 / float(count));
    return true;
}

bool NavMeshReady()
{
    return NativeAvailable("NavMesh_Exists") && NativeAvailable("NavMesh_GetNearestArea")
        && NativeAvailable("NavMesh_CollectSurroundingAreas") && NativeAvailable("NavMeshArea_GetCenter")
        && NativeAvailable("NavMeshArea_GetHidingSpots") && NativeAvailable("NavHidingSpot_GetPosition") && NavMesh_Exists();
}

bool NativeAvailable(const char[] name) { return GetFeatureStatus(FeatureType_Native, name) == FeatureStatus_Available; }

int CollectTBots(int clients[MAXPLAYERS + 1])
{
    int count;
    for (int client = 1; client <= MaxClients; client++) if (IsTBot(client)) clients[count++] = client;
    return count;
}

bool IsTBot(int client)
{
    return client >= 1 && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client)
        && IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_T;
}

int FindBombCarrier()
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "weapon_c4")) != -1)
    {
        int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
        if (IsTBot(owner)) return owner;
    }
    return 0;
}

int FindLooseC4()
{
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "weapon_c4")) != -1)
        if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") <= 0) return entity;
    return -1;
}

void ReleaseOrder(int client, const char[] reason)
{
    if (client < 1 || client > MaxClients || !g_hasOrder[client] || !IsClientInGame(client) || !IsFakeClient(client)) return;
    g_hasOrder[client] = false;
    g_hasLook[client] = false;
    g_combatReleased[client] = true;
    DebugLog("Released %N to native combat AI: %s", client, reason);
}

void ClearOrders()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_hasOrder[client] = false;
        g_hasLook[client] = false;
    }
}
void ClearCombatReleases() { for (int client = 1; client <= MaxClients; client++) g_combatReleased[client] = false; }
void ResetDirector() { ClearOrders(); g_phase = TPhase_Idle; g_phaseStarted = 0.0; g_targetCount = 0; g_attackContact = false; }

void GetOrderProgress(float distanceLimit, int &ready, int &ordered)
{
    ready = 0;
    ordered = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsTBot(client) || !g_hasOrder[client] || g_combatReleased[client])
            continue;
        ordered++;
        float position[3];
        GetClientAbsOrigin(client, position);
        if (Distance2D(position, g_orderGoal[client]) <= distanceLimit)
            ready++;
    }
}

bool OrdersMeetReadyPercent(float distanceLimit, int requiredPercent)
{
    int ready, ordered;
    GetOrderProgress(distanceLimit, ready, ordered);
    return ordered == 0 || ready * 100 >= ordered * requiredPercent;
}

float Distance2D(const float first[3], const float second[3])
{
    float dx = first[0] - second[0], dy = first[1] - second[1];
    return SquareRoot(dx * dx + dy * dy);
}

void Normalize2D(float &x, float &y)
{
    float length = SquareRoot(x * x + y * y);
    if (length < 1.0) { x = 1.0; y = 0.0; }
    else { x /= length; y /= length; }
}

void Rotate2D(float x, float y, float degrees, float &outX, float &outY)
{
    float radians = DegToRad(degrees);
    outX = x * Cosine(radians) - y * Sine(radians);
    outY = x * Sine(radians) + y * Cosine(radians);
}

void CopyVector(const float source[3], float destination[3])
{
    destination[0] = source[0]; destination[1] = source[1]; destination[2] = source[2];
}

void GetPhaseName(TPhase phase, char[] buffer, int length)
{
    switch (phase) { case TPhase_AttackStage: strcopy(buffer, length, "attack-stage"); case TPhase_AttackCommit: strcopy(buffer, length, "attack-commit"); case TPhase_RecoverBomb: strcopy(buffer, length, "recover-c4"); case TPhase_PostPlant: strcopy(buffer, length, "post-plant"); default: strcopy(buffer, length, "idle"); }
}

void GetBuyName(TBuyState buy, char[] buffer, int length)
{
    switch (buy) { case TBuy_Eco: strcopy(buffer, length, "eco"); case TBuy_Force: strcopy(buffer, length, "force"); default: strcopy(buffer, length, "full"); }
}

void GetPlanName(TAttackPlan plan, char[] buffer, int length)
{
    switch (plan) { case TPlan_Rush: strcopy(buffer, length, "rush"); case TPlan_Split: strcopy(buffer, length, "split"); default: strcopy(buffer, length, "default"); }
}

void DebugLog(const char[] format, any ...)
{
    if (!g_cvDebug.BoolValue) return;
    char message[256];
    VFormat(message, sizeof(message), format, 2);
    LogMessage("[T Tactics] %s", message);
}
