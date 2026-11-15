#if defined _bot_objective_watch_included
    #endinput
#endif
#define _bot_objective_watch_included

// One shared scan per objective plan, not per player command. Prefer an
// unused visible named entrance. A marked look must never rotate to an
// unrelated angle just because it has more open space.
bool g_objectiveNamed[MAXPLAYERS + 1];

stock int ObjectiveWatch_Score(const ArrayList lanes, const float hold[3], float candidates[3][3])
{
    float eye[3], item[4], best[3], score[3] = {999999.0,999999.0,999999.0};
    CopyVector(hold, eye);
    eye[2] += 64.0;
    for (int i = 0; i < lanes.Length; i++)
    {
        lanes.GetArray(i, item, sizeof(item));
        int lane = RoundToFloor(item[3]);
        best[0] = item[0]; best[1] = item[1]; best[2] = item[2] + 64.0;
        float range = GetVectorDistance(eye, best);
        if (range < 132.0 || range > 1600.0 || FloatAbs(eye[2] - best[2]) > 160.0) continue;
        float rank = FloatAbs(range - 500.0);
        if (rank >= score[lane] || !TacticalAngles_ClearExactRay(eye, best)) continue;
        score[lane] = rank;
        CopyVector(best, candidates[lane]);
    }
    int mask;
    for (int lane = 0; lane < 3; lane++)
        if (score[lane] < 999999.0) mask |= 1 << lane;
    return mask;
}

stock int ObjectiveWatch_Available(const ArrayList lanes, const float hold[3])
{
    float candidates[3][3];
    int mask = ObjectiveWatch_Score(lanes, hold, candidates);
    int count;
    for (int lane = 0; lane < 3; lane++)
        if (mask & (1 << lane)) count++;
    return count;
}

stock bool ObjectiveWatch_Select(const ArrayList lanes, const float hold[3], int &used, float look[3])
{
    float candidates[3][3];
    int mask = ObjectiveWatch_Score(lanes, hold, candidates);
    for (int pass = 0; pass < 2; pass++)
        for (int lane = 0; lane < 3; lane++)
        {
            if (!(mask & (1 << lane)) || (pass == 0 && (used & (1 << lane)))) continue;
            used |= 1 << lane;
            CopyVector(candidates[lane], look);
            return true;
        }
    return false;
}

stock ArrayList ObjectiveWatch_Collect(int map, int site, bool retake, const float center[3])
{
    ArrayList points = new ArrayList(4);
    if (map < 0 || !NativeAvailable("NavMeshArea_GetPlaceCanonical") || !NativeAvailable("NavMesh_WorldToGridX")
        || !NativeAvailable("NavMesh_WorldToGridY") || !NativeAvailable("NavMesh_GetAreasOnGrid")) return points;
    char names[3][32];
    for (int lane = 0; lane < 3; lane++) TacticalMap_GetWatchPlace(map, site, lane, retake, names[lane], sizeof(names[]));
    ArrayStack areas = new ArrayStack();
    StringMap seen = new StringMap();
    for (int x = NavMesh_WorldToGridX(center[0] - 1500.0); x <= NavMesh_WorldToGridX(center[0] + 1500.0); x++)
        for (int y = NavMesh_WorldToGridY(center[1] - 1500.0); y <= NavMesh_WorldToGridY(center[1] + 1500.0); y++)
            NavMesh_GetAreasOnGrid(areas, x, y);
    int counts[3];
    while (!areas.Empty)
    {
        int area = areas.Pop();
        char key[16], name[32];
        IntToString(area, key, sizeof(key));
        if (!seen.SetValue(key, 1, false)) continue;
        NavMeshArea_GetPlaceCanonical(area, name, sizeof(name));
        for (int lane = 0; lane < 3; lane++)
        {
            if (counts[lane] >= 80 || !names[lane][0] || !StrEqual(name, names[lane], false)) continue;
            float point[4], nav[3];
            if (!NavMeshArea_GetCenter(area, nav) || GetVectorDistance(center, nav) > 1750.0) continue;
            point[0] = nav[0]; point[1] = nav[1]; point[2] = nav[2]; point[3] = float(lane);
            points.PushArray(point);
            counts[lane]++;
            if (counts[lane] < 80 && NativeAvailable("NavMeshArea_GetClosestPointOnArea"))
            {
                // The center of a named area can be behind a corner even
                // though its near edge is the actual doorway/ramp to hold.
                NavMeshArea_GetClosestPointOnArea(area, center, nav);
                float dx = nav[0] - point[0], dy = nav[1] - point[1];
                if (dx * dx + dy * dy >= 36.0 * 36.0)
                {
                    point[0] = nav[0]; point[1] = nav[1]; point[2] = nav[2];
                    points.PushArray(point);
                    counts[lane]++;
                }
            }
        }
    }
    delete areas;
    delete seen;
    return points;
}

