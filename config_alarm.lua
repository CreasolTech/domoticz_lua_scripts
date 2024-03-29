
-- scripts/lua/alarm_config.lua - Configuration file for alarm scripts
-- Written by Creasol, https://creasol.it/products
--
dofile "/home/pi/domoticz/scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "/home/pi/domoticz/scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

-- Some constants: DON'T MODIFY
-- bitmask associated to alarmLevel: don't care
ALARM_OFF=1
ALARM_DAY=2
ALARM_NIGHT=4
ALARM_AWAY=8
ALARM_TEST=16

-- alarmStatus: don't care
STATUS_OK=0
STATUS_PREDELAY=1
STATUS_ALARM=2

-- telegram and debug msg level: don't care
E_NONE=0		-- log nothing
E_ERROR=1		-- log only errors
E_WARNING=2		-- log errors + warnings
E_INFO=3		-- log errors + warnings + info
E_DEBUG=4		-- log everything

-- DEBUG LEVEL on LOGS and TELEGRAM notifications
DEBUG_LEVEL=E_DEBUG			-- 0 => log nothing, 1=> log alarms, 2=> more log, notify to telegram private chat.. 4=>DEBUG
TELEGRAM_LEVEL=E_WARNING 	-- 1=LOG only errors/activations 2=Log warnings 
DEBUG_PREFIX=''

-- =================== Next table of variables MUST BE MODIFIED TO MATCH YOUR CONFIGURATION AND PREFERENCES ==============================
--
-- ALARMlist is a bit difficult to configure: for any type of alarm (Day, Night, Away, ...) set which PIRs and MCS sensors should be enabled  
-- For example:
-- PIRlist={
--   {'PIR_Garage',15},		-- bitmask: 0x01  (binary 0b00000001)
--   {'PIR_Kitchen',15},	-- bitmask: 0x02  (binary 0b00000010)
--   {'PIR_Living',15},		-- bitmask: 0x04  (binary 0b00000100)
--   {'PIR_Stairway',15},	-- bitmask: 0x08  (binary 0b00001000)
--   {'PIR_Bedroom',15},	-- bitmask: 0x10  (binary 0b00010000)
-- }
--
-- ALARM OFF => no PIRs enabled => 0x00000000
-- ALARM Day => only Garage PIR is enabled => 0x00000001. To enable PIR_Garage (0x01) PIR_Stairway (0x08) and PIR_Bedroom (0x10) sum these items 
--              (use an hex calculator) and write the result (0x00000019) in (ALARM Day,PIRs en) position
-- ALARM Night => Garage+Kitchen+Living+Stairway enabled => 1+2+4+8=15 => 0x0f in hex => 0x0000000f
-- ALARM Away => All PIRs enabled => 0xffffffff or 0x0000001f if only 5 pirs are installed
-- 
ALARMlist={
-- AlarmLevel: Name, 			Tampers	    PIRs en.   	MCS1 en.    MCS2 en.  
	[0x01]={'ALARM OFF',		0xffffffff, 0x00000000, 0x00000000, 0x00000000},	-- Tampers: all enabled; PIRS: all disabled; MCS: all disabled
	[0x02]={'ALARM Day',		0xffffffff, 0x00000003, 0xffffffff, 0xffffffff}, 	-- Only PIR1 and PIR2 enabled, all MCS enabled
	[0x04]={'ALARM Night',		0xffffffff, 0x00000001,	0xffffffff, 0xffffffff}, 	-- Only PIR1 enabled, all MCS enabled
	[0x08]={'ALARM Away',  		0xffffffff, 0x00000001, 0xffffffff, 0xffffffff},	-- Only PIR1 enabled, all MCS enabled
	[0x10]={'ALARM Test',  		0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff},	-- All PIRs and MCSs are enabled
}


