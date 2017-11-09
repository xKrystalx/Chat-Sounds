#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Punky"
#define PLUGIN_VERSION "1.0"
#define MAP_MAX_LENGTH 128

#include <sourcemod>
#include <sdktools>
#include <cstrike>
//#include <emitsoundany>
#include <scp>		//simple chat processor
//#include <sdkhooks>

//#pragma newdecls required

EngineVersion g_Game;

public Plugin myinfo = 
{
	name = "",
	author = PLUGIN_AUTHOR,
	description = "Plays sounds from chat",
	version = PLUGIN_VERSION,
	url = ""
};

//Handle h_Enabled = null;
Handle h_Volume = null;
//Handle h_Amount = null;
Handle h_Delay = null;
//Handle h_Interval = null;
Handle h_Debug = null;
Handle h_Display = null;

StringMap soundstable = null;
StringMap volumetable = null;
KeyValues kv_sounds = null;

int snd_debug = 0, snd_display = 0;
float snd_volume = 0.0, cooldown_time = 0.0, client_delay[MAXPLAYERS+1] = {0.0};

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if(g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("[Chat Sounds] This plugin is for CSGO/CSS only.");	
	}
	
	//h_Enabled = CreateConVar("sm_sounds_enabled", "1", "Enable/Disable sound playback from chat", FCVAR_NONE, true, 0.0, true, 1.0);
	h_Volume = CreateConVar("sm_sounds_volume", "1.0", "Volume multiplier for each of the sounds", FCVAR_NONE, true, 0.0, true, 1.0);
	//h_Amount = CreateConVar("sm_sounds_amount", "3", "Determines the amount of sounds a player can execute in a given timeframe", FCVAR_NONE, true, 0.0, true, 20.0);
	//h_Interval = CreateConVar("sm_sounds_interval", "0.5", "Amount of time in between the sounds, before a player can execute another one (applies only to that player)", FCVAR_NONE, true, 0.0, false, 0.0);
	h_Delay = CreateConVar("sm_sounds_delay", "5.0", "Delay between each sound a player can execute", FCVAR_NONE, true, 0.0, false, 20.0);
	h_Debug = CreateConVar("sm_sounds_debug", "1", "Log plugin actions and player executes", FCVAR_NONE, true, 0.0, true, 1.0);
	h_Display = CreateConVar("sm_sounds_display", "1", "Enable/Disable the message triggers from displaying in chat", FCVAR_NONE, true, 0.0, true, 1.0);
	
	HookConVarChange(h_Volume, OnConVarChange);
	HookConVarChange(h_Delay, OnConVarChange);
	HookConVarChange(h_Debug, OnConVarChange);
	HookConVarChange(h_Display, OnConVarChange);
	
	RegAdminCmd("sm_sounds_reload", Command_SoundsReload, ADMFLAG_CONVARS, "Reload the sound file");
	//RegAdminCmd("sm_sounds_config_reload", Command_ConfigReload, ADMFLAG_CONVARS, "Reload the plugin config");
}

public void OnMapStart()
{
	AutoExecConfig(true, "say_sounds_cvars", "sourcemod/say_sounds");
	if (!FileExists("cfg/sourcemod/say_sounds/say_sounds_list.txt", false, _))
	{
		SetFailState("[Chat Sounds] Sound list does not exist.");
	}
	
	ReloadSoundList();
	ReloadConfig();
}

public void OnMapEnd()
{
	soundstable.Clear();
	soundstable = null;
}

public void OnClientPostAdminCheck(int client)
{
	client_delay[client] = 0.0;
}

public void OnClientDisconnect(int client)
{
	client_delay[client] = 0.0;
}

public Action Command_SoundsReload(int args, int client)
{
	ReloadSoundList();
}

/*public Action Command_ConfigReload(int args, int client)
{
	ReloadConfig();
}*/

public OnConVarChange(Handle convar, const char[] oldValue, const char[] newValue)
{
	ReloadConfig();
}

public void ReloadConfig()
{
	cooldown_time = GetConVarFloat(h_Delay);
	snd_volume = GetConVarFloat(h_Volume);
	snd_debug = GetConVarInt(h_Debug);
	snd_display = GetConVarInt(h_Display);
}

