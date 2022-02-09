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

DEBUG_LEVEL=E_INFO
--DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="Power: "

PowerMeter='PowerMeter'			-- Device name for power/energy meter (negative value in case of exporting data. PowerMeter='' => use Import/Export devices below
--PowerMeter=''	-- uses PowerMeterImport and PowerMeterExport devices (defined below)
PowerMeterImport='PowerMeter Import'				-- Alternative devices to measure import and export energy, in case that two different devices are used. Set to '' if you have a powermeter that measure negative power in case of exporting
--PowerMeterImport=''
PowerMeterExport='PowerMeter Export'
--PowerMeterExport=''
ledsGreen={'Led_Cucina_Green', 'Led_EV_Green'}	-- green LEDs that show power production
ledsRed={'Led_Cucina_Red', 'Led_EV_Red'}		-- red LEDs that show power usage
ledsWhite={'Light_Night_Led','Led_Camera_White','Led_Camera_Ospiti_White','Led_Camera_Ospiti_WhiteLow', 'Led_EV_White'}	-- White LEDs that will be activated in case of blackout. List of devices configured as On/Off switches
ledsWhiteSelector={'Led_Cucina_White'}		-- White LEDs that will be activated in case of blackout. List of devices configured as Selector switches
blackoutDevice='Supply_HeatPump'			-- device used to monitor the 230V voltage. Off in case of power outage (blackout)
HPMode='HeatPump_Mode'              		-- Selector switch for Off, Winter (heating), Summer (cooling) 

EVPowerMeter='Kia eNiro - Charging Power'	-- Device measuring EV charging power, if available
EVLedStatus={'EVSE_LedPower'}				-- status indicator for the electric car charging (1 flash => more than 1kW, 2 flashes => more than 2kW, ...}
PowerThreshold={
	5500,  	-- available power (Italy: power+10%)
	6350,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
	4800,	-- send alert after 4800s (80minutes) . Imported power can stay at TH[2] for 90min, then must be below TH[1] for at least 90 minutes
	60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s)
}
--[[	-- DEBUG: reduce power and time threshold to test script
PowerThreshold={ --DEBUG values
	4000,  	-- available power (Italy: power+10%)
	5000,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
	80,		-- send alert after 4800s (80minutes)
	60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
}
]]

PowerMeterAlerts={	-- buzzer devices to be activated when usage power is very high and the script can't disable any load to reduce usage power
	--buzzer device   OFF_command  ON_command
--	{'Display_Lab_12V','Off','On'},
	{'Buzzer_Cucina','Off','On'},
}

-- devices that can be disconnected in case of overloading, specified in the right priority (the first device is the first to be disabled in case of overload)
overloadDisconnect={ -- syntax: device name, command to disable, command to enable
	{'HeatPump_HalfPower','On','Off'},	-- heat pump: Off => full power, On => half power
	{'HeatPump_Fancoil','Off','On'},	-- heat pump, high temperature
	{'HeatPump','Off','On'},			-- heat pump (general)
	{'Irrigazione','Off','On'},			-- garden watering pump
	{'Kia eNiro - Contactor','Off','On'},	-- electric car charging socket
}

-- list of electric vehicles
-- 3rd field is the battery level device name or variable name containing the battery charge level%: if not available, set to '' (will be set to 50%)
-- 4th and 5th fields refers to virtual selector switches (to be added manually) configured with some battery levels, e.g. Off, 25, 50, 80, 90, 100 (%)
--   These selector switches will be used to set the min battery level (if battery state is below, charge EV anyway) and max battery level 
--   (if battery state of charge between min and max level, charge only using energy from photovoltaic)
eVehicles={ -- on/off device, 	power	battery level % 		Min battery level			Max battery level			DistanceDev				SpeedDev			Charge mode pushbutton		Charging mode 				Range
	-- {'Kia eNiro - Contactor', 	2500,	'Kia eNiro - Battery', 	'Kia eNiro - Battery min', 'Kia eNiro - Battery max', 'Kia eNiro - Distance', 'Kia eNiro - Speed', 'Kia eNiro - Button charge', 'Kia eNiro - Charging mode', 'Kia eNiro - Range'},
}