stock bool ObjectiveCover_Shot(const float from[3], const float to[3])
{
    Handle ray = TR_TraceRayFilterEx(from, to, MASK_SHOT, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
    bool clear = !TR_StartSolid(ray) && !TR_DidHit(ray);
    delete ray;
    return clear;
}

stock int ObjectiveCover_Exposure(const ArrayList lanes, const float feet[3])
{
    float item[4], eye[3], target[3];
    int mask, exposed;
    for (int i = 0; i < lanes.Length; i++)
    {
        lanes.GetArray(i, item, sizeof(item));
        int lane = RoundToFloor(item[3]);
        if (mask & (1 << lane)) continue;
        eye[0] = item[0]; eye[1] = item[1]; eye[2] = item[2] + 64.0;
        float distance = GetVectorDistance(eye, feet);
        if (distance < 120.0 || distance > 2200.0) continue;
        CopyVector(feet, target);
        target[2] += 64.0;
        bool clear = ObjectiveCover_Shot(eye, target);
        if (!clear)
        {
            target[2] -= 14.0;
            clear = ObjectiveCover_Shot(eye, target);
            float bearing = ArcTangent2(eye[1] - feet[1], eye[0] - feet[0]);
            for (int side = -1; !clear && side <= 1; side += 2)
            {
                target[0] = feet[0] + float(side) * 12.0 * Sine(bearing);
                target[1] = feet[1] - float(side) * 12.0 * Cosine(bearing);
                clear = ObjectiveCover_Shot(eye, target);
            }
        }
        if (clear) { mask |= 1 << lane; exposed++; }
    }
    return exposed;
}

stock bool ObjectiveCover_Floor(const float point[3], float foot[3])
{
    float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0}, below[3];
    CopyVector(point, foot);
    foot[2] += 6.0;
    CopyVector(foot, below);
    below[2] -= 25.0;
    Handle hull = TR_TraceHullFilterEx(foot, below, mins, maxs, MASK_PLAYERSOLID, TacticalAngles_TraceFilter, 0);
    bool fits = TR_DidHit(hull) && !TR_StartSolid(hull) && !TR_AllSolid(hull);
    if (fits)
    {
        float normal[3];
        TR_GetPlaneNormal(hull, normal);
        fits = normal[2] >= 0.68;
        TR_GetEndPosition(foot, hull);
        foot[2] += 2.0;
    }
    delete hull;
    return fits;
}

stock int ObjectiveCover_AimLane(int map, int site, bool retake, const float aim[3])
{
    if (!NativeAvailable("NavMeshArea_GetPlaceCanonical")) return -1;
    float foot[3];
    CopyVector(aim, foot);
    foot[2] -= 64.0;
    int area = NavMesh_GetNearestArea(foot, false, 45.0, false, true, TEAM_ANY);
    if (area < 0) return -1;
    char name[32], expected[32];
    NavMeshArea_GetPlaceCanonical(area, name, sizeof(name));
    for (int lane = 0; lane < 3; lane++)
        if (TacticalMap_GetWatchPlace(map, site, lane, retake, expected, sizeof(expected))
            && StrEqual(name, expected, false)) return lane;
    return -1;
}

