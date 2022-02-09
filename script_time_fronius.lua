-- Get telemetry data from Fronius inverter into Domoticz
-- More information at https://www.domoticz.com/wiki/Fronius_inverter
-- Last update script at https://github.com/CreasolTech/domoticz_lua_scripts
-- Originally written by GeyerA, revised by CreasolTech
--
-- This script fetch data from Fronius inverter by http, and update a virtual sensor in domoticz with the current power/energy
-- Look below the lines local PV* with description of the virtual sensors that must be created manually!
local IPFronius='192.168.1.253' -- IP adress of the Fronius inverter
local PVPowerIDX=660		-- IDX of the inverte virtual sensor, to be created manually, type Electric (Instant+Counter)
local PVVacIDX=PVPowerIDX+1	-- IDX of the AC Voltage virtual sensor, to be created manually, type 
local PVVdcIDX=PVVacIDX+1	-- IDX of the AC Voltage virtual sensor, to be created manually, type 
local PVFreqIDX=PVVdcIDX+1	-- IDX of the Frequency virtual sensor, to be created manually, type Custom Sensor, with "Hz" as Axis label
local PVDisabledAtNight=1	-- 0 => always get telemetry.  1 => disable fetching telemetry in the night
local DEBUG=2			-- 0 => do NOT print anything to log. 1 => print debugging info. 2 => print more debugging info

commandArray = {}
if (DEBUG>=1) then startTime=os.clock() end

if (PVDisabledAtNight==1) then
	-- Inverter is OFF during the night, so it does not answer to the LAN interface. Does not try to contact inverter, saving a lot of time (curl timeout)
	timeNow = os.date("*t")
	minutesNow = timeNow.min + timeNow.hour * 60  -- number of minutes since midnight
	if (minutesNow<timeofday['SunriseInMinutes']-60 or minutesNow>timeofday['SunsetInMinutes']+60) then 
		if (DEBUG>=2) then print("fronius: night time!") end
		if (DEBUG>=2) then print("fronius script took ".. (os.clock()-startTime) .."s") end
		return commandArray
	end
end


JSON = (loadfile "/home/pi/domoticz/scripts/lua/JSON.lua")()   -- For Linux

--Extract data from Fronius converter.
froniusurl   = 'curl --connect-timeout 1 "http://'..IPFronius..'/solar_api/v1/GetInverterRealtimeData.cgi?Scope=Device&DeviceId=1&DataCollection=CommonInverterData"'
jsondata    = assert(io.popen(froniusurl))
froniusdevice = jsondata:read('*all')
local retcode={jsondata:close()}
if (retcode[3]~=28) then	-- curl returns 28 in case of timeout => inverter not operational (during the night?)
	-- Inverter connection not in timeout
	if (DEBUG>=2) then print("fronius: json data="..froniusdevice) end	-- print data from Inverter
	froniusdata = JSON:decode(froniusdevice)

	if (froniusdata ~= nil) then
		-- Inverter returned json data with telemetry
		local StatusCode       = froniusdata['Body']['Data']['DeviceStatus']['StatusCode']
		local DAY_ENERGY   = froniusdata['Body']['Data']['TOTAL_ENERGY']['Value']
		local Pac=0
		if( StatusCode == 7) then --Fronius converter is Running
			Pac = froniusdata['Body']['Data']['PAC']['Value']
			local Vac = froniusdata['Body']['Data']['PAC']['Value']
		else
			Pac=0
		end   
		local Vac=froniusdata['Body']['Data']['UAC']['Value']
		local Vdc=froniusdata['Body']['Data']['UDC']['Value']
		local Freq=froniusdata['Body']['Data']['FAC']['Value']
		commandArray[1] = {['UpdateDevice'] = PVPowerIDX .. "|0|" .. Pac .. ";" .. DAY_ENERGY}
		commandArray[2] = {['UpdateDevice'] = PVVacIDX .. "|"..Vac.."|"..Vac}
		commandArray[3] = {['UpdateDevice'] = PVVdcIDX .. "|"..Vdc.."|"..Vdc}
		commandArray[4] = {['UpdateDevice'] = PVFreqIDX .. "|"..Freq.."|"..Freq}
	end
end

::exit::
if (DEBUG>=1) then print("fronius script took ".. (os.clock()-startTime) .."s") end
return commandArray
