#include <sourcemod>
#include <zombiereloaded>
#include <geoip>
#include <clientprefs>
#include <multicolors>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"
#define MENU_SteamID "#MenuSteamID"
#define MENU_Damege "#MenuDamege"
#define MENU_Infect "#MenuInfect"
#define MENU_Kill "#MenuKill"
#define MENU_Win "#MenuWin"
#define MENU_Country "#MenuCountry"
#define MENU_ToggleHud "#MenuToggleHud"
#define MENU_ToggleStopMusic "#MenuToggleStopMusic"

new Handle:DB = INVALID_HANDLE;
new Handle:hQuery = INVALID_HANDLE;
int DamageTable[MAXPLAYERS + 1];
int InfectedTable[MAXPLAYERS + 1];
int KillsTable[MAXPLAYERS + 1];
int MenuPlayerSelected[MAXPLAYERS + 1];
bool EnableDamageHud[MAXPLAYERS + 1];
bool EnableStopMusic[MAXPLAYERS + 1];

int EmptyArray[MAXPLAYERS + 1] = {0};

new Handle:gH_DamageHud = INVALID_HANDLE;
new Handle:gH_StopMusic = INVALID_HANDLE;
new Handle:gH_DamageHudCookie;
new Handle:gH_StopMusicCookie;


new bool:bDamageHud = true;
new bool:bStopMusic = true;

new g_iNumSounds;
new g_iSoundEnts[2048];

new String:g_SQL_SelectPlayer[] = "SELECT * FROM `zr_stats` WHERE auth = '%s';";
new String:g_SQL_CreateNewPlayer[] = "INSERT INTO `zr_stats` (auth, name, ip) VALUES ('%s', '%s', '%s');";
new String:g_SQL_UpdatePlayerName[] = "UPDATE `zr_stats` SET name = '%s', ip = '%s' WHERE auth = '%s';";
new String:g_SQL_UpdatePlayer[] = "UPDATE `zr_stats` SET damage = '%d', infect = '%d', kills = '%d' WHERE auth = '%s';";
new String:g_SQL_UpdatePlayerWithWin[] = "UPDATE `zr_stats` SET damage = '%d', infect = '%d', kills = '%d', win = '%d' WHERE auth = '%s';";
new String:g_SQL_CreateTable[] = "CREATE TABLE IF NOT EXISTS `zr_stats` ( `id` int(11) NOT NULL AUTO_INCREMENT, `name` varchar(255) COLLATE utf8mb4_bin NOT NULL, `auth` varchar(255) COLLATE utf8mb4_bin NOT NULL, `damage` int(20) NOT NULL, `infect` int(11) NOT NULL, `kills` int(11) NOT NULL, `win` int(11) NOT NULL, `ip` varchar(20) COLLATE utf8mb4_bin NOT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin AUTO_INCREMENT=1 ;";

public Plugin:myinfo = {
	name = "[TWZE]Player Stats",
	author = "jery0987",
	description = "Zombie Escape player stats",
	version      = PLUGIN_VERSION,
	url = ""
};

