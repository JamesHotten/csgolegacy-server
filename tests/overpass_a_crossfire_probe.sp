#define OnPluginStart Opening_Start
#include "ct_opening_position_runtime_probe.sp"
#undef OnPluginStart

native int NavMesh_WorldToGridX(float x);
native int NavMesh_WorldToGridY(float y);
native void NavMesh_GetAreasOnGrid(ArrayStack areas, int x, int y);
native bool NavMeshArea_GetCenter(int area, float p[3]);

// Enemy eye positions from actual Lower Park kills (rounded to map units).
static const float Park[3][3] = {{-2505.0,260.0,517.0},{-2450.0,92.0,490.0},{-2487.0,269.0,522.0}};
float doors[48][4];
int doorCount;
float reference[3];

public void OnPluginStart()
{
    Opening_Start();
    HookEvent("round_freeze_end", PairFreeze, EventHookMode_PostNoCopy);
}

public void OnConfigsExecuted()
{
    if (!Safe() || !FindCommandLineParam("-ovcrossoff")) return;
    ConVar mode=FindConVar("sm_bot_ct_overpass_a_crossfire");
    if (mode==null) SetFailState("Overpass pair cvar unavailable");
    else mode.BoolValue=false;
}

public void PairFreeze(Event event, const char[] name, bool quiet)
{
    if (!Safe() || !StrEqual(g_mapName,"de_overpass") || GameRules_GetProp("m_bWarmupPeriod")) return;
    CreateTimer(0.35, PairMeasure, false, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(9.0, PairMeasure, true, TIMER_FLAG_NO_MAPCHANGE);
}

bool FireLine(const float eye[3], const float point[3])
{
    Handle h=TR_TraceRayFilterEx(eye,point,MASK_SHOT,RayType_EndPoint,World);
    bool valid=!TR_DidHit(h) && !TR_StartSolid(h);
    delete h;
    return valid;
}

bool Floor(const float point[3], float foot[3])
{
    float mins[3]={-16.0,-16.0,0.0}, maxs[3]={16.0,16.0,72.0}, down[3];
    foot=point;foot[2]+=8.0; down=foot;down[2]-=24.0;
    Handle h=TR_TraceHullFilterEx(foot,down,mins,maxs,MASK_PLAYERSOLID,World);
    bool valid=TR_DidHit(h) && !TR_StartSolid(h);
    if(valid){TR_GetEndPosition(foot,h);foot[2]+=2.0;}
    delete h;
    return valid;
}

int ParkMask(const float foot[3])
{
    float eye[3]; eye=foot;eye[2]+=64.0;
    int count;
    for(int j=0;j<sizeof(Park);j++) if(FireLine(eye,Park[j])) count|=1<<j;
    return count;
}

int SectorMask(const float foot[3])
{
    float eye[3];eye=foot;eye[2]+=64.0;
    int mask;
    for(int i=0;i<doorCount;i++){
        float aim[3]; for(int j=0;j<3;j++) aim[j]=doors[i][j]; aim[2]+=64.0;
        int bit=RoundToNearest(doors[i][3]);
        if(!(mask&bit) && GetVectorDistance(aim,eye)>=130.0 && FireLine(eye,aim)) mask|=bit;
    }
    return mask;
}

void Apertures(const float ref[3], bool survey)
{
    ArrayStack nav=new ArrayStack();
    for(int x=NavMesh_WorldToGridX(ref[0]-1100.0);x<=NavMesh_WorldToGridX(ref[0]+1100.0);x++)
        for(int y=NavMesh_WorldToGridY(ref[1]-1350.0);y<=NavMesh_WorldToGridY(ref[1]+950.0);y++) NavMesh_GetAreasOnGrid(nav,x,y);
    StringMap seen=new StringMap();ArrayList holds=new ArrayList(3);
    doorCount=0;
    while(!nav.Empty)
    {
        int area=nav.Pop();
        char key[20], place[32];IntToString(area,key,sizeof(key));
        if(!seen.SetValue(key,1,false))continue;
        float p[3];if(!NavMeshArea_GetCenter(area,p))continue;
        NavMeshArea_GetPlaceCanonical(area,place,sizeof(place));
        int bit;
        if(StrEqual(place,"Restroom",false))bit=1;
        if(StrEqual(place,"UpperPark",false))bit=2;
        if(StrEqual(place,"Connector",false))bit=4;
        if(bit && doorCount<sizeof(doors) && GetVectorDistance(p,ref)<1520.0){
            for(int j=0;j<3;j++) doors[doorCount][j]=p[j];doors[doorCount++][3]=float(bit);
            if(survey)PrintToServer("OVC_APERTURE bit=%d p=%.1f,%.1f,%.1f",bit,p[0],p[1],p[2]+64.0);
        }
        if(survey && FloatAbs(p[2]-ref[2])<=83.0 && GetVectorDistance(p,ref)<630.0)holds.PushArray(p);
    }
    for(int n=0;n<holds.Length;n++){
        float p[3],foot[3];holds.GetArray(n,p);
        if(!Floor(p,foot)) continue;
        int park=ParkMask(foot);
        if(!park)continue;
        PrintToServer("OVC_SCAN p=%.1f,%.1f,%.1f zone=%d park=%d sectors=%d",foot[0],foot[1],foot[2],InZone(foot),park,SectorMask(foot));
    }
    delete nav;delete seen;delete holds;
}

public Action PairMeasure(Handle timer, any live)
{
    if(!Safe() || g_round!=1)return Plugin_Stop;
    TacticalMap_PlantGround(g_map,0,reference);
    if(!live)Apertures(reference,FindCommandLineParam("-ovcrosssurvey"));
    int common=7,count,restroom;
    for(int slot=0;slot<g_roster;slot++)
    {
        if(GetVectorDistance(reference,g_goal[slot])>850.0 || FloatAbs(g_goal[slot][2]-reference[2])>105.0) continue;
        int client=GetClientOfUserId(g_uid[slot]);if(!client || !IsPlayerAlive(client))continue;
        float foot[3], aim[3];foot=g_goal[slot];
        if(live)GetClientAbsOrigin(client,foot);
        bool hasAim=BotCTTactics_GetAim(client,aim,live!=0);
        int mask=ParkMask(foot), others=SectorMask(foot);common&=mask;restroom|=others;
        count++;
        PrintToServer("OVC_SLOT phase=%d zone=%d park=%d sectors=%d goal=%.0f,%.0f,%.0f pos=%.0f,%.0f,%.0f aim=%d at=%.0f look=%.0f,%.0f,%.0f hold=%.0f",
            live,InZone(foot),mask,others,g_goal[slot][0],g_goal[slot][1],g_goal[slot][2],foot[0],foot[1],foot[2],hasAim && ClearAim(foot,aim),
            GetVectorDistance(foot,g_goal[slot]),aim[0],aim[1],aim[2],g_radius[slot]);
    }
    PrintToServer("OVC_RESULT phase=%d count=%d shared=%d restroom=%d",live,count,count==2?common:0,(restroom&1)!=0);
    if(live && StrEqual(g_mapName,"de_overpass"))
        CreateTimer(2.0, PairQuit, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action PairQuit(Handle timer)
{
    if(Safe()) ServerCommand("quit");
    return Plugin_Stop;
}
