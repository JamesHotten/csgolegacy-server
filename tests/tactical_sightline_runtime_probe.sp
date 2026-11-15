#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <cstrike>

native bool BotCTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotCTTactics_GetAim(int client, float look[3], bool live = false);
native bool BotTTactics_GetOrder(int client, float goal[3], int &route);
native bool BotTTactics_GetAim(int client, float look[3], bool live = false);
native int NavMesh_GetNearestArea(const float pos[3], bool anyZ=false, float maxDist=10000.0, bool checkLOS=false, bool checkGround=true, int team=-2);
native void NavMeshArea_GetPlaceCanonical(int area, char[] name, int length);
native int NavMesh_WorldToGridX(float x);
native int NavMesh_WorldToGridY(float y);
native void NavMesh_GetAreasOnGrid(ArrayStack areas, int x, int y);
native bool NavMeshArea_GetCenter(int area, float out[3]);
native void NavMeshArea_GetClosestPointOnArea(int area, const float from[3], float out[3]);
native bool BotStuff_CanSeeLooseC4(int client, int bomb);
#include "../mods/include/bot_tactical_map_profiles.inc"

public Plugin myinfo = {name = "Isolated objective sightline survey", version = "1.1"};
ConVar g_on;
ConVar g_endMap, g_seed, g_exposure;
bool g_armed;
int g_map, g_site, g_planter, g_bomb = INVALID_ENT_REFERENCE;
float g_started;
int g_loose = INVALID_ENT_REFERENCE, g_spotter;
float g_looseStart, g_spotterOriginal[3], g_spotterAngles[3], g_spotterAim[3];
MoveType g_spotterMove;
int g_samplesByLane[3];
static const char Maps[][] = {"de_inferno","de_train","de_mirage","de_nuke","de_dust2","de_overpass","de_vertigo","de_cache","de_ancient","de_anubis"};
// On this server these exact standing spots passed the earlier engine bomb-zone survey.
static const float Plant[10][2][3] = {
    {{1887.5,475.0,160.0},{475.0,2650.0,160.0}},
    {{637.5,-137.5,-217.9},{50.0,-1287.5,-286.9}},
    {{-437.5,-2200.0,-177.9},{-2100.0,187.5,-159.9}},
    {{587.5,-762.5,-399.9},{700.0,-987.5,-769.1}},
    {{1100.0,2462.5,96.0},{-1550.0,2687.5,5.9}},
    {{-2062.5,662.5,472.0},{-1100.0,50.0,98.0}},
    {{-287.5,-575.0,11775.0},{-2212.5,725.0,11744.0}},
    {{-312.5,1762.5,1686.5},{-37.5,-1250.0,1659.1}},
    {{-1425.0,825.0,53.5},{987.5,-50.0,131.0}},
    {{1262.5,1987.5,-191.9},{-950.0,625.0,-1.9}}
};

public void OnPluginStart()
{
    g_on = CreateConVar("sm_objective_angle_survey", "0", "Only on isolated loopback server.");
    g_endMap = CreateConVar("sm_objective_angle_end_map", "de_anubis", "Last map to inspect.");
    g_seed = CreateConVar("sm_objective_angle_seed", "12015", "Use the same objective planning seed for geometry comparisons.");
    g_exposure = CreateConVar("sm_hold_exposure_survey", "0", "Include objective exposure and loose-C4 checks on the isolated server.");
    HookEvent("round_freeze_end", Start, EventHookMode_PostNoCopy);
}

bool Safe()
{
    if (!g_on.BoolValue) return false;
    for (int i = 1; i <= MaxClients; i++) if (IsClientConnected(i) && !IsFakeClient(i)) return false;
    return true;
}

