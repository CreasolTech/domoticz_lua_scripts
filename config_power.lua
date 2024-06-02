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

-- PLEASE NOTE THAT EVERY INPUT DEVICE MUST CONTAINS "Power" in its name!
PowerMeter='PowerMeter Grid'			-- Device name for power/energy meter (negative value in case of exporting data. PowerMeter='' => use Import/Export devices below
--PowerMeter=''	-- uses PowerMeterImport and PowerMeterExport devices (defined below)
PowerMeterImport='PowerMeter Import'				-- Alternative devices to measure import and export energy, in case that two different devices are used. Set to '' if you have a powermeter that measure negative power in case of exporting
--PowerMeterImport=''
PowerMeterExport='PowerMeter Export'
--PowerMeterExport=''
POWERMETER_GENS={'PV_PowerMeter', 'PV_Garden'}	-- list of devices measuring power from renewable plants (PV on the roof, PV on the garden, wind, ...)

-- The following 5 devices have to be created manually, and will be filled by the script
POWERMETER_USAGE='Power_Used'					-- Electric+Counter virtual device (to be created manually)
POWERMETER_PROD='Power_Produced'					-- Electric+Counter virtual device (to be created manually)
POWERMETER_SELF='Power_SelfConsumption'			-- Electric+Counter virtual device (to be created manually)
PERCENTAGE_SELF='Perc_SelfConsumption'			-- Percentage virtual device (to be created manually)
PERCENTAGE_SUFF='Perc_SelfSufficiency'			-- Percentage virtual device (to be created manually)

blackoutDevice='PowerSupply_HeatPump'			-- device used to monitor the 230V voltage. Off in case of power outage (blackout)
EVPowerMeter='EV Energy'	-- Device measuring EV charging power, if available
--DOMBUSEVSE_GRIDPOWER={'dombus2 - (ffe3.c) Grid Power'}	-- Virtual device on DomBusEVSE to send current grid power measured by another energy meter not directly connected to DomBusEVSE
--DOMBUSEVSE_GRIDPOWER={'Grid Power'}	-- Virtual devices on DomBusEVSE to send current grid power measured by another energy meter not directly connected to DomBusEVSE
DOMBUSEVSE_GRIDPOWER={'Grid Power','dombus2 - (ffe3.c) Grid Power'}	-- Virtual devices on DomBusEVSE to send current grid power measured by another energy meter not directly connected to DomBusEVSE

-- Hoymiles inverter using OpenDTU monitoring device: automatically update the output power limit to get a Grid power corresponding to the specified HOYMILES_TARGET_POWER
-- In this example, I can export max 6000W and have two inverters connected to my house. Hoymiles inverter (1600W, in my case) will limit the production power to export max 6000W to the grid
HOYMILES_ID='solar/116493522530/cmd/limit_nonpersistent_absolute'	-- MQTT name to set the output power limit using OpenDTU. '' to disable this function
--HOYMILES_ID=''	-- MQTT name to set the output power limit using OpenDTU. '' to disable this function
HOYMILES_LIMIT_MAX=1600		-- Max power in watt
HOYMILES_TARGET_POWER=-6000		-- Target Power: 0 => no export. 50=import always at least 50W. -300=try to export always 300W
HOYMILES_VOLTAGE_DEV='PVGarden_Voltage'
HOYMILES_LIMIT_PERC_DEV='PVGarden_Limit'
HOYMILES_PRODUCING_DEV='PVGarden_InverterProducing'
HOYMILES_RESTART_DEV='PVGarden_RestartInverter'

-- Output device: use any name of your choice
ledsGreen={'Led_Cucina_Green','Living_Led_Green','BagnoPT_LedG'}	-- green LEDs that show power production
-- ledsRed={'Led_Cucina_Red','Living_Led_Red','BagnoPT_LedR' }		-- red LEDs that show power usage
ledsRed={'Led_Cucina_Red','BagnoPT_LedR' }		-- red LEDs that show power usage
ledsWhite={'Living_Led_White','Light_Night_Led','Led_Camera_White','Led_Camera_Ospiti_White','Led_Camera_Ospiti_WhiteLow'}	-- White LEDs that will be activated in case of blackout. List of devices configured as On/Off switches
ledsWhiteSelector={'Led_Cucina_White','BagnoPT_LedW'}		-- White LEDs that will be activated in case of blackout. List of devices configured as Selector switches
blackoutBuzzers={'Buzzer_Camera'}			-- Audio alert in case of power outage
HPMode='HeatPump_Mode'              		-- Selector switch for Off, Winter (heating), Summer (cooling) 

EVLedStatus={''}				-- status indicator for the electric car charging (1 flash => more than 1kW, 2 flashes => more than 2kW, ...}
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
	{'Irrigazione','Off FOR 30 MINUTES','On'},			-- garden watering pump
	{'KEV Mode','Off','Solar'},	-- electric car charging socket
}

