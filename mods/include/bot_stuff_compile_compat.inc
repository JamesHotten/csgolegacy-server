#if defined _bot_stuff_compile_compat_included
    #endinput
#endif
#define _bot_stuff_compile_compat_included

// Only the eItems API used by BetterBots 1.4.4 is declared here. The runtime
// implementation remains the existing eitems.smx plugin.
native int eItems_GetWeaponSlotByDefIndex(int defIndex);
native int eItems_GetWeaponSlotByWeapon(int weapon);
native int eItems_FindWeaponByDefIndex(int client, int defIndex);

// The BetterBots source uses these four SMLib helpers. Keeping their original
// implementations here makes the source reproducibly buildable without
// replacing any runtime extension or plugin.
#define BOT_STUFF_SIZE_OF_INT 2147483647

stock void Array_Fill(any[] array, int size, any value, int start = 0)
{
    if (start < 0)
        start = 0;

    for (int i = start; i < size; i++)
        array[i] = value;
}

stock void Array_Copy(const any[] array, any[] destination, int size)
{
    for (int i = 0; i < size; i++)
        destination[i] = array[i];
}

stock int Math_GetRandomInt(int min, int max)
{
    int random = GetURandomInt();
    if (random == 0)
        random++;
    return RoundToCeil(float(random) / (float(BOT_STUFF_SIZE_OF_INT) / float(max - min + 1))) + min - 1;
}

stock float Math_GetRandomFloat(float min, float max)
{
    return (GetURandomFloat() * (max - min)) + min;
}