EVChargingModeNames={'Off', 'Min0', 'Min50', 'Min50_Max100', 'On'}
EVChargingModeConf={
	-- MinLevel, value,	MaxLevel, value
	-- MinLevel: 0=0%, 10=50%, 20=65%, 30=80%, 40=90%, 50=100%
	-- MaxLevel: 0=0%, 10=60%, 20=70%, 30=80%, 40=90%, 50=100%
	{	0, 	0,		0, 	0	},
	{	0, 	0,		30, 80	},
	{	10,	50, 	30,	80	},
	{	10,	50, 	50, 100	},
	{	50,	100,	50, 100	},
}

EVSE_CURRENT_DEV='EVSE_current'		-- device used to set the charging current. Set to '' to disable EVSE management
EVSE_STATE_DEV='EVSE_state'			-- EVSE status: Disconnected, Connected, Charging, ....
EVSE_MAXCURRENTVALUE=32				
EVSE_SOC_DEV='Kia eNiro - Battery'	-- device that show the battery state of charge (e.g. 65%). Set to '' to disable this checking
EVSE_SOC_MIN='EVSE_batteryMin'		-- virtual device (dimmer) that set the min battery level
EVSE_SOC_MAX='EVSE_batteryMax'		-- virtual device (dimmer) that set the max battery level
EVSE_CURRENTMAX='EVSE_currentMax'	-- virtual device (selector switch) setting the max current
EVSE_NIGHT_START=23					-- hour when low-cost tariff for energy starts (or when energy consumption decreases, in the night)
EVSE_NIGHT_STOP=7					-- hour when low-cost tariff for energy stops (or when energy consumption increase in the morning)
EVSE_POWERMETER='Kia eNiro - Charging Power'	-- Device measuring EV charging power, if available
EVSE_POWERIMPORT='PowerMeter Import'			-- Device measuring import power from GRID
EVSE_RENEWABLE='EVSE_greenPower'	-- virtual device (electricity meter, return, from device) measuring the power/energy used to charge car that come from renewable source


DEVauxlist={
	-- loads that can be activated when extra power from renewable are available. This list is evaluated every minute
    -- max_work_minutes: used for driers or other devices that can work for maximum N minutes before an action must be taken (empty the water bolt, for example)
    -- minutes_before_stop: number of minutes to wait before stopping a device due to insufficient power (this is used to avoid continuous start/stop)
    -- device                   minwinterlevel  minsummerlevel  power   temphumdev winter   gt=1, lt=0  value   temphumdev summer   gt=1, lt=0  value   max_work_minutes condition_on condition_off
--  {'Dehumidifier_Camera',         1,          1,              300,    'RH_Camera',                1,  60,     'RH_Camera',                1,  60,     0}, -- Dehumidifier
    {'Dehumidifier_Camera_Ospiti',  1,          1,              300,    'RH_Camera_Ospiti',         1,  65,     'RH_Camera_Ospiti',         1,  65,     0, '', ''}, -- Dehumidifier (disabled)
    {'Dehumidifier_Cantina',        1,          1,              500,    'RH_Cantina',               1,  65,     'RH_Cantina',               1,  65,     720, 'tonumber(uservariables["alarmLevel"])<=1', 'tonumber(uservariables["alarmLevel"])>1'},   -- Dehumidifier: stop after 480 minutes to avoid water overflow, and notify by telegram that dehumidifier is full
    {'Bagno_Scaldasalviette',       1,          100,            450,    'Temp_Bagno',               0,  22,     'Temp_Bagno',               0,  20,     0, '', ''} -- Electric heater in bathroom
}

DEVauxfastlist={
	-- fast loads, that can be activated/disactivated quickly, e.g. electric heaters during the winter
    -- device                   minwinterlevel  minsummerlevel  power   temphumdev winter   gt=1, lt=0  value   temphumdev summer   gt=1, lt=0  value   0 condition_on condition_off
    {'Pranzo_Stufetta',       		0,          100,            950,    'Temp_Cucina',              0,  24,     'Temp_Cucina',              0,  18,     0, '', ''} -- Electric heater in the kitchen
}


