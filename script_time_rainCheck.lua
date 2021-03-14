-- control rain, wind, ....
RAINDEV='Rain'		-- name of device that shows the rain rate/level
WINDDEV='Wind'		-- name of device that shows the wind speed/gust
VENTILATION_DEV='VMC_Rinnovo'
-- VENTILATION_COIL_DEV=""	-- not defined: coil to heat/cool air is not available
VENTILATION_COIL_DEV="VMC_CaldoFreddo"	-- coil to heat/cool air: will be activated only if Heat Pump is ON
HEATPUMP_DEV="HeatPump"		-- heat pump device On/Off state
VENTILATION_START=120	-- Start ventilation 120 minutes after SunRise
VENTILATION_STOP=-30	-- normally stop ventilation 30 minutes before Sunset
VENTILATION_TIME=240	-- ventilation ON for max 6 hours a day
VENTILATION_TIME_ADD=30	-- additional time (in minutes) when ventilation is forced ON (this works even after SunSet+VENTILATION_STOP)

DEBUG=E_WARNING
DEBUG_PREFIX="RainCheck: "

dofile "/home/pi/domoticz/scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "/home/pi/domoticz/scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

function CMVinit()
	-- check or initialize the CMV table of variables, that will be saved, coded in JSON, into the zVentilation Domoticz variable
	if (CMV==nil) then CMV={} end
	if (CMV['time']==nil) then CMV['time']=0 end	-- minutes the CMV was ON, today
	if (CMV['maxtime']==nil) then CMV['maxtime']=VENTILATION_TIME end	-- minutes the CMV was ON, today
	if (CMV['auto']==nil) then CMV['auto']=0 end	-- 1 of CMV has been started automatically by this script
end

commandArray={}

timeNow = os.date("*t")
minutesNow = timeNow.min + timeNow.hour * 60  -- number of minutes since midnight
json=require("dkjson")

-- extract the rain rate (otherdevices[dev]="rainRate;rainCounter")
for str in otherdevices[RAINDEV]:gmatch("[^;]+") do
	rainRate=tonumber(str)/40;
	break
end

-- extract wind direction and speed
-- Wind: 315;NW;9;12;6.1;6.1   315=direction; NW=direction, 9=speed 0.9ms/s, 12=gust 1.2ms/s
for dd, s in otherdevices[WINDDEV]:gmatch("([^;]+);[^;]+;([^;]+);.*") do
	windDirection=tonumber(dd)
	windSpeed=tonumber(s)
	break
end

-- If it's raining more than 8mm/hour, disable the 230V socket in the garden
dev='Prese_Giardino' -- socket device
if (otherdevices[dev]=='On' and rainRate>8) then -- more than 8mm/h
	log(E_WARNING,"Device "..dev.." is On while raining (rainRate="..rainRate..") => turn OFF")
	commandArray[dev]='Off'
end


-- check ventilation: enabled since 2 hours after sunrise, for 6 hours, and stop by 30 minutes before sunset
-- During the winter, ventilation is disabled when wind from W or S to avoid smell from combustion smoke from adjacent buildings using wood heaters.
if (uservariables['zVentilation'] == nil) then
	-- initialize variable
	CMVinit()    --init CMV table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zVentilation',2,json.encode(CMV))
else
    CMV=json.decode(uservariables['zVentilation'])
	CMVinit()   -- check that all variables in CMV table are initialized
end

-- at start time, reset ventilation time (ventilation active for TIME minutes) and set auto=0
if (minutesNow==(timeofday['SunriseInMinutes']+VENTILATION_START)) then
	CMV['time']=0
	CMV['maxtime']=VENTILATION_TIME
	CMV['auto']=0	-- 0=ventilation OFF, 1=ventilation ON by this script, 2=ventilation ON by this script, but disabled manually, 3=forced ON
end

log(E_INFO,"Ventilation "..otherdevices[VENTILATION_DEV]..": CMV['auto']="..CMV['auto'].." time="..CMV['time'].."/"..CMV['maxtime'].." windSpeed="..windSpeed.." windDirection="..windDirection)
if (otherdevices[VENTILATION_DEV]=='Off') then
	-- ventilation was OFF
	if (CMV['auto']==1 or CMV['auto']==3) then
		-- ventilation was ON by this script, but was forced OFF manually
		CMV['auto']=2
		if (CMV['time']>=VENTILATION_TIME or minutesNow>(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
			-- already worked for a sufficient time: disable it
			CMV['maxtime']=CMV['time']
		end
	elseif (CMV['auto']==0 and CMV['time']<CMV['maxtime'] and windSpeed>=3 and (windDirection<160 or windSpeed>20)) then
-- enable ventilation only in a specific time range		if (minutesNow>=(timeofday['SunriseInMinutes']+VENTILATION_START) and minutesNow<(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
			log(E_INFO,"Ventilation ON: windSpeed="..windSpeed.." windDirection="..windDirection)
			CMV['auto']=1	-- ON
			commandArray[VENTILATION_DEV]='On'
--		end
	end
else
	-- ventilation is ON
	CMV['time']=CMV['time']+1
	if (CMV['auto']==0) then
		-- ventilation ON manually: add another 30 minutes (VENTILATION_TIME_ADD) to the working time ?
		CMV['auto']=3
		if (CMV['time']>=CMV['maxtime']) then
			CMV['maxtime']=CMV['maxtime']+VENTILATION_TIME_ADD
		end
	elseif (CMV['auto']==2) then
		-- was forced OFF, now have been restarted => go for automatic
		CMV['auto']=1
	elseif (CMV['auto']==1 or CMV['auto']==3) then
		if (CMV['maxtime']==VENTILATION_TIME and minutesNow==(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
			log(E_INFO,"Ventilation OFF: reached the stop time. Duration="..CMV['time'].." minutes")
			CMV['auto']=0
			commandArray[VENTILATION_DEV]='Off'
		elseif (CMV['time']>=CMV['maxtime'] or windSpeed==0 or (windDirection>160 and windSpeed<20)) then
			log(E_INFO,"Ventilation OFF: duration="..CMV['time'].." minutes, windSpeed=".. (windSpeed/10) .." m/s, windDirection=".. windDirection .."°")
			CMV['auto']=0
			commandArray[VENTILATION_DEV]='Off'
		end
	end
end

if ((otherdevices[VENTILATION_COIL_DEV]~=nil)) then
	-- ventilation coil exists: 
	-- if ventilation is ON and heatpump ON => ventilation coil must be ON
	-- else must be OFF
	if (otherdevices[HEATPUMP_DEV]=='On' and ((commandArray[VENTILATION_DEV]~=nil and commandArray[VENTILATION_DEV]=='On') or (commandArray[VENTILATION_DEV]==nil and otherdevices[VENTILATION_DEV]=='On'))) then
		if (otherdevices[VENTILATION_COIL_DEV]~='On') then
			commandArray[VENTILATION_COIL_DEV]='On'
		end
	else
		if (otherdevices[VENTILATION_COIL_DEV]~='Off') then
			commandArray[VENTILATION_COIL_DEV]='Off'
		end
	end
end

commandArray['Variable:zVentilation']=json.encode(CMV)
return commandArray


