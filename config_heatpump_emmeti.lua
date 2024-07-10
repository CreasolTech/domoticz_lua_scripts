-- scripts/lua/config_heatingpump.lua - Configuration file for heating pump heater/cooler system
-- Written by Creasol, https://creasol.it - linux@creasol.it
--

dofile "scripts/lua/globalvariables.lua"	-- some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"	-- some functions common to all scripts

-- Some constants
TEMP_HISTERESIS=0.1
TEMP_WINTER_HP_MAX=48 				-- maximum fluid temperature from HP during the Winter
TEMP_SUMMER_HP_MIN=14				-- minimum fluid temperature from HP during the Summer
OVERHEAT=0.5						-- Increase temperature setpoint in case of available power from solar photovoltaic
OVERCOOL=-0.2						-- Decrease temperature setpoint in case of available power from solar photovoltaic
POWER_MAX=5500						-- Increment heat pump level only if consumed power is less than POWER_MAX
EVPOWER_DEV='EV Energy'
EVSTATE_DEV="EV State"      		-- EV state, used to know if vehicle is in charging state or not: "Dis", "Con", "Ch"


--GasHeater='GasHeater'				-- Activate gas heater instead of heat pump when external temperature very low: set to '' if a boiler does not exist
GasHeater=''		-- it's not cheaper not greener than PDC => manually enabled only if PDC is not able to keep the temperature
GRID_VOLTAGE='Inverter - AC Voltage'	-- Device measuring house voltage: if above 248V, heatpump can consume all available power
powerMeter='PowerMeter Grid'	-- device name of power meter, that measure consumed power from the electric grid (negative when photovoltaic produced more than house usage)
inverterMeter='PV_PowerMeter'	-- Inverter output power (photovoltaic). Set to '' if not available
inverter2Meter='PV_Garden'		-- Inverter for the 2nd renewable energy source. Set to '' if not available
heatpumpMeter='PowerMeter HeatPump'	-- power meter that supply the heat pump ('' if not used)
TEMPHPOUT_DEV='Temp_HeatPumpFluidOut' 	-- Temperature of water produced by heat pump (before entering coils or underfloor radiant system)
TEMPHPIN_DEV= 'Temp_HeatPumpFluidIn'	-- Temperature of water that exits from coils and/or underfloor radiant system, and gets into the Heat Pump again
tempOutdoor='Meteo outdoor'			-- Temperature outdoor, or meteo sensor ("temp;humidity;pression;0")
HPOn='HeatPump'						-- Device that enable/disable the heat pump (thermostat input?)
HPSummer='HeatPump_Summer'			-- Device to set if HP must cooling instead of heating
HPMode='HeatPump_Mode'				-- Selector switch for Off, Winter, Summer
HPLevel='HeatPump_Level'			-- Selector switch to force a specific power level: Off, 1, 2, 3, ... Auto
HPStatus='HeatPump_Status'			-- Virtual text device, where to write status data
HPStatusIDX=1723					-- IDX of the virtual text device HPStatus
HPStatus2IDX=2370                   -- IDX of the virtual text device used in Energy Dashboard
HPCompressor='HeatPump - Compressor max'	-- Device that set the max compressor level (0-100%)
HPCompressorNow='HeatPump - Compressor now'	-- Device that set the max compressor level (0-100%)
HPTempOutlet='HeatPump - Temp. outlet'	-- Outlet temperature
HPTempOutletComputed='HeatPump - Temp. outlet computed'	-- Setpoint for the output temperature
HPTempWinterMin='HeatPump - Temp min outlet Winter'	-- Device to set minimum outlet temperature for Winter (35°C)
HPTempWinterMinIDX=2045
HPTempWinterMax='HeatPump - Temp max outlet Winter'	-- Device to set maximum outlet temperature for Winter (40°C)
HPTempWinterMaxIDX=2046
HPTempSummerMin='HeatPump - Temp min outlet Summer'	-- Device to set minimum outlet temperature for Summer (15°C)
HPTempSummerMinIDX=2047
HPTempSummerMax='HeatPump - Temp max outlet Summer'	-- Device to set maximum outlet temperature for Summer (17°C)
HPTempSummerMaxIDX=2048

-- fields for the following table
ZONE_NAME=1
ZONE_TEMP_DEV=2
ZONE_RH_DEV=3
ZONE_VALVE=4
ZONE_WINTER_START=5
ZONE_WINTER_STOP=6
ZONE_WINTER_OFFSET=7
ZONE_WINTER_WEIGHT=8
ZONE_SUMMER_START=9
ZONE_SUMMER_STOP=10
ZONE_SUMMER_OFFSET=11
ZONE_SUMMER_WEIGHT=12

-- heat pump working level
LEVEL_OFF=0					-- heat pump is completely OFF
LEVEL_ON=1					-- On, half power