-- list of electric vehicles
-- 3rd field is the battery level device name or variable name containing the battery charge level%: if not available, set to '' (will be set to 50%)
-- 4th and 5th fields refers to virtual selector switches (to be added manually) configured with some battery levels, e.g. Off, 25, 50, 80, 90, 100 (%)
--   These selector switches will be used to set the min battery level (if battery state is below, charge EV anyway) and max battery level 
--   (if battery state of charge between min and max level, charge only using energy from photovoltaic)
eVehicles={ 
	-- on/off device, 	power	battery level % 		Min battery level			Max battery level			DistanceDev				SpeedDev			Charge mode pushbutton		Charging mode 				Range
	-- Please note that pushbutton and chargingMode device names must contain the "Power" word
	-- {'Kia eNiro - Contactor', 	2500,	'Kia eNiro - Battery', 	'Kia eNiro - Battery min', 'Kia eNiro - Battery max', 'Kia eNiro - Distance', 'Kia eNiro - Speed', 'Kia eNiro - PowerButton charge', 'Kia eNiro - PowerCharging mode', 'Kia eNiro - Range'},
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

EVSE_CURRENT_DEV='EVSE Current'		-- device used to set the charging current. Set to '' to disable EVSE management
EVSE_STATE_DEV='EVSE State'			-- EVSE status: Disconnected, Connected, Charging, ....
EVSE_MAXCURRENTVALUE=32				
EVSE_SOC_DEV='Kia - eNiro EV battery level'	-- device that show the battery state of charge (e.g. 65%). Set to '' to disable this checking
EVSE_SOC_MIN='EVSE BatteryMin'		-- virtual device (dimmer) that set the min battery level
EVSE_SOC_MAX='EVSE BatteryMax'		-- virtual device (dimmer) that set the max battery level
EVSE_CURRENTMAX='EVSE CurrentMax'	-- virtual device (selector switch) setting the max current
EVSE_NIGHT_START=23					-- hour when low-cost tariff for energy starts (or when energy consumption decreases, in the night)
EVSE_NIGHT_STOP=7					-- hour when low-cost tariff for energy stops (or when energy consumption increase in the morning)
EVSE_POWERMETER='EVSE Charge Power'	-- Device measuring EV charging power, if available
EVSE_POWERIMPORT='PowerMeter Import'			-- Device measuring import power from GRID
EVSE_RENEWABLE='EVSE GreenPower'	-- virtual device (electricity meter, return, from device) measuring the power/energy used to charge car that come from renewable source
EVSE_RENEWABLE_PERCENTAGE='EVSE Green/Total'	-- virtual device (percentage) measuring the renewable/charging power percentage
EVSE_BUTTON='EVSE Button'						-- UP/DOWN twin button on DomBusEVSE module (or external, connected to IO4)
EVSE_MENU='EVSE Menu'							-- MENU UP/DOWN twin button on DomBusEVSE module (or external, connected to IO5)

DEVauxlist={
	-- loads that can be activated when extra power from renewable are available. This list is evaluated every minute
    -- max_work_minutes: used for driers or other devices that can work for maximum N minutes before an action must be taken (empty the water bolt, for example)
    -- minutes_before_stop: number of minutes to wait before stopping a device due to insufficient power (this is used to avoid continuous start/stop)
    -- device                   minwinterlevel  minsummerlevel  power   condition_to_enable		condition_to_disable, work_minutes 
    {'Dehumidifier_Camera_Ospiti',  0,          0,              300,    'tonumber(uservariables["alarmLevel"])<=1 and tonumber(otherdevices["RH_Camera_Ospiti"])>=70', 'tonumber(uservariables["alarmLevel"])>1 or tonumber(otherdevices["RH_Camera_Ospiti"])<=65', 0}, -- Dehumidifier 
    {'Dehumidifier_Cantina',        0,          0,              500,    'tonumber(uservariables["alarmLevel"])<=1 and tonumber(otherdevices["RH_Cantina"])>=70 and timeNow.hour>=12 and timeNow.hour<=15', 'tonumber(uservariables["alarmLevel"])>1 or tonumber(otherdevices["RH_Cantina"])<=65', 600},   -- Dehumidifier: stop after 480 minutes to avoid water overflow, and notify by telegram that dehumidifier is full
--    {'Bagno_Scaldasalviette',       1,          100,            450,    'Temp_Bagno',               0,  22,     'Temp_Bagno',               0,  20,     0, '', ''} -- Electric heater in bathroom
}

DEVauxfastlist={
	-- fast loads, that can be activated/disactivated quickly, e.g. electric heaters during the winter
    -- device                   minwinterlevel  minsummerlevel  power   temphumdev winter   gt=1, lt=0  value   temphumdev summer   gt=1, lt=0  value   0 condition_on condition_off
    --{'Pranzo_Stufetta',       		0,          100,            950,    'Temp_Cucina',              0,  22.2,     'Temp_Cucina',              0,  18,     0, 'otherdevices["EV Mode"]=="Off" or otherdevices["EV State"]=="Dis"', 'otherdevices["EV Mode"]~="Off" and otherdevices["EV State"]=="Ch"'} -- Electric heater in the kitchen
}


