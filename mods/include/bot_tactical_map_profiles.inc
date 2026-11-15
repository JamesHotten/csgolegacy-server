#if defined _bot_tactical_map_profiles_included
    #endinput
#endif
#define _bot_tactical_map_profiles_included

// Exact NAV names from the local CS:GO Legacy maps (Cache has embedded NAV).
// Per site: CT watch priority (three names), then T main/split staging.
// Blank entries intentionally do not invent an independent attack lane.
static const char g_TacticalMapNames[][] = {
    "de_inferno", "de_train", "de_mirage", "de_nuke", "de_dust2",
    "de_overpass", "de_vertigo", "de_cache", "de_ancient", "de_anubis"
};
// Ground references verified with the actual Legacy bomb triggers. The
// bombsite manager's center and a NAV place name alone do not imply a valid
// floor position (especially on multi-level or irregular sites).
static const float g_TacticalPlantGround[10][2][3] = {
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

stock void TacticalMap_PlantGround(int map, int site, float position[3])
{
    for (int axis = 0; axis < 3; axis++) position[axis] = g_TacticalPlantGround[map][site][axis];
}
static const char g_TacticalMapPlaces[10][2][5][32] = {
    {{"TopofMid", "Balcony", "Arch", "TopofMid", "Apartments"},
     {"Banana", "Ruins", "", "Banana", ""}},                                      // Inferno
    {{"TMain", "Ivy", "PopDog", "TMain", "Ivy"},
     {"BPlatform", "TStairs", "Connector", "LockerRoom", "BPlatform"}},            // Train
    {{"TRamp", "PalaceInterior", "Connector", "TRamp", "PalaceInterior"},
     {"Apartments", "Catwalk", "", "Apartments", "Catwalk"}},                     // Mirage
    {{"Hut", "Squeaky", "Mini", "Lobby", "Outside"},
     {"Ramp", "Decon", "Secret", "Ramp", "Secret"}},                              // Nuke
    {{"LongA", "Short", "", "LongA", "Short"},
     {"UpperTunnel", "BDoors", "", "UpperTunnel", ""}},                           // Dust II
    {{"UpperPark", "Restroom", "Connector", "Restroom", "UnderA"},
     {"Pipe", "Water", "Connector", "Pipe", "Water"}},                           // Overpass
    {{"ARamp", "Side", "Elevator", "ARamp", "Side"},
     {"BPlatform", "TopofMid", "BackofB", "BPlatform", "TopofMid"}},                // Vertigo
    {{"LongA", "Squeaky", "Catwalk", "LongA", "Squeaky"},
     {"LongHall", "Ducts", "CTSpawn", "LongHall", "Ducts"}},                      // Cache
    {{"MainHall", "TopofMid", "SideEntrance", "MainHall", "TopofMid"},
     {"Ramp", "SideHall", "Ruins", "Ramp", "SideHall"}},                          // Ancient
    {{"Main", "Connector", "Heaven", "Main", "Connector"},
     {"Bricks", "MidDoors", "PalaceInterior", "Bricks", "MidDoors"}}               // Anubis
};

// The opposite approaches: used by T after starting to plant.
static const char g_TacticalRetakePlaces[10][2][3][32] = {
    {{"Library", "Arch", "Pit"}, {"CTSpawn", "Ruins", "Banana"}},
    {{"CTSpawn", "Connector", "Ivy"}, {"Connector", "BackofB", "BPlatform"}},
    {{"TicketBooth", "Jungle", "Connector"}, {"Shop", "Catwalk", "Truck"}},
    {{"Mini", "Heaven", "Hut"}, {"Ramp", "Decon", "Secret"}},
    {{"CTSpawn", "Short", "LongA"}, {"BDoors", "Hole", "UpperTunnel"}},
    {{"BackofA", "UnderA", "Stairs"}, {"Construction", "Bridge", "Water"}},
    {{"BackofA", "Elevator", "Side"}, {"BackofB", "CTSpawn", "TopofMid"}},
    {{"CTSpawn", "Catwalk", "LongA"}, {"CTSpawn", "Ducts", "LongHall"}},
    {{"CTSpawn", "SideEntrance", "TopofMid"}, {"CTSpawn", "Alley", "SideHall"}},
    {{"Heaven", "Fountain", "Connector"}, {"BackofB", "CTSpawn", "MidDoors"}}
};

stock bool TacticalMap_GetWatchPlace(int profile, int site, int entry, bool retake, char[] place, int length)
{
    if (!retake) return TacticalMap_GetPlace(profile, site, entry, place, length);
    place[0] = '\0';
    if (profile < 0 || profile >= sizeof(g_TacticalMapNames) || site < 0 || site > 1
        || entry < 0 || entry >= 3) return false;
    strcopy(place, length, g_TacticalRetakePlaces[profile][site][entry]);
    return place[0] != '\0';
}

stock int TacticalMap_Find(const char[] map)
{
    for (int index = 0; index < sizeof(g_TacticalMapNames); index++)
        if (StrEqual(map, g_TacticalMapNames[index], false)) return index;
    return -1;
}

stock bool TacticalMap_GetPlace(int profile, int site, int entry, char[] place, int length)
{
    place[0] = '\0';
    if (profile < 0 || profile >= sizeof(g_TacticalMapNames) || site < 0 || site > 1
        || entry < 0 || entry >= 5) return false;
    strcopy(place, length, g_TacticalMapPlaces[profile][site][entry]);
    return place[0] != '\0';
}

stock bool TacticalMap_GetName(int profile, char[] map, int length)
{
    if (profile < 0 || profile >= sizeof(g_TacticalMapNames)) return false;
    strcopy(map, length, g_TacticalMapNames[profile]);
    return true;
}
