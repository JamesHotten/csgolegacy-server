#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "CS:GO Side Win Statistics",
    author = "JamesHotten server project",
    description = "Counts decisive CT/T round wins by session, map and server",
    version = "1.0.0",
    url = "https://github.com/JamesHotten/csgolegacy-server"
};

char g_storePath[PLATFORM_MAX_PATH];
char g_mapName[PLATFORM_MAX_PATH];
int g_sessionWins[4];
int g_mapWins[4];
int g_allWins[4];
bool g_eligibleRound;

public void OnPluginStart()
{
    BuildPath(Path_SM, g_storePath, sizeof(g_storePath), "data/bot_side_win_stats.txt");
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
    RegConsoleCmd("sm_sidewin", Command_SideWin, "Show CT/T decisive-round win rates.");
    OnMapStart();
}

public void OnMapStart()
{
    GetCurrentMap(g_mapName, sizeof(g_mapName));
    g_sessionWins[CS_TEAM_T] = 0;
    g_sessionWins[CS_TEAM_CT] = 0;
    g_eligibleRound = false;
    LoadCounts();
}

void LoadCounts()
{
    g_mapWins[CS_TEAM_T] = 0;
    g_mapWins[CS_TEAM_CT] = 0;
    g_allWins[CS_TEAM_T] = 0;
    g_allWins[CS_TEAM_CT] = 0;

    KeyValues store = new KeyValues("SideWinStats");
    if (!store.ImportFromFile(g_storePath))
    {
        delete store;
        return;
    }
    if (store.JumpToKey("all"))
    {
        g_allWins[CS_TEAM_T] = store.GetNum("t", 0);
        g_allWins[CS_TEAM_CT] = store.GetNum("ct", 0);
        store.Rewind();
    }
    if (store.JumpToKey("maps") && store.JumpToKey(g_mapName))
    {
        g_mapWins[CS_TEAM_T] = store.GetNum("t", 0);
        g_mapWins[CS_TEAM_CT] = store.GetNum("ct", 0);
    }
    delete store;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_eligibleRound = GameRules_GetProp("m_bWarmupPeriod") == 0;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner");
    if (!g_eligibleRound || GameRules_GetProp("m_bWarmupPeriod") != 0
        || (winner != CS_TEAM_T && winner != CS_TEAM_CT))
        return;

    // A second round_end event must not count the same round twice.
    g_eligibleRound = false;
    g_sessionWins[winner]++;
    g_mapWins[winner]++;
    g_allWins[winner]++;
    SaveCounts();
}

void SaveCounts()
{
    KeyValues store = new KeyValues("SideWinStats");
    store.ImportFromFile(g_storePath);
    store.JumpToKey("all", true);
    store.SetNum("t", g_allWins[CS_TEAM_T]);
    store.SetNum("ct", g_allWins[CS_TEAM_CT]);
    store.Rewind();
    store.JumpToKey("maps", true);
    store.JumpToKey(g_mapName, true);
    store.SetNum("t", g_mapWins[CS_TEAM_T]);
    store.SetNum("ct", g_mapWins[CS_TEAM_CT]);
    store.Rewind();
    if (!store.ExportToFile(g_storePath))
        LogError("Could not save CT/T round wins to %s", g_storePath);
    delete store;
}

public Action Command_SideWin(int client, int args)
{
    ShowCounts(client, "This map session", g_sessionWins);
    char label[PLATFORM_MAX_PATH + 16];
    Format(label, sizeof(label), "Map %s", g_mapName);
    ShowCounts(client, label, g_mapWins);
    ShowCounts(client, "All maps", g_allWins);
    return Plugin_Handled;
}

void ShowCounts(int client, const char[] label, const int wins[4])
{
    int total = wins[CS_TEAM_T] + wins[CS_TEAM_CT];
    if (total == 0)
    {
        ReplyToCommand(client, "[SideWin] %s: no decisive rounds recorded yet.", label);
        return;
    }
    ReplyToCommand(client, "[SideWin] %s: T %d/%d (%.1f%%), CT %d/%d (%.1f%%).",
        label, wins[CS_TEAM_T], total, float(wins[CS_TEAM_T]) * 100.0 / float(total),
        wins[CS_TEAM_CT], total, float(wins[CS_TEAM_CT]) * 100.0 / float(total));
}
