#if defined _bot_tactical_recovery_included
    #endinput
#endif
#define _bot_tactical_recovery_included

// Included by each director (their order state remains independent).
float g_recoveryDriveAt[MAXPLAYERS + 1];
bool g_recoveryTried[MAXPLAYERS + 1];
float g_recoverySearchAt;

stock void TacticalRecovery_Report(int client, bool driving)
{
    g_recoveryDriveAt[client] = driving ? GetGameTime() : 0.0;
}

stock bool TacticalRecovery_Driving(int client, float now)
{
    return g_recoveryDriveAt[client] > 0.0 && now - g_recoveryDriveAt[client] <= 0.35;
}

public int TacticalRecovery_Cost(int area, int from, int ladder, any maxCost)
{
    if (from < 0) return 0;
    float a[3], b[3];
    if (!NavMeshArea_GetCenter(from, a) || !NavMeshArea_GetCenter(area, b)) return -1;
    int cost = NavMeshArea_GetCostSoFar(from) + RoundToCeil(GetVectorDistance(a, b));
    return cost <= maxCost ? cost : -1;
}

stock bool TacticalRecovery_Find(int client, const float pos[3], float result[3])
{
    if (!NativeAvailable("NavMesh_BuildPath") || !NativeAvailable("NavMeshArea_GetCostSoFar")
        || !NativeAvailable("NavMeshArea_GetPlaceCanonical"))
        return false;
    float goal[3];
    CopyVector(g_orderGoal[client], goal);
    int original = NavMesh_GetNearestArea(goal, false, 100.0, false, true, TEAM_ANY);
    int start = NavMesh_GetNearestArea(pos, false, 140.0, false, true, TEAM_ANY);
    if (original < 0 || start < 0) return false;
    char lane[32], name[32];
    NavMeshArea_GetPlaceCanonical(original, lane, sizeof(lane));
    ArrayStack areas = new ArrayStack();
    NavMesh_CollectSurroundingAreas(areas, original, 380.0, 24.0, 42.0);
    float best = 999999.0;
    int attempts;
    while (!areas.Empty && attempts < 6)
    {
        int area = areas.Pop();
        float point[3];
        if (area == original || area == start || !NavMeshArea_GetCenter(area, point)) continue;
        float offset = GetVectorDistance(point, goal);
        if (offset < 65.0 || offset > 290.0 || FloatAbs(point[2] - goal[2]) > 42.0
            || GetVectorDistance(pos, point) < 160.0
            || GetVectorDistance(pos, point) > GetVectorDistance(pos, goal) + 100.0)
            continue;
        NavMeshArea_GetPlaceCanonical(area, name, sizeof(name));
        // Unlabeled NAV areas may only use a small, locally connected offset.
        if (!StrEqual(lane, name, false) || (!lane[0] && offset > 155.0)) continue;
        bool occupied;
        for (int peer = 1; peer <= MaxClients; peer++)
            if (peer != client && g_hasOrder[peer] && GetVectorDistance(point, g_orderGoal[peer]) < 90.0)
            { occupied = true; break; }
        if (occupied || offset >= best) continue;
        float foot[3], mins[3] = {-16.0,-16.0,0.0}, maxs[3] = {16.0,16.0,70.0};
        CopyVector(point, foot);
        foot[2] += 4.0;
        Handle hull = TR_TraceHullFilterEx(foot, foot, mins, maxs, MASK_PLAYERSOLID, TacticalAngles_TraceFilter, client);
        bool fits = !TR_DidHit(hull) && !TR_StartSolid(hull);
        delete hull;
        if (!fits) continue;
        attempts++;
        int closest;
        if (!NavMesh_BuildPath(start, area, point, TacticalRecovery_Cost, 6800, closest, 0.0, 0.0)
            || !NavMesh_BuildPath(area, original, goal, TacticalRecovery_Cost, 550, closest, 0.0, 0.0))
            continue;
        best = offset;
        CopyVector(point, result);
    }
    delete areas;
    return best < 999999.0;
}
