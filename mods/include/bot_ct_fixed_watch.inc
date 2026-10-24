#if defined _bot_ct_fixed_watch_included
    #endinput
#endif
#define _bot_ct_fixed_watch_included

// CT-only quiet hold policy. No direct eye-angle writes, target-memory writes,
// movement changes or combat/weapon timing changes are allowed here.
stock bool BotCTWatch_IsQuietHold(int client)
{
    if (!IsValidClient(client) || !IsFakeClient(client) || !IsPlayerAlive(client)
        || GetClientTeam(client) != CS_TEAM_CT || g_bBombPlanted
        || !g_bTacticalHoldReached[client] || GetEntData(client, g_iEnemyVisibleOffset) != 0
        || GetEntData(client, g_iBotNearbyEnemiesOffset) != 0
        || g_bThrowGrenade[client] || g_iDoingSmokeNum[client] != -1
        || BotMimic_IsPlayerMimicing(client) || GetEntityMoveType(client) == MOVETYPE_LADDER
        || GetTask(client) == ESCAPE_FROM_BOMB || GetTask(client) == ESCAPE_FROM_FLAMES)
        return false;
    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (active > MaxClients && IsValidEntity(active)
        && eItems_GetWeaponSlotByWeapon(active) == CS_SLOT_GRENADE)
        return false;
    if (GetFeatureStatus(FeatureType_Native, "BotCTTactics_GetOrder") != FeatureStatus_Available
        || GetFeatureStatus(FeatureType_Native, "BotCTTactics_GetAim") != FeatureStatus_Available)
        return false;
    float goal[3], look[3], position[3];
    int route;
    // Re-query rather than trust last frame: a same-frame fire/hurt event or
    // plugin disable must immediately release native attention.
    if (!BotCTTactics_GetOrder(client, goal, route) || !BotCTTactics_GetAim(client, look))
        return false;
    GetClientAbsOrigin(client, position);
    return GetVectorDistance(position, goal) <= 256.0;
}

stock bool BotCTWatch_IsEssentialLook(const char[] description, bool attack)
{
    return attack || StrEqual(description, "CT assigned hold")
        || StrEqual(description, "Defuse bomb") || StrEqual(description, "Use entity")
        || StrEqual(description, "Open door") || StrEqual(description, "Hostage")
        || StrEqual(description, "Avoid Flashbang") || StrEqual(description, "Blind")
        || StrEqual(description, "GrenadeThrowBend");
}
