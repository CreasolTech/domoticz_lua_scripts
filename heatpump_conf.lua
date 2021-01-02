-- scripts/lua/heating_pump_config.lua - Configuration file for heating pump heater/cooler system
-- Written by Creasol, https://creasol.it - linux@creasol.it
--
-- Some constants
TELEGRAM_DEBUG_CHATID="91676505"	-- Telegram chatid where to send testing notifications (when DEBUG_LEVEL >= 2)
TELEGRAM_IMPORTANT_CHATID="-1001192035046"
TELEGRAM_TOKEN="671359246:AAG2v9DpxUpEla1ql0FiuGI1cRdEK7B7fzo"
DOMOTICZ_URL="http://127.0.0.1:8080"	-- Domoticz URL (used to create variables using JSON URL
TEMP_HISTERESIS=0.1
TEMP_WINTER_HP_MAX=40				-- maximum fluid temperature from HP during the Winter
TEMP_SUMMER_HP_MIN=14				-- minimum fluid temperature from HP during the Summer
OVERHEAT=1.0						-- Increase temperature setpoint in case of available power from solar photovoltaic
OVERCOOL=-0.5						-- Decrease temperature setpoint in case of available power from solar photovoltaic
POWER_MAX=5500						-- Increment heat pump level only if consumed power is less than 4500

GasHeater='GasHeater'				-- Activate gas heater instead of heat pump when external temperature very low: set to '' if a boiler does not exist
powerMeter='PowerMeter'	-- device name of power meter, that measure consumed power from the electric grid (negative when photovoltaic produced more than house usage)
inverterMeter='kWh Meter Inverter 1'	-- Inverter output power (photovoltaic). Set to '' if not available
tempHPout='Temp_HeatPumpFluidOut' 	-- Temperature of water produced by heat pump (before entering coils or underfloor radiant system)
tempHPin= 'Temp_HeatPumpFluidIn'	-- Temperature of water that exits from coils and/or underfloor radiant system, and gets into the Heat Pump again
tempOutdoor='Meteo outdoor'			-- Temperature outdoor, or meteo sensor ("temp;humidity;pression;0")

-- fields for the following table
ZONE_TEMP_DEV=1
ZONE_RH_DEV=2
ZONE_VALVE=3
ZONE_WINTER_START=4
ZONE_WINTER_STOP=5
ZONE_WINTER_OFFSET=6
ZONE_WINTER_WEIGHT=7
ZONE_SUMMER_START=8
ZONE_SUMMER_STOP=9
ZONE_SUMMER_OFFSET=10
ZONE_SUMMER_WEIGHT=11


DEVlist={
	-- deviceName=name of each device involved in heating/cooling
	-- winterLevel=heating level (0=OFF, 1=LOW, 2=MEDIUM, 3=HIGH)
	-- summerLevel=cooling level (0=OFF, 1=LOW, 2=MEDIUM, 3=HIGH, 4=VERY HIGH)
	-- First device MUST be the heat pump ON/OFF
	--'deviceName',				winterLevel,	summerLevel
	{'HeatPump',				1,				1	},	-- HeatPump input ON/OFF (thermostat input)
	{'HeatPump_FullPower',		3,				4	},	-- HeatPump input FullPower (if Off, works at 50% of nominal power)
	{'HeatPump_Fancoil',		2,				3	},	-- HeatPump input Fancoil (set point for the fluid temperature: Off=use radiant, On=use coil with extreme temperatures
	{'HeatPump_Summer',			100,			1	},	-- HeatPump input Summer (if On, the heat pump produce cold fluid)
	{'Valve_Radiant_Coil',		100,			2	},	-- Valve to switch between Radiant (On) or Coil (Off) circuit
	{'VMC_CaldoFreddo',			100,			1	},	-- Ventilation input coil: if On, the coil supplied by heat pump is enabled (to heat/cool air)
	{'VMC_Deumidificazione',	100,			1	},	-- Ventilation input dryer: if On, the internal ciller is turned on to dehumidify air
}

DEVauxlist={
	-- device					minwinterlevel	minsummerlevel	power	temphumdev winter	gt=1, lt=0	value	temphumdev summer   gt=1, lt=0  value	max_work_minutes
	{'Dehumidifier_Camera',			2,			2,				300,	'RH_Camera',				1,	60,		'RH_Camera',         		1,  60,		0},	-- Dehumidifier
	{'Dehumidifier_Camera_Ospiti',	2,			2,				30000,	'RH_Camera_Ospiti',			1,	70,		'RH_Camera_Ospiti',         1,  60,		0},	-- Dehumidifier (disabled)
	{'Dehumidifier_Cantina',		2,			2,				500,	'RH_Cantina',				1,	65,		'RH_Cantina',         		1,  60,		600},	-- Dehumidifier: stop after 480 minutes to avoid water overflow, and notify by telegram that dehumidifier is full
	{'Bagno_Scaldasalviette',		3,			100,			450,	'Temp_Bagno',				0,	22,		'Temp_Bagno',				0,	20,		0},	-- Electric heater in bathroom
}

-- heat pump working level
LEVEL_OFF=0					-- heat pump is completely OFF
LEVEL_ON=1					-- On, half power
LEVEL_WINTER_FANCOIL=2				-- fancoil=on => higher temperature in heating mode, lower temperature in cooling mode
LEVEL_WINTER_FULLPOWER=3			-- full power
LEVEL_WINTER_MAX=3

LEVEL_SUMMER_MAX=4



HP_ON='HeatPump'				-- device corresponding to heatpump on/off
HP_FULLPOWER='HeatPump_FullPower'

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
	['Cucina']={		'Temp_Cucina',		'RH_Cucina',		'',						4,		22,		-0.2,	1,		7,		23,		0.2,	1},	
	['Studio']={		'Temp_Studio',		'',                 '',						8,		19,		-2,		0.8,	8,		19,		0.5,	0.8},
	['Bagno']={			'Temp_Bagno', 		'',                 'Valve_Bagno',			11,		21,		-1,		0.5,	16,		19,		1,		0.5},
	['Camera']={		'Temp_Camera', 		'RH_Camera',        'Valve_Camera',			13,		22,		-0.4,	0.5,	13,		23,		0.5,	0.8},	
    ['Camera_Valentina']={'Temp_Camera_Valentina','',           'Valve_Camera_Valentina',	13,	24,		-0.5,	0.5,	13,		23,		0.5,	0.8},	
    ['Camera_Ospiti']={'Temp_Camera_Ospiti','',                 'Valve_Camera_Ospiti',	13,		24,		-0.5,	0.5,	13,		23,		0.5,	0.3},
    ['Stireria']={'Temp_Stireria',			'',                 'Valve_Stireria',		13,		20,		-1,		0.5,	8,		20,		1,		0.3},
}


-- coeffArray defines a coefficient to be multiply for the average diffMax (diff between setpoint and real temperature, multiplied by a weight that decreased (<1) in case of lower importance)
--
--    --                                      |^^^^^^^^^^^^^^^^^^^^^^^^^^^_______________________
--        -- _______________|^^^^^^^^^^^^^^^^^^^^^^                                                  |_____________________
--            -- 0          Sunrise+1                 11                    Sunset-0.5                   20
--
coeffArray={
	-- [minutes since midnigth]=coeff  => value of coefficient from 0 or previous time, to this time. 
	-- The coefficient is multiplied by temperature_difference and then compare with diffMax (0.3°C)
	[180]=0.4,  -- 00:00 -> 02:00 => start pump if diffMax>=0.3/0.4=0.75C (really different temperature)
	[300]=0.9,  -- 03:00 -> 05:00 => start pump if diffMax>=0.3/0.8=0.4C
	[360]=0.4,  -- 05:00 -> 06:00 => start pump if diffMax>=0.3/0.9=0.75C  (gas heater will be ON)
	[timeofday['SunriseInMinutes']+60]=0.5, -- 06:00 -> Sunrise+60min => stop pump
	[480]=0.5,
	[timeofday['SunsetInMinutes']-30]=1,    -- from Sunrise+60m or 08:00 -> Sunset-30 => coeff = 1
	[1200]=1,                             -- Sunset-30m -> 20:00 => coeff=0.8
	[1440]=0.6,                             -- stop pump after 20:00
}

-- GasHeater parameters
GHdiffMax=0.6				-- activate gas heater, during the night, if difference between setpoint and temperature is >0.4°C
GHoutdoorTemperatureMax=2	-- GasHeater disabled if outdoor temperature >= GHoutdoorTemperatureMax
GHtimeMin=300				-- Minutes from midnight when GasHeater will be enabled
GHtimeMax=480				-- Minutes from midnight when GasHeater will be disabled
GHdevicesToEnable={}		-- Device to enable when gas heater is ON {'devicename1','devicename2'}

E_CRITICAL=0
E_ERROR=1
E_WARNING=2
E_INFO=3
E_DEBUG=4

DEBUG_LEVEL=E_DEBUG
TELEGRAM_LEVEL=E_CRITICAL

-- ------------------ Some common functions ---------------------------
function log(level, msg)
	local text='HeatPump: '..msg
	if (DEBUG_LEVEL>=level) then
		print(text)
	end	
	if (TELEGRAM_LEVEL>=level) then 
		local chatid=TELEGRAM_IMPORTANT_CHATID
		if (chatid) then 
			os.execute('curl --data chat_id='..chatid..' --data-urlencode "text='..msg..'"  "https://api.telegram.org/bot'..TELEGRAM_TOKEN..'/sendMessage" ')
		end
	end
end

function min2hours(mins)
    -- convert minutes in hh:mm format
    return string.format('%02d:%02d',mins/60,mins%60)
end

function timedifference (s)
    year = string.sub(s, 1, 4)
    month = string.sub(s, 6, 7)
    day = string.sub(s, 9, 10)
    hour = string.sub(s, 12, 13)
    minutes = string.sub(s, 15, 16)
    seconds = string.sub(s, 18, 19)
    t1 = os.time()
    t2 = os.time{year=year, month=month, day=day, hour=hour, min=minutes, sec=seconds}
    difference = os.difftime (t1, t2)
    return difference
end

function checkVar(varname,vartype,value)
    -- check if a user variable already exists in Domoticz: if not exist, create a variable with defined type and value
    -- type=
    -- 0=Integer
    -- 1=Float
    -- 2=String
    -- 3=Date in format DD/MM/YYYY
    -- 4=Time in format HH:MM
    local url
    if (uservariables[varname] == nil) then
        print('Created variable ' .. varname..' = ' .. value)
        url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=' .. varname .. '&vtype=' .. vartype .. '&vvalue=' .. value
        -- openurl works, but can open only 1 url per time. If I have 10 variables to initialize, it takes 10 minutes to do that!
		-- print("url="..url)
        -- commandArray['OpenURL']=url
        os.execute('curl "'..url..'"')
        uservariables[varname] = value;
    end
end

