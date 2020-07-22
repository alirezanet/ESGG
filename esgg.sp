#pragma tabsize 4 // Warning for tabsize
#pragma semicolon 1 // use simicolon
#include <sourcemod>
#include <clients>
#include <timers>
#include <string>
#include <cstrike>
#include <halflife>
#include <sdktools_functions>

//globalVariables --------------------------------------------------------------------------- 
Handle g_hWhitelistSteamIdTrie = INVALID_HANDLE;
KeyValues g_hRegistredPlayers = null;
bool IsSecondHalf = false;
bool IsTeamSwap = false;
int MatchStartCounter = 0;
int WinnerTeam = 0;
int SideChoosePeriod = 60;
Handle Timer_SideChooseHandle = INVALID_HANDLE;

//ConVars --------------------------------------------------------------------------- 
ConVar esgg_whitelist = null;
ConVar esgg_shutdown_after_matchend = null;

// API Events --------------------------------------------------------------------------- 
public void OnPluginStart()
{
	matchManager_PluginStart();
	whiteList_PluginStart();
	joinTeamLock_PluginStart();
	shutdownServer_PluginStart();
	AutoExecConfig(true, "esgg");
	LogMessage("Plugin Loaded.");
}
public void OnPluginEnd()
{
	
}
public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client))
		return;

	//CreateTimer(60.0,BanDisconnectedClient,client,TIMER_REPEAT);
}
// [ES-GG] AlienStalker has disconnected from the server. They have 5 minutes to rejoin the server or they will be issued a cool down.
// public Action BanDisconnectedClient(Handle timer , any client)
// {

// }


// Match Manager Warmup/Knife/Live -----------------------------------------------------------
void matchManager_PluginStart()
{
	HookEvent("round_start",Event_RoundStart);
	HookEvent("round_end",Event_RoundEnd);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	MatchStartCounter += 1;
	switch (MatchStartCounter)
	{
		case 1:{} //warmup
		case 2: // warmup finish
		{
			LogMessage("warmup finish");

			g_hRegistredPlayers.Rewind();
			if (!g_hRegistredPlayers.GotoFirstSubKey())
				return;

			char buffer[255];
			do
			{
				g_hRegistredPlayers.GetString("Joined",buffer, sizeof(buffer),"0");
				if (StrEqual(buffer, "0"))
				{
					// start canceling match
					ServerCommand("mp_pause_match");
					PrintToChatAll(" \x04[ES-GG] \x07Match will be cancelled, because one or more players did not joined the server.");

					decl String:path[ PLATFORM_MAX_PATH ];
					BuildPath( PathType:Path_SM, path, sizeof(path), "logs/esgg/RegistredPlayers.json");
					g_hRegistredPlayers.Rewind();
					g_hRegistredPlayers.ExportToFile(path);
					delete g_hRegistredPlayers;

					LogMessage("Server will be shutdown after 15 seconds");
					CreateTimer(15.0, shutdownEngine);
					return;
				}
			} while (g_hRegistredPlayers.GotoNextKey());
			// everything is ok Lets go Knife 
			ServerCommand("exec knife.cfg");
		}
		case 3: //knife rnd
		{
			ServerCommand("tv_record MatchDemo");
			PrintToChatAll(" \x04[ES-GG] \x06KNIFE !");
			PrintToChatAll(" \x04[ES-GG] \x06KNIFE !");
			PrintToChatAll(" \x04[ES-GG] \x06KNIFE !");
		} 
		case 4: // knife finish
		{
			LogMessage("knife finish");
			ServerCommand("mp_pause_match");
			RegConsoleCmd("stay",command_stay);
			RegConsoleCmd("switch",command_switch);
			Timer_SideChooseHandle = CreateTimer(15.0,Timer_SideChoosePeriod,_,TIMER_REPEAT);
			PrintToChatTeam(WinnerTeam," \x04[ES-GG] \x0APlease choose CT/T by following commands [\x0E!stay \x0AOR \x0E!switch\x0A]");
			if(WinnerTeam == CS_TEAM_CT)
			{
				PrintToChatTeam(CS_TEAM_T," \x04[ES-GG] \x0APlease wait until CT pick sides. (Maximum \x0C1 minute\x0A)");
			}
			else
			{
				PrintToChatTeam(CS_TEAM_CT," \x04[ES-GG] \x0APlease wait until TR pick sides. (Maximum \x0C1 minute\x0A)");
			}
		}
		case 5: // Live 
		{
			PrintToChatAll(" \x04[ES-GG] \x06LIVE !");
			PrintToChatAll(" \x04[ES-GG] \x06LIVE !");
			PrintToChatAll(" \x04[ES-GG] \x06LIVE !");
			PrintToChatAll(" \x04[ES-GG] \x0APlease be aware that all matches have overtime enabled, there are no ties in competitive play.");
		}
		default: // Just Print Score Info
		{
			char CtTeamName[254];
			char TrTeamName[254];

			bool IsCt = true;
			if(IsSecondHalf){IsCt = !IsCt;}
			if(IsCt)
			{
				GetConVarString(FindConVar("mp_teamname_1"),CtTeamName,sizeof(CtTeamName));
				GetConVarString(FindConVar("mp_teamname_2"),TrTeamName,sizeof(TrTeamName));
			}
			else
			{
				GetConVarString(FindConVar("mp_teamname_2"),CtTeamName,sizeof(CtTeamName));
				GetConVarString(FindConVar("mp_teamname_1"),TrTeamName,sizeof(TrTeamName));
			}

			int CtScore = CS_GetTeamScore(CS_TEAM_CT);
			int TrScore = CS_GetTeamScore(CS_TEAM_T);
			PrintToChatAll(" \x04[ES-GG] \x0C%s \x01[\x0E %d \x01-\x0E %d \x01] \x10%s ",CtTeamName,CtScore,TrScore,TrTeamName);
		}
	}
}

