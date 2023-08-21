-- script_time_rainWindCheck.lua for Domoticz 
-- Author: CreasolTech https://www.creasol.it

-- This LUA script checks rain and wind data, and controls
-- * outdoor power outlet (in the garden), that can be disabled when raining
-- * mechanical ventilation: activates it only when there is enough wind and not from certain directions (to prevent stove smoke from the neighboor to enter into the house).
-- * if both heat pump and ventilation are active, also activates the hydronic coil inside the ventilation machine (to pre-heat/cool the air)
-- * if WindGuru station id and password are available, export wind/temperature/humidity data to WindGuru website
-- * fan/aspirator in the attic, used for cooling the attic in the Summer, or dehumidifing it, or heat in the Winter
-- * Control the power outlet connected to a mosquitto killer

-- This script needs also to access two configuration files:
--   globalvariables.lua
--   globalfunctions.lua
-- Put this script and the 2 configuration files on DOMOTICZDIR/scripts/lua

RAINTIMEOUT=30					-- Wait 30 minutes after rainCounter stops incrementing and rainRate returns to zero, before determining that the rain is over.

VENTILATION_START_WINTER=210	-- Start ventilation 3.5 hours after SunRise (Winter)
VENTILATION_START_SUMMER=120	-- Start ventilation 2 hours after SunRise (Summer)
VENTILATION_STOP=-30	-- normally stop ventilation 30 minutes before Sunset
VENTILATION_TIME=150	-- ventilation ON for max 6 hours a day
VENTILATION_TIME_ADD=90	-- additional time (in minutes) when ventilation is forced ON (this works even after SunSet+VENTILATION_STOP)
--VENTILATION_TIME_ADD=300	-- very long time (in minutes), useful when dining with friends

-- This section is used to enable one or two fans in the attic for cooling, heating or drying.
-- A virtual "Selector Switch" named as ATTIC_SELECTOR_DEV variable should be create, with state "Off", "On", "Winter", "Summer" used to enable these function modes
ATTIC_FAN_DEV="Fan_Attic"	-- Fan used for cooling the attic during the Summer. "" = not used.  DomBus36 in the attic, port 7
ATTIC_FAN2_DEV=""		-- Aspirator used for cooling the attic during the Summer. "" = not used. DomBus36 in the attic, port 8
ATTIC_SELECTOR_DEV="Attic_Fans_Active" -- Virtual selector switch to be created manually with levels "Off", "On", "Winter", "Summer"
ATTIC_TEMP_DEV="Temp_Attic"	-- Temperature sensor in the attic. DomBusTH in the attic.
ATTIC_DELTA_START=8
ATTIC_DELTA_STOP=5

MOSQUITO_DEV="Socket_GarageVerde"	-- power outlet used to supply the mosquito killer ("" if not used) - DomBus31 in the laundry
MOSQUITTO_SELECTOR_DEV="Mosquitto_Killer_Active" -- Virtual selector switch to be created manually with levels "Off" and "On"

dofile "/home/pi/domoticz/scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "/home/pi/domoticz/scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

function RWCinit()
	-- check or initialize the RWC table of variables, that will be saved, coded in JSON, into the zRainWindCheck Domoticz variable
	if (RWC==nil) then RWC={} end
	if (RWC['time']==nil) then RWC['time']=0 end	-- minutes the RWC was ON, today
	if (RWC['maxtime']==nil) then RWC['maxtime']=VENTILATION_TIME end	-- minutes the CMV was ON, today
	if (RWC['auto']==nil) then RWC['auto']=0 end	-- 1 of CMV has been started automatically by this script
	if (RWC['wind']==nil) then RWC['wind']='' end
end

DEBUG_LEVEL=E_INFO
DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="RainWindCheck: "
commandArray={}

timeNow = os.date("*t")
minutesNow = timeNow.min + timeNow.hour * 60  -- number of minutes since midnight
json=require("dkjson")
log(E_DEBUG,"====================== RainWindCheck ============================")
-- extract the rain rate (otherdevices[dev]="rainRate;rainCounter")
i=0
-- otherdevices[RAINDEV]="0.0;21451.1")
for str in otherdevices[RAINDEV]:gmatch("[^;]+") do
	if (i==0) then 
		rainRate=tonumber(str)/40
	else
		rainCounter=tonumber(str)
		break;
	end
	i=i+1
end

