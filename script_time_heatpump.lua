-- Lua script for Domoticz, controlling the heating/cooling system by a heat pump supplied by electric grid + photovoltaic system.
-- Designed to consume as most as possible energy from photovoltaic
-- Written by Creasol, https://www.creasol.it , linux@creasol.it
--
-- Please assure that
-- 127.0.0.1 is enabled to connect without authentication, in Domoticz -> Configuration -> Settings -> Local Networks (e.g. 127.0.0.1;192.168.1.*)
--
commandArray={}

--do return commandArray	end --Return now, skipping everything else
dofile "/home/pi/domoticz/scripts/lua/heatpump_conf.lua"

-- Level can be 0 (OFF) or >0 (ON: the higher the level, more power can be used by the heat pump)
-- Increment the level (available power for the heat pump)
function incLevel() 
	HP['Level']=HP['Level']+1
	log(E_INFO,'Increment Level to '..HP['Level'])
end

-- Decrement the level to reduce heat pump power usage
function decLevel()
	if (HP['Level']>0) then
		HP['Level']=HP['Level']-1
		log(E_INFO,'Decrement Level to '..HP['Level'])
	else
		HP['Level']=0
	end
end

-- Initialize the HP domoticz variable (json coded, within several state variables)
function HPinit()
	if (HP==nil) then HP={} end
	if (HP['otmin']==nil) then HP['otmin']=20 end	-- outodorTemperatureMin
	if (HP['Level']==nil) then HP['Level']=0 end
end

function deviceOn(devName,devIndex)
	-- if devname is off => turn it on
	if (otherdevices[devName]~='On') then 
		print("deviceOn("..devName..","..devIndex..")")
		commandArray[devName]='On'	-- switch on
		HP['d'..devIndex]='a'	-- store in HP that device was automatically turned ON (and can be turned off)
	end
end

function deviceOff(devName,devIndex)
	-- if devname is on and was enabled by this script => turn it off
	-- if devname was enabled manually, for example to force heating/cooling, leave it ON.
	if (otherdevices[devName]~='Off' and (HP['d'..devIndex]==nil or HP['d'..devIndex]=='a')) then 
		print("deviceOff("..devName..","..devIndex..")")
		commandArray[devName]='Off'	-- switch off
		HP['d'..devIndex]=''	-- store in HP that device was automatically turned ON (and can be turned off)
	end
end

function heatPumpOn()
	if (otherdevices['HeatPump']=='Off') then
		if (uservariables['HeatPumpWinter']==1) then
			deviceOff('HeatPump_Summer')
		else
			deviceOn('HeatPump_Summer')
		end
		deviceOff('HeatPump_Fancoil')
		deviceOff('HeatPump_FullPower')
		deviceOn('HeatPump')
	end
end

function heatPumpOff(timeOff)
	deviceOff('HeatPump')
	deviceOff('HeatPump_Fancoil')
	deviceOff('HeatPump_FullPower')
	deviceOff('HeatPump_Summer')
	HP['Level']=LEVEL_OFF
end

-- switch ON/OFF valves to enable/disable zones
function updateValves()
	-- check valveStateTemp and update valve status
	for n,v in pairs(zones) do
		-- n=zonename (HeatingSP_n = setpoint temperature)
		-- v[ZONE_TEMP_DEV]=tempsensor
		-- v[ZONE_VALVE]=valve device
		-- v[ZONE_WINTER_START]=start time
		-- v[ZONE_WINTER_STOP]=end time
		-- v[ZONE_WINTER_OFFSET]=offset outside the time slot (start time..end time)
		--
		-- if HeatPump == Off => don't activate electrovalve
		if (otherdevices[DEVlist[1][1] ]=='Off') then 
			valveStateTemp[v[ZONE_VALVE] ]='Off'	
		end
		-- update commandArray only when valve status have changed
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE] ]~=valveStateTemp[v[ZONE_VALVE] ]) then
			commandArray[v[ZONE_VALVE] ]=valveStateTemp[v[ZONE_VALVE] ]
			log(E_INFO,'**** Valve for zone '..n..' changed to '..valveStateTemp[ v[ZONE_VALVE] ])
		end

	end 
