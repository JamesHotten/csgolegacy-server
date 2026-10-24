#if defined _bot_ct_entrance_watch_included
    #endinput
#endif
#define _bot_ct_entrance_watch_included

// Named NAV places, not guessed world coordinates. Opening CT orders only.
// An entrance must have a directly visible candidate from the assigned hold;
// otherwise the caller retains the established generic angle planner.
stock bool CTEntrance_Profile(const char[] map, int site, int entrance, char[] place, int length)
{
    place[0] = '\0';
    if (site < 0 || site > 1 || entrance < 0 || entrance > 2) return false;
    if (StrEqual(map, "de_mirage", false))
    {
        if (site == 0)
        {
            switch (entrance)
            {
                case 0: strcopy(place, length, "TRamp");
                case 1: strcopy(place, length, "PalaceInterior");
                case 2: strcopy(place, length, "Connector");
            }
        }
        else
        {
            switch (entrance)
            {
                case 0: strcopy(place, length, "Apartments");
                case 1: strcopy(place, length, "Catwalk");
            }
        }
    }
    else if (StrEqual(map, "de_dust2", false))
    {
        if (site == 0)
        {
            switch (entrance)
            {
                case 0: strcopy(place, length, "LongA");
                case 1: strcopy(place, length, "Short");
            }
        }
        else
        {
            switch (entrance)
            {
                case 0: strcopy(place, length, "UpperTunnel");
                case 1: strcopy(place, length, "BDoors");
            }
        }
    }
    return place[0] != '\0';
}

stock void CTEntrance_Consider(int client, const float hold[3], const float eye[3],
    const float candidate[3], float preferred, float &best, float result[3])
{
    float distance = Distance2D(hold, candidate);
    if (distance < 128.0 || distance > 1800.0 || FloatAbs(candidate[2] - hold[2]) > 400.0) return;
    float target[3], fraction;
    CopyVector(candidate, target);
    target[2] += 64.0;
    if (!TacticalAngles_IsVisible(eye, target, client, fraction)) return;
    float score = -FloatAbs(distance - preferred);
    if (score > best)
    {
        best = score;
        CopyVector(target, result);
    }
}

stock bool CTEntrance_SelectLook(int client, const float hold[3], int site,
    int &usedEntrances, float result[3], char[] selectedPlace, int length)
{
    selectedPlace[0] = '\0';
    if (GetFeatureStatus(FeatureType_Native, "NavMeshArea_GetPlaceCanonical") != FeatureStatus_Available) return false;
    if (!NativeAvailable("NavMesh_WorldToGridX") || !NativeAvailable("NavMesh_WorldToGridY")
        || !NativeAvailable("NavMesh_GetAreasOnGrid")) return false;
    char map[64], places[3][32];
    GetCurrentMap(map, sizeof(map));
    if (!CTEntrance_Profile(map, site, 0, places[0], 32)) return false;
    for (int entry = 1; entry < 3; entry++)
        CTEntrance_Profile(map, site, entry, places[entry], 32);
    ArrayStack areas = new ArrayStack();
    // Visibility is spatial, not walk connectivity: CT cannot walk up a
    // one-way palace/apartments drop, but must still cover that entrance.
    int minX = NavMesh_WorldToGridX(hold[0] - 1800.0), maxX = NavMesh_WorldToGridX(hold[0] + 1800.0);
    int minY = NavMesh_WorldToGridY(hold[1] - 1800.0), maxY = NavMesh_WorldToGridY(hold[1] + 1800.0);
    for (int x = minX; x <= maxX; x++)
        for (int y = minY; y <= maxY; y++)
            NavMesh_GetAreasOnGrid(areas, x, y);
    StringMap visited = new StringMap();
    float eye[3], scores[3], targets[3][3];
    CopyVector(hold, eye);
    eye[2] += 64.0;
    for (int entry = 0; entry < 3; entry++) scores[entry] = -999999.0;
    float preferred = TacticalAngles_GetPreferredDistance(client);
    while (!areas.Empty)
    {
        int area = areas.Pop();
        char key[16];
        IntToString(area, key, sizeof(key));
        int ignored;
        if (visited.GetValue(key, ignored)) continue;
        visited.SetValue(key, 1);
        char place[32];
        NavMeshArea_GetPlaceCanonical(area, place, sizeof(place));
        for (int entry = 0; entry < 3; entry++)
        {
            if (places[entry][0] == '\0' || !StrEqual(place, places[entry], false)) continue;
            float center[3];
            if (NavMeshArea_GetCenter(area, center))
                CTEntrance_Consider(client, hold, eye, center, preferred, scores[entry], targets[entry]);
            if (GetFeatureStatus(FeatureType_Native, "NavMeshArea_GetClosestPointOnArea") == FeatureStatus_Available)
            {
                // A room's NAV center can be hidden while its entrance edge
                // is visible. Do not require looking through the whole room.
                float edge[3];
                NavMeshArea_GetClosestPointOnArea(area, hold, edge);
                CTEntrance_Consider(client, hold, eye, edge, preferred, scores[entry], targets[entry]);
            }
        }
    }
    delete areas;
    delete visited;
    // First cover an unassigned visible entrance, then allow crossfire on an
    // already covered entrance if no new entrance is visible from this hold.
    for (int pass = 0; pass < 2; pass++)
    {
        for (int entry = 0; entry < 3; entry++)
        {
            if (scores[entry] <= -999999.0 || (pass == 0 && (usedEntrances & (1 << entry)) != 0)) continue;
            usedEntrances |= 1 << entry;
            CopyVector(targets[entry], result);
            strcopy(selectedPlace, length, places[entry]);
            return true;
        }
    }
    return false;
}
