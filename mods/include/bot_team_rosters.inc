#if defined _bot_team_rosters_included
    #endinput
#endif
#define _bot_team_rosters_included

#define BTR_TEAM_NAME_MAX 64
#define BTR_ROSTER_SIZE 5

ConVar g_BTR_Randomizer;
char g_BTR_CTTeam[BTR_TEAM_NAME_MAX];
char g_BTR_TTeam[BTR_TEAM_NAME_MAX];
bool g_BTR_RebuildPending;
bool g_BTR_PhaseCheckActive;
float g_BTR_PhaseCheckUntil;

void BotTeams_OnPluginStart()
{
    g_BTR_Randomizer = CreateConVar("sm_bot_teams_randomizer", "1", "Select two professional BOT rosters on each map.", _, true, 0.0, true, 1.0);
    HookEvent("player_team", BotTeams_EventPlayerTeam, EventHookMode_Post);
    HookEvent("announce_phase_end", BotTeams_EventPhaseEnd, EventHookMode_PostNoCopy);
    RegConsoleCmd("sm_bot_teams_status", BotTeams_CommandStatus);
}

void BotTeams_OnMapStart()
{
    g_BTR_CTTeam[0] = '\0';
    g_BTR_TTeam[0] = '\0';
    g_BTR_RebuildPending = false;
    g_BTR_PhaseCheckActive = false;
    g_BTR_PhaseCheckUntil = 0.0;
    CreateTimer(1.5, BotTeams_TimerInitialAssignment, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action BotTeams_TimerInitialAssignment(Handle timer)
{
    char configuredCT[BTR_TEAM_NAME_MAX], configuredT[BTR_TEAM_NAME_MAX];
    bool configRandomizer = true;
    BotTeams_ReadConfig(configRandomizer, configuredCT, sizeof(configuredCT), configuredT, sizeof(configuredT));
    g_BTR_Randomizer.BoolValue = configRandomizer;

    if (configuredCT[0] != '\0' && !BotTeams_RosterExists(configuredCT))
    {
        LogError("Configured CT BOT team does not exist: %s", configuredCT);
        configuredCT[0] = '\0';
    }
    if (configuredT[0] != '\0' && !BotTeams_RosterExists(configuredT))
    {
        LogError("Configured T BOT team does not exist: %s", configuredT);
        configuredT[0] = '\0';
    }

    if (configuredCT[0] != '\0')
        strcopy(g_BTR_CTTeam, sizeof(g_BTR_CTTeam), configuredCT);
    if (configuredT[0] != '\0')
        strcopy(g_BTR_TTeam, sizeof(g_BTR_TTeam), configuredT);

    if (g_BTR_Randomizer.BoolValue)
    {
        if (!BotTeams_FillRandomSelections())
        {
            LogError("Could not select two valid BOT rosters.");
            return Plugin_Stop;
        }
    }

    if (g_BTR_CTTeam[0] != '\0' || g_BTR_TTeam[0] != '\0')
        BotTeams_RebuildAll();
    return Plugin_Stop;
}

public Action BotTeams_CommandTeam(int client, int args)
{
    if (args < 2)
    {
        ReplyToCommand(client, "Usage: team <TeamName> <t|ct>");
        return Plugin_Handled;
    }

    char teamName[BTR_TEAM_NAME_MAX], sideName[8];
    GetCmdArg(1, teamName, sizeof(teamName));
    GetCmdArg(2, sideName, sizeof(sideName));
    int side;
    if (StrEqual(sideName, "ct", false))
        side = CS_TEAM_CT;
    else if (StrEqual(sideName, "t", false))
        side = CS_TEAM_T;
    else
    {
        ReplyToCommand(client, "Invalid side: %s (use t or ct)", sideName);
        return Plugin_Handled;
    }

    if (!BotTeams_RosterExists(teamName))
    {
        ReplyToCommand(client, "Unknown team: %s", teamName);
        return Plugin_Handled;
    }

    if (side == CS_TEAM_CT)
        strcopy(g_BTR_CTTeam, sizeof(g_BTR_CTTeam), teamName);
    else
        strcopy(g_BTR_TTeam, sizeof(g_BTR_TTeam), teamName);

    BotTeams_RebuildSide(side);
    ReplyToCommand(client, "[BotTeams] %s assigned to %s; human slots are reserved automatically.", teamName, sideName);
    return Plugin_Handled;
}

public Action BotTeams_CommandStatus(int client, int args)
{
    ReplyToCommand(client, "[BotTeams] randomizer=%d CT=%s (human=%d bot=%d) T=%s (human=%d bot=%d)",
        g_BTR_Randomizer.BoolValue,
        g_BTR_CTTeam[0] == '\0' ? "<none>" : g_BTR_CTTeam,
        BotTeams_CountHumans(CS_TEAM_CT), BotTeams_CountBots(CS_TEAM_CT),
        g_BTR_TTeam[0] == '\0' ? "<none>" : g_BTR_TTeam,
        BotTeams_CountHumans(CS_TEAM_T), BotTeams_CountBots(CS_TEAM_T));
    return Plugin_Handled;
}

public void BotTeams_EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
        BotTeams_ScheduleRebuild();
}

void BotTeams_OnClientDisconnect(int client)
{
    // The Legacy player_disconnect event reports bot=0 even for BOTs during
    // side switches. OnClientDisconnect still has a valid client type here.
    if (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
        BotTeams_ScheduleRebuild();
}

public void BotTeams_EventPhaseEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_BTR_CTTeam[0] == '\0' || g_BTR_TTeam[0] == '\0' || g_BTR_PhaseCheckActive)
        return;
    ConVar halftime = FindConVar("mp_halftime");
    if (halftime == null || !halftime.BoolValue)
        return;

    // announce_phase_end also fires between overtimes when sides do NOT flip.
    // Watch the actual BOT identities for one halftime window instead of
    // swapping roster names on the event alone.
    g_BTR_PhaseCheckActive = true;
    g_BTR_PhaseCheckUntil = GetGameTime() + 20.0;
    CreateTimer(1.0, BotTeams_TimerPhaseCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action BotTeams_TimerPhaseCheck(Handle timer)
{
    if (!g_BTR_PhaseCheckActive || GetGameTime() >= g_BTR_PhaseCheckUntil)
    {
        g_BTR_PhaseCheckActive = false;
        return Plugin_Stop;
    }
    if (BotTeams_MaybeFollowSwappedSides())
    {
        BotTeams_ScheduleRebuild();
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

void BotTeams_ScheduleRebuild()
{
    if (g_BTR_CTTeam[0] == '\0' && g_BTR_TTeam[0] == '\0')
        return;
    // Normal quota counts BOTs, not total players. Reduce it as soon as a
    // human changes teams so the engine removes/adds the required single slot
    // before we reconcile the professional names.
    BotTeams_ApplyQuota();
    if (g_BTR_RebuildPending)
        return;
    g_BTR_RebuildPending = true;
    CreateTimer(0.8, BotTeams_TimerRebuild, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action BotTeams_TimerRebuild(Handle timer)
{
    g_BTR_RebuildPending = false;
    BotTeams_MaybeFollowSwappedSides();
    // Wait for the physical side exchange instead of treating players in
    // transit through the engine's halftime phase as foreign roster BOTs.
    if (g_BTR_PhaseCheckActive && GameRules_GetProp("m_gamePhase") == 4)
        return Plugin_Stop;
    BotTeams_ReconcileSide(CS_TEAM_CT);
    BotTeams_ReconcileSide(CS_TEAM_T);
    return Plugin_Stop;
}

bool BotTeams_NameInRoster(const char[] name, const char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], int count)
{
    for (int index = 0; index < count; index++)
    {
        if (StrEqual(name, players[index], false))
            return true;
    }
    return false;
}

bool BotTeams_MaybeFollowSwappedSides()
{
    if (g_BTR_CTTeam[0] == '\0' || g_BTR_TTeam[0] == '\0')
        return false;

    char ctPlayers[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], tPlayers[BTR_ROSTER_SIZE][MAX_NAME_LENGTH];
    char ctLogo[64], tLogo[64];
    int ctCount, tCount;
    if (!BotTeams_LoadRoster(g_BTR_CTTeam, ctPlayers, ctCount, ctLogo, sizeof(ctLogo))
        || !BotTeams_LoadRoster(g_BTR_TTeam, tPlayers, tCount, tLogo, sizeof(tLogo)))
        return false;

    int ctMovedToT, tMovedToCT, ctStayedCT, tStayedT;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client))
            continue;
        int side = GetClientTeam(client);
        if (side != CS_TEAM_CT && side != CS_TEAM_T)
            continue;
        char botName[MAX_NAME_LENGTH];
        GetClientName(client, botName, sizeof(botName));
        bool fromCT = BotTeams_NameInRoster(botName, ctPlayers, ctCount);
        bool fromT = BotTeams_NameInRoster(botName, tPlayers, tCount);
        if (fromCT == fromT) // Ignore duplicate names in two rosters.
            continue;
        if (fromCT && side == CS_TEAM_T) ctMovedToT++;
        if (fromT && side == CS_TEAM_CT) tMovedToCT++;
        if (fromCT && side == CS_TEAM_CT) ctStayedCT++;
        if (fromT && side == CS_TEAM_T) tStayedT++;
    }

    int moved = ctMovedToT + tMovedToCT;
    int stayed = ctStayedCT + tStayedT;
    bool ctAccountedFor = ctMovedToT > 0 || (g_BTR_PhaseCheckActive && BotTeams_CountHumans(CS_TEAM_T) >= BTR_ROSTER_SIZE);
    bool tAccountedFor = tMovedToCT > 0 || (g_BTR_PhaseCheckActive && BotTeams_CountHumans(CS_TEAM_CT) >= BTR_ROSTER_SIZE);
    if (moved < 3 || moved <= stayed || !ctAccountedFor || !tAccountedFor)
        return false;

    char oldCT[BTR_TEAM_NAME_MAX];
    strcopy(oldCT, sizeof(oldCT), g_BTR_CTTeam);
    strcopy(g_BTR_CTTeam, sizeof(g_BTR_CTTeam), g_BTR_TTeam);
    strcopy(g_BTR_TTeam, sizeof(g_BTR_TTeam), oldCT);
    g_BTR_PhaseCheckActive = false;
    LogMessage("BOT rosters followed real side swap: CT=%s, T=%s; preserving %d switched BOTs.",
        g_BTR_CTTeam, g_BTR_TTeam, moved);
    return true;
}

void BotTeams_RebuildAll()
{
    // Temporarily disable automatic quota adjustment so it cannot race the
    // named bot_add commands and create anonymous filler BOTs.
    ServerCommand("bot_quota_mode normal");
    ServerCommand("bot_kick ct all");
    ServerCommand("bot_kick t all");
    BotTeams_QueueRoster(CS_TEAM_CT, g_BTR_CTTeam);
    BotTeams_QueueRoster(CS_TEAM_T, g_BTR_TTeam);
    ServerExecute();
    BotTeams_ApplyQuota();
}

void BotTeams_RebuildSide(int side)
{
    ServerCommand("bot_quota_mode normal");
    ServerCommand("bot_kick %s all", side == CS_TEAM_CT ? "ct" : "t");
    BotTeams_QueueRoster(side, side == CS_TEAM_CT ? g_BTR_CTTeam : g_BTR_TTeam);
    ServerExecute();
    BotTeams_ApplyQuota();
}

void BotTeams_ReconcileSide(int side)
{
    char teamName[BTR_TEAM_NAME_MAX];
    strcopy(teamName, sizeof(teamName), side == CS_TEAM_CT ? g_BTR_CTTeam : g_BTR_TTeam);
    if (teamName[0] == '\0')
        return;

    char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], logo[64];
    int playerCount;
    if (!BotTeams_LoadRoster(teamName, players, playerCount, logo, sizeof(logo)))
        return;

    int wanted = BTR_ROSTER_SIZE - BotTeams_CountHumans(side);
    if (wanted < 0)
        wanted = 0;
    if (wanted > playerCount)
        wanted = playerCount;

    bool used[BTR_ROSTER_SIZE];
    int matchedClients[BTR_ROSTER_SIZE], matchedRosterIndex[BTR_ROSTER_SIZE], matchedCount;
    int outsiderClients[MAXPLAYERS + 1], outsiderCount;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsFakeClient(client) || GetClientTeam(client) != side)
            continue;

        char botName[MAX_NAME_LENGTH];
        GetClientName(client, botName, sizeof(botName));
        int rosterIndex = -1;
        for (int index = 0; index < playerCount; index++)
        {
            if (!used[index] && StrEqual(botName, players[index], false))
            {
                rosterIndex = index;
                break;
            }
        }

        if (rosterIndex >= 0)
        {
            used[rosterIndex] = true;
            matchedClients[matchedCount] = client;
            matchedRosterIndex[matchedCount] = rosterIndex;
            matchedCount++;
        }
        else
        {
            outsiderClients[outsiderCount++] = client;
        }
    }

    // Preserve as many existing professional BOTs as possible. Remove quota
    // filler first, then only the minimum excess roster BOTs.
    int keepMatched = matchedCount;
    if (keepMatched > wanted)
        keepMatched = wanted;

    ServerCommand("bot_quota_mode normal");
    for (int index = 0; index < outsiderCount; index++)
        KickClient(outsiderClients[index], "Replacing quota filler with configured roster");
    for (int index = keepMatched; index < matchedCount; index++)
    {
        used[matchedRosterIndex[index]] = false;
        KickClient(matchedClients[index], "Reserving a slot for a human player");
    }

    int addCount = wanted - keepMatched;
    char sideName[3];
    strcopy(sideName, sizeof(sideName), side == CS_TEAM_CT ? "ct" : "t");
    for (int index = 0; index < playerCount && addCount > 0; index++)
    {
        if (used[index])
            continue;
        ReplaceString(players[index], sizeof(players[]), "\"", "");
        ServerCommand("bot_add_%s \"%s\"", sideName, players[index]);
        used[index] = true;
        addCount--;
    }
    ServerExecute();
    BotTeams_ApplyQuota();

    if (logo[0] != '\0')
        ServerCommand("mp_teamlogo_%d \"%s\"", side == CS_TEAM_CT ? 1 : 2, logo);
}