DEVlist={
	-- deviceName=name of each device involved in heating/cooling
	-- winterLevel=heating level (0=OFF, 1=LOW, 2=MEDIUM, 3=HIGH)
	-- summerLevel=cooling level (0=OFF, 1=LOW, 2=MEDIUM, 3=HIGH, 4=VERY HIGH)
	-- First device MUST be the heat pump ON/OFF
	-- *Level=10 or any value >=LEVEL_*_MAX+1 => always set OFF
	-- *Level=255 => ignore
	--'deviceName',				winterLevel,		summerLevel
	--							start stop			start	stop
	{'HeatPump',				1, 		255,		1, 		255	},	-- HeatPump input ON/OFF (thermostat input)
	{'HeatPump_HalfPower',		1,		2,			1, 		2	},	-- HeatPump input HalfPower (if On, works at 50% of nominal power)
	{'HeatPump_Fancoil',		255,	255,		255,	255	},	-- HeatPump input Fancoil (set point for the fluid temperature: Off=use radiant, On=use coil with extreme temperatures
	{'HeatPump_Summer',			255,	255,		1,		255	},	-- HeatPump input Summer (if On, the heat pump produce cold fluid) -- LEVEL_WINTER_MAX+1 => Always OFF
--	{'VMC_CaldoFreddo',			255,	255,		1,		255	},	-- Ventilation input coil: if On, the coil supplied by heat pump is enabled (to heat/cool air)
	{'VMC_Deumidificazione',	255,	255,		255,	255	},	-- Ventilation input dryer: if On, the internal ciller is turned on to dehumidify air
}

HP_ON='HeatPump'				-- device corresponding to heatpump on/off

zones={ 
	-- start and stop indicates the comport period (hour of the day) when temperature must be equal to the setpoint
	-- offset is the max tolerated difference from set temperature outside the comfort period
	-- weight is used to set the importance of temperature in each rooms. 1=very important, 0.5 means that temperature can be a bit different from the set point, 0=ignore temperature in this room. If weight is less than 1, it's tolerated a greater offset in case there is not enough energy from renewable (photovoltaic)
	--
	-- for example:   				                            		<---------- Winter -------->  <---------- Summer ----------> 
	-- zone name		temp device_name	Rel.Hum device		valve	start	stop	offset	weight  start	stop	offset	weight  
	-- ['Cucina']={		'Temp_Cucina',		'RH_Cucina',		'',		5,		22,		0.2,	1,		7,		23,		0.2,	1},	
	-- Zone name is "Cucina" (kitchen)
	-- Temperature sensor is "Temp_Cucina"
	-- RH sensor is "RH_Cucina"
	-- No electrovalve for this room (always enabled)
	-- During the winter, keep the setpoint from 5:00 to 22:00 (comfort period), and keep setpoint-0.2 (offset) outside the comfort period. This zone is really important, so weight=1
	-- During the summer, keep setpoin from 7:00 to 23:00, then temperature can raise to setpoint+0.2. Weight is 1 (important zone)
	--
	--            						                                                  <---------- Winter -------->  <---------- Summer ----------> 
	-- zone name		temp device_name	Rel.Hum device		valve					start	stop	offset	weight  start	stop	offset	weight  
	{'Cucina',			'Temp_Cucina',		'RH_Cucina',		'',						4,		20,		-0.2,		1,		7,		23,		0.2,	1},	
	{'Studio',			'Temp_Studio',		'',                 '',						9,		18,		-0.2,		0.2,	8,		19,		0.5,	0.8},
	{'Bagno',			'Temp_Bagno', 		'',                 'Valve_Bagno',			11,		21,		-1,		0.3,	16,		19,		1,		0.5},
	{'Camera',			'Temp_Camera', 		'RH_Camera',        'Valve_Camera',			13,		22,		-0.6,	0.5,	10,		23,		0.5,	0.8},	
	{'Camera_Valentina','Temp_Camera_Valentina','',           'Valve_Camera_Valentina',	13,		22,		-0.8,	0.3,	13,		23,		0.5,	0.8},	
	{'Camera_Ospiti',	'Temp_Camera_Ospiti','',                'Valve_Camera_Ospiti',	13,		22,		-0.8,	0.3,	13,		23,		0.5,	0.3},
	{'Stireria',		'Temp_Stireria',	'',                 'Valve_Stireria',		13,		18,		-1,		0.3,	8,		20,		1,		0.3},
}


-- Temperature device for a zone that is always active (used to compute gradients)
TempZoneAlwaysOn='Temp_Cucina'

-- GasHeater parameters
GHdiffMax=0.4				-- activate gas heater, during the night, if difference between setpoint and temperature is >0.4°C
GHoutdoorTemperatureMax=2	-- GasHeater disabled if outdoor temperature >= GHoutdoorTemperatureMax
GHoutdoorHumidityMin=88		-- Minimum outdoor humidity to start GasHeater, else start heat pump
GHtimeMin=300				-- Minutes from midnight when GasHeater will be enabled (or heatpump, if outdoor humidity is not high)
GHtimeMax=480				-- Minutes from midnight when GasHeater will be disabled
GHdevicesToEnable={}		-- Device to enable when gas heater is ON {'devicename1','devicename2'}

