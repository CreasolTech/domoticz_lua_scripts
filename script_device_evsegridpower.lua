-- LUA script for Domoticz, writing the DomBusEVSE virtual device "Grid power" with the sum of 1 or more power meters
-- More scripts in https://github.com/CreasolTech/domoticz_lua_scripts

GRIDMETER="Power from grid"						-- Main meter measuring the power from the electricity grid (negative if power is exported to grid)
BATTERYMETER="Power to battery"					-- Device measuring the power to the battery (negative if power is fetched from battery to the inverter)
--BATTERYMETER=""								-- If battery does not exist: uncomment this line and ignore/comment the previous line!
EVSEGRIDMETER="dombus - (1.c) Grid Power"		-- Name of the virtual device on DomBusEVSE

commandArray={}

function getPowerValue(devValue)
    -- extract the power value from string "POWER;ENERGY...."
    for str in devValue:gmatch("[^;]+") do
        return tonumber(str)
    end
end

if (devicechanged[GRIDMETER]~=nil) then
	-- mains energy meter changed => update the EVSE GridPower virtual meter
	local batteryPower=0
	if (BATTERYMETER~="" and otherdevices[BATTERYMETER]~=nil) then
		batteryPower=getPowerValue(otherdevices[BATTERYMETER])		-- example: batteryPower=1000 => 1000W from Inverter to Battery
	end
	local power=getPowerValue(otherdevices[GRIDMETER])-batteryPower	-- example: 4000W to the grid (-4000) and 1000W to the battery (1000) => power=-5000
	commandArray[EVSEGRIDMETER]=tostring(power)..';0'
end

return commandArray


