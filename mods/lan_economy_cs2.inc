#if defined _lan_economy_cs2_included
	#endinput
#endif
#define _lan_economy_cs2_included

int LanEconomyCs2_GetCtEliminationBonus(int team, int terroristEliminations, int perEliminationBonus)
{
	if (team != CS_TEAM_CT || terroristEliminations <= 0 || perEliminationBonus <= 0)
		return 0;
	return terroristEliminations * perEliminationBonus;
}

int LanEconomyCs2_GetOfflineTeamAward(int team, int winner, CSRoundEndReason reason, int ctRoundBonus)
{
	return LanEconomyCsgo_GetOfflineTeamAward(team, winner, reason) +
		(team == CS_TEAM_CT && ctRoundBonus > 0 ? ctRoundBonus : 0);
}
