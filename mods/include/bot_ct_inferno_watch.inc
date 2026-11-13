#if defined _bot_ct_inferno_watch_included
    #endinput
#endif
#define _bot_ct_inferno_watch_included

// Paired positions and sightlines measured on the Legacy Inferno BSP/NAV.
// The target's Z already includes the 64-unit eye-height offset.
static const float g_CTInfernoHolds[5][3] = {
    {1825.0, -50.0, 128.6},  // A site -> top mid
    {2350.0, -512.5, 86.3},  // pit -> balcony
    {862.5, 2362.5, 142.0},  // near B -> Banana
    {662.5, 2575.0, 138.0},  // deep B -> Banana from a separate angle
    {1850.0, 1012.5, 165.7}  // arch rotator -> top mid
};
static const float g_CTInfernoLooks[5][3] = {
    {1350.0, 237.5, 193.1},
    {1999.5, -108.7, 315.4},
    {550.0, 1900.0, 194.4},
    {712.5, 2037.5, 197.7},
    {1300.0, 1212.5, 234.3}
};
static const char g_CTInfernoHoldPlaces[5][32] = {
    "BombsiteA", "Pit", "BombsiteB", "BombsiteB", "Arch"
};
static const char g_CTInfernoThreatPlaces[5][32] = {
    "TopofMid", "Balcony", "Banana", "Banana", "TopofMid"
};

stock int CTInferno_GetRole(int slot, int count)
{
    // Smaller teams keep one defender on each site before adding a rotator.
    if (count == 1) return 4;
    if (count <= 3) return slot == 0 ? 0 : slot == 1 ? 2 : 4;
    return slot;
}

stock bool CTInferno_ClearSight(const float eye[3], const float aim[3])
{
    if (GetVectorDistance(eye, aim) < 128.0) return false;
    Handle trace = TR_TraceRayFilterEx(eye, aim, MASK_VISIBLE, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
    bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace);
    delete trace;
    return clear;
}

stock bool CTInferno_GetPair(int role, float hold[3], float aim[3])
{
    if (role < 0 || role >= sizeof(g_CTInfernoHolds) || !NativeAvailable("NavMeshArea_GetPlaceCanonical")) return false;
    CopyVector(g_CTInfernoHolds[role], hold);
    CopyVector(g_CTInfernoLooks[role], aim);
    float foot[3], eye[3], enemyFoot[3];
    CopyVector(hold, foot);
    CopyVector(hold, eye);
    CopyVector(aim, enemyFoot);
    foot[2] += 3.0;
    eye[2] += 64.0;
    enemyFoot[2] -= 64.0;
    int area = NavMesh_GetNearestArea(hold, true, 96.0, false, false, TEAM_ANY);
    int entry = NavMesh_GetNearestArea(enemyFoot, true, 96.0, false, false, TEAM_ANY);
    if (area < 0 || entry < 0) return false;
    char place[32];
    NavMeshArea_GetPlaceCanonical(area, place, sizeof(place));
    if (!StrEqual(place, g_CTInfernoHoldPlaces[role])) return false;
    NavMeshArea_GetPlaceCanonical(entry, place, sizeof(place));
    if (!StrEqual(place, g_CTInfernoThreatPlaces[role])) return false;
    float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0};
    Handle hull = TR_TraceHullFilterEx(foot, foot, mins, maxs, MASK_PLAYERSOLID, TacticalAngles_TraceFilter, 0);
    bool fits = !TR_DidHit(hull) && !TR_StartSolid(hull);
    if (!fits)
    {
        int blocker = TR_GetEntityIndex(hull);
        char classname[64];
        if (blocker >= 0 && IsValidEntity(blocker)) GetEntityClassname(blocker, classname, sizeof(classname));
        DebugLog("Inferno pair %d standing hull blocked by %d %s", role, blocker, classname);
    }
    delete hull;
    return fits && CTInferno_ClearSight(eye, aim);
}
