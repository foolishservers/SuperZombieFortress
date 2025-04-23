void Event_Init()
{
	HookEvent("teamplay_setup_finished", Event_SetupEnd);
	HookEvent("teamplay_round_win", Event_RoundEnd);
	HookEvent("post_inventory_application", Event_PlayerInventoryUpdate);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	HookEvent("player_builtobject", Event_PlayerBuiltObject);
	HookEvent("player_healed", Event_PlayerHealed);
	HookEvent("object_destroyed", Event_ObjectDestoryed, EventHookMode_Pre);
	HookEvent("teamplay_point_captured", Event_CPCapture);
	HookEvent("teamplay_point_startcapture", Event_CPCaptureStart);
	HookEvent("teamplay_broadcast_audio", Event_Broadcast, EventHookMode_Pre);
	HookEvent("player_death", Event_HideNotice, EventHookMode_Pre);
	HookEvent("fish_notice", Event_HideNotice, EventHookMode_Pre);
	HookEvent("fish_notice__arm", Event_HideNotice, EventHookMode_Pre);
	HookEventEx("slap_notice", Event_HideNotice, EventHookMode_Pre);
}

public Action Event_SetupEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	EndGracePeriod();
	
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	//Prepare for a completely new round
	TFTeam nTeam = view_as<TFTeam>(event.GetInt("team"));
	g_bNewFullRound = event.GetBool("full_round");
	g_nRoundState = SZFRoundState_End;
	
	if (nTeam == TFTeam_Zombie)
		Sound_PlayMusicToAll("lose");
	else if (nTeam == TFTeam_Survivor)
		Sound_PlayMusicToAll("win");
	
	SetGlow();
	UpdateZombieDamageScale();
	g_bTankRefreshed = false;
	
	return Plugin_Continue;
}