public Action Timer_SideChoosePeriod(Handle timer)
{
	SideChoosePeriod -= 15;
	if(SideChoosePeriod == 0)
	{
		ServerCommand("mp_unpause_match");
		ServerCommand("exec live.cfg");
		return Plugin_Stop;
	}
	else
	{
		PrintToChatAll(" \x04[ES-GG] \x0ARemaining time to choose a side \x0C%d seconds.",SideChoosePeriod);
		PrintToChatTeam(WinnerTeam," \x04[ES-GG] \x0APlease choose CT/T by following commands [\x0E!stay \x0AOR \x0E!switch\x0A]");
		return Plugin_Continue;
	}
}

public Action command_stay(int client ,int args)
{
	if (!IsClientInGame(client))
		return Plugin_Handled;

	if (MatchStartCounter == 4 && GetClientTeam(client) == WinnerTeam )
	{	
		char cname[254];
		GetClientName(client,cname,sizeof(cname));
		ServerCommand("mp_unpause_match");
		ServerCommand("exec live.cfg");
		CloseHandle(Timer_SideChooseHandle);
		PrintToChatAll(" \x04[ES-GG] \x0APlayer \x0C%s \x0Apicked \x0CSTAY ",cname);
	}
	else
	{
		ReplyToCommand(client," \x04[ES-GG] \x07You can not use stay command at this time!");
	}
	return	Plugin_Handled;
}
public Action command_switch(int client ,int args)
{
	if (!IsClientInGame(client))
		return Plugin_Handled;

	if (MatchStartCounter == 4 && GetClientTeam(client) == WinnerTeam )
	{	
		char cname[254];
		GetClientName(client,cname,sizeof(cname));
		ServerCommand("mp_unpause_match");
		ServerCommand("mp_swapteams");
		ServerCommand("exec live.cfg");
		IsTeamSwap = true;
		CloseHandle(Timer_SideChooseHandle);
		PrintToChatAll(" \x04[ES-GG] \x0APlayer \x0C%s \x0Apicked \x0CSWITCH ", cname);
	}
	else
	{
		ReplyToCommand(client," \x04[ES-GG] \x07You can not use stay command at this time!");
	}
	return	Plugin_Handled;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (MatchStartCounter < 2)
		return;
	
	WinnerTeam = event.GetInt("winner");
}

