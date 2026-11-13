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