public Action Event_PlayerInventoryUpdate(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if (TF2_GetClientTeam(iClient) <= TFTeam_Spectator)
		return Plugin_Continue;
	
	Stun_EndPlayer(iClient);
	
	//Reset overlay
	ClientCommand(iClient, "r_screenoverlay\"\"");
	
	if (g_iMaxHealth[iClient] != -1)
	{
		//Make sure max health hook is reset properly
		g_iMaxHealth[iClient] = -1;
		TF2_RespawnPlayer2(iClient);
		return Plugin_Continue;
	}
	
	g_iKillsThisLife[iClient] = 0;
	g_iDamageTakenLife[iClient] = 0;
	g_iDamageDealtLife[iClient] = 0;
	
	ResetClientState(iClient);
	DropCarryingItem(iClient, false);
	
	SetEntityRenderColor(iClient, 255, 255, 255, 255);
	SetEntityRenderMode(iClient, RENDER_NORMAL);
	SetEntProp(iClient, Prop_Send, "m_nModelIndexOverrides", 0, _, VISION_MODE_ROME);
	
	TFClassType nClass = TF2_GetPlayerClass(iClient);
	Infected nInfected = g_nInfected[iClient];
	
	//Figure out what special infected client is
	if (g_nRoundState == SZFRoundState_Active)
	{
		//If client got a force set as specific special infected, set as that infected
		if (g_nNextInfected[iClient] != Infected_None)
		{
			nInfected  = g_nNextInfected[iClient];
		}
		else if (g_bSpawnAsSpecialInfected[iClient])
		{
			g_bSpawnAsSpecialInfected[iClient] = false;
			
			//Create list of all special infected to randomize, apart from tank and non-special infected
			int iLength = view_as<int>(Infected_Count) - 2;
			Infected[] nSpecialInfected = new Infected[iLength];
			for (int i = 0; i < iLength; i++)
				nSpecialInfected[i] = view_as<Infected>(i + 2);
			
			//Randomize, sort list of special infected
			SortIntegers(view_as<int>(nSpecialInfected), iLength, Sort_Random);
			
			//Go through each special infected in the list and find the first one thats not in cooldown
			int i = 0;
			while (nInfected  == Infected_None && i < iLength)
			{
				if (IsValidInfected(nSpecialInfected[i]) && g_flInfectedCooldown[nSpecialInfected[i]] <= GetGameTime() - 12.0 && g_iInfectedCooldown[nSpecialInfected[i]] != iClient)
				{
					//We found it, set as that special infected
					nInfected  = nSpecialInfected[i];
				}
				
				i++;
			}
		}
		
		g_nNextInfected[iClient] = Infected_None;
	}
	
	Classes_SetClient(iClient, nInfected);
	
	//Force respawn if client is playing as disallowed class
	if (IsSurvivor(iClient))
	{
		if (g_nRoundState == SZFRoundState_Active)
		{
			SpawnClient(iClient, TFTeam_Zombie);
			return Plugin_Continue;
		}
		
		if (!IsValidSurvivorClass(nClass))
		{
			TF2_RespawnPlayer2(iClient);
			return Plugin_Continue;
		}
		
		HandleSurvivorLoadout(iClient);
		if (GetCookie(iClient, g_cFirstTimeSurvivor) < 1)
			InitiateSurvivorTutorial(iClient);
	}
	else if (IsZombie(iClient))
	{
		if (g_nInfected[iClient] != Infected_None && nClass != GetInfectedClass(g_nInfected[iClient]))
		{
			TF2_SetPlayerClass(iClient, GetInfectedClass(g_nInfected[iClient]));
			TF2_RespawnPlayer(iClient);
			return Plugin_Continue;
		}
		
		if (!IsValidZombieClass(nClass))
		{
			TF2_RespawnPlayer2(iClient);
			return Plugin_Continue;
		}
		
		if (g_nRoundState == SZFRoundState_Active)
			if (g_nInfected[iClient] != Infected_Tank && !PerformFastRespawn(iClient))
				TF2_AddCondition(iClient, TFCond_Ubercharged, 2.0);
		
		HandleZombieLoadout(iClient);
		if (GetCookie(iClient, g_cFirstTimeZombie) < 1)
			InitiateZombieTutorial(iClient);
	}
	
	if (g_nRoundState == SZFRoundState_Active)
	{
		if (g_ClientClasses[iClient].callback_spawn != INVALID_FUNCTION)
		{
			Call_StartFunction(null, g_ClientClasses[iClient].callback_spawn);
			Call_PushCell(iClient);
			Call_Finish();
		}
		SetEntityRenderMode(iClient, RENDER_TRANSCOLOR);
		SetEntityRenderColor(iClient, g_ClientClasses[iClient].iColor[0], g_ClientClasses[iClient].iColor[1], g_ClientClasses[iClient].iColor[2], g_ClientClasses[iClient].iColor[3]);
		
		if (g_ClientClasses[iClient].sMessage[0])
			CPrintToChat(iClient, "%t", g_ClientClasses[iClient].sMessage);
		
		if (g_nInfected[iClient] != Infected_None && g_nInfected[iClient] != Infected_Tank && g_iInfectedCooldown[g_nInfected[iClient]] != iClient)
		{
			//Set new cooldown
			g_flInfectedCooldown[g_nInfected[iClient]] = GetGameTime();	//time for cooldown
			g_iInfectedCooldown[g_nInfected[iClient]] = iClient;			//client to prevent abuse to cycle through any infected
		}
		
		if (g_bShouldBacteriaPlay[iClient])
		{
			if (g_ClientClasses[iClient].sSoundSpawn[0])
			{
				EmitSoundToClient(iClient, g_ClientClasses[iClient].sSoundSpawn);
				
				for (int i = 1; i <= MaxClients; i++)
					if (IsValidLivingSurvivor(i))
						EmitSoundToClient(i, g_ClientClasses[iClient].sSoundSpawn);
			}
			
			g_bShouldBacteriaPlay[iClient] = false;
		}
	}
	
	SetGlow();
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	int iKillers[2];
	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	iKillers[0] = GetClientOfUserId(event.GetInt("attacker"));
	iKillers[1] = GetClientOfUserId(event.GetInt("assister"));
	int iInflictor = event.GetInt("inflictor_entindex");
	bool bDeadRinger = event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER != 0;
	
	ClientCommand(iVictim, "r_screenoverlay\"\"");
	
	DropCarryingItem(iVictim);
	
	//Handle bonuses
	if (!bDeadRinger && IsValidZombie(iKillers[0]) && iKillers[0] != iVictim)
	{
		g_iKillsThisLife[iKillers[0]]++;
		
		//50%
		if (g_nNextInfected[iKillers[0]] == Infected_None && !GetRandomInt(0, 1) && g_nRoundState == SZFRoundState_Active)
			g_bSpawnAsSpecialInfected[iKillers[0]] = true;
		
		if (g_iKillsThisLife[iKillers[0]] == 3 && g_nInfected[iKillers[0]] != Infected_Tank)
			TF2_AddCondition(iKillers[0], TFCond_DefenseBuffed, TFCondDuration_Infinite);
	}
	
	if (!bDeadRinger && IsValidZombie(iKillers[1]) && iKillers[1] != iVictim)
	{
		//20%
		if (g_nNextInfected[iVictim] == Infected_None && !GetRandomInt(0, 4) && g_nRoundState == SZFRoundState_Active)
			g_bSpawnAsSpecialInfected[iKillers[1]] = true;
	}
	
	if (iVictim != iKillers[0] && iKillers[0] == iInflictor)
	{
		int iPos;
		WeaponClasses weapon;
		while (g_ClientClasses[iKillers[0]].GetWeapon(iPos, weapon))
		{
			if (weapon.iIndex == event.GetInt("weapon_def_index"))
			{
				if (weapon.sLogName[0])
					event.SetString("weapon_logclassname", weapon.sLogName);
				
				if (weapon.sIconName[0])
					event.SetString("weapon", weapon.sIconName);
			}
		}
	}
	
	// Spitter bleed
	if (IsValidZombie(iKillers[0]) && g_nInfected[iKillers[0]] == Infected_Spitter && event.GetInt("customkill") == TF_CUSTOM_BLEEDING)
		event.SetString("weapon", "infection_acid_puddle");
	
	if (iInflictor != INVALID_ENT_REFERENCE && IsClassname(iInflictor, "prop_physics"))
	{
		// Could be a tank thorwing debris to set kill icon
		char sModel[256];
		GetEntityModel(iInflictor, sModel, sizeof(sModel));
		
		Debris debris;
		if (Config_GetDebrisFromModel(sModel, debris))
			event.SetString("weapon", debris.sIconName);
	}
	
	g_iMaxHealth[iVictim] = -1;
	g_bShouldBacteriaPlay[iVictim] = true;
	
	//Handle zombie death logic, all round states.
	if (IsValidZombie(iVictim))
	{
		if (g_ClientClasses[iVictim].callback_death != INVALID_FUNCTION)
		{
			Call_StartFunction(null, g_ClientClasses[iVictim].callback_death);
			Call_PushCell(iVictim);
			Call_PushCell(iKillers[0]);
			Call_PushCell(iKillers[1]);
			Call_Finish();
		}
		
		if (g_nInfected[iVictim] == Infected_Tank)	//Tank plays death sound global
			Sound_PlayInfectedVoToAll(Infected_Tank, SoundVo_Death);
		else
			Sound_PlayInfectedVo(iVictim, g_nInfected[iVictim], SoundVo_Death);
		
		//10%
		if (IsValidSurvivor(iKillers[0]) && !GetRandomInt(0, 9) && g_nRoundState == SZFRoundState_Active)
			g_bSpawnAsSpecialInfected[iVictim] = true;
		
		//Set special infected state
		g_nInfected[iVictim] = Infected_None;
		
		//Destroy buildings from zombies
		int iBuilding = -1;
		while ((iBuilding = FindEntityByClassname(iBuilding, "obj_*")) != -1)
		{
			if (GetEntPropEnt(iBuilding, Prop_Send, "m_hBuilder") == iVictim)
			{
				SetVariantInt(GetEntProp(iBuilding, Prop_Send, "m_iHealth"));
				AcceptEntityInput(iBuilding, "RemoveHealth");
			}
		}
		
		//Zombie rage: instant respawn
		if (g_bZombieRage && g_nRoundState == SZFRoundState_Active)
		{
			float flTimer = 0.1;
			
			//Check if respawn stress reaches time limit, if so add cooldown/timer so we dont instant respawn too much zombies at once
			if (g_flRageRespawnStress > GetGameTime())
				flTimer += g_flRageRespawnStress - GetGameTime();
			
			g_flRageRespawnStress += g_cvFrenzyRespawnStress.FloatValue / GetActivePlayerCount();	// Add stress time for every respawns
			CreateTimer(flTimer, Timer_RespawnPlayer, iVictim);
		}
		
		//Check for spec bypass from AFK manager
		RequestFrame(Frame_CheckZombieBypass, GetClientSerial(iVictim));
	}
	
	//Instant respawn outside of the actual gameplay
	if (g_nRoundState != SZFRoundState_Active && g_nRoundState != SZFRoundState_End)
	{
		CreateTimer(0.1, Timer_RespawnPlayer, iVictim);
		return Plugin_Continue;
	}
	
	//Handle survivor death logic, active round only.
	if (IsValidSurvivor(iVictim) && !bDeadRinger)
	{
		//Black and white effect for death, if not a suicide to join spec team
		if (event.GetInt("customkill") != TF_CUSTOM_SUICIDE)
			ClientCommand(iVictim, "r_screenoverlay\"debug/yuv\"");
		
		g_aSurvivorDeathTimes.Push(GetGameTime());
		g_iZombiesKilledSpree = 0;
		
		//Set zombie time to iVictim as he started playing zombie
		g_flTimeStartAsZombie[iVictim] = GetGameTime();
		
		//Transfer player to zombie team.
		CreateTimer(6.0, Timer_Zombify, iVictim, TIMER_FLAG_NO_MAPCHANGE);
		//Check if he's the last
		CheckLastSurvivor(iVictim);
		
		Sound_EndSpecificMusic(iVictim, "rabies");
		Sound_PlayMusicToClient(iVictim, "dead");
	}
	
	//Handle zombie death logic, active round only.
	else if (IsValidZombie(iVictim))
	{
		if (IsValidSurvivor(iKillers[0]))
			g_iZombiesKilledSpree++;
		
		for (int i = 0; i < 2; i++)
		{
			if (IsValidLivingClient(iKillers[i]))
				TF2_AddAmmo(iKillers[i], WeaponSlot_Primary, g_ClientClasses[iKillers[i]].iAmmo);
		}
	}
	
	SetGlow();
	
	return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	int iDamageAmount = event.GetInt("damageamount");
	
	if (IsValidClient(iVictim) && IsValidClient(iAttacker) && iAttacker != iVictim)
	{
		g_iDamageTakenLife[iVictim] += iDamageAmount;
		g_iDamageDealtLife[iAttacker] += iDamageAmount;
		
		if (IsValidZombie(iAttacker))
		{
			g_iDamageZombie[iAttacker] += iDamageAmount;
			
			if (!GetEntProp(iAttacker, Prop_Send, "m_bRageDraining") && TF2_IsSlotClassname(iAttacker, WeaponSlot_Secondary, "tf_weapon_buff_item"))
			{
				g_flBannerMeter[iAttacker] += float(iDamageAmount) / g_cvBannerRequirement.FloatValue * 100.0;
				if (g_flBannerMeter[iAttacker] >= 100.0)
					g_flBannerMeter[iAttacker] = 100.0;
				
				SetEntPropFloat(iAttacker, Prop_Send, "m_flRageMeter", g_flBannerMeter[iAttacker]);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Event_PlayerBuiltObject(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	int iEntity = event.GetInt("index");
	TFObjectType nObjectType = view_as<TFObjectType>(event.GetInt("object"));
	   
	if (nObjectType == TFObject_Dispenser && IsSurvivor(iClient))
	{
		SetEntProp(iEntity, Prop_Send, "m_bMiniBuilding", true);	// This also prevents starting 25 metal being set
		
		if (!GetEntProp(iEntity, Prop_Send, "m_bCarryDeploy"))
		{
			g_flDispenserUsage[iClient] = 1.0;
			SetEntProp(iEntity, Prop_Send, "m_iAmmoMetal", MINI_DISPENSER_MAX_METAL);
			
			// Starting half of max health due to side effect of mini building
			int iOffset = FindSendPropInfo("CObjectDispenser", "m_flPercentageConstructed") + 4;	// m_flHealth
			
			const iMaxHealth = 100;	// TF2 game forces it to be 100 due to mini building
			
			SetEntProp(iEntity, Prop_Send, "m_iMaxHealth", iMaxHealth);
			SetEntDataFloat(iEntity, iOffset, float(iMaxHealth) * 0.5);
			SetEntProp(iEntity, Prop_Send, "m_iHealth", RoundToFloor(float(iMaxHealth) * 0.5));
		}
	}
	
	return Plugin_Continue;
}

public Action Event_PlayerHealed(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	// Don't think there a better way to do this in a simple way
	int iClient = GetClientOfUserId(event.GetInt("healer"));
	if (!IsValidSurvivor(iClient))
		return Plugin_Continue;
	
	int iDispenser = TF2_GetBuilding(iClient, TFObject_Dispenser);
	if (iDispenser == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	int iAmount = event.GetInt("amount");
	g_flDispenserUsage[iClient] -= float(iAmount) / g_cvDispenserHealMax.FloatValue;
	
	if (g_flDispenserUsage[iClient] > 0.0)
	{
		SetEntProp(iDispenser, Prop_Send, "m_iAmmoMetal", RoundToCeil(g_flDispenserUsage[iClient] * MINI_DISPENSER_MAX_METAL));
	}
	else
	{
		SetVariantInt(GetEntProp(iDispenser, Prop_Send, "m_iMaxHealth"));
		AcceptEntityInput(iDispenser, "RemoveHealth");
	}
	
	return Plugin_Continue;
}

public Action Event_ObjectDestoryed(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	int iKiller = event.GetInt("attacker");
	if (iKiller != event.GetInt("userid"))
	{
		iKiller = GetClientOfUserId(iKiller);
		if (IsValidZombie(iKiller))
		{
			int iWeapon = GetEntPropEnt(iKiller, Prop_Send, "m_hActiveWeapon");
			if (iWeapon > MaxClients)
			{
				iWeapon = GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex");
				
				int iPos;
				WeaponClasses weapon;
				while (g_ClientClasses[iKiller].GetWeapon(iPos, weapon))
					if (weapon.iIndex == iWeapon && weapon.sIconName[0])
						event.SetString("weapon", weapon.sIconName);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Event_CPCapture(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	if (g_iControlPoints <= 0) 
		return Plugin_Continue;
	
	int iCaptureIndex = event.GetInt("cp");
	if (iCaptureIndex < 0 || iCaptureIndex >= g_iControlPoints)
		return Plugin_Continue;
	
	for (int i = 0; i < g_iControlPoints; i++)
	{
		if (g_iControlPointsInfo[i][0] == iCaptureIndex)
			g_iControlPointsInfo[i][1] = 2;
	}
	
	for (int iClient = 0; iClient < MaxClients; iClient++)
	{
		if (g_iCapturingPoint[iClient] == iCaptureIndex)
			g_iCapturingPoint[iClient] = -1;
	}
	
	CheckRemainingCP();
	
	return Plugin_Continue;
}

public Action Event_CPCaptureStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	if (g_iControlPoints <= 0)
		return Plugin_Continue;
	
	int iCaptureIndex = event.GetInt("cp");
	if (iCaptureIndex < 0 || iCaptureIndex >= g_iControlPoints)
		return Plugin_Continue;
	
	for (int i = 0; i < g_iControlPoints; i++)
		if (g_iControlPointsInfo[i][0] == iCaptureIndex)
			g_iControlPointsInfo[i][1] = 1;
	
	CheckRemainingCP();
	
	return Plugin_Continue;
}

public Action Event_Broadcast(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	char sSound[20];
	event.GetString("sound", sSound, sizeof(sSound));
	
	if (!strcmp(sSound, "Game.YourTeamWon", false) || !strcmp(sSound, "Game.YourTeamLost", false))
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action Event_HideNotice(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled)
		return Plugin_Continue;
	
	//Don't show notices to stunned players
	event.BroadcastDisabled = true;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
		if (IsClientInGame(iClient) && !Stun_IsPlayerStunned(iClient))
			event.FireToClient(iClient);
	
	return Plugin_Continue;
}