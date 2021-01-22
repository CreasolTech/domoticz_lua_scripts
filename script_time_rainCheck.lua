-- control rain, wind, ....
RAINDEV='Rain'		-- name of device that shows the rain rate/level
WINDDEV='Wind'		-- name of device that shows the wind speed/gust
VENTILATION_DEV='VMC_Rinnovo'
VENTILATION_START=120	--120 minutes after SunRise
VENTILATION_STOP=-30	--30 minutes before SunSet
VENTILATION_TIME=360	-- ventilation ON for max 6 hours a day


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
        url='http://127.0.0.1:8080/json.htm?type=command&param=adduservariable&vname=' .. varname .. '&vtype=' .. vartype .. '&vvalue=' .. value
        -- openurl works, but can open only 1 url per time. If I have 10 variables to initialize, it takes 10 minutes to do that!
        -- print("url="..url)
        -- commandArray['OpenURL']=url
        os.execute('curl "'..url..'"')
        uservariables[varname] = value;
    end
end

function CMVinit()
	-- check or initialize the CMV table of variables, that will be saved, coded in JSON, into the zVentilation Domoticz variable
	if (CMV==nil) then CMV={} end
	if (CMV['time']==nil) then CMV['time']=0 end	-- minutes the CMV was ON, today
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
	print("Device "..dev.." is On while raining (rainRate="..rainRate..") => turn OFF")
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

-- at start time, reset time (ventilation active for TIME minutes) and set auto=0
if (minutesNow==(timeofday['SunriseInMinutes']+VENTILATION_START)) then
	CMV['time']=0
	CMV['auto']=0	-- 0=ventilation OFF, 1=ventilation ON by this script, 2=ventilation ON by this script, but disabled manually, 3=forced ON
end

if (otherdevices[VENTILATION_DEV]=='Off') then
	-- ventilation was OFF
	if (CMV['auto']==1) then
		-- ventilation was ON by this script, but was forced OFF manually
		CMV['auto']=2
	elseif (CMV['auto']==3) then 
		-- ventilation was forced ON, now has been disabled => go for automatic
		CMV['auto']=0
	elseif (CMV['auto']==0 and CMV['time']<VENTILATION_TIME and windSpeed>=5 and windDirection>=0 and windDirection<160) then
		if (minutesNow>=(timeofday['SunriseInMinutes']+VENTILATION_START) and minutesNow<(timeofday['SunsetInMinutes']+VENTILATION_STOP)) then
			print("Ventilation ON: windSpeed="..windSpeed.." windDirection="..windDirection)
			CMV['auto']=1	-- ON
			commandArray[VENTILATION_DEV]='On'
		end
	end
else
	-- ventilation is ON
	CMV['time']=CMV['time']+1
	if (CMV['auto']==0) then
		CMV['auto']=3	-- forced ON
	elseif (CMV['auto']==2) then
		-- was forced OFF, now have been restarted => go for automatic
		CMV['auto']=1
	elseif (CMV['auto']==1 and (minutesNow>=(timeofday['SunsetInMinutes']+VENTILATION_STOP) or CMV['time']>=VENTILATION_TIME or windSpeed==0 or windDirection>160)) then
		print("Ventilation OFF: duration="..CMV['time'].." minutes, windSpeed="..windSpeed/10.." m/s, windDirection="..windDirection.."°")
		CMV['auto']=0
		commandArray[VENTILATION_DEV]='Off'
	end
end


commandArray['Variable:zVentilation']=json.encode(CMV)
return commandArray


