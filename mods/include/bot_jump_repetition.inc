#if defined _bot_jump_repetition_included
    #endinput
#endif
#define _bot_jump_repetition_included

// Count actual engine takeoffs, not repeated input ticks or mid-air requests.
int g_iBotLocalJumpCount[MAXPLAYERS + 1];
float g_fBotLocalJumpAnchor[MAXPLAYERS + 1][3];
float g_fBotLocalJumpLast[MAXPLAYERS + 1];

stock void BotJumpReset(int client)
{
    g_iBotLocalJumpCount[client] = 0;
    g_fBotLocalJumpLast[client] = 0.0;
}

stock bool BotJumpMadeProgress(int client, const float origin[3])
{
    float dx = origin[0] - g_fBotLocalJumpAnchor[client][0];
    float dy = origin[1] - g_fBotLocalJumpAnchor[client][1];
    return dx * dx + dy * dy >= 64.0 * 64.0 || FloatAbs(origin[2] - g_fBotLocalJumpAnchor[client][2]) >= 32.0;
}

stock void BotJumpRecordTakeoff(int client)
{
    float origin[3], now = GetGameTime();
    GetClientAbsOrigin(client, origin);
    if (g_iBotLocalJumpCount[client] == 0 || BotJumpMadeProgress(client, origin)
        || now - g_fBotLocalJumpLast[client] >= 8.0
        || (g_iBotLocalJumpCount[client] < 3 && now - g_fBotLocalJumpLast[client] > 1.65))
    {
        for (int axis = 0; axis < 3; axis++) g_fBotLocalJumpAnchor[client][axis] = origin[axis];
        g_iBotLocalJumpCount[client] = 0;
    }
    if (g_iBotLocalJumpCount[client] < 3) g_iBotLocalJumpCount[client]++;
    g_fBotLocalJumpLast[client] = now;
}

stock bool BotJumpSuppressLocalRepeat(int client, const float origin[3], float now)
{
    if (g_iBotLocalJumpCount[client] == 0 || (GetEntityFlags(client) & FL_ONGROUND) == 0) return false;
    if (BotJumpMadeProgress(client, origin) || now - g_fBotLocalJumpLast[client] >= 8.0)
    {
        BotJumpReset(client);
        return false;
    }
    // Only throttle a proven loop, even on NAV jump areas. Keep occasional
    // native retries in case an obstacle moves or the navigator finds a way.
    return g_iBotLocalJumpCount[client] >= 3 && now - g_fBotLocalJumpLast[client] < 2.75;
}