public OnPluginStart()
{
	gH_DamageHud = CreateConVar("zr_stats_damegehud", "1", "Enable damage hud?;1 = Enable;0 = Disable", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gH_StopMusic = CreateConVar("zr_stats_stopmusic", "1", "Enable stop music?;1 = Enable;0 = Disable", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gH_DamageHudCookie = RegClientCookie("zr_stats_damegehud_cookie", "ZR Stats Damage Hud Cookie", CookieAccess_Protected);
	gH_StopMusicCookie = RegClientCookie("zr_stats_stopmusic_cookie", "ZR Stats Stop Music Cookie", CookieAccess_Protected);
	SetCookiePrefabMenu(gH_DamageHudCookie, CookieMenu_OnOff, "ZR Stats Damage Hud");
	SetCookiePrefabMenu(gH_StopMusicCookie, CookieMenu_OnOff, "ZR Stats Stop Music");
	
	RegConsoleCmd("sm_stats", Command_StatsMenu, "See your stats or someone's stats");
	
	HookConVarChange(gH_DamageHud, ConVarChanged);
	HookConVarChange(gH_StopMusic, ConVarChanged);
	
	AutoExecConfig();
	LoadTranslations("zr_stats.phrases");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerDeath);
	
	new String:Error[128];
	DB = SQL_Connect("ZR_Stats", true, Error, sizeof(Error));
	if(DB == INVALID_HANDLE){
		LogError("[ZR_Stats] mysql connection error: %s", Error);
		CloseHandle(DB);
		LogError("[ZR_Stats] plugin unloaded");
		new String:filename[256];
		GetPluginFilename(INVALID_HANDLE, filename, sizeof(filename));
		ServerCommand("sm plugins unload %s", filename);
	}
	
	SQL_SetCharset(DB, "utf8mb4");
	SQL_FastQuery(DB, "SET NAMES \"utf8mb4\""); 
	SQL_FastQuery(DB, g_SQL_CreateTable);
	
	for (new i = 1; i <= MaxClients; ++i)
	{
		if (AreClientCookiesCached(i))
			OnClientCookiesCached(i);
	}
	
	CreateTimer(10.0, Post_Start, _, TIMER_REPEAT);
}

public ConVarChanged(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if(cvar == gH_DamageHud)
		bDamageHud = bool:StringToInt(newVal);
	if(cvar == gH_StopMusic)
		bStopMusic = bool:StringToInt(newVal);
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	DamageTable = EmptyArray;
	InfectedTable = EmptyArray;
	KillsTable = EmptyArray;
	g_iNumSounds = 0;
	UpdateSounds();
	CreateTimer(0.8, Post_Start);
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	bool ctwin = false;
	if(GetEventInt(event, "winner") == 3){
		ctwin = true;
	}
	
	CreateTimer(1.0, RoundEndUpdate, ctwin);
}

public Action RoundEndUpdate(Handle timer, Handle ctwin)
{
	for(new i = 1; i <= MaxClients; i++){
		if (IsClientInGame(i) && (!IsFakeClient(i))){
			new String:query[200];
			new String:auth[200];
			
			int damage;
			int infect;
			int kill;
			int win;
			
			GetClientAuthId(i, AuthId_SteamID64, auth, sizeof(auth));
			
			Format(query, sizeof(query), g_SQL_SelectPlayer, auth);
			hQuery = SQL_Query(DB, query);
			if(SQL_FetchRow(hQuery)){
				damage = SQL_FetchInt(hQuery, 3);
				infect = SQL_FetchInt(hQuery, 4);
				kill = SQL_FetchInt(hQuery, 5);
				win = SQL_FetchInt(hQuery, 6);
			}
			CloseHandle(hQuery)
			if(IsPlayerAlive(i) && ctwin){
				win += 1;
			}
			damage += DamageTable[i];
			infect += InfectedTable[i];
			kill += KillsTable[i];
			
			Format(query, sizeof(query), g_SQL_UpdatePlayerWithWin, damage, infect, kill, win, auth);
			SQL_FastQuery(DB, query);
		}
	}
}

public OnClientAuthorized(client)
{
	new String:query[200];
	new String:auth[200];
	new String:name[200];
	new String:ip[200];
	
	GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth));
	GetClientName(client, name, sizeof(name));
	GetClientIP(client, ip, sizeof(ip));
	
	SQL_SetCharset(DB, "utf8mb4");
	SQL_FastQuery(DB, "SET NAMES \"utf8mb4\""); 
	
	Format(query, sizeof(query), g_SQL_SelectPlayer, auth);
	hQuery = SQL_Query(DB, query);
	if(!SQL_FetchRow(hQuery)){
		Format(query, sizeof(query), g_SQL_CreateNewPlayer, auth, name, ip);
		SQL_FastQuery(DB, query);
	}else{
		Format(query, sizeof(query), g_SQL_UpdatePlayerName, name, ip, auth);
		SQL_FastQuery(DB, query);
	}
	CloseHandle(hQuery);
	
}

