#if defined _lan_economy_csgo_included
	#endinput
#endif
#define _lan_economy_csgo_included

int LanEconomyCsgo_GetOfflineTeamAward(int team, int winner, CSRoundEndReason reason)
{
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
		return 0;

	if (team != winner)
	{
		int consecutiveLosses = GameRules_GetProp(team == CS_TEAM_CT ?
			"m_iNumConsecutiveCTLoses" : "m_iNumConsecutiveTerroristLoses");
		int lossTier = consecutiveLosses - 1;
		if (lossTier < 0)
			lossTier = 0;
		int maxTier = GetCashConVar("mp_consecutive_loss_max");
		if (maxTier >= 0 && lossTier > maxTier)
			lossTier = maxTier;

		int award = GetCashConVar("cash_team_loser_bonus") +
			(lossTier * GetCashConVar("cash_team_loser_bonus_consecutive_rounds"));
		if (team == CS_TEAM_T && reason == CSRoundEnd_BombDefused)
			award += GetCashConVar("cash_team_planted_bomb_but_defused");
		return award;
	}

	switch (reason)
	{
		case CSRoundEnd_TargetBombed:
			return GetCashConVar("cash_team_terrorist_win_bomb");
		case CSRoundEnd_BombDefused:
			return GetCashConVar("cash_team_win_by_defusing_bomb");
		case CSRoundEnd_TargetSaved:
			return GetCashConVar("cash_team_win_by_time_running_out_bomb");
		case CSRoundEnd_HostagesRescued:
			return GetCashConVar("cash_team_win_by_hostage_rescue");
		case CSRoundEnd_HostagesNotRescued:
			return GetCashConVar("cash_team_win_by_time_running_out_hostage");
		case CSRoundEnd_CTWin, CSRoundEnd_TerroristWin,
			CSRoundEnd_TerroristsSurrender, CSRoundEnd_CTSurrender:
		{
			if (view_as<bool>(GameRules_GetProp("m_bMapHasBombTarget")))
				return GetCashConVar("cash_team_elimination_bomb_map");
			return GetCashConVar(team == CS_TEAM_CT ?
				"cash_team_elimination_hostage_map_ct" : "cash_team_elimination_hostage_map_t");
		}
	}
	return 0;
}
