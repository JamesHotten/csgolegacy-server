#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include "../mods/include/bot_ct_watch_sectors.inc"
native bool BotCTTactics_GetOrder(int client,float goal[3],int &route);
native bool BotCTTactics_GetAim(int client,float look[3]);
native int NavMesh_GetNearestArea(const float pos[3],bool anyZ=false,float maxDist=10000.0,bool checkLOS=false,bool checkGround=true,int team=-2);
native void NavMeshArea_GetPlace(int area,char[] place,int length);
native void NavMeshArea_GetPlaceCanonical(int area,char[] place,int length);
public APLRes AskPluginLoad2(Handle myself,bool late,char[] error,int length)
{
    MarkNativeAsOptional("NavMeshArea_GetPlaceCanonical");
    return APLRes_Success;
}
public Plugin myinfo={name="CT fixed watch probe",author="server project",version="1.0"};
Handle g_look;
ConVar g_auto,g_rosterTest,g_settings[5];
int g_old[5],g_stage,g_bot,g_failures,g_samples,g_aligned;
bool g_running,g_done,g_settled;
float g_settleSince;
float g_after,g_start,g_goal[3],g_aim[3],g_opposite[3];
float g_positions[MAXPLAYERS+1][3],g_angles[MAXPLAYERS+1][3];
MoveType g_moves[MAXPLAYERS+1];
int g_users[MAXPLAYERS+1];
public void OnPluginStart()
{
    for(int count=1;count<=5;count++)
    {
        bool used[5];
        for(int slot=0;slot<count;slot++)
        {
            int sector=CTWatch_GetSector(slot,count);
            if(sector<0||sector>4||used[sector])SetFailState("Duplicate site-local watch sector");
            used[sector]=true;
        }
    }
    if(CTWatch_GetSector(0,1)!=0||CTWatch_GetSector(0,2)!=1||CTWatch_GetSector(1,2)!=2)
        SetFailState("Incorrect lone-anchor or left/right watch assignment");
    GameData data=new GameData("botstuff.games");
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(data,SDKConf_Signature,"CCSBot::SetLookAt");
    PrepSDKCall_AddParameter(SDKType_String,SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_Vector,SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData,SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float,SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool,SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float,SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Bool,SDKPass_Plain);
    g_look=EndPrepSDKCall();delete data;
    if(g_look==null)SetFailState("Cannot prepare installed look SDKCall");
    g_auto=CreateConVar("sm_ct_watch_probe_auto","0","Explicit empty-server watch-direction probe.");
    g_rosterTest=CreateConVar("sm_ct_watch_probe_roster","0","Explicit missing-profile/no-logo roster fixture.");
    CreateTimer(0.1,Tick,_,TIMER_REPEAT);
}
public Action Tick(Handle timer)
{
    if(g_done||!g_auto.BoolValue)return Plugin_Continue;
    for(int i=1;i<=MaxClients;i++)
        if(IsClientInGame(i)&&!IsFakeClient(i)){Cleanup();return Plugin_Stop;}
    if(g_stage==0)
    {
        if(GetGameTime()<12.0)return Plugin_Continue;
        if(GetFeatureStatus(FeatureType_Native,"NavMeshArea_GetPlaceCanonical")==FeatureStatus_Available)
        {
            int spawn=FindEntityByClassname(-1,"info_player_terrorist");float position[3];
            GetEntPropVector(spawn,Prop_Send,"m_vecOrigin",position);
            int area=NavMesh_GetNearestArea(position,true,600.0,false,true,-2);
            char legacy[32],canonical[32];NavMeshArea_GetPlace(area,legacy,32);NavMeshArea_GetPlaceCanonical(area,canonical,32);
            PrintToServer("NAV_PLACE_PROBE legacy=%s canonical=%s",legacy,canonical);
            Check("canonical_t_spawn_place",StrEqual(canonical,"TSpawn"));
        }
        char names[5][48]={"bot_dont_shoot","sm_bot_t_tactics_enable","sm_bot_experience_record_enable","mp_ignore_round_win_conditions","sm_bot_ct_tactics_debug"};
        for(int n=0;n<5;n++){g_settings[n]=FindConVar(names[n]);g_old[n]=g_settings[n].IntValue;g_settings[n].IntValue=(n==0||n>=3)?1:0;}
        g_running=true;
        if(g_rosterTest.BoolValue)ServerCommand("mp_teamlogo_1 g2; mp_teamname_1 stale; team LargadosyPelados ct");
        ServerCommand("mp_warmup_end; mp_restartgame 1");
        g_after=GetGameTime()+2.0;g_stage=1;return Plugin_Continue;
    }
    if(GetGameTime()<g_after)return Plugin_Continue;
    if(g_stage==1)
    {
        if(GameRules_GetProp("m_bFreezePeriod")!=0)return Plugin_Continue;
        // No live opponents during an attention-arbitration measurement.
        // Hiding them below the map is insufficient: native enemy memory can
        // still report the C4 carrier there and correctly replan the defense.
        for(int i=1;i<=MaxClients;i++)
        {
            if(!IsClientInGame(i)||!IsFakeClient(i)||!IsPlayerAlive(i)||GetClientTeam(i)!=CS_TEAM_T)continue;
            int c4=GetPlayerWeaponSlot(i,CS_SLOT_C4);
            if(c4!=-1){RemovePlayerItem(i,c4);RemoveEntity(c4);}
            ForcePlayerSuicide(i);
        }
        bool ordered;
        for(int i=1;i<=MaxClients;i++)
        {
            float goal[3];int route;
            if(IsClientInGame(i)&&IsFakeClient(i)&&IsPlayerAlive(i)&&GetClientTeam(i)==CS_TEAM_CT&&BotCTTactics_GetOrder(i,goal,route))ordered=true;
        }
        if(!ordered)return Plugin_Continue;
        if(g_rosterTest.BoolValue)
        {
            char expected[5][32]={"zmb","happ","Leomonster","divine","Alisson"};
            int matches;bool seen[5];
            for(int i=1;i<=MaxClients;i++)
            {
                if(!IsClientInGame(i)||!IsFakeClient(i)||GetClientTeam(i)!=CS_TEAM_CT)continue;
                char name[32];GetClientName(i,name,sizeof(name));
                for(int n=0;n<5;n++)if(!seen[n]&&StrEqual(name,expected[n])){seen[n]=true;matches++;break;}
            }
            Check("repaired_roster_spawns_all_five_names",matches==5);
            char logo[64],team[64];FindConVar("mp_teamlogo_1").GetString(logo,sizeof(logo));FindConVar("mp_teamname_1").GetString(team,sizeof(team));
            Check("no_logo_clears_stale_identity",logo[0]=='\0'&&StrEqual(team,"LargadosyPelados"));
        }
        for(int i=1;i<=MaxClients;i++)
        {
            if(!IsClientInGame(i)||!IsFakeClient(i)||!IsPlayerAlive(i))continue;
            float goal[3];int route;
            bool ct=GetClientTeam(i)==CS_TEAM_CT&&BotCTTactics_GetOrder(i,goal,route);
            GetClientAbsOrigin(i,g_positions[i]);GetClientEyeAngles(i,g_angles[i]);g_users[i]=GetClientUserId(i);
            g_moves[i]=GetEntityMoveType(i);SetEntityMoveType(i,MOVETYPE_NONE);
            if(ct)
            {
                goal[2]+=4.0;TeleportEntity(i,goal,NULL_VECTOR,NULL_VECTOR);
                if(g_bot==0&&BotCTTactics_GetAim(i,g_aim)){g_bot=i;for(int k=0;k<3;k++)g_goal[k]=goal[k];}
                int grenade;while((grenade=GetPlayerWeaponSlot(i,CS_SLOT_GRENADE))!=-1){RemovePlayerItem(i,grenade);RemoveEntity(grenade);}
                int gun=GetPlayerWeaponSlot(i,CS_SLOT_PRIMARY);if(gun==-1)gun=GetPlayerWeaponSlot(i,CS_SLOT_SECONDARY);if(gun!=-1)EquipPlayerWeapon(i,gun);
            }
            else
            {
                float hidden[3]={0.0,0.0,-10000.0};hidden[0]=float(i)*500.0;TeleportEntity(i,hidden,NULL_VECTOR,NULL_VECTOR);
            }
        }
        if(g_bot==0)SetFailState("Need a quiet ordered CT after freeze end");
        float eye[3];GetClientEyePosition(g_bot,eye);
        for(int k=0;k<3;k++)g_opposite[k]=eye[k]-(g_aim[k]-eye[k]);
        g_start=GetGameTime();g_stage=2;
        PrintToServer("CT_WATCH_PROBE_STARTED bot=%N",g_bot);
    }
    if(g_stage==2)
    {
        // Measure resistance to competing requests only after the native
        // controller has settled. Also bound and report initial convergence,
        // rather than treating slow natural turning as attention theft.
        if(!g_settled)
        {
            float now=GetGameTime();
            if(Error(g_aim)<10.0)
            {
                if(g_settleSince==0.0)g_settleSince=now;
                if(now-g_settleSince>=0.5)
                {
                    PrintToServer("CT_WATCH_PROBE initial_settle_seconds=%.1f",now-g_start);
                    g_settled=true;g_start=now-2.0;
                }
            }
            else g_settleSince=0.0;
            if(!g_settled&&now-g_start>10.0)
            {
                Check("initial_heading_converges_within_10s",false);
                PrintToServer("CT_WATCH_PROBE_FAIL failures=%d",g_failures);Cleanup();return Plugin_Stop;
            }
            return Plugin_Continue;
        }
        float elapsed=GetGameTime()-g_start;
        if(elapsed>=2.0&&elapsed<9.0)
        {
            float cached[3];
            CheckSilent("cached_heading_stays_fixed",BotCTTactics_GetAim(g_bot,cached)&&GetVectorDistance(cached,g_aim)<1.0);
            g_samples++;float error=Error(g_aim);if(error<15.0)g_aligned++;
            if(g_samples%10==0)PrintToServer("CT_WATCH_PROBE elapsed=%.1f error=%.1f",elapsed,error);
            // Standard idle/noise look request competing with a quiet settled
            // assignment; never inject enemy visibility, damage or forced aim.
            SDKCall(g_look,g_bot,"Noise",g_opposite,2,1.0,false,8.0,false);
        }
        if(elapsed>=9.0)
        {
            PrintToServer("CT_WATCH_PROBE aligned=%d/%d",g_aligned,g_samples);
            Check("quiet_assigned_heading_resists_idle_glances",g_samples>0&&g_aligned*100>=g_samples*85);
            Event fired=CreateEvent("weapon_fire");fired.SetInt("userid",GetClientUserId(g_bot));fired.SetString("weapon","ak47");fired.Fire();
            float goal[3];int route;
            Check("combat_releases_assignment",!BotCTTactics_GetOrder(g_bot,goal,route));
            g_after=GetGameTime()+1.5;g_stage=3;
        }
    }
    else if(g_stage==3)
    {
        SDKCall(g_look,g_bot,"Noise",g_opposite,2,1.0,false,8.0,false);
        // Tick's early timer gate is intentionally bypassed in stage 4 so the
        // native controller has time to turn after assignment release.
        g_after=0.0;g_start=GetGameTime();g_stage=4;
    }
    else if(g_stage==4)
    {
        SDKCall(g_look,g_bot,"Noise",g_opposite,2,1.0,false,8.0,false);
        if(GetGameTime()-g_start>=1.5)
        {
            Check("released_ct_can_turn_to_combat_noise",Error(g_aim)>45.0);
            PrintToServer("CT_WATCH_PROBE_%s failures=%d",g_failures==0?"PASS":"FAIL",g_failures);Cleanup();return Plugin_Stop;
        }
    }
    return Plugin_Continue;
}
float Error(const float target[3])
{
    float eye[3],angles[3],direction[3],aim[3];GetClientEyePosition(g_bot,eye);GetClientEyeAngles(g_bot,angles);
    MakeVectorFromPoints(eye,target,direction);NormalizeVector(direction,direction);GetAngleVectors(angles,aim,NULL_VECTOR,NULL_VECTOR);
    float dot=GetVectorDotProduct(direction,aim);if(dot>1.0)dot=1.0;if(dot< -1.0)dot=-1.0;return RadToDeg(ArcCosine(dot));
}
void Check(const char[] name,bool ok){PrintToServer("CT_WATCH_PROBE %s %s",name,ok?"PASS":"FAIL");if(!ok)g_failures++;}
void CheckSilent(const char[] name,bool ok){if(!ok){Check(name,false);}}
void Cleanup()
{
    if(g_done)return;g_done=true;
    if(g_running)
    {
        for(int n=0;n<5;n++)if(g_settings[n]!=null)g_settings[n].IntValue=g_old[n];
        for(int i=1;i<=MaxClients;i++)if(IsClientInGame(i)&&IsPlayerAlive(i)&&g_users[i]==GetClientUserId(i))
        {SetEntityMoveType(i,g_moves[i]);TeleportEntity(i,g_positions[i],g_angles[i],NULL_VECTOR);}
    }
}
public void OnPluginEnd(){Cleanup();}
