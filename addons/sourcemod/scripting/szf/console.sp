void Console_Init()
{
	AddCommandListener(Console_JoinTeam, "jointeam");
	AddCommandListener(Console_JoinTeam, "spectate");
	AddCommandListener(Console_JoinTeam, "autoteam");
	AddCommandListener(Console_JoinClass, "joinclass");
	AddCommandListener(Console_VoiceMenu, "voicemenu");
	AddCommandListener(Console_Build, "build");
}

public Action Console_JoinTeam(int iClient, const char[] sCommand, int iArgs)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	if (iArgs < 1 && StrEqual(sCommand, "jointeam", false))
		return Plugin_Handled;
	
	if (g_nRoundState < SZFRoundState_Grace)
		return Plugin_Continue;
	
	if (!IsClientInGame(iClient))
		return Plugin_Continue;
	
	char sArg[32], sSurTeam[16], sZomTeam[16], sZomVgui[16];
	
	//Get command/arg on which team player joined
	if (StrEqual(sCommand, "jointeam", false)) //This is done because "jointeam spectate" should take priority over "spectate"
		GetCmdArg(1, sArg, sizeof(sArg));
	else if (StrEqual(sCommand, "spectate", false))
		strcopy(sArg, sizeof(sArg), "spectate");	
	else if (StrEqual(sCommand, "autoteam", false))
		strcopy(sArg, sizeof(sArg), "autoteam");		
	
	//Check if client is trying to skip playing as zombie by joining spectator
	if (StrEqual(sArg, "spectate", false))
		CheckZombieBypass(iClient);
	
	//Assign team-specific strings
	if (TFTeam_Zombie == TFTeam_Blue)
	{
		sSurTeam = "red";
		sZomTeam = "blue";
		sZomVgui = "class_blue";
	}
	else
	{
		sSurTeam = "blue";
		sZomTeam = "red";
		sZomVgui = "class_red";
	}
	
	if (g_nRoundState >= SZFRoundState_Grace)
	{
		//If client tries to join the survivor team or a random team
		//during an active round, place them on the zombie
		//team and present them with the zombie class select screen.
		if (StrEqual(sArg, sSurTeam, false) || StrEqual(sArg, "auto", false))
		{
			TF2_ChangeClientTeam(iClient, TFTeam_Zombie);
			ShowVGUIPanel(iClient, sZomVgui);
			
			if (g_nRoundState == SZFRoundState_Grace)
				SetClientStartedAsZombie(iClient);	// Client pretty much will play a whole round as zombie
			
			return Plugin_Handled;
		}
		//If client tries to join the zombie team or spectator
		//during an active round, let them do so.
		else if (StrEqual(sArg, sZomTeam, false))
		{
			if (g_nRoundState == SZFRoundState_Grace)
				SetClientStartedAsZombie(iClient);
			
			return Plugin_Continue;
		}
		else if (StrEqual(sArg, "spectate", false))
			return Plugin_Continue;
		//Prevent joining any other team.
		else
			return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Console_JoinClass(int iClient, const char[] sCommand, int iArgs)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	if (iArgs < 1)
		return Plugin_Handled;
	
	char sArg[32], sMsg[256];
	GetCmdArg(1, sArg, sizeof(sArg));
	
	if (IsZombie(iClient))
	{
		if (g_nInfected[iClient] != Infected_None)
			return Plugin_Handled;
		
		//Check if the player selected a valid zombie class
		if (IsValidZombieClass(TF2_GetClass(sArg)))
		{
			if (!IsPlayerAlive(iClient))
				Classes_SetClient(iClient, _, TF2_GetClass(sArg));
			
			return Plugin_Continue;
		}
		
		//It's invalid, then display which classes the player can choose
		for (int i = 1; i < view_as<int>(TFClass_Engineer) + 1; i++)
		{
			if (IsValidZombieClass(view_as<TFClassType>(i)))
			{
				//Place a comma before if it's not the first one
				if (strlen(sMsg))
					Format(sMsg, sizeof(sMsg), "%s,", sMsg);
				
				TF2_GetClassName(sArg, sizeof(sArg), i);
				Format(sMsg, sizeof(sMsg), "%s %s", sMsg, sArg);
			}
		}
		
		CPrintToChat(iClient, "%t", "JoinClass_ValidZombies", "{red}", sMsg);
		return Plugin_Continue;
	}
	else if (IsSurvivor(iClient))
	{
		//Prevent survivors from switching classes during the round.
		if (g_nRoundState == SZFRoundState_Active && IsPlayerAlive(iClient))
		{
			CPrintToChat(iClient, "%t", "JoinClass_SurvivorsCantChange", "{red}");
			return Plugin_Handled;
		}
		
		//Check if the player selected a valid survivor class
		if (IsValidSurvivorClass(TF2_GetClass(sArg)))
		{
			if (!IsPlayerAlive(iClient))
				Classes_SetClient(iClient, _, TF2_GetClass(sArg));
			
			return Plugin_Continue;
		}
		
		//It's invalid, then display which classes the player can choose
		for (int i = 1; i < view_as<int>(TFClass_Engineer) + 1; i++)
		{
			if (IsValidSurvivorClass(view_as<TFClassType>(i)))
			{
				//Place a comma before if it's not the first one
				if (strlen(sMsg))
					Format(sMsg, sizeof(sMsg), "%s,", sMsg);
				
				TF2_GetClassName(sArg, sizeof(sArg), i);
				Format(sMsg, sizeof(sMsg), "%s %s", sMsg, sArg);
			}
		}
		
		CPrintToChat(iClient, "%t", "JoinClass_ValidSurvivors", "{red}", sMsg);
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

public Action Console_VoiceMenu(int iClient, const char[] sCommand, int iArgs)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	if (iArgs < 2)
		return Plugin_Handled;
	
	char sArg1[32];
	char sArg2[32];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));
	
	//Capture call for medic commands (represented by "voicemenu 0 0").
	//Activate zombie Rage ability (150% health), if possible. Rage
	//can't be activated below full health or if it's already active.
	//Rage recharges after 30 seconds.
	if (sArg1[0] == '0' && sArg2[0] == '0')
	{
		//If an item was succesfully grabbed
		if (AttemptGrabItem(iClient))
			return Plugin_Handled;
		
		if (IsSurvivor(iClient) && AttemptCarryItem(iClient))
			return Plugin_Handled;
		
		if (IsZombie(iClient) && !TF2_IsPlayerInCondition(iClient, TFCond_Taunting))
		{
			if (g_iRageTimer[iClient] == 0)
			{
				Sound_PlayInfectedVo(iClient, g_nInfected[iClient], SoundVo_Rage);
				g_iRageTimer[iClient] = g_ClientClasses[iClient].iRageCooldown;
				if (g_iRageTimer[iClient])
					g_iRageTimer[iClient]++;	// +1 as it'd take less than a second till main timer runs, and for "Rage is ready in" display
				
				if (g_ClientClasses[iClient].callback_rage != INVALID_FUNCTION)
				{
					Call_StartFunction(null, g_ClientClasses[iClient].callback_rage);
					Call_PushCell(iClient);
					Call_Finish();
				}
			}
			else
			{
				ClientCommand(iClient, "voicemenu 2 5");
				PrintHintText(iClient, "%t", "Infected_CantUseRage");
			}
			
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action Console_Build(int iClient, const char[] sCommand, int iArgs)
{
	if (!g_bEnabled || !iClient)
		return Plugin_Continue;
	
	//Get arguments
	char sObjectType[32];
	GetCmdArg(1, sObjectType, sizeof(sObjectType));
	TFObjectType nObjectType = view_as<TFObjectType>(StringToInt(sObjectType));
	
	//if not sentry or dispenser, then block building
	if (nObjectType != TFObject_Dispenser && nObjectType != TFObject_Sentry)
		return Plugin_Handled;
	
	// Dispenser have m_bCarried set to 1 to disable healing, but also allowed to build multiples, which we want to prevent that
	if (TF2_GetBuilding(iClient, nObjectType) != INVALID_ENT_REFERENCE)
		return Plugin_Handled;
	
	return Plugin_Continue;
}