end

timenow = os.date("*t")
minutesnow = timenow.min + timenow.hour * 60

-- check variables
json=require("dkjson")
if (uservariables['zHeatPump'] == nil) then
	-- initialize variable
	HPinit()	--init HP table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zHeatPump',2,json.encode(HP))
else
	HP=json.decode(uservariables['zHeatPump'])
	HPinit()	-- check that all variables in HP table are initialized
end

levelOld=HP['Level']	-- save previous level
diffMax=0
checkVar('HeatPumpSummer',0,0)
checkVar('HeatPumpWinter',0,0)

for n,v in pairs(zones) do	-- check that temperature setpoint exist
	-- n=zone name, v=CSV separated by | containing tempsensor and electrovalve device name
	checkVar('TempSet_'..n,1,21)
	-- check that devices exist
	if (otherdevices[v[ZONE_TEMP_DEV] ]==nil) then
		log(E_CRITICAL,'Zone '..n..': temperature sensor '..v[ZONE_TEMP_DEV]..' does not exist')
	end
	if (v[ZONE_RH_DEV] and v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV] ]==nil) then
		log(E_CRITICAL,'Zone '..n..': relative humidity device '..v[ZONE_RH_DEV]..' defined in heatpump_conf.lua but does not exist')
	end
	if (v[ZONE_VALVE] and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE] ]==nil) then
		log(E_CRITICAL,'Zone '..n..': valve device '..v[ZONE_VALVE]..' defined in heatpump_conf.lua but does not exist')
	end
end

if (otherdevices[tempHPout] == nil) then
	log(E_CRITICAL,'Please create a temperature sensor named "'..tempHPout..'" that measures the temperature of fluid from heat pump to the radiant/coil system')
	goto mainEnd
end
if (otherdevices[tempHPin] == nil) then
	log(E_CRITICAL,'Please create a temperature sensor named "'..tempHPin..'" that measures the temperature of fluid from the radiant/coil system back to the heat pump')
	goto mainEnd
end

valveState=''
valveStateTemp={}
tempFluidLimit=25	-- initialize value to avoid any error

-- Also, I have to consider the availability of power from photovoltaic
if (otherdevices[powerMeter]~=nil) then
	-- power meter exists, returning value "usagePower;totalEnergy"
	--[[
	for str in otherdevices[powerMeter]:gmatch("[^;]+") do
		usagePower=tonumber(str)
		break
	end
	]]
	usagePower=uservariables['avgPower']	-- use the average power instead of instant power!
else 
	usagePower=500 -- power meter does not exist: set usagePower to 500W by default
end
prodPower=0-usagePower

if (uservariables['HeatPumpWinter']==0 and uservariables['HeatPumpSummer']==0) then
	-- Both heating and cooling are disabled
	HP['Level']=LEVEL_OFF