void BotTeams_QueueRoster(int side, const char[] teamName)
{
    if (teamName[0] == '\0')
        return;

    char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], logo[64];
    int playerCount;
    if (!BotTeams_LoadRoster(teamName, players, playerCount, logo, sizeof(logo)))
        return;

    int wanted = BTR_ROSTER_SIZE - BotTeams_CountHumans(side);
    if (wanted < 0)
        wanted = 0;
    if (wanted > playerCount)
        wanted = playerCount;

    char sideName[3];
    strcopy(sideName, sizeof(sideName), side == CS_TEAM_CT ? "ct" : "t");
    for (int index = 0; index < wanted; index++)
    {
        ReplaceString(players[index], sizeof(players[]), "\"", "");
        ServerCommand("bot_add_%s \"%s\"", sideName, players[index]);
    }

    if (logo[0] != '\0')
        ServerCommand("mp_teamlogo_%d \"%s\"", side == CS_TEAM_CT ? 1 : 2, logo);
}

int BotTeams_CountHumans(int side)
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == side)
            count++;
    }
    return count;
}

int BotTeams_CountBots(int side)
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == side)
            count++;
    }
    return count;
}

void BotTeams_ApplyQuota()
{
    int humanCount = BotTeams_CountHumans(CS_TEAM_CT) + BotTeams_CountHumans(CS_TEAM_T);
    int wantedBots = (BTR_ROSTER_SIZE * 2) - humanCount;
    if (wantedBots < 0)
        wantedBots = 0;
    ServerCommand("bot_quota_mode normal");
    ServerCommand("bot_quota %d", wantedBots);
}

