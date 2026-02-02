void CalculateMaxSpeedPost(int iClient)
{
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient))
	{
		float flDefault = 300.0;
		switch (TF2_GetPlayerClass(iClient))
		{
			case TFClass_Scout:
				flDefault = 400.0;
			
			case TFClass_Soldier:
				flDefault = 240.0;
			
			case TFClass_DemoMan:
				flDefault = 280.0;
			
			case TFClass_Heavy:
				flDefault = 230.0;
			
			case TFClass_Medic, TFClass_Spy:
				flDefault = 320.0;
		}
		
		float flSpeed = flDefault + g_ClientClasses[iClient].flSpeed;
		
		if (IsZombie(iClient))
		{
			if (g_nInfected[iClient] == Infected_None)
			{
				//Movement speed increase
				float flSpeedBonus = fMin(g_ClientClasses[iClient].flMaxHorde, g_ClientClasses[iClient].flHorde * g_iHorde[iClient]);
				
				if (TF2_IsPlayerInCondition(iClient, TFCond_TeleportedGlow))
					flSpeedBonus += 40.0; //Screamer effect
				
				if (GetClientHealth(iClient) > SDKCall_GetMaxHealth(iClient))
					flSpeedBonus += 20.0; //Has overheal due to normal rage
				
				if (g_bZombieRage && flSpeedBonus < 40.0)
					flSpeedBonus += 40.0; //Map-wide zombie enrage event, but don't stack too much from other bonus
				
				flSpeed += flSpeedBonus;
				
				//Movement speed decrease
				if (TF2_IsPlayerInCondition(iClient, TFCond_Jarated))
					flSpeed -= 30.0; //Jarate'd by sniper
				
				if (GetClientHealth(iClient) < 50)
					flSpeed -= 50.0 - float(GetClientHealth(iClient)); //If under 50 health, tick away one speed per hp lost
			}
			else
			{
				switch (g_nInfected[iClient])
				{
					//Tank: movement speed penalty based on damage taken and dealt
					case Infected_Tank:
					{
						//Reduce speed when tank deals damage to survivors 
						flSpeed -= fMin(70.0, (float(g_iDamageDealtLife[iClient]) / 10.0));
						
						//Reduce speed when tank takes damage from survivors 
						flSpeed -= fMin(100.0, (float(g_iDamageTakenLife[iClient]) / 10.0));
						
						if (TF2_IsPlayerInCondition(iClient, TFCond_Jarated))
							flSpeed -= 30.0; //Jarate'd by sniper
					}
					
					//Cloaked: super speed if cloaked
					case Infected_Stalker:
					{
						if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked))
							flSpeed += 200.0;
					}
				}
			}
		}
		else if (IsSurvivor(iClient))
		{
			//If under 50 health, tick away one speed per hp lost
			if (GetClientHealth(iClient) < 50)
				flSpeed -= 50.0 - float(GetClientHealth(iClient));
		}
		
		if (Stun_IsPlayerStunned(iClient))
		{
			flSpeed *= Stun_GetSpeedMulti(iClient);
			if (GetEntityFlags(iClient) & FL_ONGROUND)
			{
				float vecVelocity[3];
				GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVelocity);
				if (GetVectorLength(vecVelocity) > flSpeed)
				{
					NormalizeVector(vecVelocity, vecVelocity);
					ScaleVector(vecVelocity, flSpeed);
					TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, vecVelocity);
				}
			}
		}
		
		if (flSpeed <= 1.0)	// Do not set speed to negative or you'll send em to the backrooms
			flSpeed = 1.0;
		
		TF2Attrib_SetByName(iClient, "major move speed bonus", flSpeed / flDefault);
	}
}

void DHook_OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (!g_bTF2Items && !g_bGiveNamedItemSkip && StrContains(sClassname, "tf_wea") == 0)
		RequestFrame(OnGiveNamedItemPre, EntIndexToEntRef(iEntity));
}

static void OnGiveNamedItemPre(int iRef)
{
	int iEntity = EntRefToEntIndex(iRef);
	if (iEntity == INVALID_ENT_REFERENCE)
		return;
	
	if ((HasEntProp(iEntity, Prop_Send, "m_bDisguiseWearable") && GetEntProp(iEntity, Prop_Send, "m_bDisguiseWearable")) ||
		(HasEntProp(iEntity, Prop_Send, "m_bDisguiseWeapon") && GetEntProp(iEntity, Prop_Send, "m_bDisguiseWeapon")))
		return;
	
	int iClient = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
	if (iClient < 1 || iClient > MaxClients)
		return;
	
	int iIndex = GetEntProp(iEntity, Prop_Send, "m_iItemDefinitionIndex");
	
	Action iAction = OnGiveNamedItem(iClient, iIndex);
	
	if (iAction == Plugin_Handled)
	{
		char sClassname[36];
		GetEntityClassname(iEntity, sClassname, sizeof(sClassname));
		if (StrContains(sClassname, "tf_weapon") == 0)
		{
			RemoveItem(iClient, iEntity);
		}
		else
		{
			TF2_RemoveWearable(iClient, iEntity);
		}
	}
}

static void RemoveItem(int iClient, int iWeapon)
{
	int iEntity = GetEntPropEnt(iWeapon, Prop_Send, "m_hExtraWearable");
	if (iEntity != -1)
		TF2_RemoveWearable(iClient, iEntity);

	iEntity = GetEntPropEnt(iWeapon, Prop_Send, "m_hExtraWearableViewModel");
	if (iEntity != -1)
		TF2_RemoveWearable(iClient, iEntity);

	RemovePlayerItem(iClient, iWeapon);
	RemoveEntity(iWeapon);
}

