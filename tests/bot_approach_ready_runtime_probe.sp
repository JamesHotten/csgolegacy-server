#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <commandline>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3], bool live = false);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_ShouldHoldStage(int client);
native int NavMesh_GetNearestArea(const float pos[3], bool anyZ=false, float maxDist=10000.0, bool checkLOS=false, bool checkGround=true, int team=-2);
native bool NavMeshArea_GetCenter(int area, float result[3]);

public Plugin myinfo = {name = "Isolated tactical approach gun readiness", version = "1.0"};
int g_stage, g_user, g_safe, g_visible, g_rifle, g_knife, g_samples, g_rifleSamples;
int g_nearby, g_expected, g_opponentUser;
float g_since, g_goal[3];
float g_seenAt, g_revealAt;
bool g_tSide, g_testThreat, g_reveal;
int g_holdCase;
float g_holdAim[3];
int g_enemyOffset, g_lookState, g_visibleTicks, g_readyTicks;

public void OnPluginStart()
{
    if (GetCommandLineParamInt("-botapproachprobe") != 1) return;
    char ip[32];
    GetCommandLineParam("-ip",ip,sizeof(ip));
    if (!StrEqual(ip,"127.0.0.1")) SetFailState("Approach fixture needs loopback");
    char side[8];
    GetCommandLineParam("-botapproachside",side,sizeof(side));
    g_tSide=StrEqual(side,"T",false);
    g_testThreat=GetCommandLineParamInt("-botapproachthreat") == 1;
    g_expected=GetCommandLineParamInt("-botapproachexpect", -1);
    g_reveal=GetCommandLineParamInt("-botapproachreveal") == 1;
    g_holdCase=GetCommandLineParamInt("-botapproachholdcase"); // Require settled CT and a ready rifle at reveal.
    if (g_holdCase && (g_tSide || !g_reveal || g_testThreat)) SetFailState("Hold-fire case requires CT, reveal, and no simulated contact");
    GameData data = new GameData("botstuff.games");
    if (data == null) SetFailState("BetterBots gamedata missing");
    g_safe = data.GetOffset("CCSBot::m_safeTime");
    g_visible = data.GetOffset("CCSBot::m_isEnemyVisible");
    g_nearby = data.GetOffset("CCSBot::m_nearbyEnemyCount");
    g_enemyOffset = data.GetOffset("CCSBot::m_enemy");
    g_lookState = data.GetOffset("CCSBot::m_lookAtSpotState");
    delete data;
    if (g_safe < 0 || g_visible < 0 || g_nearby < 0 || g_enemyOffset < 0 || g_lookState < 0) SetFailState("BetterBots offsets missing");
    HookEvent("weapon_fire", Fired);
    CreateTimer(0.1,Tick,_,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action Tick(Handle timer)
{
    if (g_stage==4) return Plugin_Stop;
    for (int i=1;i<=MaxClients;i++)
        if (IsClientConnected(i) && !IsFakeClient(i)) return Plugin_Stop;
    float now=GetGameTime();
    if (!g_stage)
    {
        if (now<9.0) return Plugin_Continue;
        if (g_holdCase==2)
        {
            char map[64]; GetCurrentMap(map,sizeof(map));
            if (!StrEqual(map,"de_mirage")) SetFailState("Pinned hold-fire geometry requires Mirage");
        }
        ServerCommand("bot_dont_shoot 1; sm_bot_experience_record_enable 0; mp_ignore_round_win_conditions 1; mp_freezetime 1; mp_warmup_end");
        if (g_tSide)
            ServerCommand("sm_bot_ct_tactics_enable 0; sm_bot_t_tactics_enable 1; sm_bot_t_tactics_sync_enable 1; sm_bot_t_tactics_sync_stage_min 10; sm_bot_t_tactics_sync_stage_timeout 20; sm_bot_t_eco_rush_chance 0; sm_bot_t_force_rush_chance 0; sm_bot_t_full_rush_chance 0");
        else ServerCommand("sm_bot_t_tactics_enable 0");
        ServerCommand("mp_restartgame 1");
        g_stage=1;
        g_since=now;
        return Plugin_Continue;
    }
    if (g_stage==1)
    {
        if (now-g_since<3.0 || GameRules_GetProp("m_bFreezePeriod")) return Plugin_Continue;
        int bot, opponent, side=g_tSide ? CS_TEAM_T : CS_TEAM_CT;
        float goal[3], approach[3];
        for (int i=1;i<=MaxClients;i++)
        {
            if (!IsClientInGame(i) || !IsFakeClient(i) || !IsPlayerAlive(i)) continue;
            if (GetClientTeam(i)>CS_TEAM_SPECTATOR && GetClientTeam(i)!=side) { SetEntityMoveType(i,MOVETYPE_NONE); opponent=i; }
            if (!bot && GetClientTeam(i)==side && GetAssignedApproach(i,goal))
            {
                if (g_holdCase)
                {
                    if (g_holdCase==2)
                    {
                        float pinned[3]={-87.0,-1912.0,-165.0};
                        if (GetVectorDistance(goal,pinned)>16.0) continue;
                    }
                    if (!BotCTTactics_GetAim(i,g_holdAim)) continue;
                    approach=goal; approach[2]+=4.0;
                    bot=i;
                }
                else if (FindApproach(goal,approach)) bot=i;
            }
        }
        if (!bot || !opponent)
        {
            if (now-g_since>14.0) SetFailState("No assigned approach fixture");
            return Plugin_Continue;
        }
        g_goal=goal;
        g_user=GetClientUserId(bot);
        g_opponentUser=GetClientUserId(opponent);
        g_rifle=GetPlayerWeaponSlot(bot,CS_SLOT_PRIMARY);
        if (g_rifle<=MaxClients) g_rifle=GivePlayerItem(bot,"weapon_ak47");
        g_knife=GetPlayerWeaponSlot(bot,CS_SLOT_KNIFE);
        if (g_rifle<=MaxClients || g_knife<=MaxClients) SetFailState("Approach fixture needs rifle and knife");
        if (g_holdCase)
        {
            float stopped[3]; TeleportEntity(bot,approach,NULL_VECTOR,stopped);
        }
        else TeleportEntity(bot,approach,NULL_VECTOR,NULL_VECTOR);
        SetEntityMoveType(bot,MOVETYPE_NONE);
        if (g_holdCase)
        {
            float eye[3], direction[3], angles[3];
            GetClientEyePosition(bot,eye);
            MakeVectorFromPoints(eye,g_holdAim,direction);
            GetVectorAngles(direction,angles);
            TeleportEntity(bot,NULL_VECTOR,angles,NULL_VECTOR);
            EquipPlayerWeapon(bot,g_rifle);
            SetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon",g_rifle);
        }
        else
        {
            SetEntDataFloat(bot,g_safe,120.0);
            SetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon",g_knife);
        }
        g_since=now;
        g_stage=2;
        return Plugin_Continue;
    }
    int bot=GetClientOfUserId(g_user);
    float foot[3], goal[3];
    if (!bot || !IsPlayerAlive(bot)) SetFailState("Lost approach fixture BOT");
    if (g_stage==3)
    {
        if (now-g_revealAt>5.0)
        {
            PrintToServer("[DEBUG-approach] REVEAL_TIMEOUT seen=%d",g_seenAt>0.0);
            ReportHandoff();
            g_stage=4;
            return Plugin_Stop;
        }
        return Plugin_Continue;
    }
    GetClientAbsOrigin(bot,foot);
    float distance=GetVectorDistance(foot,g_goal);
    if (GetEntData(bot,g_visible,1)!=0 || (!g_holdCase && (distance<290.0 || distance>470.0))
        || (g_holdCase && distance>16.0)
        || !GetAssignedApproach(bot,goal) || GetVectorDistance(goal,g_goal)>32.0)
        SetFailState("BOT left the valid out-of-hold approach fixture");
    if (now-g_since>(g_holdCase ? 1.5 : 0.75))
    {
        g_samples++;
        if (GetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon")==g_rifle) g_rifleSamples++;
    }
    if (g_samples<8) return Plugin_Continue;
    PrintToServer("[DEBUG-approach] RESULT side=%s nearby=%d out_of_hold_distance=%.0f rifle=%d/%d",g_tSide?"T":"CT",g_testThreat,distance,g_rifleSamples,g_samples);
    if (g_expected>=0 && g_expected!=g_rifleSamples) SetFailState("Unexpected approach rifle count");
    if (g_reveal)
    {
        int opponent=GetClientOfUserId(g_opponentUser);
        float point[3], eye[3], vector[3], angles[3];
        if (!opponent || !IsPlayerAlive(opponent) || !FindReveal(bot,foot,point)) SetFailState("No clear reveal lane");
        if (g_holdCase && (GetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon")!=g_rifle
            || GetEntPropFloat(bot,Prop_Send,"m_flNextAttack")>now
            || GetEntPropFloat(g_rifle,Prop_Send,"m_flNextPrimaryAttack")>now || GetEntProp(g_rifle,Prop_Send,"m_iClip1")<=0))
            SetFailState("Hold-fire case requires a ready rifle at reveal");
        GetClientEyePosition(bot,eye);
        point[2]+=64.0;
        MakeVectorFromPoints(eye,point,vector);
        point[2]-=64.0;
        GetVectorAngles(vector,angles);
        if (!g_holdCase || g_holdCase==2) TeleportEntity(bot,NULL_VECTOR,angles,NULL_VECTOR);
        SetEntityHealth(bot,10000);
        SetEntityHealth(opponent,10000);
        TeleportEntity(opponent,point,NULL_VECTOR,NULL_VECTOR);
        PrintToServer("[DEBUG-approach] REVEAL_READY rifle=%d cooldown_ms=%.1f",GetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon")==g_rifle,
            (GetEntPropFloat(bot,Prop_Send,"m_flNextAttack")-now)*1000.0);
        if (g_holdCase)
        {
            float current[3]; GetClientEyeAngles(bot,current);
            PrintToServer("[DEBUG-approach] WATCH_GEOMETRY goal=%.0f,%.0f,%.0f reveal=%.0f,%.0f,%.0f yaw_error=%.1f",
                g_goal[0],g_goal[1],g_goal[2],point[0],point[1],point[2],FloatAbs(AngleDiff(current[1],angles[1])));
        }
        g_revealAt=now;
        g_stage=3;
        ServerCommand("bot_dont_shoot 0");
        return Plugin_Continue;
    }
    return Plugin_Stop;
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (g_stage<2 || g_stage>3 || client!=GetClientOfUserId(g_user)) return;
    for (int i=1;i<=MaxClients;i++) if (IsClientConnected(i) && !IsFakeClient(i)) return;
    if (g_stage==2 && g_testThreat) SetEntData(client,g_nearby,1);
    if (g_stage==3)
    {
        if (GetEntData(client,g_visible,1)==0 || GetEntDataEnt2(client,g_enemyOffset)!=GetClientOfUserId(g_opponentUser)) return;
        float now=GetGameTime();
        if (!g_seenAt)
        {
            g_seenAt=now;
            if (g_holdCase)
            {
                float velocity[3]; GetEntPropVector(client,Prop_Data,"m_vecAbsVelocity",velocity);
                PrintToServer("[DEBUG-approach] CONTACT_STATE look=%d speed=%.1f",GetEntData(client,g_lookState),GetVectorLength(velocity));
            }
        }
        g_visibleTicks++;
        if (GetEntPropEnt(client,Prop_Send,"m_hActiveWeapon")==g_rifle
            && GetEntPropFloat(client,Prop_Send,"m_flNextAttack")<=now
            && GetEntPropFloat(g_rifle,Prop_Send,"m_flNextPrimaryAttack")<=now
            && !GetEntProp(g_rifle,Prop_Data,"m_bInReload") && GetEntProp(g_rifle,Prop_Send,"m_iClip1")>0) g_readyTicks++;
    }
}

public void Fired(Event event,const char[] name,bool dontBroadcast)
{
    if (g_stage!=3 || GetClientOfUserId(event.GetInt("userid"))!=GetClientOfUserId(g_user)) return;
    int bot=GetClientOfUserId(g_user);
    if (!bot || GetEntPropEnt(bot,Prop_Send,"m_hActiveWeapon")!=g_rifle) return;
    PrintToServer("[DEBUG-approach] FIRST_RIFLE_FIRE reveal_ms=%.1f seen_ms=%.1f",(GetGameTime()-g_revealAt)*1000.0,
        g_seenAt>0.0 ? (GetGameTime()-g_seenAt)*1000.0 : -1.0);
    ReportHandoff();
    g_stage=4;
}

void ReportHandoff()
{
    if (g_holdCase) PrintToServer("[DEBUG-approach] HANDOFF visible_ticks=%d ready_ticks=%d",g_visibleTicks,g_readyTicks);
}

bool FindReveal(int bot,const float foot[3],float point[3])
{
    float eye[3]; GetClientEyePosition(bot,eye);
    if (g_holdCase==2)
    {
        float pinned[3]={125.0,-1525.0,-169.0}, target[3];
        point=pinned; target=pinned; target[2]+=64.0;
        Handle trace=TR_TraceRayFilterEx(eye,target,MASK_SHOT,RayType_EndPoint,IgnorePlayers);
        bool clear=!TR_DidHit(trace); delete trace;
        return clear;
    }
    float best=-2.0, holdDir[3];
    if (g_holdCase) { MakeVectorFromPoints(eye,g_holdAim,holdDir); NormalizeVector(holdDir,holdDir); }
    for (int i=0;i<24;i++)
    {
        float guess[3], angle=DegToRad(float(i)*15.0);
        guess[0]=foot[0]+Cosine(angle)*460.0;
        guess[1]=foot[1]+Sine(angle)*460.0;
        guess[2]=foot[2];
        int area=NavMesh_GetNearestArea(guess,false,130.0,false,true,-2);
        float candidate[3];
        if (area<0 || !NavMeshArea_GetCenter(area,candidate) || FloatAbs(candidate[2]-foot[2])>48.0) continue;
        float distance=GetVectorDistance(foot,candidate);
        if (distance<350.0 || distance>600.0) continue;
        float target[3]; target=candidate; target[2]+=64.0;
        Handle trace=TR_TraceRayFilterEx(eye,target,MASK_SHOT,RayType_EndPoint,IgnorePlayers);
        bool clear=!TR_DidHit(trace); delete trace;
        if (!clear) continue;
        if (!g_holdCase) { point=candidate; point[2]+=4.0; return true; }
        float dir[3]; MakeVectorFromPoints(eye,target,dir); NormalizeVector(dir,dir);
        float dot=GetVectorDotProduct(dir,holdDir);
        if (dot>best && dot>0.60) { best=dot; point=candidate; point[2]+=4.0; }
    }
    return best>0.60;
}

float AngleDiff(float a,float b)
{
    float delta=a-b;
    while(delta>180.0) delta-=360.0;
    while(delta < -180.0) delta+=360.0;
    return delta;
}

public bool IgnorePlayers(int entity,int mask) { return entity>MaxClients; }

bool GetAssignedApproach(int client,float goal[3])
{
    int route;
    if (g_tSide) return BotTTactics_ShouldHoldStage(client) && BotTTactics_GetOrder(client,goal,route);
    float aim[3];
    return BotCTTactics_GetOrder(client,goal,route) && BotCTTactics_GetAim(client,aim);
}

bool FindApproach(const float goal[3],float pos[3])
{
    for (int i=0;i<24;i++)
    {
        float guess[3], angle=DegToRad(float(i)*15.0);
        guess[0]=goal[0]+Cosine(angle)*380.0;
        guess[1]=goal[1]+Sine(angle)*380.0;
        guess[2]=goal[2];
        int area=NavMesh_GetNearestArea(guess,false,108.0,false,true,-2);
        if (area<0 || !NavMeshArea_GetCenter(area,pos)) continue;
        float distance=GetVectorDistance(pos,goal);
        if (distance<300.0 || distance>455.0 || FloatAbs(pos[2]-goal[2])>48.0) continue;
        pos[2]+=4.0;
        return true;
    }
    return false;
}
