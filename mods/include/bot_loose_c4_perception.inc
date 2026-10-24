#if defined _bot_loose_c4_perception_included
    #endinput
#endif
#define _bot_loose_c4_perception_included

// Included by BetterBots after its SDK handles/globals are declared. These
// queries do not change movement, aim, money, equipment or player identity.
public any Native_CanSeeLooseC4(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    int bomb = GetNativeCell(2);
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_CT
        || bomb <= MaxClients || !IsValidEntity(bomb))
        return false;
    char classname[32];
    GetEntityClassname(bomb, classname, sizeof(classname));
    if (!StrEqual(classname, "weapon_c4") || GetEntPropEnt(bomb, Prop_Send, "m_hOwnerEntity") > 0)
        return false;

    float eye[3], position[3];
    GetClientEyePosition(client, eye);
    GetEntPropVector(bomb, Prop_Send, "m_vecOrigin", position);
    position[2] += 8.0;
    if (GetVectorDistance(eye, position) > 2500.0 || g_hIsLineBlockedBySmoke == null
        || LineGoesThroughSmoke(eye, position))
        return false;
    // Check the actual current view for both humans and bots. The bot SDK's
    // cached FOV alone can lag after a sharp turn or while bot_stop is set.
    float angles[3], viewDirection[3], direction[3];
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, viewDirection, NULL_VECTOR, NULL_VECTOR);
    MakeVectorFromPoints(eye, position, direction);
    NormalizeVector(direction, direction);
    if (GetVectorDotProduct(viewDirection, direction) < 0.5)
        return false;
    if (IsFakeClient(client))
        return g_hBotIsVisible != null && BotIsVisible(client, position, true, bomb);
    Handle trace = TR_TraceRayFilterEx(eye, position, MASK_VISIBLE, RayType_EndPoint,
        LooseC4SightFilter, bomb);
    bool visible = !TR_DidHit(trace) || TR_GetFraction(trace) >= 0.99;
    delete trace;
    return visible;
}

public bool LooseC4SightFilter(int entity, int contentsMask, any bomb)
{
    return entity > MaxClients && entity != bomb;
}

public any Native_HasVisibleEnemy(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsValidClient(client) || !IsFakeClient(client) || !IsPlayerAlive(client))
        return false;
    int enemy = BotGetEnemy(client);
    return IsValidClient(enemy) && IsPlayerAlive(enemy) && GetClientTeam(enemy) != GetClientTeam(client)
        && GetEntData(client, g_iEnemyVisibleOffset) != 0;
}