stock int ObjectiveCover_Support(int client, const float feet[3], bool measureLinks = false)
{
    int count;
    float eye[3], other[3];
    CopyVector(feet, eye);
    eye[2] += 64.0;
    for (int peer = 1; peer <= MaxClients; peer++)
    {
        if (peer == client || !g_hasOrder[peer]) continue;
        float distance = GetVectorDistance(feet, g_orderGoal[peer]);
        if (distance < (measureLinks ? 115.0 : 105.0)) return -1;
        if (!measureLinks || distance > 500.0 || FloatAbs(feet[2] - g_orderGoal[peer][2]) > 70.0) continue;
        CopyVector(g_orderGoal[peer], other);
        other[2] += 64.0;
        Handle trace = TR_TraceRayFilterEx(eye, other, MASK_VISIBLE, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
        if (!TR_DidHit(trace) && !TR_StartSolid(trace)) count++;
        delete trace;
    }
    return count;
}

stock void ObjectiveCover_AuditLinks(int &pairs, int &overlap, int &support)
{
    pairs = overlap = support = 0;
    for (int first = 1; first <= MaxClients; first++)
    {
        if (!g_hasOrder[first]) continue;
        for (int second = first + 1; second <= MaxClients; second++)
        {
            if (!g_hasOrder[second]) continue;
            pairs++;
            float distance = GetVectorDistance(g_orderGoal[first], g_orderGoal[second]);
            if (distance < 115.0) { overlap++; continue; }
            if (distance > 500.0 || FloatAbs(g_orderGoal[first][2] - g_orderGoal[second][2]) > 70.0) continue;
            float from[3], to[3];
            CopyVector(g_orderGoal[first], from);
            CopyVector(g_orderGoal[second], to);
            from[2] += 64.0;
            to[2] += 64.0;
            Handle trace = TR_TraceRayFilterEx(from, to, MASK_VISIBLE, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
            if (!TR_StartSolid(trace) && !TR_DidHit(trace)) support++;
            delete trace;
        }
    }
}

// Called once when publishing a hold. Only improve an exposed destination:
// same connected floor, still watching its assigned lane, and never stack
// onto a teammate or trade the last support line for a prettier solo spot.
stock bool ObjectiveCover_Refine(int client, const ArrayList lanes, int map, int site, bool retake,
    const float objective[3], bool preserveSupport, bool preserveDevice = false, int alternateLane = -1)
{
    if (lanes.Length == 0) return false;
    int initial = ObjectiveCover_Exposure(lanes, g_orderGoal[client]);
    if (initial < 2) return false;
    int area = NavMesh_GetNearestArea(g_orderGoal[client], false, 120.0, false, true, TEAM_ANY);
    if (area < 0) return false;
    int lane = ObjectiveCover_AimLane(map, site, retake, g_orderLook[client]);
    if (lane < 0 && alternateLane >= 0) lane = alternateLane;
    int originalSupport = preserveSupport ? ObjectiveCover_Support(client, g_orderGoal[client], true) : 0;
    float originalRadius = GetVectorDistance(objective, g_orderGoal[client]);
    float device[3], oldEye[3];
    CopyVector(objective, device);
    device[2] += 12.0;
    CopyVector(g_orderGoal[client], oldEye);
    oldEye[2] += 64.0;
    bool keepDevice = preserveDevice && ObjectiveCover_Shot(oldEye, device);
    ArrayStack nearby = new ArrayStack();
    NavMesh_CollectSurroundingAreas(nearby, area, alternateLane >= 0 ? 740.0 : 560.0, 22.0, 35.0);
    int budget = 28, bestExposure = initial;
    float bestDistance = 999999.0, bestPoint[3], bestAim[3];
    while (!nearby.Empty && budget > 0)
    {
        float center[3], point[3], eye[3], aim[3];
        if (!NavMeshArea_GetCenter(nearby.Pop(), center) || !ObjectiveCover_Floor(center, point)) continue;
        float distance = GetVectorDistance(point, g_orderGoal[client]);
        float radius = GetVectorDistance(point, objective);
        if (distance < 45.0 || distance > (alternateLane >= 0 ? 575.0 : 420.0)
            || FloatAbs(point[2] - g_orderGoal[client][2]) > (alternateLane >= 0 ? 110.0 : 40.0)
            || radius > originalRadius + 150.0) continue;
        int support = ObjectiveCover_Support(client, point, preserveSupport);
        if (support < 0 || (originalSupport > 0 && support < originalSupport)) continue;
        budget--;
        int exposure = ObjectiveCover_Exposure(lanes, point);
        if (exposure >= initial || exposure > bestExposure || (exposure == bestExposure && distance >= bestDistance)) continue;
        CopyVector(point, eye);
        eye[2] += 64.0;
        if (keepDevice && !ObjectiveCover_Shot(eye, device)) continue;
        if (lane >= 0)
        {
            float targets[3][3];
            if (!(ObjectiveWatch_Score(lanes, point, targets) & (1 << lane))) continue;
            CopyVector(targets[lane], aim);
        }
        else
        {
            CopyVector(g_orderLook[client], aim);
            if (GetVectorDistance(eye, aim) < 150.0 || !TacticalAngles_ClearExactRay(eye, aim)) continue;
        }
        bestExposure = exposure;
        bestDistance = distance;
        CopyVector(point, bestPoint);
        CopyVector(aim, bestAim);
    }
    delete nearby;
    if (bestExposure >= initial) return false;
    CopyVector(bestPoint, g_orderGoal[client]);
    CopyVector(bestAim, g_orderLook[client]);
    return true;
}
