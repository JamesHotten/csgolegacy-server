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
    if (armor > 0 && helmet)
        return 0;
    if (armor > 0)
        return 350;
    return 1000;
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
    int money = GetEntProp(client, Prop_Send, "m_iAccount");
    if (hasPrimary)
    {
        CSWeaponID weapon = CS_ItemDefIndexToID(GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex"));
        int weaponPrice = weapon == CSWeapon_NONE ? 0 : CS_GetWeaponPrice(client, weapon);
        if (weaponPrice >= BotEquipment_GetCheapestRiflePrice(client)
            && ((armor > 0 && helmet) || money >= BotEquipment_GetArmorReserve(client)))
            return BotEquip_Full;
        return BotEquip_Force;
    }

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

    if (players == 0)
        return BotEquip_Eco;
    if (full >= 4)
        return BotEquip_Full;
    if (forceOrBetter >= 3)
        return BotEquip_Force;
    return BotEquip_Eco;
}

#if defined BOT_EQUIPMENT_CORE
BotEquipmentTier g_BotEquipmentRoundPlan[4];
BotEquipmentTier g_BotEquipmentPreviousPlan[4];

void BotEquipment_BeginRound(bool resetRound, bool forceT, bool forceCT)
{
    for (int team = CS_TEAM_T; team <= CS_TEAM_CT; team++)
    {
        BotEquipmentTier plan = BotEquipment_ClassifyTeam(team);
        if (resetRound || (team == CS_TEAM_T ? forceT : forceCT))
            plan = BotEquip_Full;
        else if (plan == BotEquip_Force && g_BotEquipmentPreviousPlan[team] == BotEquip_Force)
            plan = BotEquip_Eco;
        g_BotEquipmentRoundPlan[team] = plan;
        g_BotEquipmentPreviousPlan[team] = plan;
    }
}

BotEquipmentTier BotEquipment_GetRoundPlan(int team)
{
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return BotEquip_Eco;
    return g_BotEquipmentRoundPlan[team];
}

bool BotEquipment_CanSelfBuyPrimary(int client)
{
    if (GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) != -1)
        return true;
    int money = GetEntProp(client, Prop_Send, "m_iAccount");
    return money >= BotEquipment_GetCheapestRiflePrice(client) + BotEquipment_GetArmorReserve(client);
}

bool BotEquipment_CanDonateWeapon(int client, int replacementPrice)
{
    if (BotEquipment_GetRoundPlan(GetClientTeam(client)) == BotEquip_Eco)
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
    g_BotEquipmentRoundPlan[CS_TEAM_T] = BotEquip_Full;
    g_BotEquipmentRoundPlan[CS_TEAM_CT] = BotEquip_Full;
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
            view_as<int>(BotEquipment_GetRoundPlan(team)));
    }
    return Plugin_Handled;
}
#endif
