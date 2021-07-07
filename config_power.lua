-- scripts/lua/config_power.lua
-- Configuration file for scripts/lua/script_device_power.lua
-- Written by Creasol, https://creasol.it linux@creasol.it
-- Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions
--   1. Send notification when consumed power is above a threshold (to avoid power outage)
--   2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid
--   3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored
--   4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
--      green LED flashes 1..M times if photovoltaic produces up to 1..M kWatt
--

DEBUG_LEVEL=E_WARNING
--DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="Power: "

PowerMeter='PowerMeter'			-- Device name for power/energy meter (negative value in case of exporting data. PowerMeter='' => use Import/Export devices below
--PowerMeter=''	-- uses PowerMeterImport and PowerMeterExport devices (defined below)
PowerMeterImport='PowerMeter Import'				-- Alternative devices to measure import and export energy, in case that two different devices are used. Set to '' if you have a powermeter that measure negative power in case of exporting
--PowerMeterImport=''
PowerMeterExport='PowerMeter Export'
--PowerMeterExport=''
ledsGreen={'Led_Cucina_Green'}	-- green LEDs that show power production
ledsRed={'Led_Cucina_Red'}		-- red LEDs that show power usage
ledsWhite={'Light_Night_Led','Led_Camera_White','Led_Camera_Ospiti_White','Led_Camera_Ospiti_WhiteLow'}	-- White LEDs that will be activated in case of blackout. List of devices configured as On/Off switches
ledsWhiteSelector={'Led_Cucina_White'}	-- White LEDs that will be activated in case of blackout. List of devices configured as Selector switches
blackoutDevice='Supply_HeatPump'	-- device used to monitor the 230V voltage. Off in case of power outage (blackout)

if (DEBUG_LEVEL>=E_DEBUG) then
	PowerThreshold={ --DEBUG values
		3000,  	-- available power (Italy: power+10%)
		2000,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		80,		-- send alert after 4800s (80minutes)
		60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
	}
else
	PowerThreshold={
		5400,  	-- available power (Italy: power+10%)
		6300,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		4800,	-- send alert after 4800s (80minutes)
		60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
	}
end

PowerMeterAlerts={	-- buzzer devices to be activated when usage power is very high and the script can't disable any load to reduce usage power
	--buzzer device   OFF_command  ON_command
--	{'Display_Lab_12V','Off','On'},
	{'Buzzer_Cucina','Off','On'},
}

-- devices that can be disconnected in case of overloading, specified in the right priority (the first device is the first to be disabled in case of overload)
overloadDisconnect={ -- syntax: device name, command to disable, command to enable
	{'HeatPump_FullPower','Off','On'},	-- heat pump, full power
	{'HeatPump_Fancoil','Off','On'},	-- heat pump, high temperature
	{'HeatPump','Off','On'},			-- heat pump (general)
	{'Irrigazione','Off','On'},			-- garden watering pump
	{'Kia eNiro - Socket','Off','On'},	-- electric car charging socket
}

-- list of electric vehicles
-- 3rd field is the battery level device name or variable name containing the battery charge level%: if not available, set to '' (will be set to 50%)
eVehicles={ -- on/off device, 	power	battery level % 						Min battery level			Max battery level
	{'Kia eNiro - Socket', 		1900,	'Kia eNiro - Battery state of charge', 	'Kia eNiro - Battery min', 'Kia eNiro - Battery max'},
}

DEVauxlist={
    -- max_work_minutes: used for driers or other devices that can work for maximum N minutes before an action must be taken (empty the water bolt, for example)
    -- minutes_before_stop: number of minutes to wait before stopping a device due to insufficient power (this is used to avoid continuous start/stop)
    -- device                   minwinterlevel  minsummerlevel  power   temphumdev winter   gt=1, lt=0  value   temphumdev summer   gt=1, lt=0  value   max_work_minutes minutes_before_stop
--  {'Dehumidifier_Camera',         1,          1,              300,    'RH_Camera',                1,  60,     'RH_Camera',                1,  60,     0}, -- Dehumidifier
    {'Dehumidifier_Camera_Ospiti',  1,          1,              300,    'RH_Camera_Ospiti',         1,  65,     'RH_Camera_Ospiti',         1,  60,     0}, -- Dehumidifier (disabled)
    {'Dehumidifier_Cantina',        1,          1,              500,    'RH_Cantina',               1,  60,     'RH_Cantina',               1,  60,     720},   -- Dehumidifier: stop after 480 minutes to avoid water overflow, and notify by telegram that dehumidifier is full
    {'Bagno_Scaldasalviette',       1,          100,            450,    'Temp_Bagno',               0,  22,     'Temp_Bagno',               0,  20,     0}, -- Electric heater in bathroom
    {'Pranzo_Stufetta',       		1,          100,            950,    'Temp_Cucina',              0,  22,     'Temp_Cucina',              0,  18,     0} -- Electric heater in the kitchen
}



