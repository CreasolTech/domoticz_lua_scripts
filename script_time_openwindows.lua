-- Script that checks temperature and try to discover if doors/windows are open: in that case sends notification by Telegram.
-- Useful to limit energy consumption in winter and summer, if someone forgets windows or doors open.
--
-- This script should be named DOMOTICZ_HOME/scripts/lua/script_time_SCRIPTNAME.lua , e.g. /home/pi/domoticz/scripts/lua/script_time_openwindows.lua
-- It will be called every minute and will check and compare, for each zone (defined below), the current temperature with previous temperature.
--
-- The following user variables must be set:
-- telegramChatid : the Telegram chat ID where notifications should be sent : see https://www.domoticz.com/wiki/Telegram_Bot
-- telegramToken : the Telegram token : see https://www.domoticz.com/wiki/Telegram_Bot
-- HeatingOn: a variables that assumes the following values
--   0 => Heating/Cooling system is OFF
--   1 => Heating is ON
--   2 => Cooling is ON
--
-- Creasol - https://www.creasol.it/products

dofile("/home/pi/domoticz/scripts/lua/globalvariables.lua") -- some variables common to all scripts
dofile("/home/pi/domoticz/scripts/lua/globalfunctions.lua") -- some variables common to all scripts

commandArray={}	-- reset commandArray, an associative array that will contain the list of commands for Domoticz.

DEBUG=E_ERROR
DEBUG_PREFIX="Openwindows: "
TELEGRAM_DEBUG=E_WARNING

-- zones: array that associate for each zone the name of the temperature device, and max difference for temperature
-- This script automatically create a variable zTemp_ZONENAME that contains the temperature measured before
zones={	--zonename  {tempsensor,difference,gradient}
	['Cucina']={'Temp_Cucina',0.4,2},	
	['Bagno']={'Temp_Bagno',0.4,4},
	['Camera']={'Temp_Camera',0.4,3}, 
	['Camera_Valentina']={'Temp_Camera_Valentina',0.4,4},
	['Camera_Ospiti']={'Temp_Camera_Ospiti',0.4,4},
	['Stireria']={'Temp_Stireria',0.6,4}, 
}


log(E_INFO,'------------------------- openwindows --------------------------------')

timenow = os.date("*t")
minutesnow = timenow.min + timenow.hour * 60

for n,v in pairs(zones) do	-- check that temperature setpoint exist
	-- n=zone name, v=array with temperature sensor name and max acceptable temperature drop in degrees
	checkVar('zTemp_'..n,1,otherdevices[v[1]])	-- if zTemp_Cucina does not exist, create variable and store current temperature
	if (otherdevices[v[1]]==nil) then
		telegramNotify('Zone '..n..': temperature sensor '..v[1]..' does not exist')
	end
end

if (uservariables['HeatPumpWinter']==1) then
	-- Heating enabled
	-- compare zTemp_ZONE (old temperature) with current temperature
	for n,v in pairs(zones) do
		-- n=zonename (HeatingSP_n = setpoint temperature)
		-- v[1]=tempsensor
		-- v[2]=max difference
		diffTemp=tonumber(otherdevices[v[1]])-uservariables['zTemp_'..n]
		if (diffTemp==0) then
			-- ignore
		elseif (diffTemp>0) then
			-- current temperature > old temperature: update old temperature
			commandArray['Variable:zTemp_'..n]=otherdevices[v[1]]
		else
			-- current temperature < old temperature
			-- compute gradient (diffTemp/TIME)
			gradient=diffTemp*3600/timedifference(uservariables_lastupdate['zTemp_'..n])	-- degrees/hour
			log(E_INFO,'Zone='..n..' gradient='..string.format('%0.3f',gradient)..'K/h v[3]='..v[3]..' Temp='..otherdevices[v[1]]..'C diffTemp='..diffTemp)
			if (math.abs(gradient)<(0.4) or diffTemp>=0.3) then -- temperature falls slowly, less than 0.2C on 30 minutes
				-- |gradient|<0.4degree on 60 minutes : temperature decreases smoothly
				commandArray['Variable:zTemp_'..n]=otherdevices[v[1]]	-- update zTemp_ZONE temperature
			else
				-- rapid decreasing temperature
				-- check if there is a variable with setpoint
				if (uservariables['HeatingSP_'..n]) then
					tempSet=uservariables['HeatingSP_'..n]
				else
					tempSet=18
				end
				print('tempSet for zona '..n..'='..tempSet)
				if (math.abs(diffTemp)>=v[2] and math.abs(gradient)>v[3] and tonumber(otherdevices[v[1]])<tempSet) then
					telegramNotify('Zone '..n..': window open!! Temp='..otherdevices[v[1]]..' Gradient='..string.format('%0.2f',gradient)..'K/hour');
					commandArray['Variable:zTemp_'..n]=otherdevices[v[1]]	-- update zTemp_ZONE temperature
				end
			end
		end
	end
elseif (uservariables['HeatPumpSummer']==1) then	
	-- Cooling
	-- TODO
end

::mainEnd::
return commandArray