-- extract wind direction and speed
-- Wind: 315;NW;9;12;6.1;6.1   315=direction; NW=direction, 9=speed 0.9m/s, 12=gust 1.2m/s
local w1, w2, w3, w4
for w1, w2, w3, w4 in otherdevices[WINDDEV]:gmatch("([^;]+);([^;]+);([^;]+);([^;]+).*") do
	windDirection=tonumber(w1)
	windDirectionName=w2
	windSpeed=tonumber(w3)
	windGust=tonumber(w4)
	break
end

if (TEMPERATURE_OUTDOOR_DEV~=nil and TEMPERATURE_OUTDOOR_DEV~='') then
	-- temperature from weather station value should be in the format "12.20;42;0;1017;0"
	--log(E_DEBUG,"WindGuru: TEMPERATURE_OUTDOOR="..otherdevices[TEMPERATURE_OUTDOOR_DEV])
	for w1, w2, w3, w4 in otherdevices[TEMPERATURE_OUTDOOR_DEV]:gmatch("([^;]+);([^;]+);([^;]+);([^;]+).*") do
		outdoorTemp=tonumber(w1)
		outdoorRH=tonumber(w2)
		outdoorBaro=tonumber(w4)
		break
	end
end

-- If it's raining more than 8mm/hour, disable the 230V socket in the garden
dev='Garden_Socket' -- socket device
if (otherdevices[dev]=='On' and rainRate>8) then -- more than 8mm/h
	log(E_WARNING,"Device "..dev.." is On while raining (rainRate="..rainRate..") => turn OFF")
	commandArray[dev]='Off'
end

-- check ventilation: enabled since 2 hours after sunrise, for 6 hours, and stop by 30 minutes before sunset
-- During the winter, ventilation is disabled when wind from W or S to avoid smell from combustion smoke from adjacent buildings using wood heaters.

checkVar('raining',0,0)	-- create uservariable "raining" if it does not exist
raining=uservariables['raining'] -- 0 => not raining; 30, 29, 28, 27, ... => it's raining

if (uservariables['zRainWindCheck'] == nil) then
	-- initialize variable
	RWCinit()    --init RWC table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zRainWindCheck',2,json.encode(RWC))
	RWC['rc']=rainCounter
else
    RWC=json.decode(uservariables['zRainWindCheck'])
	RWCinit()   -- check that all variables in RWC table are initialized
end

--print("rainRate="..rainRate.." rainCounter="..rainCounter.." raining="..raining)
if (rainCounter~=RWC['rc'] or rainRate>0) then
	-- it's raining
	raining=RAINTIMEOUT;
	RWC['rc']=rainCounter
else
	if (raining>0) then
		raining=raining-1
	end
end

-- at start time, reset ventilation time (ventilation active for TIME minutes) and set auto=0
if (timeNow.month>=10 or timeNow.month<=5) then
	VENTILATION_START=VENTILATION_START_WINTER
else
	VENTILATION_START=VENTILATION_START_SUMMER
end

if (minutesNow==(timeofday['SunriseInMinutes']+VENTILATION_START)) then
	RWC['time']=0
	RWC['maxtime']=VENTILATION_TIME
	RWC['auto']=0	-- 0=ventilation OFF, 1=ventilation ON by this script, 2=ventilation ON by this script, but disabled manually, 3=forced ON
end

