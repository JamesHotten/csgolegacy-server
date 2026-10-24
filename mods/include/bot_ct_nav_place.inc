// Compiled into the installed NAV parser. This adds a separate read-only
// canonical interface; the legacy public interface/arrays remain unchanged.
public int Native_CTNavPlaceCanonical(Handle plugin, int numParams)
{
    int area = GetNativeCell(1), length = GetNativeCell(3);
    if (length < 1 || length > 1024) return ThrowNativeError(SP_ERROR_PARAM, "Invalid place buffer length");
    char[] place = new char[length];
    if (g_bNavMeshBuilt && area >= 0 && area < g_hNavMeshAreas.Length)
    {
        // NAV directory 0 = unnamed; 1..N address a zero-based string array.
        int index = g_hNavMeshAreas.Get(area, NavMeshArea_PlaceID) - 1;
        if (index >= 0 && index < g_hNavMeshPlaces.Length)
            g_hNavMeshPlaces.GetString(index, place, length);
    }
    SetNativeString(2, place, length);
    return 0;
}