public void OnMapStart()
{
    g_map = -1;
    g_site = 0;
    g_armed = false;
    g_bomb = INVALID_ENT_REFERENCE;
    g_loose = INVALID_ENT_REFERENCE;
    char map[32];
    GetCurrentMap(map,sizeof(map));
    for (int i = 0; i < sizeof(Maps); i++) if (StrEqual(Maps[i],map)) g_map = i;
    CreateTimer(7.0, Prep, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Prep(Handle timer)
{
    if (!Safe() || g_map < 0) return Plugin_Stop;
    ServerCommand("sv_cheats 1; bot_stop 1; bot_dont_shoot 1; mp_autoteambalance 0; mp_limitteams 0; mp_freezetime 2; mp_do_warmup_period 0; mp_ignore_round_win_conditions 1; bot_quota 0; bot_kick");
    ServerExecute();
    if (g_exposure.BoolValue) FindConVar("sm_bot_t_tactics_debug").BoolValue = true;
    for (int i = 0; i < 5; i++) ServerCommand("bot_add_ct; bot_add_t");
    ServerExecute();
    g_armed = true;
    g_started = GetGameTime();
    ServerCommand("mp_warmup_end; mp_restartgame 1");
    CreateTimer(5.0, CheckStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action CheckStart(Handle timer)
{
    if (!Safe() || !g_armed) return Plugin_Stop;
    if (GetGameTime() - g_started > 18.0)
    {
        PrintToServer("ANGLE_SKIP map=%s site=%d no_freeze_end", Maps[g_map], g_site);
        NextMap();
        return Plugin_Stop;
    }
    if (GameRules_GetProp("m_bWarmupPeriod")) ServerCommand("mp_warmup_end; mp_restartgame 1");
    return Plugin_Continue;
}

public void Start(Event event, const char[] name, bool noBroadcast)
{
    if (!Safe() || !g_armed || GameRules_GetProp("m_bWarmupPeriod")) return;
    g_armed = false;
    CreateTimer(0.30, Cover, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Cover(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    ServerCommand("sm_bot_experience_record_enable 0");
    SetRandomSeed(g_seed.IntValue + g_map * 10 + g_site);
    Measure("ct_open", true);
    if (!g_exposure.BoolValue) return BeginPlantCover(timer);
    InspectExposure("ct_open", true, false);
    if (StartLoose())
    {
        CreateTimer(0.25, CheckLoose, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }
    PrintToServer("EXPOSURE_SKIP map=%s site=%d phase=ct_loose no_fixture", Maps[g_map], g_site);
    return BeginPlantCover(timer);
}

bool StartLoose()
{
    g_spotter = 0;
    int actual = -1;
    while ((actual = FindEntityByClassname(actual, "weapon_c4")) != -1)
        if (GetEntPropEnt(actual, Prop_Send, "m_hOwnerEntity") <= 0) RemoveEntity(actual);
    for (int i=1; i<=MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_CT) {g_spotter=i; break;}
    if (!g_spotter) return false;
    int bomb = CreateEntityByName("weapon_c4");
    if (bomb == -1) return false;
    DispatchSpawn(bomb);
    SetEntityMoveType(bomb, MOVETYPE_NONE);
    float point[3], foot[3], eye[3], dir[3];
    point = Plant[g_map][g_site];
    point[2] += 12.0;
    TeleportEntity(bomb, point, NULL_VECTOR, NULL_VECTOR);
    GetClientAbsOrigin(g_spotter, g_spotterOriginal);
    GetClientEyeAngles(g_spotter, g_spotterAngles);
    for (int ring=1; ring<=3; ring++)
    {
        for (int step=0; step<8; step++)
        {
            foot = Plant[g_map][g_site];
            foot[0] += float(ring*48) * Cosine(float(step)*0.785398163);
            foot[1] += float(ring*48) * Sine(float(step)*0.785398163);
            if (!SafeFloor(foot, eye)) continue;
            foot = eye;
            eye[2] += 64.0;
            float bombEye[3];
            bombEye = point;
            bombEye[2] += 8.0;
            if (!Shot(eye, bombEye, bomb)) continue;
            MakeVectorFromPoints(eye, bombEye, dir);
            GetVectorAngles(dir,g_spotterAim);
            g_spotterMove = GetEntityMoveType(g_spotter);
            SetEntityMoveType(g_spotter,MOVETYPE_NONE);
            TeleportEntity(g_spotter,foot,g_spotterAim,NULL_VECTOR);
            SetEntPropFloat(g_spotter,Prop_Send,"m_angEyeAngles[0]",g_spotterAim[0]);
            SetEntPropFloat(g_spotter,Prop_Send,"m_angEyeAngles[1]",g_spotterAim[1]);
            g_loose = EntIndexToEntRef(bomb);
            g_looseStart = GetGameTime();
            Event event = CreateEvent("bomb_dropped");
            event.Fire();
            return true;
        }
    }
    RemoveEntity(bomb);
    TeleportEntity(g_spotter,g_spotterOriginal,g_spotterAngles,NULL_VECTOR);
    return false;
}

public void OnGameFrame()
{
    if (g_loose == INVALID_ENT_REFERENCE || !Safe() || !IsClientInGame(g_spotter)) return;
    TeleportEntity(g_spotter,NULL_VECTOR,g_spotterAim,NULL_VECTOR);
    SetEntPropFloat(g_spotter,Prop_Send,"m_angEyeAngles[0]",g_spotterAim[0]);
    SetEntPropFloat(g_spotter,Prop_Send,"m_angEyeAngles[1]",g_spotterAim[1]);
}

public Action CheckLoose(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int guards;
    for (int i=1;i<=MaxClients;i++)
    {
        int route;
        float goal[3];
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i)==CS_TEAM_CT
            && BotCTTactics_GetOrder(i,goal,route) && route==1
            && GetVectorDistance(Plant[g_map][g_site],goal)<700.0) guards++;
    }
    if (guards < 4 && GetGameTime()-g_looseStart < 4.0) return Plugin_Continue;
    int bomb=EntRefToEntIndex(g_loose);
    if (guards >= 4)
    {
        ServerCommand("sm_ct_tactics_status");
        ServerExecute();
        InspectExposure("ct_loose", true, false);
    }
    else PrintToServer("EXPOSURE_SKIP map=%s site=%d phase=ct_loose guards=%d visible=%d",Maps[g_map],g_site,guards,
        bomb!=INVALID_ENT_REFERENCE && BotStuff_CanSeeLooseC4(g_spotter,bomb));
    if(bomb!=INVALID_ENT_REFERENCE) RemoveEntity(bomb);
    g_loose=INVALID_ENT_REFERENCE;
    SetEntityMoveType(g_spotter,g_spotterMove);
    TeleportEntity(g_spotter,g_spotterOriginal,g_spotterAngles,NULL_VECTOR);
    Event event=CreateEvent("bomb_pickup");
    event.Fire();
    CreateTimer(0.25,BeginPlantCover,_,TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action BeginPlantCover(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    g_planter = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && GetPlayerWeaponSlot(i, CS_SLOT_C4) > MaxClients) {g_planter=i; break;}
    if (!g_planter)
    {
        PrintToServer("ANGLE_SKIP map=%s site=%d no_carrier", Maps[g_map], g_site);
        NextSite();
        return Plugin_Stop;
    }
    float point[3];
    point = Plant[g_map][g_site];
    point[2] += 2.0;
    TeleportEntity(g_planter,point,NULL_VECTOR,NULL_VECTOR);
    Event event = CreateEvent("bomb_beginplant");
    event.SetInt("userid", GetClientUserId(g_planter));
    event.Fire();
    Measure("t_cover", false);
    if (g_exposure.BoolValue) InspectExposure("t_cover", false, true);
    CreateTimer(0.25, Planted, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Planted(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    int bomb = CreateEntityByName("planted_c4");
    if (bomb == -1) SetFailState("Test bomb allocation failed");
    DispatchSpawn(bomb);
    TeleportEntity(bomb,Plant[g_map][g_site],NULL_VECTOR,NULL_VECTOR);
    SetEntProp(bomb, Prop_Send, "m_bBombTicking", 1);
    SetEntPropFloat(bomb, Prop_Send, "m_flC4Blow", GetGameTime() + 40.0);
    g_bomb = EntIndexToEntRef(bomb);
    SetRandomSeed(g_seed.IntValue + 1200 + g_map * 10 + g_site);
    Event event = CreateEvent("bomb_planted");
    event.SetInt("userid", GetClientUserId(g_planter));
    event.Fire();
    CreateTimer(0.4, RetakeStage, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action RetakeStage(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    Measure("t_postplant", false);
    if (g_exposure.BoolValue) InspectExposure("t_postplant", false, true);
    Measure("ct_retake_stage", true, 2);
    for (int i = 1; i <= MaxClients; i++)
    {
        float goal[3]; int route;
        if (!BotCTTactics_GetOrder(i, goal, route) || route != 2) continue;
        Event event = CreateEvent("weapon_fire");
        event.SetInt("userid",GetClientUserId(i));
        event.SetString("weapon","usp_silencer");
        event.Fire();
        break;
    }
    CreateTimer(0.75, RetakeCommit, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action RetakeCommit(Handle timer)
{
    if (!Safe()) return Plugin_Stop;
    Measure("ct_retake_commit", true, 1);
    int bomb = EntRefToEntIndex(g_bomb);
    if (bomb != INVALID_ENT_REFERENCE) RemoveEntity(bomb);
    g_bomb = INVALID_ENT_REFERENCE;
    NextSite();
    return Plugin_Stop;
}

void NextSite()
{
    if (++g_site < 2)
    {
        g_armed = true;
        g_started = GetGameTime();
        ServerCommand("mp_restartgame 1");
        CreateTimer(5.0, CheckStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
        return;
    }
    NextMap();
}

void NextMap()
{
    g_armed = false;
    char last[32];
    g_endMap.GetString(last, sizeof(last));
    if (!StrEqual(Maps[g_map], last, false) && g_map + 1 < sizeof(Maps)) ServerCommand("changelevel %s", Maps[g_map + 1]);
    else PrintToServer("ANGLE_SURVEY_DONE");
}

public bool World(int entity, int mask, any unused) { return entity > MaxClients; }

ArrayList EntranceEyes(bool retake)
{
    ArrayList result = new ArrayList(4);
    StringMap seen = new StringMap();
    ArrayStack areas = new ArrayStack();
    char names[3][32];
    for (int i=0;i<3;i++)
    {
        g_samplesByLane[i] = 0;
        TacticalMap_GetWatchPlace(g_map,g_site,i,retake,names[i],sizeof(names[]));
    }
    float site[3];
    site = Plant[g_map][g_site];
    for (int x=NavMesh_WorldToGridX(site[0]-1800.0); x<=NavMesh_WorldToGridX(site[0]+1800.0); x++)
        for (int y=NavMesh_WorldToGridY(site[1]-1800.0); y<=NavMesh_WorldToGridY(site[1]+1800.0); y++)
            NavMesh_GetAreasOnGrid(areas,x,y);
    while (!areas.Empty)
    {
        int area=areas.Pop();
        char key[16], found[32];
        IntToString(area,key,sizeof(key));
        if (!seen.SetValue(key,1,false)) continue;
        NavMeshArea_GetPlaceCanonical(area,found,sizeof(found));
        for (int lane=0;lane<3;lane++)
        {
            if (!names[lane][0] || !StrEqual(names[lane],found,false)) continue;
            for (int mode=0;mode<2;mode++)
            {
                float p[3], feet[3], eye[4];
                if (mode == 0 && !NavMeshArea_GetCenter(area,p)) continue;
                if (mode == 1) NavMeshArea_GetClosestPointOnArea(area,site,p);
                if (GetVectorDistance(site,p)>2100.0 || !SafeFloor(p,feet)) continue;
                eye[0]=feet[0]; eye[1]=feet[1]; eye[2]=feet[2]+64.0; eye[3]=float(lane);
                result.PushArray(eye);
                g_samplesByLane[lane]++;
            }
        }
    }
    delete seen;
    delete areas;
    return result;
}

public bool BulletWorld(int entity,int mask,any ignored) { return entity>MaxClients && entity!=ignored; }

bool Shot(const float from[3], const float to[3], int ignored = -1)
{
    Handle ray=TR_TraceRayFilterEx(from,to,MASK_SHOT,RayType_EndPoint,BulletWorld,ignored);
    bool clear=!TR_StartSolid(ray) && !TR_DidHit(ray);
    delete ray;
    return clear;
}

int Exposed(ArrayList eyes, const float feet[3], bool duck, float witness[3][3])
{
    int mask;
    for (int j=0;j<eyes.Length;j++)
    {
        float item[4], from[3], to[3];
        eyes.GetArray(j,item,sizeof(item));
        int lane=RoundToNearest(item[3]);
        if (mask & (1<<lane)) continue;
        from[0]=item[0];from[1]=item[1];from[2]=item[2];
        float distance=GetVectorDistance(from,feet);
        if (distance<120.0 || distance>2200.0) continue;
        to=feet;to[2]+=duck?46.0:64.0;
        bool clear=Shot(from,to);
        if (!clear)
        {
            to[2]-=duck?12.0:14.0;
            clear=Shot(from,to);
            float yaw=ArcTangent2(from[1]-to[1],from[0]-to[0]);
            for (int side=-1;!clear && side<=1;side+=2)
            {
                to[0]=feet[0]+float(side)*12.0*Sine(yaw);
                to[1]=feet[1]-float(side)*12.0*Cosine(yaw);
                clear=Shot(from,to);
            }
        }
        if (clear) { mask|=1<<lane; witness[lane]=from; }
    }
    return mask;
}

int Bits(int mask)
{
    return (mask&1) + ((mask>>1)&1) + ((mask>>2)&1);
}

void InspectExposure(const char[] phase, bool ct, bool retake)
{
    ArrayList eyes=EntranceEyes(retake);
    int orders, valid, dual, duckDual;
    for (int i=1;i<=MaxClients;i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i)!=(ct?CS_TEAM_CT:CS_TEAM_T)) continue;
        int route;
        float goal[3],look[3],feet[3],witness[3][3];
        if (!(ct?BotCTTactics_GetOrder(i,goal,route):BotTTactics_GetOrder(i,goal,route))) continue;
        if (StrEqual(phase,"ct_open") && GetVectorDistance(goal,Plant[g_map][g_site])>
            GetVectorDistance(goal,Plant[g_map][1-g_site])) continue;
        if (StrEqual(phase,"ct_loose") && (route!=1 || GetVectorDistance(goal,Plant[g_map][g_site])>=700.0)) continue;
        // Only positions with an assigned tactical watch, not the planter/order to the bomb.
        if (!(ct?BotCTTactics_GetAim(i,look):BotTTactics_GetAim(i,look))) continue;
        orders++;
        if (!SafeFloor(goal,feet)) continue;
        valid++;
        int standing=Exposed(eyes,feet,false,witness);
        if (Bits(standing)>=2)
        {
            dual++;
            PrintToServer("EXPOSURE_WITNESS map=%s site=%d phase=%s lanes=%d hold=%.0f,%.0f,%.0f entry0=%.0f,%.0f,%.0f entry1=%.0f,%.0f,%.0f entry2=%.0f,%.0f,%.0f",
                Maps[g_map],g_site,phase,standing,feet[0],feet[1],feet[2],
                witness[0][0],witness[0][1],witness[0][2],witness[1][0],witness[1][1],witness[1][2],witness[2][0],witness[2][1],witness[2][2]);

        }
        if (Bits(Exposed(eyes,feet,true,witness))>=2) duckDual++;
    }
    delete eyes;
    PrintToServer("EXPOSURE_SUMMARY map=%s site=%d phase=%s orders=%d valid=%d dual=%d crouch_dual=%d eyes=%d,%d,%d",
        Maps[g_map],g_site,phase,orders,valid,dual,duckDual,g_samplesByLane[0],g_samplesByLane[1],g_samplesByLane[2]);
}


float WallDist(const float eye[3], const float look[3])
{
    Handle ray = TR_TraceRayFilterEx(eye, look, MASK_VISIBLE, RayType_EndPoint, World);
    float result = TR_StartSolid(ray) ? 0.0 : (TR_DidHit(ray) ? GetVectorDistance(eye,look)*TR_GetFraction(ray) : -1.0);
    delete ray;
    return result;
}

void Measure(const char[] phase, bool ct, int onlyRoute = -1)
{
    int orders, aims, close, samples, offsetClose, named, namedMask;
    bool retakeWatch = StrEqual(phase, "t_cover") || StrEqual(phase, "t_postplant");
    float holds[MAXPLAYERS + 1][3];
    int pairs, overlapping, support;
    float minGoal = 99999.0, minOffset = 99999.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != (ct ? CS_TEAM_CT : CS_TEAM_T)) continue;
        float goal[3], original[3], feet[3]; int route;
        bool got = ct ? BotCTTactics_GetOrder(i,goal,route) : BotTTactics_GetOrder(i,goal,route);
        if (!got || (onlyRoute != -1 && route != onlyRoute)) continue;
        orders++;
        if (retakeWatch)
        {
            for (int peer = 1; peer < orders; peer++)
            {
                float spacing = GetVectorDistance(holds[peer], goal);
                if (spacing < 115.0) overlapping++;
                if (spacing < 115.0 || spacing > 500.0 || FloatAbs(holds[peer][2] - goal[2]) > 70.0) continue;
                float eye[3], other[3];
                eye = goal; eye[2] += 64.0;
                other = holds[peer]; other[2] += 64.0;
                if (WallDist(eye, other) < 0.0) support++;
            }
            holds[orders] = goal;
            pairs += orders - 1;
        }
        GetClientAbsOrigin(i, original);
        if (SafeFloor(goal, feet))
        {
            samples++;
            int lane;
            if (MeasureAt(i, ct, feet, minGoal, aims, retakeWatch ? g_site : -1, lane)) close++;
            if (lane >= 0) { named++; namedMask |= 1 << lane; }
        }
        for (int step = 0; step < 8; step++)
        {
            float point[3];
            point = goal;
            point[0] += 64.0 * Cosine(float(step) * 0.785398163);
            point[1] += 64.0 * Sine(float(step) * 0.785398163);
            if (!SafeFloor(point, feet)) continue;
            samples++;
            int unused;
            if (MeasureAt(i, ct, feet, minOffset, aims, -1, unused)) offsetClose++;
        }
        TeleportEntity(i, original, NULL_VECTOR, NULL_VECTOR);
    }
    PrintToServer("ANGLE_SUMMARY map=%s site=%d phase=%s orders=%d aims=%d near=%d samples=%d offset_near=%d min=%.1f offset_min=%.1f",Maps[g_map],g_site,phase,orders,aims,close,samples,offsetClose,minGoal,minOffset);
    if (retakeWatch)
    {
        PrintToServer("ENTRANCE_RESULT map=%s site=%d phase=%s assigned=%d lanes=%d", Maps[g_map],g_site,phase,named,namedMask);
        PrintToServer("CROSSFIRE_GEOMETRY map=%s site=%d phase=%s pairs=%d overlaps=%d support=%d",
            Maps[g_map], g_site, phase, pairs, overlapping, support);
    }
}
bool SafeFloor(const float point[3], float feet[3])
{
    float mins[3] = {-16.0,-16.0,0.0}, maxs[3] = {16.0,16.0,72.0}, below[3];
    feet = point;
    feet[2] += 3.0;
    below = feet;
    below[2] -= 21.0;
    Handle floor = TR_TraceHullFilterEx(feet, below, mins, maxs, MASK_PLAYERSOLID, World);
    bool clear = TR_DidHit(floor) && !TR_StartSolid(floor);
    if (clear) TR_GetEndPosition(feet, floor);
    delete floor;
    return clear;
}

bool MeasureAt(int client, bool ct, const float feet[3], float &nearestWall, int &aims, int checkSite, int &lane)
{
    lane = -1;
    TeleportEntity(client, feet, NULL_VECTOR, NULL_VECTOR);
    float eye[3], look[3];
    if (!(ct ? BotCTTactics_GetAim(client, look, true) : BotTTactics_GetAim(client, look, true))) return false;
    GetClientEyePosition(client, eye);
    aims++;
    float distance = WallDist(eye, look);
    if (checkSite >= 0 && distance < 0.0)
    {
        float nav[3];
        nav = look;
        nav[2] -= 64.0;
        int area = NavMesh_GetNearestArea(nav, false, 30.0, false, true);
        if (area >= 0)
        {
            char actual[32], expected[32];
            NavMeshArea_GetPlaceCanonical(area, actual, sizeof(actual));
            for (int i = 0; i < 3; i++)
                if (TacticalMap_GetWatchPlace(g_map, checkSite, i, true, expected, sizeof(expected)) && StrEqual(actual, expected, false))
                { lane = i; break; }
        }
    }
    if (distance < 0.0 || distance >= 128.0) return false;
    if (distance < nearestWall) nearestWall = distance;
    return true;
}