if (otherdevices[VENTILATION_DEV]~=nil) then
	log(E_INFO,"Ventilation "..otherdevices[VENTILATION_DEV]..": RWC['auto']="..RWC['auto'].." time="..RWC['time'].."/"..RWC['maxtime'].." windSpeed=".. (windSpeed/10) .."m/s windDirection="..windDirection.."°")
	if (otherdevices[VENTILATION_DEV]=='Off') then
		-- ventilation was OFF
		if (RWC['auto']==1 or RWC['auto']==3) then
			-- ventilation was ON by this script, but was forced OFF manually
			RWC['auto']=2
			if (RWC['time']>=VENTILATION_TIME or minutesNow>(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
				-- already worked for a sufficient time: disable it
				RWC['maxtime']=RWC['time']
			end
			-- elseif (RWC['auto']==0 and RWC['time']<RWC['maxtime'] and windSpeed>=3 and (windDirection<160 or windSpeed>20)) then
		elseif (RWC['auto']==0 and RWC['time']<RWC['maxtime']) then -- do not check wind direction
--		elseif (RWC['auto']==0 and RWC['time']<RWC['maxtime'] and windSpeed>=3 and (windDirection<210 or windSpeed>20)) then -- during the Winter, avoid smoke from South and West
--		elseif (RWC['auto']==0 and RWC['time']<RWC['maxtime'] and windSpeed>=3 and (windDirection>90 and windDirection<270)) then  -- avoid smoke from the North
			-- enable ventilation only in a specific time range		if (minutesNow>=(timeofday['SunriseInMinutes']+VENTILATION_START) and minutesNow<(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
			log(E_INFO,"Ventilation ON: windSpeed=".. (windSpeed/10) .." ms/s, windDirection="..windDirection .."°")
			RWC['auto']=1	-- ON
			--commandArray[VENTILATION_DEV]='On'
			deviceOn(VENTILATION_DEV,RWC,'d1')
			--		end
		end
	else
		-- ventilation is ON
		log(E_DEBUG,"Ventilation is ON")
		RWC['time']=RWC['time']+1
		if (RWC['auto']==0) then
			-- ventilation ON manually: add another 30 minutes (VENTILATION_TIME_ADD) to the working time ?
			RWC['d1']='a'	-- set device so it can be disabled automatically by deviceOff
			RWC['auto']=3
			if (RWC['time']>=RWC['maxtime']) then
				RWC['maxtime']=RWC['maxtime']+VENTILATION_TIME_ADD
			end
		elseif (RWC['auto']==2) then
			-- was forced OFF, now have been restarted => go for automatic
			RWC['d1']='a'	-- set device so it can be disabled automatically by deviceOff
			RWC['auto']=1
		elseif (RWC['auto']==1 or RWC['auto']==3) then
			if (RWC['maxtime']==VENTILATION_TIME and minutesNow==(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
				log(E_INFO,"Ventilation OFF: reached the stop time. Duration="..RWC['time'].." minutes")
				RWC['auto']=0
				-- commandArray[VENTILATION_DEV]='Off'
				deviceOff(VENTILATION_DEV,RWC,'d1')
				-- elseif (RWC['time']>=RWC['maxtime'] or (otherdevices['HeatPump_Mode']=='Winter' and (windSpeed==0 or (windDirection>160 and windSpeed<20)))) then
			elseif (RWC['time']>=RWC['maxtime']) then -- do not check for windDirection (smoke)
--			elseif (RWC['time']>=RWC['maxtime'] or (otherdevices['HeatPump_Mode']=='Winter' and ((windDirection>160 and windSpeed<20)))) then -- during the Winter
--			elseif (RWC['time']>=RWC['maxtime'] or ((windDirection>210 or windDirection<45))) then -- avoid Smoke from Belluno
				log(E_INFO,"Ventilation OFF: duration="..RWC['time'].." minutes, windSpeed=".. (windSpeed/10) .." m/s, windDirection=".. windDirection .."°")
				RWC['auto']=0
				-- commandArray[VENTILATION_DEV]='Off'
				deviceOff(VENTILATION_DEV,RWC,'d1')
			end
		end
	end
end

if (otherdevices['HeatPump_Mode']=='Winter') then 
	-- in Winter, activate the ventilation water coil when heat pump and ventilation are ON (to heat the air from ventilation)
	if ((otherdevices[VENTILATION_COIL_DEV]~=nil)) then
		-- ventilation coil exists: 
		-- if ventilation is ON and heatpump ON => ventilation coil must be ON
		-- else must be OFF
		if (otherdevices[HEATPUMP_DEV]=='On' and otherdevices[VENTILATION_DEV]=='On' or otherdevices[VENTILATION_DEHUMIDIFY_DEV]=='On') then
			if (otherdevices[VENTILATION_COIL_DEV]~='On') then
				commandArray[VENTILATION_COIL_DEV]='On'
			end
		else
			if (otherdevices[VENTILATION_COIL_DEV]~='Off') then
				commandArray[VENTILATION_COIL_DEV]='Off'
			end
		end
	end
end

if (WINDGURU_USER ~= nil and WINDGURU_USER ~= '') then
	-- publish wind data on WindGuru website
	if (RWC['wind']==nil or RWC['wind']~=otherdevices[WINDDEV]) then
		-- wind has changed
		local windSpeedkn=string.format("%.2f", windSpeed*0.1943)
		local windGustkn =string.format("%.2f", windGust*0.1943)
		log(E_DEBUG,"WindGuru: "..otherdevices[WINDDEV].." Speed="..windSpeedkn.."kn Gust="..windGustkn.."kn Dir="..windDirection)
		local windgurusalt=os.date('%Y%m%d%H%M%S')
		local windgurusecret=windgurusalt..WINDGURU_USER..WINDGURU_PASS
		local windgurucmd='echo -n ' .. windgurusecret .. ' | md5sum'
		log(E_DEBUG,"WindGuru: create hash with the command "..windgurucmd)
		local fd=assert(io.popen(windgurucmd, 'r'))
		local windguruhash=assert(fd:read('*a')):match("(%w+)")
		windgurucmd='curl -m 1 -s \'http://www.windguru.cz/upload/api.php?uid='..WINDGURU_USER..'&salt='..windgurusalt..'&hash='..windguruhash..
                    '&wind_avg='..windSpeedkn..'&wind_max='..windGustkn..'&wind_direction='..windDirection
		windgurucmd=windgurucmd..'&temperature='..outdoorTemp..'&rh='..outdoorRH
		windgurucmd=windgurucmd..'\''
		log(E_DEBUG,"WindGuru cmd is "..windgurucmd)
		-- ret=os.execute(windgurucmd)
		fd=assert(io.popen(windgurucmd, 'r'))
		ret=assert(fd:read('*a'))
		log(E_DEBUG,"WindGuru returned: "..tostring(ret))
		RWC['wind']=otherdevices[WINDDEV]	-- save current wind state
	end
end


-- If ATTIC_FAN_DEV is defined, manage cooling the attic during the Summer or heat during the Winter
if (ATTIC_FAN_DEV~="") then
	atticTemp=tonumber(otherdevices[ATTIC_TEMP_DEV])
	if (otherdevices["Attic_Fans_Active"]=="Off") then
		deviceOff(ATTIC_FAN_DEV,RWC,"af1")
		if (ATTIC_FAN2_DEV~="") then deviceOff(ATTIC_FAN2_DEV,RWC,"af2") end
	elseif (otherdevices["Attic_Fans_Active"]=="On") then
		deviceOn(ATTIC_FAN_DEV,RWC,"af1")
		if (ATTIC_FAN2_DEV~="") then deviceOn(ATTIC_FAN2_DEV,RWC,"af2") end
	elseif (otherdevices["Attic_Fans_Active"]=="Summer") then
		if (timeNow.month>=5 and timeNow.month<=9 and otherdevices["Attic_Fans_Active"]=="Summer") then
			if (otherdevices[ATTIC_FAN_DEV]=="Off") then
				-- Fans are off
				-- if (atticTemp>26 and outdoorTemp+ATTIC_DELTA_START<atticTemp and (minutesNow>120 or tonumber(uservariables["alarmLevel"])<=2)) then
				if (atticTemp>28 and outdoorTemp+ATTIC_DELTA_START<atticTemp and (minutesNow%20)<15 and raining==0) then
					deviceOn(ATTIC_FAN_DEV,RWC,"af1")
					if (ATTIC_FAN2_DEV~="") then deviceOn(ATTIC_FAN2_DEV,RWC,"af2") end
				end
			else
				-- Fans are On !!
				-- if (atticTemp<26 or outdoorTemp+ATTIC_DELTA_STOP>atticTemp or (minutesNow<240 and tonumber(uservariables["alarmLevel"])>2)) then
				if (atticTemp<27 or outdoorTemp+ATTIC_DELTA_STOP>atticTemp or (minutesNow%20>=15) or raining~=0) then
					deviceOff(ATTIC_FAN_DEV,RWC,"af1")
					if (ATTIC_FAN2_DEV~="") then deviceOff(ATTIC_FAN2_DEV,RWC,"af2") end
				end
			end
		end
	end
end
			
if (MOSQUITO_DEV~="") then
	-- Manage the mosquito killer: turn on in the evening (if not raining) and turn off in case of rain or in the morning
	if (otherdevices[MOSQUITO_DEV]=='Off') then
		-- moquito killer not supplied
		if (otherdevices[MOSQUITTO_SELECTOR_DEV]~='Off' and (minutesNow>=timeofday['SunsetInMinutes']-120 or minutesNow<timeofday['SunriseInMinutes']) and raining==0) then
			deviceOn(MOSQUITO_DEV,RWC,"MK")
		end
	else
		-- mosquitoes killer already On
		if (otherdevices[MOSQUITTO_SELECTOR_DEV]=='Off' or (minutesNow<timeofday['SunsetInMinutes']-120 and minutesNow>=timeofday['SunriseInMinutes']) or raining~=0) then
			deviceOff(MOSQUITO_DEV,RWC,"MK")
		end
	end
end



commandArray['Variable:raining']=tostring(raining)
commandArray['Variable:zRainWindCheck']=json.encode(RWC)
return commandArray


