-- scripts/lua/script_device_power2p1.lua 
-- Written by Creasol, https://creasol.it linux@creasol.it
-- Used to fill a virtual P1 meter with import and export power/energy. P1 meter is used by the Energy Dashboard
-- You have to create, in Domoticz -> Setup -> Hardware, a virtual P1 meter and update the 4 variables below.
-- Also, it groups several energy sources (photovoltaic1, photovoltaic2, wind, ...) into a single renewable generator virtual device, used by the Energy Dashboard
-- The virtual device (name is written in GENERATOR_SUM_DEV below) should be created manually: see below.

GRID_DEV="PowerMeter Grid"		-- existing meter used to measure the grid power (negative when producing)
P1_DEV="PowerMeter Grid P1"		-- virtual P1 meter that is managed/updated by this script
TARIFF1_START=420				-- minutes since midnight when TARIFF1 starts (420=7:00)
TARIFF1_STOP=1360				-- minutes since midnight when TARIFF2 stops  (1360=23:00)

--GENERATOR_SUM_DEV=''	-- uncomment to disable the function that sums more generators into a single virtual generator
GENERATOR_SUM_DEV='PowerMeter_Renewable'		-- Virtual kWh meter that must be created manually from Setup -> Hardware : it will be used to sum the generators power in case that more than one power source is available, for example two photovoltaic inverters, wind turbine, .... Comment and enable previous line in case you have only one generator
GENERATOR_DEVS={'PV_PowerMeter', 'PV_Garden'}	-- Empty => no generators available (photovoltaic, wind, ...).  {'Inverter_Power'} => only one generator named 'Inverter_Power'
DOMOTICZ_URL='http://127.0.0.1:8080'		-- Replace 8080 with the port used by Domoticz. Also, verify in Setup -> Settings -> Security that 127.0.0.1 is permitted to access Domoticz

commandArray={}
if (devicechanged[GRID_DEV]~=nil) then
	devValue=devicechanged[GRID_DEV]	-- general kWh meter returns power;energy
	local power=0
	local energy=0
	local energyOld=0
	local energyDiff=0
	local str=""
	local i=0
	for str in devValue:gmatch("[^;]+") do
        if (i==0) then
            power=math.floor(tonumber(str))
			i=1
        else
            energy=tonumber(str)
        end
    end
	-- check that uservariables[zP1Energy] exists
	if (uservariables['zP1Energy']~=nil) then
		energyOld=tonumber(uservariables['zP1Energy'])
	else
		-- zP1Energy variables does not exist: create it!
		energyOld=energy
		os.execute('curl -m 1 "http://127.0.0.1:8080/json.htm?type=command&param=adduservariable&vname=zP1Energy&vtype=0&vvalue='..energyOld..'"')	-- Create variable, type integer
		print("Power2P1: create new variable zP1Energy")
	end
	energyDiff=energy-energyOld

	local usage1,usage2,return1,return2,powerin,powerout
	i=0
	for str in otherdevices_svalues[P1_DEV]:gmatch("[^;]+") do
        if (i==0) then
            usage1=tonumber(str)
            i=1
        elseif (i==1) then
			usage2=tonumber(str)
			i=2
		elseif (i==2) then
			return1=tonumber(str)
			i=3
		elseif (i==3) then
			return2=tonumber(str)
			i=4
			break
		end
	end
	local timeNow = os.date("*t")
	local minutesNow = timeNow.min + timeNow.hour * 60  -- number of minutes since midnight


	if (energyDiff>=0) then
		-- usage have to be incremented
		if (minutesNow>=TARIFF1_START and minutesNow<TARIFF1_STOP) then
			usage1=usage1+energyDiff
		else
			usage2=usage2+energyDiff
		end
	else
		-- return have to be incremented
		if (minutesNow>=TARIFF1_START and minutesNow<TARIFF1_STOP) then
			return1=return1-energyDiff
		else
			return2=return2-energyDiff
		end
	end
	if (power>=0) then
		powerin=power
		powerout=0
	else
		powerin=0
		powerout=0-power
	end
	str=usage1..';'..usage2..';'..return1..';'..return2..';'..powerin..';'..powerout
	commandArray[0]={['UpdateDevice']=otherdevices_idx[P1_DEV].."|0|"..str}
	commandArray['Variable:zP1Energy']=tostring(energy)
	-- print('Power2P1: energy='..energy..'Wh energyOld='..energyOld..'Wh energyDiff='..energyDiff..'Wh => Update P1 meter with values '..str)
	
	if (GENERATOR_SUM_DEV~='') then
		if (otherdevices[GENERATOR_SUM_DEV]==nil) then
			print('Power2P1: please create a Electric Instant+Counter device from Setup -> Hardware, named '..GENERATOR_SUM_DEV..', and set it in "Computed" mode')
		else
			powerout=0
			for i,devName in pairs(GENERATOR_DEVS) do
				for str in otherdevices_svalues[devName]:gmatch("[^;]+") do
            		powerout=powerout+tonumber(str)
					break
				end
			end
			commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[GENERATOR_SUM_DEV].."|0|"..powerout..';0'}
		end
	end
end
return commandArray

