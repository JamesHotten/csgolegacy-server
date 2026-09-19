#if defined _bot_tactical_angles_included
    #endinput
#endif
#define _bot_tactical_angles_included

// Shared, stateless angle selection for the CT and T directors. Callers retain
// ownership of phase/state so one side can be disabled or rolled back alone.

public bool TacticalAngles_TraceFilter(int entity, int contentsMask, any client)
{
    // World geometry is always traced by the engine. Ignore players so a
    // teammate crossing the ray while the plan is built does not invalidate it.
    return entity > MaxClients;
}

stock float TacticalAngles_GetPreferredDistance(int client)
{
    int weapon = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
    if (!IsValidEntity(weapon))
        return 600.0;

    char classname[48];
    GetEntityClassname(weapon, classname, sizeof(classname));
    if (StrEqual(classname, "weapon_awp") || StrEqual(classname, "weapon_ssg08")
        || StrEqual(classname, "weapon_scar20") || StrEqual(classname, "weapon_g3sg1"))
        return 950.0;

    if (StrEqual(classname, "weapon_nova") || StrEqual(classname, "weapon_xm1014")
        || StrEqual(classname, "weapon_mag7") || StrEqual(classname, "weapon_sawedoff")
        || StrEqual(classname, "weapon_mac10") || StrEqual(classname, "weapon_mp9")
        || StrEqual(classname, "weapon_mp7") || StrEqual(classname, "weapon_mp5sd")
        || StrEqual(classname, "weapon_ump45") || StrEqual(classname, "weapon_p90")
        || StrEqual(classname, "weapon_bizon"))
        return 500.0;

    return 750.0;
}

stock float TacticalAngles_GetSlotOffset(int slot)
{
    switch (slot % 5)
    {
        case 1: return -35.0;
        case 2: return 35.0;
        case 3: return -70.0;
        case 4: return 70.0;
    }
    return 0.0;
}

stock bool TacticalAngles_IsVisible(const float start[3], const float target[3], int client, float &fraction)
{
    Handle trace = TR_TraceRayFilterEx(start, target, MASK_VISIBLE, RayType_EndPoint,
        TacticalAngles_TraceFilter, client);
    fraction = TR_GetFraction(trace);
    delete trace;
    return fraction >= 0.90;
}

stock bool TacticalAngles_SelectLook(int client, const float hold[3], const float threat[3], int slot, float result[3])
{
    float baseX = threat[0] - hold[0];
    float baseY = threat[1] - hold[1];
    Normalize2D(baseX, baseY);

    float slotX, slotY;
    Rotate2D(baseX, baseY, TacticalAngles_GetSlotOffset(slot), slotX, slotY);
    float preferredDistance = TacticalAngles_GetPreferredDistance(client);
    float deviations[5] = {0.0, -10.0, 10.0, -20.0, 20.0};
    float eye[3];
    CopyVector(hold, eye);
    eye[2] += 64.0;

    bool found;
    float bestScore = -999999.0;
    for (int attempt = 0; attempt < sizeof(deviations); attempt++)
    {
        float dirX, dirY;
        Rotate2D(slotX, slotY, deviations[attempt], dirX, dirY);
        float desired[3];
        desired[0] = hold[0] + dirX * preferredDistance;
        desired[1] = hold[1] + dirY * preferredDistance;
        desired[2] = hold[2];

        float candidates[2][3];
        CopyVector(desired, candidates[0]);
        int area = NavMesh_GetNearestArea(desired, true, 900.0, false, true, TEAM_ANY);
        int candidateCount = 1;
        if (area >= 0 && NavMeshArea_GetCenter(area, candidates[1]))
            candidateCount = 2;

        for (int candidate = 0; candidate < candidateCount; candidate++)
        {
            candidates[candidate][2] += 64.0;
            float distance = Distance2D(hold, candidates[candidate]);
            if (distance < 128.0)
                continue;

            float visibleFraction;
            bool visible = TacticalAngles_IsVisible(eye, candidates[candidate], client, visibleFraction);
            float score = visibleFraction * 400.0 - FloatAbs(distance - preferredDistance) * 0.15
                - FloatAbs(deviations[attempt]) * 2.0;
            if (visible)
                score += 1000.0;
            if (!found || score > bestScore)
            {
                found = true;
                bestScore = score;
                CopyVector(candidates[candidate], result);
            }
        }
    }

    if (!found)
    {
        result[0] = hold[0] + slotX * preferredDistance;
        result[1] = hold[1] + slotY * preferredDistance;
        result[2] = hold[2] + 64.0;
    }
    return found;
}