public OnClientDisconnect(client)
{
	new String:query[200];
	new String:auth[200];
	
	int damage;
	int infect;
	int kill;
	
	GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth));
	
	Format(query, sizeof(query), g_SQL_SelectPlayer, auth);
	hQuery = SQL_Query(DB, query);
	if(SQL_FetchRow(hQuery)){
		damage = SQL_FetchInt(hQuery, 3);
		infect = SQL_FetchInt(hQuery, 4);
		kill = SQL_FetchInt(hQuery, 5);
	}
	CloseHandle(hQuery);
	
	damage += DamageTable[client];
	infect += InfectedTable[client];
	kill += KillsTable[client];
	
	Format(query, sizeof(query), g_SQL_UpdatePlayer, damage, infect, kill, auth);
	SQL_FastQuery(DB, query);
	
	DamageTable[client] = 0;
	InfectedTable[client] = 0;
	KillsTable[client] = 0;
	EnableDamageHud[client] = false;
	EnableStopMusic[client] = false;
}

public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client_temp = GetEventInt(event, "userid");
	int attacker_temp = GetEventInt(event, "attacker");
	int damage = GetEventInt(event, "dmg_health");
	int health = GetEventInt(event, "health");
	
	int client = GetClientOfUserId(client_temp);
	int attacker = GetClientOfUserId(attacker_temp);
	
	if(client != 0 && attacker != 0){
		if(IsClientInGame(client) && damage > 0 && ZR_IsClientZombie(client)){
			if(IsClientInGame(attacker) && !IsFakeClient(attacker) && ZR_IsClientHuman(attacker)){
				if(bDamageHud && EnableDamageHud[attacker]){
					PrintHintText(attacker, "%t", "Damage Hint Text", client, health, damage);
				}
				DamageTable[attacker] += damage;
			}
		}
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client_temp = GetEventInt(event, "userid");
	int attacker_temp = GetEventInt(event, "attacker");
	int client = GetClientOfUserId(client_temp);
	int attacker = GetClientOfUserId(attacker_temp);
	
	if(client != 0 && attacker != 0){
		if(IsClientInGame(client) && IsPlayerAlive(attacker)){
			if(IsClientInGame(attacker) && !IsFakeClient(attacker) && ZR_IsClientHuman(attacker)){
				KillsTable[attacker] += 1;
			}
		}
	}
}

public ZR_OnClientInfected(client, attacker, bool:motherInfect, bool:respawnOverride, bool:respawn)
{
	if(!motherInfect && IsClientInGame(attacker) && !IsFakeClient(attacker)){
		InfectedTable[attacker] += 1;
	}
}

public Action:Command_StatsMenu(client, args)
{
	new Handle:menu = CreateMenu(StatsMenuHandler, MENU_ACTIONS_ALL);
	if(args < 1){
		MenuPlayerSelected[client] = client;
		SetMenuTitle(menu, "%T", "Stats Menu Title", client);
		AddMenuItem(menu, MENU_SteamID, "SteamID", ITEMDRAW_RAWLINE);
		AddMenuItem(menu, MENU_Damege, "Damage", ITEMDRAW_RAWLINE);
		AddMenuItem(menu, MENU_Infect, "Infect", ITEMDRAW_RAWLINE);
		AddMenuItem(menu, MENU_Win, "Win", ITEMDRAW_RAWLINE);
		AddMenuItem(menu, MENU_Kill, "Kill", ITEMDRAW_RAWLINE);
		AddMenuItem(menu, MENU_Country, "Country", ITEMDRAW_RAWLINE);
		
		if(bDamageHud){
			AddMenuItem(menu, MENU_ToggleHud, "ToggleHud");
		}
		if(bStopMusic){
			AddMenuItem(menu, MENU_ToggleStopMusic, "ToggleStopMusic");
		}
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, 20);
	}else{
		new String:name[32];
		new String:other[32];
		GetCmdArg(1, name, sizeof(name));
		int target = -1;
		int found = 0;
		for (int i=1; i<=MaxClients; i++){
			if (IsClientInGame(i) && !IsFakeClient(i)){
				GetClientName(i, other, sizeof(other));
				if (StrContains(other, name, false) != -1){
					target = i;
					found++;
				}
			}
		}
		if(found > 1){
			CPrintToChat(client, "%t%t", "ChatPrefix", "More Then One Players");
			return Plugin_Handled;
		}
		if(target != -1){
			MenuPlayerSelected[client] = target;
			SetMenuTitle(menu, "%T", "Other Player Stats Menu Title", client, other);
			AddMenuItem(menu, MENU_SteamID, "SteamID", ITEMDRAW_RAWLINE);
			AddMenuItem(menu, MENU_Damege, "Damage", ITEMDRAW_RAWLINE);
			AddMenuItem(menu, MENU_Infect, "Infect", ITEMDRAW_RAWLINE);
			AddMenuItem(menu, MENU_Win, "Win", ITEMDRAW_RAWLINE);
			AddMenuItem(menu, MENU_Kill, "Kill", ITEMDRAW_RAWLINE);
			AddMenuItem(menu, MENU_Country, "Country", ITEMDRAW_RAWLINE);
			SetMenuExitButton(menu, true);
			DisplayMenu(menu, client, 20);
		}else{
			CPrintToChat(client, "%t%t", "ChatPrefix", "Cant Find Player", name);
		}
	}
 
	return Plugin_Handled;
}

public StatsMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action){
		case MenuAction_Select:{
			new String:info[64];
			GetMenuItem(menu, param2, info, sizeof(info));
			if (StrEqual(info, MENU_ToggleHud)){
				EnableDamageHud[param1] = !EnableDamageHud[param1];
				SetClientCookie(param1, gH_DamageHudCookie, EnableDamageHud[param1] ? "1" : "0");
				DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), 20)
			}
			if (StrEqual(info, MENU_ToggleStopMusic)){
				EnableStopMusic[param1] = !EnableStopMusic[param1];
				SetClientCookie(param1, gH_StopMusicCookie, EnableStopMusic[param1] ? "1" : "0");
				DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), 20)
				if(EnableStopMusic[param1]){
					new String:sSound[PLATFORM_MAX_PATH], entity;
					for (new i = 0; i < g_iNumSounds; i++)
					{
						entity = EntRefToEntIndex(g_iSoundEnts[i]);
						
						if (entity != INVALID_ENT_REFERENCE)
						{
							GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
							Client_StopSound(param1, entity, SNDCHAN_STATIC, sSound);
						}
					}
				}
			}
		}
		
		case MenuAction_DrawItem:
		{
			new style;
			new String:info[64];
			GetMenuItem(menu, param2, info, sizeof(info), style);

			if (StrEqual(info, MENU_SteamID)){
				return ITEMDRAW_DISABLED;
			}else if (StrEqual(info, MENU_Damege)){
				return ITEMDRAW_DISABLED;
			}else if (StrEqual(info, MENU_Infect)){
				return ITEMDRAW_DISABLED;
			}else if (StrEqual(info, MENU_Win)){
				return ITEMDRAW_DISABLED;
			}else if (StrEqual(info, MENU_Kill)){
				return ITEMDRAW_DISABLED;
			}else if (StrEqual(info, MENU_Country)){
				return ITEMDRAW_DISABLED;
			}else{
				return ITEMDRAW_DEFAULT;
			}

		}
		
		case MenuAction_DisplayItem:{
			int target = MenuPlayerSelected[param1];
			new String:info[64];
			new String:display[64];
			GetMenuItem(menu, param2, info, sizeof(info));
			
			new String:query[200];
			new String:auth[200];
			new String:SteamID[200];
			int damage;
			int infect;
			int kill;
			int win;
			new String:ip[32];
			new String:country[32];
			GetClientAuthId(target, AuthId_SteamID64, auth, sizeof(auth));
			GetClientAuthId(target, AuthId_Steam3, SteamID, sizeof(SteamID));
			Format(query, sizeof(query), g_SQL_SelectPlayer, auth);
			hQuery = SQL_Query(DB, query);
			if(SQL_FetchRow(hQuery)){
				damage = SQL_FetchInt(hQuery, 3);
				infect = SQL_FetchInt(hQuery, 4);
				kill = SQL_FetchInt(hQuery, 5);
				win = SQL_FetchInt(hQuery, 6);
				SQL_FetchString(hQuery, 7, ip, sizeof(ip));
			}
			CloseHandle(hQuery)
			bool foundcountry = GeoipCountry(ip, country, sizeof(country));
			
			if (StrEqual(info, MENU_SteamID)){
				Format(display, sizeof(display), "%T", "Menu SteamID", param1, SteamID);
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_Damege)){
				Format(display, sizeof(display), "%T", "Menu Damage", param1, damage);
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_Infect)){
				Format(display, sizeof(display), "%T", "Menu Infect", param1, infect);
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_Win)){
				Format(display, sizeof(display), "%T", "Menu Win", param1, win);
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_Kill)){
				Format(display, sizeof(display), "%T", "Menu Kill", param1, kill);
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_Country)){
				if(foundcountry){
					Format(display, sizeof(display), "%T", "Menu Country", param1, country);
				}else{
					new String:unknown[64];
					Format(unknown, sizeof(unknown), "%T", "Unknown", param1);
					Format(display, sizeof(display), "%T", "Menu Country", param1, unknown);
				}
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_ToggleHud)){
				if(EnableDamageHud[param1]){
					Format(display, sizeof(display), "%T%T", "Menu ToggleHud", param1, "Enable", param1);
				}else{
					Format(display, sizeof(display), "%T%T", "Menu ToggleHud", param1, "Disable", param1);
				}
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, MENU_ToggleStopMusic)){
				if(EnableStopMusic[param1]){
					Format(display, sizeof(display), "%T%T", "Menu ToggleStopMusic", param1, "Enable", param1);
				}else{
					Format(display, sizeof(display), "%T%T", "Menu ToggleStopMusic", param1, "Disable", param1);
				}
				return RedrawMenuItem(display);
			}
		}
	}
	return 0;
}

