#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
    MarkNativeAsOptional("BotCTTactics_GetOrder");
    return APLRes_Success;
}
public Plugin myinfo = { name = "BOT live combat observer", author = "server project", version = "1.0" };
ConVar g_auto, g_record;
bool g_running, g_done;
int g_visible, g_enemy, g_profile, g_rounds;
float g_started;
File g_output;
int g_target[MAXPLAYERS+1], g_round[MAXPLAYERS+1];
float g_seen[MAXPLAYERS+1], g_shot[MAXPLAYERS+1], g_hit[MAXPLAYERS+1];
float g_seenError[MAXPLAYERS+1], g_shotError[MAXPLAYERS+1], g_speed[MAXPLAYERS+1], g_reaction[MAXPLAYERS+1];
bool g_order[MAXPLAYERS+1], g_written[MAXPLAYERS+1];
bool g_sameTarget[MAXPLAYERS+1];
float g_exposure[MAXPLAYERS+1], g_shotExposure[MAXPLAYERS+1];
char g_weapon[MAXPLAYERS+1][48];
float g_oldRecord;

public void OnPluginStart()
{
    GameData data = new GameData("botstuff.games");
    g_visible = data.GetOffset("CCSBot::m_isEnemyVisible");
    g_enemy = data.GetOffset("CCSBot::m_enemy");
    g_profile = data.GetOffset("CCSBot::m_pLocalProfile");
    delete data;
    g_auto = CreateConVar("sm_combat_observer_auto", "0", "Empty-server read-only combat observer.");
    HookEvent("weapon_fire", Fired);
    HookEvent("player_hurt", Hurt);
    HookEvent("player_death", Died);
    HookEvent("round_end", RoundEnd);
    HookEvent("player_spawn", Spawned);
    CreateTimer(1.0, Tick, _, TIMER_REPEAT);
}
public Action Tick(Handle timer)
{
    if (g_done || !g_auto.BoolValue) return Plugin_Continue;
    for (int i=1; i<=MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i)) { Cleanup(); return Plugin_Stop; }
    if (!g_running)
    {
        if (GetGameTime() < 12.0) return Plugin_Continue;
        g_running = true;
        g_started = GetGameTime();
        char path[PLATFORM_MAX_PATH];
        BuildPath(Path_SM,path,sizeof(path),"data/combat-observer-1019-%d.csv",GetTime());
        g_output = OpenFile(path,"w");
        if (g_output == null) SetFailState("No observer output");
        g_output.WriteLine("round,team,name,enemy,profile_ms,seen_error_deg,shot_delay_ms,hit_delay_ms,shot_error_deg,shot_speed,ct_order_at_contact,outcome,same_target_at_shot,visible_exposure_ms,weapon");
        g_record = FindConVar("sm_bot_experience_record_enable");
        if (g_record != null) { g_oldRecord=g_record.FloatValue; g_record.IntValue=0; }
        ServerCommand("mp_warmup_end");
        PrintToServer("[DEBUG-combat-1019] OBSERVER_START %s",path);
    }
    if (GetGameTime()-g_started > 180.0) Cleanup();
    return Plugin_Continue;
}
public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_running || g_done || !IsFakeClient(client) || !IsPlayerAlive(client)
        || GameRules_GetProp("m_bWarmupPeriod") != 0 || GameRules_GetProp("m_bFreezePeriod") != 0) return;
    int enemy=GetEntDataEnt2(client,g_enemy);
    if (!GetEntData(client,g_visible) || enemy<1 || enemy>MaxClients || !IsClientInGame(enemy) || !IsPlayerAlive(enemy)) return;
    if (g_seen[client]>0.0)
    {
        if (GetClientUserId(enemy)==g_target[client]) g_exposure[client]+=GetTickInterval();
        return;
    }
    g_target[client]=GetClientUserId(enemy);
    g_seen[client]=GetGameTime();
    g_seenError[client]=AimError(client,enemy);
    Address profile=view_as<Address>(GetEntData(client,g_profile));
    g_reaction[client]=view_as<float>(LoadFromAddress(profile+view_as<Address>(84),NumberType_Int32));
    g_round[client]=GameRules_GetProp("m_totalRoundsPlayed")+1;
    if (GetClientTeam(client)==3 && GetFeatureStatus(FeatureType_Native,"BotCTTactics_GetOrder")==FeatureStatus_Available)
    { float goal[3]; int route; g_order[client]=BotCTTactics_GetOrder(client,goal,route); }
}
float AimError(int client,int enemy)
{
    float eye[3], target[3], direction[3], angles[3], aim[3];
    GetClientEyePosition(client,eye); GetClientEyePosition(enemy,target);
    MakeVectorFromPoints(eye,target,direction); NormalizeVector(direction,direction);
    GetClientEyeAngles(client,angles); GetAngleVectors(angles,aim,NULL_VECTOR,NULL_VECTOR);
    float dot=GetVectorDotProduct(direction,aim);
    if (dot>1.0) dot=1.0; if (dot< -1.0) dot=-1.0;
    return RadToDeg(ArcCosine(dot));
}
public void Fired(Event event,const char[] name,bool dontBroadcast)
{
    int client=GetClientOfUserId(event.GetInt("userid"));
    if (!g_running || g_done || client<1 || g_seen[client]<=0.0 || g_shot[client]>0.0) return;
    char weapon[32]; event.GetString("weapon",weapon,sizeof(weapon));
    if (StrContains(weapon,"grenade")!=-1 || StrContains(weapon,"knife")!=-1 || StrEqual(weapon,"molotov")) return;
    int enemy=GetClientOfUserId(g_target[client]);
    if (enemy<1 || !IsPlayerAlive(enemy)) return;
    g_shot[client]=GetGameTime(); g_shotError[client]=AimError(client,enemy);
    g_sameTarget[client]=GetEntDataEnt2(client,g_enemy)==enemy && GetEntData(client,g_visible)!=0;
    g_shotExposure[client]=g_exposure[client];
    int active=GetEntPropEnt(client,Prop_Send,"m_hActiveWeapon");
    if(active>MaxClients&&IsValidEntity(active))GetEntityClassname(active,g_weapon[client],sizeof(g_weapon[]));
    float velocity[3]; GetEntPropVector(client,Prop_Data,"m_vecAbsVelocity",velocity);
    g_speed[client]=GetVectorLength(velocity);
}
public void Hurt(Event event,const char[] name,bool dontBroadcast)
{
    int client=GetClientOfUserId(event.GetInt("attacker"));
    if (!g_running || g_done || client<1 || g_seen[client]<=0.0 || g_hit[client]>0.0
        || event.GetInt("userid")!=g_target[client]) return;
    g_hit[client]=GetGameTime();
}
public void Died(Event event,const char[] name,bool dontBroadcast)
{
    int client=GetClientOfUserId(event.GetInt("userid"));
    if (client>0 && g_running && !g_done) WriteResult(client,"died");
}
public void RoundEnd(Event event,const char[] name,bool dontBroadcast)
{
    if (!g_running || g_done || GameRules_GetProp("m_bWarmupPeriod")!=0) return;
    for (int i=1;i<=MaxClients;i++) if(IsClientInGame(i)&&IsFakeClient(i)) WriteResult(i,"round_end");
    g_rounds++; if(g_rounds>=3) Cleanup();
}
public void Spawned(Event event,const char[] name,bool dontBroadcast)
{
    int client=GetClientOfUserId(event.GetInt("userid"));
    if(client<1)return;
    g_seen[client]=g_shot[client]=g_hit[client]=0.0; g_written[client]=false; g_order[client]=false;
    g_sameTarget[client]=false; g_exposure[client]=g_shotExposure[client]=0.0; g_weapon[client][0]='\0';
}
void WriteResult(int client,const char[] outcome)
{
    if(g_output==null || g_seen[client]<=0.0 || g_written[client])return;
    g_written[client]=true;
    char name[64],enemyName[64]; GetClientName(client,name,sizeof(name));
    int enemy=GetClientOfUserId(g_target[client]); if(enemy>0)GetClientName(enemy,enemyName,sizeof(enemyName));
    ReplaceString(name,sizeof(name),",","_"); ReplaceString(enemyName,sizeof(enemyName),",","_");
    float shot=g_shot[client]>0.0?(g_shot[client]-g_seen[client])*1000.0:-1.0;
    float hit=g_hit[client]>0.0?(g_hit[client]-g_seen[client])*1000.0:-1.0;
    g_output.WriteLine("%d,%s,%s,%s,%.1f,%.2f,%.1f,%.1f,%.2f,%.1f,%d,%s,%d,%.1f,%s",g_round[client],GetClientTeam(client)==3?"CT":"T",
        name,enemyName,g_reaction[client]*1000.0,g_seenError[client],shot,hit,g_shotError[client],g_speed[client],g_order[client],outcome,
        g_sameTarget[client],g_shotExposure[client]*1000.0,g_weapon[client]);
    g_output.Flush();
    PrintToServer("[DEBUG-combat-1019] OBS round=%d %s %s shot=%.0f hit=%.0f error=%.1f speed=%.0f order=%d",
        g_round[client],GetClientTeam(client)==3?"CT":"T",name,shot,hit,g_shotError[client],g_speed[client],g_order[client]);
}
void Cleanup()
{
    if(g_done)return;
    if(g_running)
    {
        for(int i=1;i<=MaxClients;i++) if(IsClientInGame(i)&&IsFakeClient(i)) WriteResult(i,"end_observe");
        if(g_record!=null)g_record.FloatValue=g_oldRecord;
    }
    g_done=true; delete g_output;
    PrintToServer("[DEBUG-combat-1019] OBSERVER_COMPLETE rounds=%d",g_rounds);
}
public void OnPluginEnd(){Cleanup();}