// joinTeamLock --------------------------------------------------------------------------
void joinTeamLock_PluginStart()
{
	AddCommandListener(Command_JoinTeam, "jointeam");
	HookEvent("announce_phase_end",Event_announce_phase_end);
}
public Action:Command_JoinTeam(client, const String:command[], args)
{    
	char arg[4];
	GetCmdArg(1, arg, sizeof(arg));
	int toTeam = StringToInt(arg);
    if(IsClientInGame(client) && !IsFakeClient(client))
    {
		if ( GetClientTeam(client) > 1) // when client is in game
        {
			PrintToChat(client, " \x04[ES-GG] \x07You cannot change your team during a match!");
            return Plugin_Stop;
        }
		else
		{
			char authId[25];
			GetClientAuthId (client,AuthId_Engine,authId,sizeof(authId));
			int playerIndex;
			GetTrieValue(g_hWhitelistSteamIdTrie, authId, playerIndex ); // find player index in Trie

			// register player for joined info (MatchManager)
			g_hRegistredPlayers.Rewind();
			g_hRegistredPlayers.JumpToKey(authId, false); 
			g_hRegistredPlayers.SetString("Joined","1");

			bool IsCt = false;
			if (playerIndex > 0 && playerIndex <= 5){IsCt=true;} 
			else if (playerIndex > 5 && playerIndex <= 10) {IsCt = false;} 
			else //above index 10 must to go spec
			{
				ChangeClientTeam(client, CS_TEAM_SPECTATOR);
				return Plugin_Continue;
			}
			if (IsTeamSwap){IsCt = !IsCt;}
			if (IsSecondHalf){IsCt = !IsCt;}
						
			if(IsCt) //ct
			{	
				if(toTeam != CS_TEAM_CT)
				{
					ChangeClientTeam(client, CS_TEAM_CT);
					return Plugin_Stop;
				}
			}
			else
			{
				if (toTeam != CS_TEAM_T)
				{
					ChangeClientTeam(client, CS_TEAM_T);
					return Plugin_Stop;
				}
			}
        }
	}	
    return Plugin_Continue;
}  
public void Event_announce_phase_end(Event event, const char[] name, bool dontBroadcast)
{
	LogMessage("Event_announce_phase_end : %d with mod value : %d" , MatchStartCounter ,((MatchStartCounter - 4) % 6));
	if ( (MatchStartCounter - 4) % 6 != 0  )//detect overtime or halfs
	{
		IsSecondHalf = !IsSecondHalf;
	}
}

// Shutdown Server ------------------------------------------------------------------------
void shutdownServer_PluginStart()
{
	esgg_shutdown_after_matchend = CreateConVar("esgg_shutdown_after_matchend", "1", "Auto shutdown server after match ended");
	HookEvent("cs_win_panel_match", Event_Game_End);
}
public void Event_Game_End(Event event, const char[] name, bool dontBroadcast)
{
	LogMessage("Match Ended Event Raised");
	CreateTimer(3.0,TvStopTimer); // TV Stop After 3 Sec
	bool isAutoShutdown = GetConVarBool(esgg_shutdown_after_matchend);
	if(isAutoShutdown)
	{
		LogMessage("Server will be shutdown after 20 seconds");
		CreateTimer(20.0, shutdownEngine);
	}
}
public Action TvStopTimer(Handle timer)
{
	ServerCommand("tv_stoprecord");
	KillTimer(timer);
}
public Action shutdownEngine(Handle timer)
{
	KillTimer(timer);
	ServerCommand("quit");
}