void RoundRespawnPre()
{
	if (g_nRoundState == SZFRoundState_Setup)
		return;
	
	DetermineControlPoints();
	
	g_bLastSurvivor = false;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		g_iDamageZombie[iClient] = 0;
		g_iKillsThisLife[iClient] = 0;
		g_bSpawnAsSpecialInfected[iClient] = false;
		g_nInfected[iClient] = Infected_None;
		g_nNextInfected[iClient] = Infected_None;
		g_iMaxHealth[iClient] = -1;
		g_flTimeStartAsZombie[iClient] = 0.0;
		g_flDamageDealtAgainstTank[iClient] = 0.0;
	}
	
	for (int i = 0; i < view_as<int>(Infected_Count); i++)
	{
		g_flInfectedCooldown[i] = 0.0;
		g_iInfectedCooldown[i] = 0;
	}
	
	g_nRoundState = SZFRoundState_Grace;
	g_iRoundPlayedCount++;
	
	CPrintToChatAll("%t", "Grace_Start", "{green}");
	
	//Assign players to zombie and survivor teams.
	int[] iClients = new int[MaxClients];
	int iLength = 0;
	int iSurvivorCount;
	
	//Find all active players.
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		Sound_EndAllMusic(iClient);
		
		if (IsClientInGame(iClient) && TF2_GetClientTeam(iClient) != TFTeam_Spectator)
		{
			// Add all unassigned and users already in team, unassigned users assumes to be put in zombie team later
			iClients[iLength] = iClient;
			iLength++;
		}
	}
	
	SortIntegers(iClients, iLength, Sort_Random);	//Randomize player list
	SortCustom1D(iClients, iLength, Sort_LastPlayedZombie);	//Order by round last played as zombie
	
	//Calculate team counts. At least one survivor must exist.
	iSurvivorCount = RoundToFloor(iLength * g_cvRatio.FloatValue);
	if (iSurvivorCount == 0 && iLength > 0)
		iSurvivorCount = 1;
	
	TFTeam[] nClientTeam = new TFTeam[MaxClients+1];
	
	//Check if we need to force players to survivor or zombie team
	for (int i = 0; i < iLength; i++)
	{
		int iClient = iClients[i];
		
		if (TF2_GetClientTeam(iClient) > TFTeam_Spectator)
		{
			Action action = Forward_ShouldStartZombie(iClient);
			
			if (action == Plugin_Handled || (g_iForceZombieStartTimestamp[iClient] > 0 && g_cvPunishAvoidingPlayers.BoolValue))
			{
				if (action != Plugin_Handled)
				{
					// If they attempted to skip playing as zombie last time, force them to be in the zombie team
					if (g_iForceZombieStartTimestamp[iClient] > g_iRoundTimestamp)
					{
						CPrintToChat(iClient, "%t", "Infected_ForceStart_LastRound", "{red}");
					}
					else
					{
						char sDuration[256];
						GetVaguePeriodOfTimeFromTimestamp(sDuration, sizeof(sDuration), g_iForceZombieStartTimestamp[iClient], iClient);
						
						CPrintToChat(iClient, "%t", "Infected_ForceStart", "{red}",  g_sForceZombieStartMapName[iClient], sDuration);
					}
					
					g_iForceZombieStartTimestamp[iClient] = 0;
					g_sForceZombieStartMapName[iClient] = "";
					
					g_cForceZombieStartTimestamp.Set(iClient, "0");
					g_cForceZombieStartMapName.Set(iClient, "");
				}
				
				//Zombie
				SpawnClient(iClient, TFTeam_Zombie, true);
				nClientTeam[iClient] = TFTeam_Zombie;
				g_flTimeStartAsZombie[iClient] = GetGameTime();
				SetClientStartedAsZombie(iClient);
			}
		}
	}
	
	//From SortIntegers, we set the rest to survivors, then zombies
	for (int i = 0; i < iLength; i++)
	{
		int iClient = iClients[i];
		
		//Check if they have not already been assigned
		if (TF2_GetClientTeam(iClient) > TFTeam_Spectator && !(nClientTeam[iClient] == TFTeam_Zombie) && !(nClientTeam[iClient] == TFTeam_Survivor))
		{
			if (iSurvivorCount > 0)
			{
				//Survivor
				SpawnClient(iClient, TFTeam_Survivor, true);
				nClientTeam[iClient] = TFTeam_Survivor;
				iSurvivorCount--;
			}
			else
			{
				//Zombie
				SpawnClient(iClient, TFTeam_Zombie, true);
				nClientTeam[iClient] = TFTeam_Zombie;
				g_flTimeStartAsZombie[iClient] = GetGameTime();
				SetClientStartedAsZombie(iClient);
			}
		}
	}
	
	//Reset counters
	g_flCapScale = -1.0;
	g_aSurvivorDeathTimes.Clear();
	g_iZombiesKilledSpree = 0;
	g_iTanksSpawned = 0;
	
	g_flTimeProgress = 0.0;
	g_hTimerProgress = null;
	
	g_iRoundTimestamp = GetTime();
	
	//Handle grace period timers.
	CreateTimer(0.5, Timer_GraceStartPost, TIMER_FLAG_NO_MAPCHANGE);
	
	SetGlow();
	UpdateZombieDamageScale();
}