-- List of magnetic contact sensors (window/door + associated shutter/blind)
-- Magnetic sensors name must start with MCS prefix
-- If the associated blind or window/door is missing, write ''
MCSlist={ -- MCS_window/door, 	MCS_shutter, 	delay[s]
    	{'MCS_Kitchen_Window1','MCS_Kitchen_Blind1',0,},	--00000001
    	{'MCS_Kitchen_Window2','MCS_Kitchen_Blind2',0,},	--00000002
    	{'MCS_Kitchen_Window3','MCS_Kitchen_Blind3',0,},	--00000004
    	{'MCS_Kitchen_Door','',10},							-- in case of alarm, "delayed sirens" must be activated after 15s (delay) --0008
		{'MCS_Living_Window1','MCS_Living_Blind1',0},		--00000010	-- finestra1 non collegato
		{'MCS_Living_Window2','MCS_Living_Blind2',0},		--00000020	-- finestra2 non collegato
    	{'MCS_Pranzo_Window1','MCS_Pranzo_Blind1',0},		--00000040
    	{'MCS_Pranzo_Window2','MCS_Pranzo_Blind2',0},		--00000080
    	{'MCS_Pranzo_Window3','MCS_Pranzo_Blind3',0},		--00000100
		{'MCS_Sud_Door','MCS_Sud_Scuro',0},					--00000200
		{'MCS_Lab_Window_Sud','MCS_Lab_Blind_Sud',0},		--00000400
		{'MCS_Lab_Window_Nord','MCS_Lab_Blind_Nord',0},		--00000800
		{'MCS_BagnoPT_Window','MCS_BagnoPT_Blind',0},		--00001000
		{'MCS_Magazzino_Window_Sud','MCS_Magazzino_Blind_Sud',0},	--00002000
		{'MCS_Magazzino_Window_Nord','MCS_Magazzino_Blind_Nord',0},	--00004000
		{'MCS_Garage_Door_Magazzino','',0},							--00008000
		{'MCS_Garage_Door_Pranzo','',0},					--00010000
		{'','MCS_Scale_Blind',0},							--00020000
		{'MCS_Notte_Scorrevole','',0},						--00040000
		{'MCS_Bedroom_Door','',0},							--00080000
		{'MCS_Bedroom_Window1','MCS_Bedroom_Blind1',0},		--00100000
		{'MCS_Bedroom_Window2','MCS_Bedroom_Blind2',0},		--00200000
		{'MCS_Bedroom_Window3','MCS_Bedroom_Blind3',0},		--00400000
		{'','MCS_Stireria_Scuri',0},						--00800000
		{'','MCS_BagnoP1_Blind',0},							--01000000
		{'','MCS_Bedroom_Ospiti_Scuri',0},					--02000000
		{'','MCS_Bedroom_Valentina_Blind1',0},				--04000000
		{'','MCS_Bedroom_Valentina_Blind2',0},				--08000000
}



--PIR sensors name must start with PIR prefix
-- List of PIRs enabled when somebody is at home
PIRlist={
	-- Name, Delay before activating external sirens
	{'PIR_Garage',15},
	{'PIR_SudEst',15},
	{'PIR_GarageVerde',15},
}

-- Tampers name must start with TAMPER prefix
TAMPERlist={ -- device_name
	{'TAMPER_Kitchen_Finestre'},
	{'TAMPER_Kitchen_Living_Scuri'},
	{'TAMPER_Sud'},
	{'TAMPER_PT_Est'},
	{'TAMPER_P1_Est'},
	{'TAMPER_Camere11'},
	{'TAMPER_Camere12'},
}


SIRENlist={ -- output_device, 	alarmLevel, 				delayed, duration[min]  -- delayed should be 1 for sirens that should start after 10-15s delay in case of alarm activation by MCS of a door
	{'SIREN_External',	ALARM_AWAY,				1,	5},
	{'SIREN_Internal',	ALARM_DAY+ALARM_NIGHT+ALARM_AWAY,	0,	5},
	{'SIREN_Internal_d',	ALARM_DAY+ALARM_NIGHT+ALARM_AWAY,	0,	5},
	{'Light_Bedroom',	ALARM_NIGHT+ALARM_AWAY,			0,	5},
	{'Light_Scale',		ALARM_NIGHT+ALARM_AWAY,			0,	5},
}  -- REMEMBER TO CONFIGURE THE LIST of IDX associated to the sirens on alarmSet.sh : this is needed to switch off sirens setting alarmLevel to OFF

ALARM_OTHERlist={	
	-- other devices. Syntax: 
	-- devicename, 			alarm_level (255 for any alarmLevel), sensor_value1, notification1, 				sensor_value2, notification2 
	{ 'ALARM_Supply_Raspberry',255,									'Off',	'PowerSupply to Raspberry is OFF',	'On','PowerSupply to Raspberry restored' },
}

ALARM_Lights={
	-- light that are automatically switched ON/OFF when ALARM_AWAY, in the right sequence 1-> 2 -> 3 -> 2 -> 1 -> 2 -> 3 ....
	-- light dev,   	min duration[s],	max duration	min/max delay before switching next ON
	{'Light_Living',	20,			2700,		4,	7},
	{'Light_Stairway'	12,			25,			-2,	2},
	{'Light_Bedroom',	20,			900,		0,	0},
}

-- Leds activated for few seconds when alarm has been activated
LEDS_ON={'Led_Bedroom1_Red','Led_Bedroom2_Red'}
-- Leds activated for few seconds when alarm has been disactivated
LEDS_OFF={'LEd_Bedroom1_Green','Led_Bedroom2_Green'}
