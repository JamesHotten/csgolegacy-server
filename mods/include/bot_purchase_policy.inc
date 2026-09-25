#if defined _bot_purchase_policy_included
    #endinput
#endif
#define _bot_purchase_policy_included

bool BotPurchase_IsPrimaryAlias(const char[] weapon)
{
    return StrEqual(weapon, "galilar") || StrEqual(weapon, "famas")
        || StrEqual(weapon, "ak47") || StrEqual(weapon, "m4a1")
        || StrEqual(weapon, "sg556") || StrEqual(weapon, "aug")
        || StrEqual(weapon, "ssg08") || StrEqual(weapon, "awp")
        || StrEqual(weapon, "g3sg1") || StrEqual(weapon, "scar20")
        || StrEqual(weapon, "nova") || StrEqual(weapon, "xm1014")
        || StrEqual(weapon, "sawedoff") || StrEqual(weapon, "mag7")
        || StrEqual(weapon, "m249") || StrEqual(weapon, "negev")
        || StrEqual(weapon, "mac10") || StrEqual(weapon, "mp9")
        || StrEqual(weapon, "mp7") || StrEqual(weapon, "ump45")
        || StrEqual(weapon, "p90") || StrEqual(weapon, "bizon");
}
void BotPurchase_EnsureArmorBeforePrimary(int client, const char[] weapon, bool fullSave)
{
    int team = GetClientTeam(client);
    if ((team != CS_TEAM_CT && team != CS_TEAM_T) || !BotPurchase_IsPrimaryAlias(weapon))
        return;

    // A genuine full save remains a save. A BOT carrying a saved primary is
    // allowed to repair its armor below in the normal armor-buy branch.
    if (fullSave && GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) == -1)
        return;

    int armor = GetEntProp(client, Prop_Data, "m_ArmorValue");
    bool helmet = view_as<bool>(GetEntProp(client, Prop_Send, "m_bHasHelmet"));
    if (armor > 0 && helmet)
        return;

    int account = GetEntProp(client, Prop_Send, "m_iAccount");
    if (!helmet && ((armor > 0 && account >= 350) || account >= 1000))
        FakeClientCommand(client, "buy vesthelm");
    else if (armor == 0 && account >= 650)
        FakeClientCommand(client, "buy vest");
}
