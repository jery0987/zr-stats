# zr-stats
Only tested on CSGO.

## Features
- Log: Nickname, SteamID, Human damage, Human win, Zombie infected, Zombie kills
- Stop map music toggle

## Requirements
- Sourcemod
- Mysql

## Installation
1. Download the archive and extract the files to the game server.
2. Add and config the following code to ``addons\sourcemod\configs\databases.cfg``
```C++
	"ZR_Stats"
	{
		"driver"         "mysql"
		"host"           "localhost"
		"database"       "csgo"
		"user"           "root"
		"pass"           "password"
	}
```
3. Start and stop your server.
4. Edit ``cfg\sourcemod\plugin.zr_stats.cfg``