public OnClientCookiesCached(client)
{
	new String:CookieValue[8];
	
	GetClientCookie(client, gH_DamageHudCookie, CookieValue, sizeof(CookieValue));
	EnableDamageHud[client] = (CookieValue[0] == '\0' || StringToInt(CookieValue));
	
	GetClientCookie(client, gH_StopMusicCookie, CookieValue, sizeof(CookieValue));
	EnableStopMusic[client] = (StringToInt(CookieValue) == 1 ? true : false);
	if(EnableStopMusic[client]){
		new String:sSound[PLATFORM_MAX_PATH], entity;
		for (new i = 0; i < g_iNumSounds; i++)
		{
			entity = EntRefToEntIndex(g_iSoundEnts[i]);
			
			if (entity != INVALID_ENT_REFERENCE)
			{
				GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
				Client_StopSound(client, entity, SNDCHAN_STATIC, sSound);
			}
		}
	}
}

public Action:Post_Start(Handle:timer){
	if(GetClientCount() <= 0){
		return Plugin_Continue;
	}
	new String:sSound[PLATFORM_MAX_PATH];
	new entity = INVALID_ENT_REFERENCE;
	for(new i=1;i<=MaxClients;i++){
		if(!EnableStopMusic[i] || !IsClientInGame(i)){ continue; }
		for (new u=0; u<g_iNumSounds; u++){
			entity = EntRefToEntIndex(g_iSoundEnts[u]);
			if (entity != INVALID_ENT_REFERENCE){
				GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
				Client_StopSound(i, entity, SNDCHAN_STATIC, sSound);
			}
		}
	}
	return Plugin_Continue;
}

UpdateSounds(){
	new String:sSound[PLATFORM_MAX_PATH];
	new entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
	{
		GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
		
		new len = strlen(sSound);
		if (len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
		{
			g_iSoundEnts[g_iNumSounds++] = EntIndexToEntRef(entity);
		}
	}
}

stock Client_StopSound(client, entity, channel, const String:name[])
{
	EmitSoundToClient(client, name, entity, channel, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
}