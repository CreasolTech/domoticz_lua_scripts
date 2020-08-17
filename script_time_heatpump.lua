-- Lua script for Domoticz, controlling the heating/cooling system by a heat pump supplied by electric grid + photovoltaic 
-- Designed to consume as most as possible energy from photovoltaic
-- Written by Creasol, https://www.creasol.it , linux@creasol.it
--
-- Please assure that
-- 127.0.0.1 is in Configuration -> Settings -> Local Networks enabled without authentication (e.g. 127.0.0.1;192.168.1.*)
--
commandArray={}

--do return commandArray	end --Return now, skipping everything else
dofile "/home/pi/domoticz/scripts/lua/heatpump_conf.lua"

-- set HP['Level'] to level , and set current level to 'auto' to permit reducing power automatically if consumed current is too high
-- note, level must be increased 1by1 so all new level are set to 'auto', otherwise the system will get stuck in a intermediate level that was not set to 'auto'
function incLevel() 
	HP['Level']=HP['Level']+1
end

-- set HP['Level'] to level , and reset current level to ''
function decLevel()
	if (HP['Level']>0) then
		HP['Level']=HP['Level']-1
		log(E_INFO,'Decrement Level to '..HP['Level'])
	else
		HP['Level']=0
	end
end

function HPinit()
	if (HP==nil) then HP={} end
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
	-- if devname is on and was on by this script => turn it off
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
		if (otherdevices[DEVlist[1][1]]=='Off') then 
			valveStateTemp[v[ZONE_VALVE]]='Off'	
		end
		-- update commandArray only when valve status have changed
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE]]~=valveStateTemp[v[ZONE_VALVE]]) then
			commandArray[v[ZONE_VALVE]]=valveStateTemp[v[ZONE_VALVE]]
			log(E_INFO,'**** Valve for zone '..n..' changed to '..valveStateTemp[v[ZONE_VALVE]])
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
checkVar('HeatPumpSummer',0,0)
checkVar('HeatPumpWinter',0,0)

for n,v in pairs(zones) do	-- check that temperature setpoint exist
	-- n=zone name, v=CSV separated by | containing tempsensor and electrovalve device name
	checkVar('TempSet_'..n,1,21)
	-- check that devices exist
	if (otherdevices[v[ZONE_TEMP_DEV]]==nil) then
		log(E_CRITICAL,'Zone '..n..': temperature sensor '..v[ZONE_TEMP_DEV]..' does not exist')
	end
	if (v[ZONE_RH_DEV] and v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV]]==nil) then
		log(E_CRITICAL,'Zone '..n..': relative humidity device '..v[ZONE_RH_DEV]..' defined in heatpump_conf.lua but does not exist')
	end
	if (v[ZONE_VALVE] and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE]]==nil) then
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

-- Also, I have to consider the availability of power from photovoltaic
if (otherdevices[powerMeter]~=nil) then
	-- power meter exists, returning value "usagePower;totalEnergy"
	for str in otherdevices[powerMeter]:gmatch("[^;]+") do
		usagePower=tonumber(str)
		break
	end
else 
	usagePower=500 -- power meter does not exist: set usagePower to 500W by default
end
prodPower=0-usagePower

