#if defined _bot_equipment_policy_included
    #endinput
#endif
#define _bot_equipment_policy_included

enum BotEquipmentTier
{
    BotEquip_Eco = 0,
    BotEquip_Force,
    BotEquip_Full
};

int BotEquipment_GetArmorReserve(int client)
{
    int armor = GetEntProp(client, Prop_Data, "m_ArmorValue");
    bool helmet = view_as<bool>(GetEntProp(client, Prop_Send, "m_bHasHelmet"));
    if (armor >= 50 && helmet)
        return 0;
    if (armor >= 50)
        return 350;
    return helmet ? 650 : 1000;
}

int BotEquipment_GetCheapestRiflePrice(int client)
{
    return CS_GetWeaponPrice(client, GetClientTeam(client) == CS_TEAM_T ? CSWeapon_GALILAR : CSWeapon_FAMAS);
}

BotEquipmentTier BotEquipment_ClassifyPlayer(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return BotEquip_Eco;

    int primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
    bool hasPrimary = primary != -1;
    int armor = GetEntProp(client, Prop_Data, "m_ArmorValue");
    bool helmet = view_as<bool>(GetEntProp(client, Prop_Send, "m_bHasHelmet"));
    if (hasPrimary)
    {
        CSWeaponID weapon = CS_ItemDefIndexToID(GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex"));
        int weaponPrice = weapon == CSWeapon_NONE ? 0 : CS_GetWeaponPrice(client, weapon);
        if (weaponPrice >= BotEquipment_GetCheapestRiflePrice(client) && armor >= 50 && helmet)
            return BotEquip_Full;
        return BotEquip_Force;
    }

    int money = GetEntProp(client, Prop_Send, "m_iAccount");
    int rifleAndArmor = BotEquipment_GetCheapestRiflePrice(client) + BotEquipment_GetArmorReserve(client);
    if (money >= rifleAndArmor)
        return BotEquip_Full;
    if (money >= 1850)
        return BotEquip_Force;
    return BotEquip_Eco;
}

BotEquipmentTier BotEquipment_ClassifyTeam(int team)
{
    int players;
    int full;
    int forceOrBetter;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != team)
            continue;
        players++;
        BotEquipmentTier tier = BotEquipment_ClassifyPlayer(client);
        if (tier == BotEquip_Full)
            full++;
        if (tier >= BotEquip_Force)
            forceOrBetter++;
    }

    if (players == 0 || full * 2 >= players)
        return BotEquip_Full;
    if (forceOrBetter * 2 >= players)
        return BotEquip_Force;
    return BotEquip_Eco;
}

#if defined BOT_EQUIPMENT_CORE
bool BotEquipment_CanSelfBuyPrimary(int client)
{
    if (GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) != -1)
        return true;
    int money = GetEntProp(client, Prop_Send, "m_iAccount");
    return money >= BotEquipment_GetCheapestRiflePrice(client) + BotEquipment_GetArmorReserve(client);
}

bool BotEquipment_CanDonateWeapon(int client, int replacementPrice)
{
    if (BotEquipment_ClassifyTeam(GetClientTeam(client)) == BotEquip_Eco)
        return false;

    int reserve = BotEquipment_GetArmorReserve(client);
    if (GetClientTeam(client) == CS_TEAM_CT
        && !view_as<bool>(GetEntProp(client, Prop_Send, "m_bHasDefuser")))
        reserve += 400;
    return GetEntProp(client, Prop_Send, "m_iAccount") >= replacementPrice + reserve;
}

int BotEquipment_GetRecipientPriority(int client)
{
    int priority = 16000 - GetEntProp(client, Prop_Send, "m_iAccount");
    if (!IsFakeClient(client))
        priority += 20000;
    if (GetEntProp(client, Prop_Data, "m_ArmorValue") > 0)
        priority += 1000;
    return priority;
}

void BotEquipment_OnPluginStart()
{
    RegConsoleCmd("sm_bot_equipment_status", BotEquipment_CommandStatus);
}

public Action BotEquipment_CommandStatus(int client, int args)
{
    for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
    {
        int eco, force, full, unarmed, eligibleDonors;
        for (int player = 1; player <= MaxClients; player++)
        {
            if (!IsClientInGame(player) || !IsPlayerAlive(player) || GetClientTeam(player) != team)
                continue;
            BotEquipmentTier tier = BotEquipment_ClassifyPlayer(player);
            if (tier == BotEquip_Full) full++;
            else if (tier == BotEquip_Force) force++;
            else eco++;
            int primary = GetPlayerWeaponSlot(player, CS_SLOT_PRIMARY);
            if (primary == -1)
                unarmed++;
            else if (IsFakeClient(player))
            {
                CSWeaponID weapon = CS_ItemDefIndexToID(GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex"));
                if (weapon != CSWeapon_NONE && BotEquipment_CanDonateWeapon(player, CS_GetWeaponPrice(player, weapon)))
                    eligibleDonors++;
            }
        }
        ReplyToCommand(client, "[BotEquipment] %s full=%d force=%d eco=%d unarmed=%d donors=%d team_state=%d",
            team == CS_TEAM_T ? "T" : "CT", full, force, eco, unarmed, eligibleDonors,
            view_as<int>(BotEquipment_ClassifyTeam(team)));
    }
    return Plugin_Handled;
}
#endif
