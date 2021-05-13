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
--DEBUG_LEVEL=E_DEBUG  -- uncomment to get verbose log
DEBUG_PREFIX="Power: "

--PowerMeter='PowerMeter'			-- Device name for power/energy meter (negative value in case of exporting data. PowerMeter='' => use Import/Export devices below
PowerMeter=''	-- '' => uses PowerMeterImport and PowerMeterExport devices (defined below)
PowerMeterImport='PowerMeter Import'				-- Alternative devices to measure import and export energy, in case that two different devices are used. Set to '' if you have a powermeter that measure negative power in case of exporting
--PowerMeterImport=''
PowerMeterExport='PowerMeter Export'
--PowerMeterExport=''

-- Leds that show current import (red) or export (green) power in kW-1
ledsGreen={'Led_Cucina_Green'}	-- green LEDs that show power production
ledsRed={'Led_Cucina_Red'}		-- red LEDs that show power usage

-- Leds that are activated in case of power outage
ledsWhite={'Light_Night_Led','Led_Camera_White','Led_Camera_Ospiti_White','Led_Camera_Ospiti_WhiteLow'}	-- White LEDs that will be activated in case of blackout. List of devices configured as On/Off switches

-- Leds that must be restored as selector (instead of On/Off device) when grid power returns.
ledsWhiteSelector={'Led_Cucina_White'}	-- White LEDs that will be activated in case of blackout. List of devices configured as Selector switches

-- Device used to know the power outage state
blackoutDevice='Supply_HeatPump'	-- device used to monitor the 230V voltage. Off in case of power outage (blackout)

-- Thresholds used to avoid power disconnect in case of high power consumption
if (DEBUG_LEVEL>=E_DEBUG) then
	PowerThreshold={ --DEBUG values
		3000,  	-- available power (Italy: power+10%)
		2000,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		80,		-- send alert after 80s 
		60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
	}
else
	PowerThreshold={
		-- In Italy, with 5kW meter, it's possible to get 5kW +10% forever, 5kW + 27% for 80 minutes, and above this threshold only 2 minutes before disconnect
		5400,  	-- available power (Italy: power+10%)
		6300,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		4800,	-- send alert after 4800s (80minutes) (energy meter will disconnect after 90 minutes)
		20		-- above threshold, send notification after 20 seconds (or the energy meter will disconnect in 120s)
	}
end

PowerMeterAlerts={	-- buzzer devices to be activated when usage power is very high and the script can't disable any load to reduce usage power
	--buzzer device   OFF_command  ON_command
--	{'Display_Lab_12V','Off','On'},
	{'Buzzer_Kitchen','Off','On'},
}

-- devices that can be disconnected in case of overloading, specified in the right priority (the first device is the first to be disabled in case of overload)
overloadDisconnect={ -- syntax: device name, command to disable, command to enable
	{'HeatPump_FullPower','Off','On'},	-- heat pump, full power
	{'HeatPump_Fancoil','Off','On'},	-- heat pump, high temperature
	{'HeatPump','Off','On'},			-- heat pump (general)
	{'IrrigationPump','Off','On'},		-- garden watering pump
	{'Kia eNiro - Socket','Off','On'},  -- electric car charging socket
}

Heaters={	-- from the highest priority to the lowest priority
	-- device name , 	power , 1 if should be enabled automatically when renewable sources produce more than secified power or 0 if this is just used to disconnect load preventing power outage, temperature device, max temperature
	{'Living_Heater',	950,	1,'Temp_Living',22.5},		-- 1000W heater connected to DomBusTH+DomRelay2
--	{'Bathroom_Heater',	450,	1,'Temp_Bathroom',22},	-- 450W heater connected to DOMBUS1
}