else
	-- Heating or cooling is enabled
	-- initialize some variables, depending by the HeatPumpWinter variable (1 => heating, 0 => cooling because HeatPumpSummer is 1 )
	if (uservariables['HeatPumpWinter']==1) then
		-- Heating enabled
		log(E_INFO,'================================= HeatPumpWinter ================================')
		zone_start=ZONE_WINTER_START	-- offset on zones[] structure
		zone_stop=ZONE_WINTER_STOP
		zone_offset=ZONE_WINTER_OFFSET
		zone_weight=ZONE_WINTER_WEIGHT
		level_max=LEVEL_WINTER_MAX -- max value for HP['Level']
		-- heating enable when usage power > 500 watt only if room temperature is distant from the set point (temperature < setpoint - 0.4)
	 	diffMaxHigh_value=0.3	-- if diffMax<diffMaxHigh_value, temperature is near the set point
		if (timenow.hour < 10) then diffMaxHigh_value=diffMaxHigh_value+0.2 end

		diffMaxHigh_power=500	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh_value)
		prodPower_incLevel=300		--minimum production power to increment level
		prodPower_incLevel2=1000	--minimum production power to increment level by 2
		spOffset=OVERHEAT
	else
		-- Cooling enabled
		log(E_INFO,'================================= HeatPumpSummer ================================')
		zone_start=ZONE_SUMMER_START	-- offset on zones[] structure
		zone_stop=ZONE_SUMMER_STOP
		zone_offset=ZONE_SUMMER_OFFSET
		zone_weight=ZONE_SUMMER_WEIGHT
		level_max=LEVEL_SUMMER_MAX -- max value for HP['Level']
		-- cooling enabled only if consumed power is < 200 Watt. It's tolerated to consume more than 200W only if room temperature > setpoint + 2°C
		diffMaxHigh_value=2		-- if diffMax<diffMaxHigh_value, temperature is near the set point
		diffMaxHigh_power=200	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh_value)
		prodPower_incLevel=800		--minimum production power to increment level
		prodPower_incLevel2=1200	--minimum production power to increment level by 2
		spOffset=OVERCOOL
	end
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0		-- max value of relative humidity
	-- rhMax=70    -- DEBUG: force RH to a high value to force dehumidification

	zonesOn=0	-- number of zones that are ON
	SPOffset=0	-- offset on setpoint
	if (prodPower>1200) then	-- more than 800W fed to the electrical grid
		SPOffset=spOffset	-- increase setpoint by OVERHEAT parameter to overheat, in case of extra available energy
	end
	
	-- check temperatures and setpoints
	for n,v in pairs(zones) do
		-- n=zonename (HeatingSP_n = setpoint temperature)
		-- v[ZONE_TEMP_DEV]=tempsensor
		-- v[ZONE_RH_DEV]=relative humidity sensor
		-- v[ZONE_VALVE]=valve device
		-- v[zone_start]=start time for comfort
		-- v[zone_stop]=end time for comfort
		-- v[zone_offset]=offset to be used during the night, used to tolerate a lower temperature when rooms are unused
		-- v[zone_weight]=weight to calculate the weighted difference between setpoint and current temperature (for some rooms, maybe it's not so important to get exactly the temperature indicated by the SetPoint variable)
		--
		-- check temperature offset defined for each zone (used to reduce temperature during the night
		temperatureOffset=0
		if (timenow.hour < v[zone_start] or timenow.hour >= v[zone_stop]) then
			-- night: reduce the temperature setpoint
			temperatureOffset=v[zone_offset]
		end
		rh=0
		if (v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV] ]~=nil) then
			rh=tonumber(otherdevices[v[ZONE_RH_DEV] ]);
			if (rh>rhMax) then rhMax=rh end
		end

		-- diff=(setpoint+offset)-temperature: if diff>0 => must heat
		diff=(uservariables['TempSet_'..n]+temperatureOffset+SPOffset)-tonumber(otherdevices[v[ZONE_TEMP_DEV] ]);
		if (uservariables['HeatPumpWinter']==0) then
			-- summer => invert diff
			diff=0-diff
		end
		if (diff>0) then
			-- must heat/cool!
			valveState='On'
			diff=diff*v[zone_weight]	-- compute the weighted difference between room temperature and setpoint
			zonesOn=zonesOn+1
		else
			-- temperature <= (setpoint+offset) => diff<=0
			valveState='Off'
		end
		if (diff>diffMax) then
			diffMax=diff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='') then
			valveStateTemp[v[ZONE_VALVE] ]=valveState
		end
		log(E_DEBUG,valveState..' zone='..n..' RH='..rh..' Temp='..otherdevices[v[ZONE_TEMP_DEV] ]..' SP='..uservariables['TempSet_'..n]..'+'..temperatureOffset..'+('..SPOffset..') diff='..diff)
	end
	-- Now diffMax stores the max weighted-difference between setpoint and temperature 
	-- To be sure that heat pump must be ON, I have to consider:
	-- time of day (in the night or morning, maybe it's better to delay heat pump ON to avoid working with high humidity and low temperatures)
	-- coeffArray defines a coefficient to be multiply for the average diffMax

	-- Temperature setpoint during Winter
	--                                      |^^^^^^^^^^^^^^^^^^^^^^^^^^^_______________________
	-- _______________|^^^^^^^^^^^^^^^^^^^^^^                                                  |_____________________
	-- 0          Sunrise+1                 11                    Sunset-0.5                   20
	

	-- Temperature setpoint during Summer
	-- 0          Sunrise+1                 10                   Sunset-0.5                   22
	-- ^^^^^^^^^^^^^^^|_____________________                                                  |^^^^^^^^^^^^^^^^^^^^^
	--                                      |___________________________^^^^^^^^^^^^^^^^^^^^^^^
	
	local minutes=1441
	local coeff=1
	-- scan entire coeffArray dictionary (because it's not sorted)
	for m,c in pairs(coeffArray) do
		if (minutesnow<m and minutes>m) then
			coeff=c
			minutes=m
		end
	end
	
	diffMaxValue=diffMax	-- difference between setpoint and real temperature
	diffMax=diffMax*coeff	-- diffMaxValue * weight that depends by time of the day
	log(E_INFO,'diffMaxValue='..diffMaxValue..' diffMax='..diffMax..' coeff='..coeff..' RHMax='..rhMax)

	-- check outdoorTemperature
	outdoorTemperature=string.gsub(otherdevices[tempOutdoor],';.*','')
	outdoorTemperature=tonumber(outdoorTemperature)	-- extract temperature, in case the device contains also humdity and/or pressure
	
	-- set outdoorTemperatureMin (reset every midnight)
	if (minutesnow==0 or HP['otmin']==nil or HP['otmin']>outdoorTemperature) then 
		HP['otmin']=outdoorTemperature
	end

	-- Also, I have to consider the availability of power from photovoltaic
	if (otherdevices[powerMeter]~=nil) then
		-- power meter exists, returning value "usagePower;totalEnergy"
		-- Also, script_device_power.lua is writing the user variable avgPower with average consumed power in the minute
		if (inverterMeter ~= '' and otherdevices[inverterMeter]~=nil) then
			-- inverterMeter device exists: extract power (skip energy or other values, separated by ;)
			for p in otherdevices[inverterMeter]:gmatch("[^;]+") do
				inverterPower=p
				break
			end
			log(E_INFO,"AveragePower:"..uservariables['avgPower'].."W From PV:"..inverterPower.."W")
		else
			log(E_INFO,"AveragePower:"..uservariables['avgPower'].."W")
		end

		-- Level indicate how much power the heating/cooling system can use, for example:
		-- Level 1 => dehumidifier ON (HeatPump ON, Ventilation ON, Ventilation chiller ON
		-- Level 2 => + radiant system ON
		-- Level 3 => + HeatPump full power
		-- Level 4 => + HeatPump Fancoil temperature (use with care with radiant system!!) Disabled by defaul
		
		-- TODO: dehumidification during winter: how? My stupid CMV needs cold water to do that!
		if (uservariables['HeatPumpWinter']==0 and rhMax>60 and HP['Level']==LEVEL_OFF and prodPower>1000) then
			-- high humidity: activate heatpump + ventilation + chiller (Level 1)
			incLevel()
		end
		
		if (minutesnow<timeofday['SunriseInMinutes']+180 and diffMax<diffMaxHigh_value) then 
			-- in the morning, if temperature is not so distant from the setpoint, try to not consume from the grid
			diffMaxHigh_power=0 
		end
		if (diffMax>0) then
			if (usagePower<POWER_MAX-1700) then
				-- must heat/cool!
				if (prodPower>prodPower_incLevel) then
					-- more available power => increment level
					if (HP['Level']<level_max) then
						incLevel()
						if (prodPower>prodPower_incLevel2 and HP['Level']<level_max) then
							incLevel()
						end
					end	
				else
					-- low or no power from PV
					-- if setpoint is much distant from actual temperature, and we're operating in "warm" hours, enable FANCOIL mode (higher temperature)
					if (diffMax>diffMaxHigh_value) then
						-- no power from photovoltaic, but temperature is far from setpoint
						--[[
						-- increase level to level_max-1
						if (HP['Level']<(level_max-1)) then
							incLevel(); 
						end
						]]
						-- in winter mode, during the day, increase again the level (it's better to use heatpump during the day than during the night!)
						if (uservariables['HeatPumpWinter']==1) then
							if (HP['Level']<2) then
								incLevel()
							end
							if (HP['Level']<level_max and (minutesnow>timeofday['SunriseInMinutes']+120 and minutesnow<=timeofday['SunsetInMinutes']+120)) then
								incLevel()
							end
						end
					elseif ((HP['Level']>1 or (minutesnow<timeofday['SunsetInMinutes']-240)) and usagePower>diffMaxHigh_power)  then  -- if diffMax<diffMaxHigh_value (temperature near setpoint) and no available power from renewables => reduce or turn off the cooling
						decLevel()
					end
				end
				-- check that fluid is not too high (Winter) or too low (Summer), else disactivate HeatPump_Fancoil output (to switch heatpump to radiant fluid, not coil fluid temperature
				if (uservariables['HeatPumpWinter']==1) then
					-- make tempFluidLimit higher if rooms are cold
					tempFluidLimit=30
					-- if outdoor temperature > 28 => tempFluidLimit-=(outdoorTemperature-28)/3
					if (HP['otmin']<10) then -- outdoorTemperatureMin<10 => if min outdoor temperature is low, increase the fluid temperature from heatpump
						tempFluidLimit=tempFluidLimit+(10-HP['otmin'])/1.3 --30°C if min outdoor temp = 10°C, 40°C if min outodor temp = -3°C
					end
					-- also, regulate fluid temperature in base of of DeltaT
					tempFluidLimit=tempFluidLimit+diffMax*2
					-- if (diffMax<0.5) then tempFluidLimit=tempFluidLimit+0.5 end
					-- if (diffMax<=0.2) then tempFluidLimit=tempFluidLimit+0.5 end
					if (tempFluidLimit>TEMP_WINTER_HP_MAX) then
						tempFluidLimit=TEMP_WINTER_HP_MAX
					end
				else
					-- during the Summer
					-- make tempFluidLimit lower if rooms are warm
					tempFluidLimit=18
					-- if outdoor temperature > 28 => tempFluidLimit-=(outdoorTemperature-28)/3
					if (outdoorTemperature>28) then
						tempFluidLimit=tempFluidLimit-(outdoorTemperature-28)/3
					end
					-- also, regulate fluid temperature in base of of DeltaT
					tempFluidLimit=tempFluidLimit-diffMax
					-- if (diffMax<0.5) then tempFluidLimit=tempFluidLimit+0.5 end
					-- if (diffMax<=0.2) then tempFluidLimit=tempFluidLimit+0.5 end
					if (tempFluidLimit<TEMP_SUMMER_HP_MIN) then
						tempFluidLimit=TEMP_SUMMER_HP_MIN
					end
				end

				if (diffMax<=0.1 and HP['Level']>3) then 
					log(E_INFO,"Rooms are almost in temperature: avoid high power levels")
					decLevel() 
				end		-- less power when rooms are in temperature

				-- regulate fluid tempeature in case of max Level 
				if (uservariables['HeatPumpWinter']==1) then
					-- tempHPout < tempFluidLimit => FANCOIL + FULLPOWER
					-- tempFluidLimit < tempHPout < tempFluidLimit+2 => FANCOIL
					-- tempHPout > tempFluidLimit+2 or tempHPin > tempFluidLimit => FANCOIL-1
					if ((HP['Level']>=LEVEL_WINTER_FANCOIL and (tonumber(otherdevices[tempHPout])>tempFluidLimit-1))) then
						-- fluid temperature > tempFluidLimit => assure that heatpump power is low
						if (HP['Level']>LEVEL_WINTER_FANCOIL) then
							decLevel()
						end
						if (tonumber(otherdevices[tempHPout])>tempFluidLimit+2 or tonumber(otherdevices[tempHPin])>tempFluidLimit) then
							log(E_INFO,"Fluid temperature to radiant/coil > "..tempFluidLimit.." => switch to radiant temperature")
							while (HP['Level']>=LEVEL_WINTER_FANCOIL) do decLevel() end
						end
					end
				else -- Summer
					-- TODO: reduce power when tempHPout is near the tempFluidLimit !!
					if ((HP['Level']<=level_max and tonumber(otherdevices[tempHPOut])<tempFluidLimit)) then
						log(E_INFO,"Fluid temperature to radiant/coil < "..tempFluidLimit.." => switch to radiant temperature")
						while (HP['Level']>=3) do decLevel() end
					end
				end
			elseif (usagePower>=POWER_MAX-500) then --usagePower>=POWER_MAX: decrement level
				decLevel()
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			--reached the set point => reduce HP['Level'] till LEVEL_ON (if must dehumidify) or LEVEL_OFF if humidity is ok
			log(E_INFO,"All zones are in temperature! RHMax="..rhMax)
			if (uservariables['HeatPumpWinter']==1 or rhMax<60 or usagePower>0 or HP['Level']>LEVEL_ON)  then 
				-- temperature and humidity are OK, or Level > 1
				-- dehumidifier ignored during winter, and disabled when there is not enough power from photovoltaic
				decLevel() 
			end
		end
	else
		log(E_DEBUG,'No power meter installed')
	end
end

gasHeaterOn=0
if (GasHeater~=nil and GasHeater~='' and otherdevices[GasHeater]~=nil and uservariables['HeatPumpWinter']==1) then
	-- boiler exists: activate it during the night if outdoorTemperature<GHoutdoorTemperatureMax and if diffMaxValue>=GHdiffMax
	if (otherdevices[GasHeater]=='On') then
		-- add some histeresys to prevent gas heater switching ON/OFF continuously
		GHdiffMax=GHdiffMax-0.1
		GHoutdoorTemperatureMax=GHoutdoorTemperatureMax+1
	end
	if (--[[HP['Level']==LEVEL_OFF and ]] minutesnow>=GHtimeMin and minutesnow<GHtimeMax and diffMaxValue>=GHdiffMax and outdoorTemperature<GHoutdoorTemperatureMax) then
		HP['Level']=LEVEL_OFF	-- force heat pump off and use only gas heater, in the night
		if (otherdevices[GasHeater]~='On') then
			gasHeaterOn=1
			deviceOn(GasHeater,'GH')
			-- enable devices that must be enabled when gas heater is On
			for n,v in pairs(GHdevicesToEnable) do
				commandArray[v]='On'
			end
		end
	else
		if (otherdevices[GasHeater]~='Off' and (HP['dGH']~=nil and HP['dGH']=='a')) then
			deviceOff(GasHeater,'GH')
			gasHeaterOn=0
			for n,v in pairs(GHdevicesToEnable) do
				commandArray[v]='Off'
			end
		end
	end
	if (otherdevices[GasHeater]=='On') then
		-- gas heater on by script, or forced ON by user => disable heat pump
		gasHeaterOn=1
		decLevel()
		decLevel()
		decLevel()
		decLevel()
	end
end

-- now scan DEVlist and enable/disable all devices based on the current level HP['Level']
if (uservariables['HeatPumpSummer']==1) then devLevel=3 else devLevel=2 end	-- summer: use next field for device level
for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	if (v[devLevel]<=level_max) then -- ignore devices configured to have a very high level
		if (HP['Level']>=v[devLevel]) then
			-- this device has a level <= of current level => enable it
			deviceOn(v[1],n)
		else
			-- this device has a level > of current level => disable it
			deviceOff(v[1],n)
		end
	end
end

updateValves()	

-- now check heaters and dehumidifiers in DEVauxlist...
-- devLevel for DEVauxlist is the same as DEVlist -- if (uservariables['HeatPumpSummer']==1) then devLevel=3 else devLevel=2 end	-- summer: use next field for device level
if (uservariables['HeatPumpSummer']==1) then devCond=8 else devCond=5 end	-- devCond = field that contains the device name for condition used to switch ON/OFF device

-- Parse DEVauxlist to check if anything should be enabled or disabled
-- If heat pump level has changed, don't enable/disable aux devices because the measured prodPower may change 
for n,v in pairs(DEVauxlist) do
	if (otherdevices[ v[devCond] ]~=nil) then
		if (tonumber(otherdevices[ v[devCond] ])<v[devCond+2]) then cond=1 else cond=0 end
		-- check timeout, if defined
		auxTimeout=0
		auxMaxTimeout=1440
		if (v[11]~=nil and v[11]>0) then
			-- max timeout defined => check that device has not reached the working time = max timeout in minutes
			auxMaxTimeout=v[11]
			checkVar('Timeout_'..v[1],0,0) -- check that uservariable at1 exists, else create it with type 0 (integer) and value 0
			auxTimeout=uservariables['Timeout_'..v[1]]
			if (otherdevices[ v[1] ]~='Off') then
				-- device is actually on => increment timeout
				auxTimeout=auxTimeout+1
				commandArray['Variable:Timeout_'..v[1]]=tostring(auxTimeout)
				if (auxTimeout>=v[11]) then
					-- timeout reached -> send notification and stop device
					deviceOff(v[1],'a'..n)
					log(TELEGRAM_LEVEL,"Timeout reached for "..v[1]..": device was stopped")
				end
			end
		end
		-- change state only if previous heatpump level match the current one (during transitions from a power level to another, power consumption changes)
		if (levelOld==HP['Level']) then
			if (otherdevices[ v[1] ]~='Off') then
				-- device is ON
				if (prodPower<(v[4]-100) or (HP['Level']<v[devLevel] and diffMax>0) or cond==v[devCond+1] --[[ or otherdevices['VMC_Rinnovo']=='On' ]]) then
					deviceOff(v[1],'a'..n)
					prodPower=prodPower+v[4]	-- update prodPower, adding the power consumed by this device that now we're going to switch off
				end
			else
				-- device is OFF
				if (auxTimeout<auxMaxTimeout and prodPower>=(v[4]+100) and cond~=v[devCond+1]) then
					deviceOn(v[1],'a'..n)
					prodPower=prodPower-v[4] 	-- update prodPower
				end
			end
		end
	end
end

-- other customizations....
-- Make sure that radiant circuit is enabled when outside temperature goes down, or in winter, because heat pump starts to avoid any damage with low temperatures
if (uservariables['HeatPumpSummer']==0) then
	if (HP['Level']>LEVEL_OFF or GasHeaterOn==1 or outdoorTemperature<=4) then
		if (otherdevices['Valve_Radiant_Coil']~='On') then
			commandArray['Valve_Radiant_Coil']='On'
		end
	else
		if (otherdevices['Valve_Radiant_Coil']~='Off') then
			commandArray['Valve_Radiant_Coil']='Off'
		end
	end
end


-- save variables
log(E_INFO,'Level:'..levelOld..'->'..HP['Level']..' GH='..otherdevices[GasHeater]..' HPout='..otherdevices[tempHPout]..' HPLimit='..string.format("%.1f", tempFluidLimit)..' HPin='..otherdevices[tempHPin]..' Outdoor='..otherdevices[tempOutdoor]..' zHeatPump='..json.encode(HP))
commandArray['Variable:zHeatPump']=json.encode(HP)

::mainEnd::
return commandArray