bool BotTeams_ReadConfig(bool &randomizer, char[] ctTeam, int ctMax, char[] tTeam, int tMax)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/bot_stuff.cfg");
    KeyValues config = new KeyValues("BotStuff");
    if (!config.ImportFromFile(path) || !config.JumpToKey("BotTeams"))
    {
        delete config;
        return false;
    }
    randomizer = config.GetNum("randomizer", 1) != 0;
    config.GetString("ct_team", ctTeam, ctMax, "");
    config.GetString("t_team", tTeam, tMax, "");
    delete config;
    return true;
}

bool BotTeams_FillRandomSelections()
{
    ArrayList teams = new ArrayList(BTR_TEAM_NAME_MAX);
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/bot_rosters.txt");
    KeyValues rosters = new KeyValues("Teams");
    if (!rosters.ImportFromFile(path) || !rosters.GotoFirstSubKey())
    {
        delete rosters;
        delete teams;
        return false;
    }

    do
    {
        char name[BTR_TEAM_NAME_MAX], playerList[256];
        rosters.GetSectionName(name, sizeof(name));
        rosters.GetString("players", playerList, sizeof(playerList), "");
        char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH];
        if (ExplodeString(playerList, ",", players, sizeof(players), sizeof(players[])) >= BTR_ROSTER_SIZE)
            teams.PushString(name);
    }
    while (rosters.GotoNextKey());
    delete rosters;

    if (teams.Length < 2)
    {
        delete teams;
        return false;
    }

    if (g_BTR_CTTeam[0] == '\0')
        teams.GetString(GetRandomInt(0, teams.Length - 1), g_BTR_CTTeam, sizeof(g_BTR_CTTeam));
    if (g_BTR_TTeam[0] == '\0')
    {
        do
        {
            teams.GetString(GetRandomInt(0, teams.Length - 1), g_BTR_TTeam, sizeof(g_BTR_TTeam));
        }
        while (StrEqual(g_BTR_CTTeam, g_BTR_TTeam, false));
    }
    else if (StrEqual(g_BTR_CTTeam, g_BTR_TTeam, false))
    {
        g_BTR_TTeam[0] = '\0';
        do
        {
            teams.GetString(GetRandomInt(0, teams.Length - 1), g_BTR_TTeam, sizeof(g_BTR_TTeam));
        }
        while (StrEqual(g_BTR_CTTeam, g_BTR_TTeam, false));
    }
    delete teams;
    return true;
}

bool BotTeams_RosterExists(const char[] teamName)
{
    char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], logo[64];
    int count;
    return BotTeams_LoadRoster(teamName, players, count, logo, sizeof(logo));
}

bool BotTeams_LoadRoster(const char[] teamName, char players[BTR_ROSTER_SIZE][MAX_NAME_LENGTH], int &playerCount, char[] logo, int logoMax)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/bot_rosters.txt");
    KeyValues rosters = new KeyValues("Teams");
    if (!rosters.ImportFromFile(path) || !rosters.JumpToKey(teamName))
    {
        delete rosters;
        return false;
    }

    char playerList[256];
    rosters.GetString("players", playerList, sizeof(playerList), "");
    rosters.GetString("logo", logo, logoMax, "");
    delete rosters;
    playerCount = ExplodeString(playerList, ",", players, sizeof(players), sizeof(players[]));
    for (int index = 0; index < playerCount; index++)
        TrimString(players[index]);
    return playerCount > 0;
}
