-- LUA script for Domoticz, writing the DomBusEVSE virtual device "Grid power" with the sum of 1 or more power meters
-- More scripts in https://github.com/CreasolTech/domoticz_lua_scripts

GRIDMETER="Power from grid"						-- Main meter measuring the power from the electricity grid (negative if power is exported to grid)
VOLTAGEMETER="Inverter Voltage"					-- Grid voltage or, better, solar inverter voltage

BATTERYMETER="Power to battery"					-- Device measuring the power to the battery (negative if power is fetched from battery to the inverter)
-- If a battery does not exist, write -- before BATTERYMETER


EVSEGRIDMETER="dombus - (1.c) Grid Power"		-- Name of the virtual device on DomBusEVSE with power (in Watt) from the grid: 
-- In case that a grid power meter is connected to the EVSE, write -- before EVSEGRIDMETER


EVSEVOLTAGE="dombus - (1.a) EV Voltage"			-- Name of the virtual device on DomBusEVSE for EV voltage (in Volt)
-- In case that EV power meter exists, write -- before EVSEVOLTAGE=

commandArray={}

function getPowerValue(devValue)
    -- extract the power value from string "POWER;ENERGY...."
    for str in devValue:gmatch("[^;]+") do
        return tonumber(str)
    end
end

if (EVSEGRIDMETER~=nil) then
	-- EVSEGRIDMETER specified => write current power (in Watt, negative if exporting) to the EVSE
	if (devicechanged[GRIDMETER]~=nil) then
		-- mains energy meter changed => update the EVSE GridPower virtual meter
		local batteryPower=0
		if (BATTERYMETER~=nil and otherdevices[BATTERYMETER]~=nil) then
			batteryPower=getPowerValue(otherdevices[BATTERYMETER])		-- example: batteryPower=1000 => 1000W from Inverter to Battery
		end
		local power=math.floor(getPowerValue(devicechanged[GRIDMETER])-batteryPower)	-- example: 4000W to the grid (-4000) and 1000W to the battery (1000) => power=-5000
		commandArray[EVSEGRIDMETER]=tostring(power)..';0'
	end
end

if (EVSEVOLTAGE~=nil) then
	-- EVSEVOLTAGE specified => write current voltage (in Volt) to the EVSE
	if (devicechanged[VOLTAGEMETER]~=nil) then
		commandArray[EVSEVOLTAGE]=math.floor(devicechanged[VOLTAGEMETER])
	end
end

return commandArray