public void ReloadSoundList()
{
	char buffer_sound_path[PLATFORM_MAX_PATH], buffer_sound_path_download[PLATFORM_MAX_PATH], buffer_sound_name[MAP_MAX_LENGTH];		//creating an array to store path and volume for those sounds
	float buffer_sound_volume;
	kv_sounds = new KeyValues("sounds");
	kv_sounds.ImportFromFile("cfg/sourcemod/say_sounds/say_sounds_list.txt");
	
	soundstable = new StringMap();
	volumetable = new StringMap();
	
	if(kv_sounds.GotoFirstSubKey())
	{
		do
		{
			kv_sounds.GetSectionName(buffer_sound_name, sizeof(buffer_sound_name));
			kv_sounds.GetString("path", buffer_sound_path, sizeof(buffer_sound_path), "");
			buffer_sound_volume = kv_sounds.GetFloat("volume", 0.0);
			soundstable.SetString(buffer_sound_name, buffer_sound_path, true);	//store the sounds in a hash map, so we don't open the .txt file over and over
			volumetable.SetValue(buffer_sound_name, buffer_sound_volume, true);
			
			Format(buffer_sound_path_download, sizeof(buffer_sound_path_download), "sound/%s", buffer_sound_path);
			if(snd_debug)
			{
				LogAction(-1, -1, "[Chat Sounds] Adding a sound to the download list: %s", buffer_sound_path_download);
			}
			AddFileToDownloadsTable(buffer_sound_path_download);
			
			if(PrecacheSound(buffer_sound_path, true))
			{
				LogAction(-1, -1, "[Chat Sounds] Found and precached a sound: %s  [Volume: %.2f]", buffer_sound_path, buffer_sound_volume);
			}
			else
			{
				LogAction(-1, -1, "[Chat Sounds] Failed to precache a sound: %s   [Volume: %.2f]", buffer_sound_path, buffer_sound_volume);
			}
		}
		while (kv_sounds.GotoNextKey());
	}
	else
	{
		SetFailState("[Chat Sounds] Sound list is empty");
	}
	
	delete kv_sounds;
	kv_sounds = null;
	
	return;
}

public Action OnChatMessage(int &client, Handle recipients, char[] name, char[] message)
{
	if(!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Handled;
	}
	if(message[0] != '.')
	{
		return Plugin_Handled;
	}	
	
	char buffer_sound_path[PLATFORM_MAX_PATH];
	float buffer_sound_volume;
	float pos[3];
	
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", pos);
	if(!soundstable.GetString(message, buffer_sound_path, sizeof(buffer_sound_path)))
	{
		if(snd_debug)
		{
			LogAction(-1, -1, "[Chat Sounds] Couldn't find the requested sound path.");
		}
		return Plugin_Handled;
	}
	if(!volumetable.GetValue(message, buffer_sound_volume))
	{
		if(snd_debug)
		{
			LogAction(-1, -1, "[Chat Sounds] Couldn't find volume parameters.");
		}
		return Plugin_Handled;
	}
	
	if(GetGameTime() <= client_delay[client])	//player is on cooldown
	{
		if(!snd_display)		//do we want to display the message
		{
			return Plugin_Stop;		//don't send the message
		}
		return Plugin_Handled;
	}
	
	client_delay[client] = GetGameTime() + cooldown_time; //sound exists and will be played so put the player on cooldown
	
	//EmitAmbientSoundAny(buffer_sound_path, pos, client, SNDLEVEL_NORMAL, SND_NOFLAGS, GetConVarFloat(h_Volume), SNDPITCH_NORMAL, 0.0);	//play the sound from the player
	EmitSoundToAll(buffer_sound_path, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, buffer_sound_volume * snd_volume, SNDPITCH_NORMAL);	//we will multiply the individual volume values by the global multiplier
	if(snd_debug)
	{
		char player[MAX_NAME_LENGTH];
		GetClientName(client, player, sizeof(player));
		LogAction(client, -1, "[Chat Sounds] %s has played a sound: %s", player, buffer_sound_path);
	}
	if(!snd_display)
	{
		return Plugin_Stop;
	}
	return Plugin_Handled;
}