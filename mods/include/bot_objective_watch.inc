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
