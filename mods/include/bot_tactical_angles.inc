#if defined _bot_tactical_angles_included
    #endinput
#endif
#define _bot_tactical_angles_included

// Shared angle selection for the CT and T directors. Callers retain
// ownership of phase and movement; each plugin has a separate look cache.

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

stock bool TacticalAngles_RequireClearWatch(const float hold[3], float look[3])
{
    float eye[3], ray[3];
    CopyVector(hold, eye);
    eye[2] += 64.0;
    MakeVectorFromPoints(eye, look, ray);
    float distance = GetVectorLength(ray);
    if (distance < 128.0) return false;
    Handle trace = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint, TacticalAngles_TraceFilter, 0);
    bool clear = !TR_StartSolid(trace) && !TR_DidHit(trace);
    float visibleDistance = distance * TR_GetFraction(trace);
    bool canShorten = !TR_StartSolid(trace) && visibleDistance >= 256.0;
    delete trace;
    if (clear) return true;
    if (!canShorten) return false;
    // The far end might be solid even though the actual line of fire is
    // usable. Aim just short of the surface, without inventing another sector.
    ScaleVector(ray, (visibleDistance - 24.0) / distance);
    AddVectors(eye, ray, look);
    return true;
}

// The director plans a sector from the assigned slot, but the engine may
// stop the BOT well short of it. Validate from the current eye only when
// a fixed look can be applied, independently of the movement/hold order.
enum struct TacticalWatchSample
{
    int userId;
    int phase;
    float time;
    float eye[3];
    float goal[3];
    float planned[3];
    float look[3];
    bool valid;
}

TacticalWatchSample g_tacticalWatch[MAXPLAYERS + 1];

stock bool TacticalAngles_ClipWatchRay(const float eye[3], float look[3])
{
    float ray[3];
    MakeVectorFromPoints(eye, look, ray);
    float length = GetVectorLength(ray);
    if (length < 1.0) return false;
    Handle trace = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint,
        TacticalAngles_TraceFilter, 0);
    bool hit = TR_DidHit(trace);
    bool solid = TR_StartSolid(trace);
    float visible = length * TR_GetFraction(trace);
    delete trace;
    if (solid) return false;
    if (!hit) return true; // A nearby visible objective is a valid look.
    if (visible < 152.0) return false;
    ScaleVector(ray, (visible - 24.0) / length);
    AddVectors(eye, ray, look);
    return true;
}

stock bool TacticalAngles_SelectLiveWatch(int client, const float goal[3], const float planned[3], int phase, float look[3])
{
    float eye[3], now = GetGameTime();
    GetClientEyePosition(client, eye);
    int userid = GetClientUserId(client);
    if (g_tacticalWatch[client].userId == userid && g_tacticalWatch[client].phase == phase
        && now >= g_tacticalWatch[client].time && now - g_tacticalWatch[client].time < 0.25
        && GetVectorDistance(eye, g_tacticalWatch[client].eye, true) < 64.0
        && GetVectorDistance(goal, g_tacticalWatch[client].goal, true) < 1.0
        && GetVectorDistance(planned, g_tacticalWatch[client].planned, true) < 1.0)
    {
        CopyVector(g_tacticalWatch[client].look, look);
        // Recheck the cached ray so an edge, prop or closing door between
        // full searches cannot let an invalid angle through.
        if (g_tacticalWatch[client].valid
            && ((now == g_tacticalWatch[client].time && GetVectorDistance(eye, g_tacticalWatch[client].eye, true) < 0.01)
                || TacticalAngles_ClipWatchRay(eye, look))) return true;
        if (!g_tacticalWatch[client].valid) return false;
    }

    CopyVector(planned, look);
    bool valid = TacticalAngles_ClipWatchRay(eye, look);
    if (!valid)
    {
        float x = planned[0] - eye[0], y = planned[1] - eye[1];
        if (x * x + y * y >= 1.0)
        {
            Normalize2D(x, y);
            // Start nearest the assigned sector. Stay level and do not turn
            // guards around or aim down onto a different floor.
            for (int step = 1; step <= 10; step++)
            {
                float dx, dy;
                float yaw = float((step + 1) / 2) * (step % 2 != 0 ? -15.0 : 15.0);
                Rotate2D(x, y, yaw, dx, dy);
                look[0] = eye[0] + dx * 420.0;
                look[1] = eye[1] + dy * 420.0;
                look[2] = eye[2];
                if (!TacticalAngles_ClipWatchRay(eye, look)) continue;
                valid = true;
                break;
            }
        }
    }
    g_tacticalWatch[client].userId = userid;
    g_tacticalWatch[client].phase = phase;
    g_tacticalWatch[client].time = now;
    g_tacticalWatch[client].valid = valid;
    CopyVector(eye, g_tacticalWatch[client].eye);
    CopyVector(goal, g_tacticalWatch[client].goal);
    CopyVector(planned, g_tacticalWatch[client].planned);
    CopyVector(look, g_tacticalWatch[client].look);
    return valid;
}

stock bool TacticalAngles_SelectLook(int client, const float hold[3], const float threat[3], int slot, float result[3], bool constrainSector = false)
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
            // CT opening sectors must not collapse onto one NAV-projected
            // target outside their responsibility. Default false preserves T
            // post-plant, dropped-C4 and retake behavior exactly as before.
            if (constrainSector)
            {
                float dx = candidates[candidate][0] - hold[0];
                float dy = candidates[candidate][1] - hold[1];
                float alignment = (dx * slotX + dy * slotY) / distance;
                if (alignment < Cosine(DegToRad(20.1))) continue;
            }

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