//WhiteList Functions ------------------------------------------------------------------------
void whiteList_PluginStart()
{
	g_hRegistredPlayers = new KeyValues("RegistredPlayers"); //MatchManager use
	esgg_whitelist = CreateConVar("esgg_whitelist", "1", "use whitelist");

	g_hWhitelistSteamIdTrie = CreateTrie();
	loadWhiteList();
}
public void OnClientAuthorized(int client,const String:szSteamId[])
{
	whiteList_ClientAuthorized(client,szSteamId);
}
void whiteList_ClientAuthorized(int client,const String:szSteamId[])
{
	if ( IsFakeClient( client ) ) //allow bots or tv to join
		return;

	bool isWhitelistEnable = GetConVarBool(esgg_whitelist);
	int playerIndex;
	bool shouldKick = !GetTrieValue( g_hWhitelistSteamIdTrie, szSteamId, playerIndex );
	if (shouldKick && isWhitelistEnable)
	{
		LogMessage("Prevent joining client %s",szSteamId);
		KickClient(client, "%s" , "Your steam account is not valid");
	}
	else
	{
		LogMessage("client with index %d and steamid ' %s ' Authorized", client , szSteamId);
	}
}
void loadWhiteList()
{
	decl String:path[ PLATFORM_MAX_PATH ];
	BuildPath( PathType:Path_SM, path, sizeof(path), "configs/esgg/whitelist.txt");
	if ( !FileExists( path ) )
	{
		LogMessage( "Could not find %s, it will be created", path );
	}
	else
	{
		Handle file = OpenFile( path, "r" );
		if(file == INVALID_HANDLE)
		{
			CloseHandle(file);
			SetFailState("Unable to read file %s", path);
		}
		ClearTrie( g_hWhitelistSteamIdTrie );
		delete g_hRegistredPlayers;
		g_hRegistredPlayers = new KeyValues("RegistredPlayers");

		bool failing;
		decl String:szLine[ 256 ];

		while( !IsEndOfFile( file ) && ReadFileLine( file, szLine, sizeof(szLine) ) )
		{
			failing = formatStrAndGetReducedSize( szLine ) < 7;
			if ( szLine[ 0 ] == '\0' )
			continue;
			if ( failing )
			{
				LogMessage( "whitelist.txt : Unrecognized SteamId, SteamGroupId : '%s'", szLine );
				continue;
			}
			if ( strStartsWith( szLine, "STEAM", false ) || strStartsWith( szLine, "[U:", false ) )
			{
				char arrOut[2][99];
				ExplodeString(szLine,"#",arrOut,2,99);
				SetTrieValue( g_hWhitelistSteamIdTrie, arrOut[0], StringToInt(arrOut[1]) , true );
				g_hRegistredPlayers.Rewind();
				g_hRegistredPlayers.JumpToKey(arrOut[0], true);	//store for check joining to server (MatchManager)
				g_hRegistredPlayers.SetString("Joined","0");
			}
			else
			{
				PrintToServer( "[ES-GG] Unrecognized SteamId : %s", szLine );
			}
		}
		CloseHandle(file);
	}
}

// usefull functions ------------------------------------------------------------------------
bool strStartsWith( String:str[], String:strStart[], bool:alsoCheckSize=true )
{
	new lenStrStart = strlen( strStart );
	if ( alsoCheckSize && strlen( str ) < lenStrStart )
		return false;
	
	return strncmp( str, strStart, lenStrStart, true ) == 0;
}
formatStrAndGetReducedSize( String:str[] )
{
	new len = strlen( str );
	for ( new i; i < len; i++ )
	{
		if ( IsCharSpace( str[ i ] ) || str[ i ] == ';' ) //remove next line !
		{
			str[ i ] = '\0';
			return i;
		}
	}
	
	return len;
}
void PrintToChatTeam(int team,const char[] format, any ...)
{
	char buffer[254];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, sizeof(buffer), format, 2);
			PrintToChat(i, "%s", buffer);
		}
	}
}

//Plugin Info ---------------------------------------------------------------------------------
public Plugin myinfo =
{
	name = "ESGG",
	author = "AliReZa Sabouri",
	description = "OpenSource Matchmaking plugin",
	version = "1.2",
	url = "https://github.com/Alirezanet/es-gg"
};
