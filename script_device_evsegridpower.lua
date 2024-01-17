-- LUA script for Domoticz, writing the DomBusEVSE virtual device "Grid power" with the sum of 1 or more power meters
-- More scripts in https://github.com/CreasolTech/domoticz_lua_scripts

GRIDMETERS={"Home Consumption", "EV Consumption"}			-- List of meters which power should be summed (1 or more meters can be specified)
EVSEGRIDMETER="dombus - (1.c) Grid Power"					-- Name of the virtual device on DomBusEVSE

commandArray={}

function getPowerValue(devValue)
    -- extract the power value from string "POWER;ENERGY...."
    for str in devValue:gmatch("[^;]+") do
        return tonumber(str)
    end
end

-- scan the list of devices that has changed
for devName,devValue in pairs(devicechanged) do
	for j,name in pairs(GRIDMETERS) do
		print("devName="..devName.." name="..name)
		if (devName == name) then
			-- one of the GRIDMETERS value has changed
			totalPower=0
			for k,meter in pairs(GRIDMETERS) do
				totalPower=totalPower + getPowerValue(otherdevices[meter])
				print("totalPower="..totalPower)
			end
			commandArray[EVSEGRIDMETER]=tostring(totalPower)..';0'
			return commandArray
		end
	end
end
return commandArray