if (uservariables['HeatPumpWinter']==1) then
	-- Heating enabled
	log(E_INFO,'================================= HeatPumpWinter ================================')
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	zonesOn=0	-- number of zones that are ON
	-- check temperatures and setpoints
	for n,v in pairs(zones) do
		-- n=zonename (HeatingSP_n = setpoint temperature)
		-- v[ZONE_TEMP_DEV]=tempsensor
		-- v[ZONE_VALVE]=valve device
		-- v[ZONE_WINTER_START]=start time
		-- v[ZONE_WINTER_STOP]=end time
		-- v[ZONE_WINTER_OFFSET]=offset to be used during the night, used to tolerate a lower temperature when rooms are unused
		-- v[ZONE_WINTER_WEIGHT]=weight to calculate the weighted difference between setpoint and current temperature (for some rooms, maybe it's not so important to get exactly the temperature indicated by the SetPoint variable)
		--
		-- check temperature offset defined for each zone (used to reduce temperature during the night
		temperatureOffset=0
		if (timenow.hour < v[ZONE_WINTER_START] or timenow.hour >= v[ZONE_WINTER_STOP]) then
			-- night: reduce the temperature setpoint
			temperatureOffset=v[ZONE_WINTER_OFFSET]
		end

		-- diff=(setpoint-offset)-temperature
		diff=(uservariables['TempSet_'..n]-temperatureOffset)-tonumber(otherdevices[v[ZONE_TEMP_DEV]]);
		if (diff>0) then
			-- must heat!
			valveState='On'
			diff=diff*v[ZONE_WINTER_WEIGHT]	-- compute the weighted difference between room temperature and setpoint
			zonesOn=zonesOn+1
		else
			-- temperature >= (setpoint-offset) => diff<=0
			valveState='Off'
		end
		if (diff>diffMax) then
			diffMax=diff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='') then
			valveStateTemp[v[ZONE_VALVE]]=valveState
		end
		log(E_DEBUG,valveState..' zone='..n..' temp='..tonumber(otherdevices[v[ZONE_TEMP_DEV]])..' SP='..uservariables['TempSet_'..n]..'-'..temperatureOffset..' diff='..diff)
	end
	-- Now diffMax stores the max weighted-difference between setpoint and temperature 
	-- To be sure that heat pump must be ON, I have to consider:
	-- time of day (in the night or morning, maybe it's better to delay heat pump ON to avoid working with high humidity and low temperatures)
	-- coeffArray defines a coefficient to be multiply for the average diffMax

	--
	--                                      |^^^^^^^^^^^^^^^^^^^^^^^^^^^_______________________
	-- _______________|^^^^^^^^^^^^^^^^^^^^^^                                                  |_____________________
	-- 0          Sunrise+1                 11                    Sunset-0.5                   20
	
	local minutes=1441
	local coeff=1
	-- scan entire dictionary (because it's not sorted)
	for m,c in pairs(coeffArray) do
		if (minutesnow<m and minutes>m) then
			coeff=c
			minutes=m
		end
	end
	
	diffMax=diffMax*coeff
	log(E_INFO,'Time of day coeff='..coeff..' diffMax='..diffMax)

	-- Also, I have to consider the availability of power from photovoltaic
	if (otherdevices[powerMeter]~=nil) then
		-- power meter exists, returning value "usagePower;totalEnergy"
		
		log(E_INFO,"currentPower:"..usagePower.."W")
		if (diffMax<0.2 and diffMax>(OVERHEAT*-1) and ((HP['Level']==LEVEL_OFF and usagePower<-800) or (HP['Level']>LEVEL_OFF and usagePower<-200))) then
			log(E_INFO,"*** Power available from PV => increase diffMax to heat more than setpoint")
			diffMax=0.2
			log(E_INFO,'Increment Level to '..HP['Level'])
			incLevel()
		elseif (diffMax>0) then
			-- must heat!
			if (usagePower<-300) then
				if (HP['Level']<LEVEL_WINTER_MAX) then
					log(E_INFO,'Increment Level to '..HP['Level'])
					incLevel()
					if (usagePower<-1000 and HP['Level']<LEVEL_WINTER_MAX) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel()
					end
				end	
			elseif (usagePower>500) then
				-- if setpoint is much distant from actual temperature, and we're operating in "warm" hours, enable FANCOIL mode (higher temperature)
				if (diffMax>0.4) then
					if (HP['Level']<LEVEL_FULLPOWER) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel();
					end
					if (HP['Level']<LEVEL_FANCOIL and ((timenow.hour>=10 and timenow.hour<17))) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel()
					end
				elseif (HP['Level']>LEVEL_ON) then	-- diffMax<=0.4 => almost in temperature
					log(E_INFO,'Reduce the HeatPump level to save power')
				end
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			--reached the set point => reduce HP['Level'] till LEVEL_OFF
			log(E_INFO,"All zones are in temperature!")
			if (HP['Level']==LEVEL_ON) then 
				heatPumpOff(0) 
			else
				decLevel()
			end
		end
	else
		log(E_DEBUG,'No power meter installed')
	end

elseif (uservariables['HeatPumpSummer']==1) then
	-- Summer => cooling and drying
	log(E_INFO,'================================= HeatPumpSummer ================================')
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0
	rhMax=70	-- DEBUG: force RH to a high value

	zonesOn=0	-- number of zones that are ON
	SPOffset=0	-- offset on setpoint
	if (prodPower>800) then	-- more than 800W fed to the electrical grid
		SPOffset=OVERCOOL	-- decrease setpoint by OVERCOOL parameter (1 degree) to overcool, in case of extra available energy
	end
	-- check temperatures and setpoints
	for n,v in pairs(zones) do
		-- n=zonename (HeatingSP_n = setpoint temperature)
		-- v[ZONE_TEMP_DEV]=tempsensor
		-- v[ZONE_RH_DEV]=relative humidity sensor
		-- v[ZONE_VALVE]=valve device
		-- v[ZONE_SUMMER_START]=start time
		-- v[ZONE_SUMMER_STOP]=end time
		-- v[ZONE_SUMMER_OFFSET]=offset to be used during the night, used to tolerate a lower temperature when rooms are unused
		-- v[ZONE_SUMMER_WEIGHT]=weight to calculate the weighted difference between setpoint and current temperature (for some rooms, maybe it's not so important to get exactly the temperature indicated by the SetPoint variable)
		--
		-- check temperature offset defined for each zone (used to reduce temperature during the night
		temperatureOffset=0
		if (timenow.hour < v[ZONE_SUMMER_START] or timenow.hour >= v[ZONE_SUMMER_STOP]) then
			-- night: reduce the temperature setpoint
			temperatureOffset=v[ZONE_SUMMER_OFFSET]
		end
		rh=0
		if (v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV]]~=nil) then
			rh=tonumber(otherdevices[v[ZONE_RH_DEV]]);
			if (rh>rhMax) then rhMax=rh end
		end

		-- diff=temperature-(setpoint+offset): if diff>0 => must cool
		diff=tonumber(otherdevices[v[ZONE_TEMP_DEV]])-(uservariables['TempSet_'..n]+temperatureOffset)+SPOffset;
		if (diff>0) then
			-- must cool!
			valveState='On'
			diff=diff*v[ZONE_SUMMER_WEIGHT]	-- compute the weighted difference between room temperature and setpoint
			zonesOn=zonesOn+1
		else
			-- temperature <= (setpoint+offset) => diff<=0
			valveState='Off'
		end
		if (diff>diffMax) then
			diffMax=diff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='') then
			valveStateTemp[v[ZONE_VALVE]]=valveState
		end
		log(E_DEBUG,valveState..' zone='..n..' RH='..rh..' Temp='..otherdevices[v[ZONE_TEMP_DEV]]..' SP='..uservariables['TempSet_'..n]..'+'..temperatureOffset..' diff='..diff)
	end
	-- Now diffMax stores the max weighted-difference between setpoint and temperature 
	-- To be sure that heat pump must be ON, I have to consider:
	-- time of day (in the night or morning, maybe it's better to delay heat pump ON to avoid working with high humidity and low temperatures)
	-- coeffArray defines a coefficient to be multiply for the average diffMax

	--
	-- 0          Sunrise+1                 10                   Sunset-0.5                   22
	-- ^^^^^^^^^^^^^^^|_____________________                                                  |^^^^^^^^^^^^^^^^^^^^^
	--                                      |___________________________^^^^^^^^^^^^^^^^^^^^^^^
	
	local minutes=1441
	local coeff=1
	-- scan entire dictionary (because it's not sorted)
	for m,c in pairs(coeffArray) do
		if (minutesnow<m and minutes>m) then
			coeff=c
			minutes=m
		end
	end
	
	diffMax=diffMax*coeff
	log(E_INFO,'Time of day coeff='..coeff..' diffMax='..diffMax..' RHMax='..rhMax)

	-- Also, I have to consider the availability of power from photovoltaic
	if (otherdevices[powerMeter]~=nil) then
		-- power meter exists, returning value "usagePower;totalEnergy"
		
		log(E_INFO,"currentPower:"..usagePower.."W")
		-- Level 1 => dehumidifier ON (HeatPump ON, Ventilation ON, Ventilation chiller ON
		-- Level 2 => + radiant system ON
		-- Level 3 => + HeatPump full power
		-- Level 4 => + HeatPump Fancoil temperature (use with care with radiant system!!) Disabled by defaul
		if (rhMax>60 and HP['Level']==LEVEL_OFF and prodPower>1000) then
			-- high humidity: activate heatpump + ventilation + chiller (Level 1)
			incLevel()
		end
		
		if (diffMax>0) then
			-- must cool!
			if (prodPower>800) then
				if (HP['Level']<LEVEL_SUMMER_MAX) then
					log(E_INFO,'Increment Level to '..HP['Level'])
					incLevel()
					if (prodPower>1000 and HP['Level']<LEVEL_SUMMER_MAX) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel()
					end
				end	
			elseif (usagePower>200) then
				-- if setpoint is much distant from actual temperature, and we're operating in "warm" hours, enable FANCOIL mode (higher temperature)
				if (diffMax>2) then
					-- no power from photovoltaic, but temperature is 2 degrees above the set level => cool!
					if (HP['Level']<LEVEL_FULLPOWER) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel();
					end
					if (HP['Level']<LEVEL_SUMMER_MAX and ((timenow.hour>=9 and timenow.hour<19))) then
						log(E_INFO,'Increment Level to '..HP['Level'])
						incLevel()
					end
--				elseif (HP['Level']>LEVEL_ON) then	-- diffMax<=0.4 => almost in temperature
				else  -- if diffMax<2 and no available power from renewables, reduce or turn off the cooling
					log(E_INFO,'Reduce the HeatPump level to save power')
					decLevel()
				end
			end
			-- check that fluid is not below 18 degrees, else disactivate HeatPump_Fancoil
			-- Also, make tempFluidMin higher if rooms are cold enough
			tempFluidMin=18
			tempOut=string.gsub(otherdevices[tempOutdoor],';.*','')	-- extract temperature, in case the device contains also humdity and/or pressure
			tempOut=tonumber(tempOut) -- convert from string to number (float)
			-- if outdoor temperature > 28 => tempFluidMin-=(tempOut-28)/3
			if (tempOut>28) then
				tempFluidMin=tempFluidMin-(tempOut-28)/3
			end
			-- also, regulate fluid temperature in base of of DeltaT
			tempFluidMin=tempFluidMin-diffMax

			if (diffMax<0.5) then tempFluidMin=tempFluidMin+0.5 end
			if (diffMax<=0.2) then tempFluidMin=tempFluidMin+0.5 end
			if (diffMax<=0.3 and HP['Level']>3) then 
				log(E_INFO,"Rooms are almost in temperature: avoid high power levels")
				decLevel() 
			end		-- less power when rooms are in temperature

			if ((HP['Level']>=3 and tonumber(otherdevices[tempHPin])<tempFluidMin) or (tonumber(otherdevices[tempHPout])<TEMP_SUMMER_HP_MIN)) then
				log(E_INFO,"Fluid temperature from radiant/coil < "..tempFluidMin.." => switch to radiant temperature")
				while (HP['Level']>=3) do decLevel() end
			elseif (HP['Level']>=4 and (tonumber(otherdevices[tempHPin])<(tempFluidMin+0.5) or tonumber(otherdevices[tempHPout])<(TEMP_SUMMER_HP_MIN+1))) then
				log(E_INFO,"Disable full power")
				decLevel();	-- avoid maximum level in case temperature is near the 
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			--reached the set point => reduce HP['Level'] till LEVEL_ON (if must dehumidify) or LEVEL_OFF if humidity is ok
			log(E_INFO,"All zones are in temperature! RHMax="..rhMax)
			if (rhMax<60 or HP['Level']>LEVEL_ON or usagePower>0)  then 
				-- temperature and humidity are OK, or Level > 1
				decLevel() 
			end
		end
	else
		log(E_DEBUG,'No power meter installed')
	end

else
	-- HeatingOn=0 => Stop heating
	if (otherdevices[DEVlist[1][1]]~='Off') then
		heatPumpOff(0)	-- turn Off
		updateValves()
	end
	goto mainEnd
end


-- now scan DEVlist and enable/disable all devices based on the current level HP['Level']
if (uservariables['HeatPumpSummer']==1) then devLevel=3 else devLevel=2 end	-- summer: use next field for device level
for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	if (HP['Level']>=v[devLevel]) then
		-- this device has a level <= of current level => enable it
		deviceOn(v[1],n)
	else
		-- this device has a level > of current level => disable it
		deviceOff(v[1],n)
	end
end
updateValves()	

-- now check heaters and dehumidifiers in DEVauxlist...
-- devLevel for DEVauxlist is the same as DEVlist -- if (uservariables['HeatPumpSummer']==1) then devLevel=3 else devLevel=2 end	-- summer: use next field for device level
if (uservariables['HeatPumpSummer']==1) then devCond=8 else devCond=5 end	-- devCond = field that contains the device name for condition used to switch ON/OFF device
if (levelOld==HP['Level']) then
	-- level was not changed: parse DEVauxlist to check if anything should be enabled or disabled
	-- if level has changed, don't enable/disable aux devices because the measured prodPower may change 
	for n,v in pairs(DEVauxlist) do
		if (tonumber(otherdevices[ v[devCond] ])<v[devCond+2]) then cond=1 else cond=0 end

		if (prodPower<(v[4]-100) or HP['Level']<v[devLevel] or cond==v[devCond+1] or otherdevices['VMC_Rinnovo']=='On') then
			deviceOff(v[1],'a'..n)
		else
			deviceOn(v[1],'a'..n)
		end
	end
end

-- save variables
log(E_INFO,'Level='..HP['Level']..' tempHPout='..otherdevices[tempHPout]..' tempHPin='..otherdevices[tempHPin]..' TempFluidMin='..tempFluidMin..' TempOutdoor='..otherdevices[tempOutdoor]..' zHeatPump='..json.encode(HP))
commandArray['Variable:zHeatPump']=json.encode(HP)

::mainEnd::
return commandArray
