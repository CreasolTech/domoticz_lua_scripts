-- script_time_fireAlarm.lua for Domoticz 
-- Author: CreasolTech https://www.creasol.it

-- This LUA script checks room temperatures and activate a fire alarm (notification by Telegram, ...) in case that a room temperature rises quickly
-- Read configuration file config_fireAlarm.lua that contains a table with rooms definition.

dofile "scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

function FAinit()
	-- check or initialize the FA table of variables, that will be saved, coded in JSON, into the zFA Domoticz variable
	if (FA==nil) then FA={} end
end

DEBUG_LEVEL=E_INFO
DEBUG_LEVEL=E_DEBUG		-- remove "--" at the begin of line, to enable debugging
DEBUG_PREFIX="FireAlarm: "
SIREN_DEV="SIREN_Internal"	-- In case of alarm, activate the internal siren
SIREN_TIME="1"				-- activation time in seconds
SIREN_TIME_NIGHT="5"		-- activation time in seconds if night alarm is ON (during the night)
SIREN2_DEV="Light_Camera"	-- Second siren (maybe a light) to be activated during the night if NIGHT alarm is ON.
SIREN2_TIME="600"			-- Activation time for the second siren/light


commandArray={}

local timeSinceLastUpdate = 86400	-- Time since last user variable update
json=require("dkjson")
log(E_DEBUG,"====================== "..DEBUG_PREFIX.." ============================")
if (uservariables['zFireAlarm'] == nil) then
	-- initialize variable
	FAinit()    --init FA table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zFireAlarm',2,json.encode(FA))
else
	timeSinceLastUpdate=timedifference(uservariables_lastupdate['zFireAlarm'])
    FA=json.decode(uservariables['zFireAlarm'])
	FAinit()   -- check that all variables in RWC table are initialized
end

dofile "scripts/lua/config_fireAlarm.lua"

for n,v in pairs(ROOMS) do
	-- n=index number, v[1]=roomName, v[2]=roomSensor, v[3]=maxTempDiff
	if (otherdevices[ v[2] ]) then
		-- temperature sensor exists
		-- extract temperature value from sensors TEMP;HUM;...
		for s in otherdevices[ v[2] ]:gmatch("[^;]+") do
			tempNow=tonumber(s)
			break
		end
		if (FA[n]~=nil) then
			-- room average value already set
			if (tempNow>FA[n]+v[3] or tempNow>=v[4] and timeSinceLastUpdate<80) then	-- also check that previous temperature is recent, not an old value
				-- fire alarm!
				log(E_CRITICAL,"room "..v[1]..", Temp. "..FA[n].."->"..tempNow)
				FA[n]=(FA[n]+tempNow)/2	-- real average between avg and the new temperature
				if (SIREN_DEV~="") then
					commandArray[SIREN_DEV]="On FOR "..SIREN_TIME.." SECONDS"
				end
				if (uservariables['alarmLevel']~=nil and uservariables['alarmLevel']==4) then
					-- alarm Night active => longer internal siren, and also activate the bedroom light
					if (SIREN_DEV~="") then
						commandArray[SIREN_DEV]="On FOR "..SIREN_TIME_NIGHT.." SECONDS"
					end
					if (SIREN2_DEV~="") then
						commandArray[SIREN2_DEV]="On FOR "..SIREN2_TIME.." SECONDS"
					end
				end
			else
				log(E_DEBUG,"room "..v[1]..", Temp. "..FA[n].."->"..tempNow)
			end
			FA[n]=math.floor(FA[n]*75+tempNow*25)/100 -- average temperature = (avg*3+current)/4
		else
			-- room average temperature not initialized
			FA[n]=math.floor(tempNow*100)/100
		end
	end
end

commandArray['Variable:zFireAlarm']=json.encode(FA)
log(E_DEBUG,"Set zFireAlarm="..commandArray['Variable:zFireAlarm'])

return commandArray


