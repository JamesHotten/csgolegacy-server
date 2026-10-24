#if defined _bot_ct_watch_sectors_included
    #endinput
#endif
#define _bot_ct_watch_sectors_included

// Stable assignment within ONE site, not the global A+B target list.
// A lone anchor watches center; a pair splits left/right, then center/flanks.
stock int CTWatch_GetSector(int localSlot, int defenderCount)
{
    if (defenderCount <= 1) return 0;
    switch (localSlot % 5)
    {
        case 0: return 1;
        case 1: return 2;
        case 2: return 0;
        case 3: return 3;
        case 4: return 4;
    }
    return 0;
}
