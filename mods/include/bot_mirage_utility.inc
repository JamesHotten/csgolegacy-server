#if defined _bot_mirage_utility_included
    #endinput
#endif
#define _bot_mirage_utility_included

ConVar g_cvMirageRouteUtility;
bool g_mirageUtilityMap;
int g_utilitySlot[MAXPLAYERS + 1]; // Selected lineup index plus one.
float g_utilityDeadline[MAXPLAYERS + 1];
int g_ctSmokeUserId;

void MirageUtility_OnMapStart()
{
    if (g_cvMirageRouteUtility == null)
        g_cvMirageRouteUtility = CreateConVar("sm_bot_mirage_route_utility", "1", "Coordinate existing Mirage smoke and flash recordings with opening routes.");
    char map[32];
    GetCurrentMap(map, sizeof(map));
    g_mirageUtilityMap = StrEqual(map, "de_mirage", false);
}

void MirageUtility_Reset()
{
    g_ctSmokeUserId = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_utilitySlot[i] = 0;
        g_utilityDeadline[i] = 0.0;
    }
}

bool MirageUtility_Enabled()
{
    return g_mirageUtilityMap && g_cvMirageRouteUtility != null && g_cvMirageRouteUtility.BoolValue;
}

int MirageUtility_Lane(int client)
{
    if (!MirageUtility_Enabled()) return -1;
    if (GetClientTeam(client) != CS_TEAM_T || GetFeatureStatus(FeatureType_Native, "BotTTactics_GetUtilityLane") != FeatureStatus_Available) return -1;
    return BotTTactics_GetUtilityLane(client);
}

bool MirageUtility_Name(const char[] path, const char[] name)
{
    char suffix[80];
    Format(suffix, sizeof(suffix), "/%s.rec", name);
    int extra = strlen(path) - strlen(suffix);
    return extra >= 0 && StrEqual(path[extra], suffix, false);
}

bool MirageUtility_Eligible(int client, const char[] replay)
{
    if (MirageUtility_Enabled() && GetClientTeam(client) == CS_TEAM_T && g_utilitySlot[client] < 0 && MirageUtility_Lane(client) >= 0) return false;
    switch (MirageUtility_Lane(client))
    {
        case 0: return false;
        case 1: return MirageUtility_Name(replay, "Stairs Smoke") || MirageUtility_Name(replay, "Jungle Smoke")
            || MirageUtility_Name(replay, "CT Smoke") || MirageUtility_Name(replay, "Lamp Flash") || MirageUtility_Name(replay, "Palace Flash");
        case 2: return MirageUtility_Name(replay, "B Entry Flash") || MirageUtility_Name(replay, "1st Arch Smoke") || MirageUtility_Name(replay, "2nd Arch Smoke");
        case 3: return MirageUtility_Name(replay, "Window Smoke") || MirageUtility_Name(replay, "Window Smoke Mid")
            || MirageUtility_Name(replay, "Con Flash") || MirageUtility_Name(replay, "Short Smoke Mid");
    }
    return true;
}

bool MirageUtility_Tick(int client, bool enemy, float now, bool hadOrder)
{
    if (!MirageUtility_Enabled()) return false;
    int lane = MirageUtility_Lane(client);
    bool ct = GetClientTeam(client) == CS_TEAM_CT;
    bool roundTask = ct ? !g_bBombPlanted && !g_bTPlanting && hadOrder : lane >= 0;
    int selected = g_iDoingSmokeNum[client];
    if (roundTask && !enemy && lane != 0 && selected < 0 && ct && g_ctSmokeUserId == 0
        && now >= g_fNadeLineupCooldown[client])
    {
        g_fNadeLineupCooldown[client] = now + 1.0;
        float origin[3];
        GetClientAbsOrigin(client, origin);
        for (int i = 0; i < g_aNades.Length; i++)
        {
            NadeLineup candidate;
            g_aNades.GetArray(i, candidate);
            if (candidate.iTeam != CS_TEAM_CT || candidate.iDefIndex != 45
                || (!MirageUtility_Name(candidate.szReplay, "B Apps Smoke") && !MirageUtility_Name(candidate.szReplay, "Ramp Smoke"))
                || GetVectorDistance(origin, candidate.fPos) > 150.0 || !FileExists(candidate.szReplay)
                || !IsValidEntity(eItems_FindWeaponByDefIndex(client, 45))) continue;
            g_ctSmokeUserId = GetClientUserId(client);
            selected = g_iDoingSmokeNum[client] = i;
            break;
        }
    }
    if (selected >= 0 && selected < g_aNades.Length && roundTask && !enemy && lane != 0)
    {
        NadeLineup nade;
        g_aNades.GetArray(selected, nade);
        if (g_utilitySlot[client] == selected + 1 && now < g_utilityDeadline[client]) return true;
        if (g_utilitySlot[client] == 0 && (ct || MirageUtility_Eligible(client, nade.szReplay)) && FileExists(nade.szReplay))
        {
            g_utilitySlot[client] = selected + 1;
            g_utilityDeadline[client] = now + 4.0;
            if (FindConVar("sm_bot_t_tactics_debug") != null && FindConVar("sm_bot_t_tactics_debug").BoolValue)
                PrintToServer("MIRAGE_UTILITY assigned bot=%d lane=%d replay=%s", client, lane, nade.szReplay);
            return true;
        }
    }
    if (g_utilitySlot[client] > 0 || (roundTask && selected >= 0))
    {
        if (BotMimic_IsPlayerMimicing(client)) BotMimic_StopPlayerMimic(client);
        g_iDoingSmokeNum[client] = -1;
        g_utilitySlot[client] = -1; // At most one assignment per opening/player.
    }
    return false;
}
