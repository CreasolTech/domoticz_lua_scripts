-- Lua script for Domoticz, controlling the EMMETI MIRAI SMI heat pump using ModBus
-- Designed to consume the most energy from photovoltaic
-- Written by Creasol, https://www.creasol.it , linux@creasol.it
--
-- Needs the lua modbus module, that should be installed in this way (from root):
-- cd /usr/local/src
-- git clone https://github.com/etactica/lua-libmodbus.git
-- cd lua-libmodbus
-- make install
--
-- Please assure that
-- 127.0.0.1 is enabled to connect without authentication, in Domoticz -> Configuration -> Settings -> Local Networks (e.g. 127.0.0.1;192.168.1.*)
--
-- Emmeti Mirai heatpump: verify that:
-- * 16436 = 140 (14°C) = minimum fluid temperature for cooling using the radiant system
--
commandArray={}
dofile "/home/pi/domoticz/scripts/lua/config_heatpump_emmeti.lua"

-- Level can be 0 (OFF) or >0 (ON: the higher the level, more power can be used by the heat pump)
-- Increment the level (available power for the heat pump)
function incLevel() 
	if (HP['Level']<levelMax) then
		HP['Level']=HP['Level']+1
		log(E_INFO,'Increment Level to '..HP['Level'])
	end
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
	if (HP['otmin']==nil) then HP['otmin']=10 end	-- outodorTemperatureMin
	if (HP['otmax']==nil) then HP['otmax']=10 end	-- outodorTemperatureMin
	if (HP['Level']==nil) then HP['Level']=0 end
	if (HP['Limit']==nil) then HP['Limit']=25 end	-- tempFluidLimit (previous saved value)
	if (HP['CP']==nil) then HP['CP']=0 end			-- compressorPerc
	if (HP['HPout']==nil) then HP['HPout']=0 end	-- TEMPHPOUT_DEV temperature
	if (HP['t']==nil) then HP['t']=0 end			-- when HP works at max level, the level can be reduced only if the system ask to reduce it for at least 5 minutes
	if (HP['trc']==nil) then HP['trc']=0 end		-- disable the Valve_Radiant_Coil after 3 minutes from HeatPump going OFF
	if (HP['OL']==nil) then HP['OL']=0 end			-- OverLimit: used to overheat or overcool
	if (HP['mb']==nil) then HP['mb']=0 end			-- Heat pump modbus error
end

-- Initialize the HPZ domoticz variable (json coded, used to compute temperature tempDerivate of a zone that is always enabled)
function HPZinit()
	if (HPZ==nil) then HPZ={} end
	if (HPZ['temp']==nil) then HPZ['temp']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, at the current hh:00 time
	if (HPZ['t0']==nil) then HPZ['t0']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, at the current hh:00 time
	if (HPZ['t1']==nil) then HPZ['t1']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, 1 hour ago (at hh-1:00)
	if (HPZ['t2']==nil) then HPZ['t2']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, 2 hour ago (at hh-1:00)
	if (HPZ['t3']==nil) then HPZ['t3']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, 3 hour ago (at hh-1:00)
	if (HPZ['t4']==nil) then HPZ['t4']=otherdevices[TempZoneAlwaysOn] end	-- Temperature of a zone always ON, 4 hour ago (at hh-1:00)
	if (HPZ['gr']==nil) then HPZ['gr']=0 end -- tempDerivate for a zone always ON
	if (HPZ['ft']==nil) then HPZ['ft']=25 end -- fluid temperature
end

-- switch ON/OFF valves to enable/disable zones
function updateValves()
	-- check valveStateTemp and update valve status
	for n,v in pairs(zones) do
		-- v[ZONE_NAME]=zonename (HeatingSP_n = setpoint temperature)
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
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='' and valveStateTemp[v[ZONE_VALVE] ]~=nil and otherdevices[v[ZONE_VALVE] ]~=valveStateTemp[v[ZONE_VALVE] ]) then
			if (valveStateTemp[v[ZONE_VALVE] ] == 'On') then
				deviceOn(v[ZONE_VALVE],HP,'v'..n)
			else
				deviceOff(v[ZONE_VALVE],HP,'v'..n)
			end
			log(E_INFO,'**** Valve for zone '..v[ZONE_NAME]..' changed to '..valveStateTemp[ v[ZONE_VALVE] ])
		end

	end 
end

monthnow = tonumber(os.date("%m"))
timenow = os.date("*t")
minutesnow = timenow.min + timenow.hour * 60

-- check variables
json=require("dkjson")
HPmode='Off'	-- Default: don't heat/cool
if (otherdevices[HPMode] == nil) then
	log(E_WARNING,"A device must be created by hand!\n***************** ERROR *****************\nSelector switch Off/Winter/Summer does not exist => must be created!\nGo to Setup -> Hardware, create a Dummy hardware (if not exists) and then Create virtual sensor, name '".. HPMode .. "' type Selector switch\nGo to Switches panel, edit the new device " .. HPMode .. " and rename level1 to 'Winter', level2 to 'Summer' and delete level 30")
else
	if (otherdevices[HPMode] == 'Winter') then
		HPmode='Winter'
	elseif (otherdevices[HPMode] == 'Summer') then
		HPmode='Summer'
	elseif (otherdevices[HPMode] ~= 'Off') then
		log(E_WARNING,"Device "..HPmode.." must have the following level names:\n0 => 'Off', 10 => 'Winter' and 20 => 'Summer'")
	end
end
if (uservariables['zHeatPump'] == nil) then
	-- initialize variable
	HPinit()	--init HP table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zHeatPump',2,json.encode(HP))
else
	HP=json.decode(uservariables['zHeatPump'])
	HPinit()	-- check that all variables in HP table are initialized
end

if (uservariables['zHeatPumpZone'] == nil) then
	-- initialize variable
	HPZinit()	--init HPZ table
	-- create a Domoticz variable, coded in json, within all variables used in this module
	checkVar('zHeatPumpZone',2,json.encode(HPZ))
else
	HPZ=json.decode(uservariables['zHeatPumpZone'])
	HPZinit()	-- check that all variables in HP table are initialized
end

if (timenow.min==0) then
	-- shift temperatures in HPZ['tn'] and compute new tempDerivate
	HPZ['t4']=HPZ['t3']
	HPZ['t3']=HPZ['t2']
	HPZ['t2']=HPZ['t1']
	HPZ['t1']=HPZ['t0']
	-- HPZ['t0']=otherdevices[TempZoneAlwaysOn]
	HPZ['t0']=HPZ['temp']
	HPZ['gr']=math.floor((HPZ['t0']-HPZ['t1'])/0.01+(HPZ['t1']-HPZ['t2'])/0.0125+(HPZ['t2']-HPZ['t3'])/0.015+(HPZ['t3']-HPZ['t4'])/0.02)/200
else
	HPZ['temp']=math.floor((HPZ['temp']*3+otherdevices[TempZoneAlwaysOn])/0.04)/100
end
tempDerivate=HPZ['gr']


levelOld=HP['Level']	-- save previous level
--levelOld=2	--DEBUG
diffMax=0

for n,v in pairs(zones) do	-- check that temperature setpoint exist
	-- n=zone name, v=CSV separated by | containing tempsensor and electrovalve device name
	checkVar('TempSet_'..v[ZONE_NAME],1,21)
	-- check that devices exist
	if (otherdevices[v[ZONE_TEMP_DEV] ]==nil) then
		log(E_CRITICAL,'Zone '..v[ZONE_NAME]..': temperature sensor '..v[ZONE_TEMP_DEV]..' does not exist')
	end
	if (v[ZONE_RH_DEV] and v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV] ]==nil) then
		log(E_CRITICAL,'Zone '..v[ZONE_NAME]..': relative humidity device '..v[ZONE_RH_DEV]..' defined in config_heatpump.lua but does not exist')
	end
	if (v[ZONE_VALVE] and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE] ]==nil) then
		log(E_CRITICAL,'Zone '..v[ZONE_NAME]..': valve device '..v[ZONE_VALVE]..' defined in config_heatpump.lua but does not exist')
	end
end

if (otherdevices[TEMPHPOUT_DEV] == nil) then
	log(E_CRITICAL,'Please create a temperature sensor named "'..TEMPHPOUT_DEV..'" that measures the temperature of fluid from heat pump to the radiant/coil system')
	goto mainEnd
end
if (otherdevices[TEMPHPIN_DEV] == nil) then
	log(E_CRITICAL,'Please create a temperature sensor named "'..TEMPHPIN_DEV..'" that measures the temperature of fluid from the radiant/coil system back to the heat pump')
	goto mainEnd
end
tempHPout=tonumber(otherdevices[TEMPHPOUT_DEV])
tempHPin=tonumber(otherdevices[TEMPHPIN_DEV])

valveState=''
valveStateTemp={}
tempFluidLimit=25	-- initialize value to avoid any error
gasHeaterOn=0
-- check outdoorTemperature
-- outdoorTemperature=string.gsub(otherdevices[tempOutdoor],';.*','')
-- outdoorTemperature=tonumber(outdoorTemperature)	-- extract temperature, in case the device contains also humdity and/or pressure
--
-- find outdoorTemperature and outdoorHumidity : otherdevices[tempOutdoor] is like "temp;hum;0;baro;"  "-2.70;89;0;1024;0"
for t, h in string.gmatch(otherdevices[tempOutdoor], "([%d.-]+);([%d.]+);.*") do
	outdoorTemperature=tonumber(t)
	outdoorHumidity=tonumber(h)
	break
end

-- Also, I have to consider the availability of power from photovoltaic
if (otherdevices[powerMeter]~=nil) then
	-- power meter exists, returning value "usagePower;totalEnergy"
	for str in otherdevices[powerMeter]:gmatch("[^;]+") do
		instPower=tonumber(str)
		break
	end
	avgPower=uservariables['avgPower']	-- use the average power instead of instant power!
	avgPower=(avgPower+instPower)/2	-- instead of using average power, it's better to check also the current power.
else 
	avgPower=500 -- power meter does not exist: set avgPower to 500W by default
end
prodPower=0-avgPower

if (heatpumpMeter~='' and otherdevices[heatpumpMeter]~=nil) then
	-- heat pump power meter exists, returning value "usagePower;totalEnergy"
	for str in otherdevices[heatpumpMeter]:gmatch("[^;]+") do
		HPPower=tonumber(str)
		break
	end
else 
	HPPower=0 -- power meter does not exist
end


if (HPmode ~= 'Winter' and HPmode ~= 'Summer') then
	-- Both heating and cooling are disabled
	HP['Level']=LEVEL_OFF
	levelOld=LEVEL_OFF	
	heatingCoolingEnabled=0
	levelMax=0
elseif (HPLevel~=nil and otherdevices[HPLevel]~=nil and otherdevices[HPLevel]=='Dehum') then
	-- Dehumidification selected
	if (HPmode ~= 'Summer') then
		-- cannot dry in Winter mode => cancel dehumidification level
		commandArray[HPLevel]='Off'
	else
		-- Activate heat pump to the minimum level, to send cold water to the MVHR (ventilation)
		log(E_INFO,'==================== HeatPump - Dehumidification ======================')
		HP['Level']=2
	end
elseif (HPLevel~=nil and otherdevices[HPLevel]~=nil and otherdevices[HPLevel]~='Auto') then
	-- Heat pump Level is forced by the selector switch
	log(E_INFO,'==================== HeatPump - Level forced to '..otherdevices[HPLevel]..' ======================')
	levelMax=tonumber(otherdevices[HPLevel])
	if (levelMax==nil) then levelMax=0 end	-- HPLevel selector switch was set to "Off" or to a non-numeric value
	HP['Level']=levelMax
	levelOld=levelMax
	if (HPmode=='Winter') then
		tempFluidLimit=35
	else
		tempFluidLimit=15
	end
else
	heatingCoolingEnabled=1
	-- Heating or cooling is enabled
	-- initialize some variables, depending by the HPmode variable)
	if (HPmode == 'Winter') then
		-- Heating enabled
		log(E_INFO,'================================= Winter ================================')
		zone_start=ZONE_WINTER_START	-- offset on zones[] structure
		zone_stop=ZONE_WINTER_STOP
		zone_offset=ZONE_WINTER_OFFSET
		zone_weight=ZONE_WINTER_WEIGHT
		levelMax=LEVEL_WINTER_MAX
		-- diffMaxHigh is used to define when room temperature is distant from the set point
	 	-- diffMaxHigh=0.1	-- if diffMax<diffMaxHigh, temperature is near the set point
		-- reduce diffMaxHigh if outdoor temperature is low (to use higher temperatures to heat the building)
		diffMaxHigh=(HP['otmin']/40)+HP['otmax']/160
		if (diffMaxHigh<0) then diffMaxHigh=0 end

		prodPower_incLevel=200		--minimum production power to increment level
		overlimitTemp=OVERHEAT		-- max overheat temperature
		overlimitPower=500			-- minimum power to start overheating	
		overlimitDiff=0.2			-- forced diffmax value
		modbusFluidTempBase=16421	-- register address for the fluid temperature
	else
		-- Cooling enabled
		log(E_INFO,'================================= Summer ================================')
		zone_start=ZONE_SUMMER_START	-- offset on zones[] structure
		zone_stop=ZONE_SUMMER_STOP
		zone_offset=ZONE_SUMMER_OFFSET
		zone_weight=ZONE_SUMMER_WEIGHT
		levelMax=LEVEL_SUMMER_MAX -- max value for HP['Level']
		-- cooling enabled only if consumed power is < 200 Watt. It's tolerated to consume more than 200W only if room temperature > setpoint + 2°C
		diffMaxHigh=2		-- if diffMax<diffMaxHigh, temperature is near the set point
		prodPower_incLevel=300		--minimum production power to increment level
		overlimitTemp=OVERCOOL		-- max overheat temperature
		overlimitPower=2500			-- minimum power to start overheating	
		overlimitDiff=0.2			-- forced diffmax value
		modbusFluidTempBase=16428	-- register address for the fluid temperature
	end
	realdiffMax=-10
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0		-- max value of relative humidity

	-- rhMax=70    -- DEBUG: force RH to a high value to force dehumidification

	zonesOn=0	-- number of zones that are ON
	
	-- check temperatures and setpoints
	for n,v in pairs(zones) do
		-- v[ZONE_NAME]=zonename (HeatingSP_n = setpoint temperature)
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
		if (v[ZONE_TEMP_DEV]==TempZoneAlwaysOn) then
			temp=HPZ['temp']
		else
			temp=tonumber(otherdevices[ v[ZONE_TEMP_DEV] ])
		end
		realdiff=uservariables['TempSet_'..v[ZONE_NAME]]+temperatureOffset-temp;	-- tempSet-temp+temperatureOffsetZone
		diff=realdiff										-- tempSet-temp+temperatureOffsetZone+temperatureOffsetGlobal
		if (HPmode ~= 'Winter') then
			-- summer => invert diff
			realdiff=0-realdiff	-- TempSet+offset(nighttime)-Temp
			diff=0-diff			-- TempSet+offset(nighttime)+offset(power)-Temp	increased when there is extra power from PV
		end
		if (diff>0) then
			-- must heat/cool!
			valveState='On'
			diff=diff*v[zone_weight]	-- compute the weighted difference between room temperature and setpoint
			realdiff=realdiff*v[zone_weight]
			zonesOn=zonesOn+1
		else
			-- temperature <= (setpoint+offset) => diff<=0
			valveState='Off'
		end
		if (diff>diffMax) then
			diffMax=diff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (realdiff>realdiffMax) then
			realdiffMax=realdiff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='') then
			valveStateTemp[v[ZONE_VALVE] ]=valveState
		end
		if (valveState=='On') then
			log(E_INFO,valveState..' zone='..v[ZONE_NAME]..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..v[ZONE_NAME]]..'+'..temperatureOffset..' diff='..diff)
		else
			log(E_DEBUG,valveState..' zone='..v[ZONE_NAME]..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..v[ZONE_NAME]]..'+'..temperatureOffset..' diff='..diff)
		end
		if (v[ZONE_TEMP_DEV]==TempZoneAlwaysOn) then
			diffZoneAlwaysOn=diff	-- diff calculated on the zone that is always on
		end
	end
	
	log(E_INFO,'tempDerivate='..tempDerivate..' diffMax='..diffMax..' diffMaxHigh='..diffMaxHigh..' RHMax='..rhMax)
	if (tempDerivate<0) then
		diffMax=diffMax-tempDerivate*2	-- if room temperature is decreasing, in winter, it's better to start heater early
		log(E_INFO,"Since tempDerivate<0 => increase diffMax to "..diffMax)
	end


	-- set outdoorTemperatureMin (reset every midnight)
	if (minutesnow==0 or HP['otmin']==nil or HP['otmin']>outdoorTemperature) then 
		HP['otmin']=outdoorTemperature
	end
	-- set outdoorTemperatureMax (reset every noon)
	if (minutesnow==720 or HP['otmax']==nil or HP['otmax']<outdoorTemperature) then 
		HP['otmax']=outdoorTemperature
	end

	-- Also, I have to consider the availability of power from photovoltaic
	if (otherdevices[powerMeter]~=nil) then
		-- power meter exists, returning value "usagePower;totalEnergy"
		-- Also, script_device_power.lua is writing the user variable avgPower with average consumed power in the minute
		if (inverterMeter ~= '' and otherdevices[inverterMeter]~=nil) then
			-- inverterMeter device exists: extract power (skip energy or other values, separated by ;)
			for p in otherdevices[inverterMeter]:gmatch("[^;]+") do
				inverterPower=tonumber(p)
				break
			end
			log(E_INFO,"AveragePower:"..uservariables['avgPower'].."W InstPower="..instPower.." From PV:"..inverterPower.."W")
		else
			inverterPower=0
			log(E_INFO,"AveragePower:"..uservariables['avgPower'].."W")
		end

		-- Level indicate how much power the heating/cooling system can use, for example:
		-- Level 1 => dehumidifier ON (HeatPump ON, Ventilation ON, Ventilation chiller ON
		-- Level 2 => + radiant system ON
		-- Level 3 => + HeatPump full power
		-- Level 4 => + HeatPump Fancoil temperature (use with care with radiant system!!) Disabled by defaul
		
		-- TODO: dehumidification during winter: how? My stupid CMV needs cold water to do that!
		if (HPmode == 'Summer' and rhMax>60 and HP['Level']==LEVEL_OFF and prodPower>1000) then
			-- high humidity: activate heatpump + ventilation + chiller (Level 1)
			incLevel()
		end

		-- In the morning, if room temperature is almost ok, try to export power to help the electricity grid
		if (peakPower()) then
			log(E_INFO,"Reduce diffMax to try exporting energy in the peak hours")
			if ((timenow.month>=11 or timenow.month<3)) then
				diffMax=diffMax-0.2
			else
				diffMax=diffMax-0.6
			end
		elseif (timenow.hour<12 or timenow.hour>=20) then
			-- in the morning, or in the night, no problem if the temperature is far from setpoint
			diffMaxHigh=diffMaxHigh+0.2
			log(E_INFO,"diffMaxHigh increased to "..diffMaxHigh)
		else
			-- during the day, not in peak hours
			if (prodPower>2000) then
				log(E_INFO,"Extra power => extra overlimit")
				overlimitTemp=overlimitTemp+0.3
			end
		end
		if (diffMax<=diffMaxHigh and diffMax+overlimitTemp>0) then
			if (HP['OL']==0 and prodPower>overlimitPower and peakPower()==false and (EVSEON_DEV=='' or otherdevices[EVSEON_DEV]=='Off')) then
				log(E_INFO,"OverHeating/Cooling: diffMax="..diffMax.."=>"..overlimitDiff)
				diffMax=overlimitDiff
				HP['OL']=1
			end
		end
		if (HP['OL']~=0) then
			-- overlimit is ON
			if ((EVSEON_DEV~='' and otherdevices[EVSEON_DEV]~='Off') or peakPower()) then
				-- EV is charging => disable overlimit now
				HP['OL']=0
				diffMax=0
			else
				-- EV not charging
				if (diffMax+overlimitTemp>0 and prodPower>0) then
					-- enough power
					HP['OL']=1
					diffMax=diffMax+overlimitDiff
				else
					-- not enough power
					log(E_INFO,"Not enough power to keep overlimit ON, or reached max temperature")
					diffMax=0.1
					HP['OL']=HP['OL']+1
					if (EVSEON_DEV~='' and otherdevices[EVSEON_DEV]=='On') then HP['OL']=HP['OL']+4 end	-- if EVSE is ON => turn off heat pump quickly
					log(E_DEBUG,"HP[OL]="..HP['OL'])
					if (HP['OL']>15) then -- more than 3 minutes with insufficient power
						-- stop overheating
						HP['OL']=0
						diffMax=0
					end
				end
			end
		end

		if (diffMax>0) then
			if (EVPOWER_DEV~=nil and EVPOWER_DEV~='') then
				-- A device measuring electric vehicle charging power exists
				-- POWER_MAX is a variable with the maximum power that the electricity meter can supply forever
				-- Increase POWER_MAX by power used by EV charger (Heat Pump has higher priority, so the EV charger should reduce its current/power)
				for str in otherdevices[EVPOWER_DEV]:gmatch("[^;]+") do	-- get power from device ("POWER;ENERGY;..."
					POWER_MAX=POWER_MAX+tonumber(str)
					break
				end
			end
			if (avgPower<POWER_MAX) then
				-- must heat/cool!
				-- check that fluid is not too high (Winter) or too low (Summer), else disactivate HeatPump_Fancoil output (to switch heatpump to radiant fluid, not coil fluid temperature
				
				if (HPmode == 'Winter') then
					-- make tempFluidLimit higher if rooms are cold
					tempFluidLimitT=29+(10-HP['otmin'])/4+diffMax*15-tempDerivate*20 -- Tf=22+(10-outdoorTempMin)/4+deltaT*10+tempDerivate*10   otmin=-6, deltaT=0.4 => Tf=30+4+3.2=37.2°C
					tempFluidLimit=HP['Limit']
					if (timenow.hour>=11 and timenow.hour<16 and outdoorTemperature<5) then
						-- very very cold
						tempFluidLimitT=tempFluidLimit+3
					end
					if (monthnow<=3 or monthnow>=12) then
						if (HP['OL']==0 and timenow.hour>=10 and timenow.hour<=16) then
							prodPower=prodPower+1000	-- From Dec to Mar, set heat pump to use at least 1000W during the day
						end
					end
					if (prodPower>100) then --increase set point for outlet water
						if (tempFluidLimit<tempHPout+2) then
							tempFluidLimit=tempHPout+2
						end
						tempFluidLimit=tempFluidLimit+prodPower/500 -- modify previous fluid Limit based on power
					elseif (prodPower<-300) then -- reduce setpoint for outlet water
						tempFluidLimit=tempFluidLimit-math.abs(HP['Limit']-(tempHPout+0.6))/3
					end
					if (tempFluidLimit<tempFluidLimitT or inverterPower==0) then
						tempFluidLimit=tempFluidLimitT	-- used computed fluid limit if greater than tempFluidLimit or during the night
					end
					if (tempFluidLimit<(tempHPout+1) and diffMax>0.1) then tempFluidLimit=tempHPout+1 end	-- assure that heat pump does not stop when it must heat
					if (tempFluidLimit>TEMP_WINTER_HP_MAX) then tempFluidLimit=TEMP_WINTER_HP_MAX end
				elseif (HPmode == 'Summer') then
					-- during the Summer
					-- make tempFluidLimit lower if rooms are warm
					tempFluidLimit=16
					-- if outdoor temperature > 28 => tempFluidLimit-=(outdoorTemperature-28)/3
					if (outdoorTemperature>28) then
						tempFluidLimit=tempFluidLimit-(outdoorTemperature-28)/3
					end
					-- also, regulate fluid temperature in base of of DeltaT
					tempFluidLimit=tempFluidLimit-diffMax
					-- if (diffMax<0.5) then tempFluidLimit=tempFluidLimit+0.5 end
					-- if (diffMax<=0.2) then tempFluidLimit=tempFluidLimit+0.5 end
				end
				if (HPmode == 'Winter') then
					-- winter
					if (diffMax>diffMaxHigh or (diffMax>0 and (monthnow>=11 or monthnow<=2))) then
						-- too much difference from set point => start heating even in case there is not enough power from PV
						log(E_DEBUG,"Too far from setpoint, or setpoint not reached from Nov to Feb")
						incLevel()
					else
						-- diffMax<diffMaxHigh: rooms almost in temperature
						if (monthnow>=3 and monthnow<=10) then
							if (HP['Level']>0 and prodPower<=-200) then 
								log(E_INFO,"From Mar to Oct, no enough power from PV and rooms almost in temperature => decLevel")
								decLevel() 
							end	-- From Apr to Oct, turn off Heat Pump if no available power from PV 
						end
					end
				else
					-- summer
					-- reduce levelMax to LEVEL_SUMMER_MAX-1 in the early morning or late afternoon, and when fluid temperature is near tempFluidLimit
					if (prodPower<=0 and (HP['otmax']<33 and diffMax<0.5) or (tempHPout-tempFluidLimit)<1 or minutesnow<540 or minutesnow>1080) then 
						levelMax=levelMax-1
					end
				end

				if (HP['Level']>0) then
					-- regulate fluid tempeature in case of max Level 
					if (HPmode == 'Winter') then
						-- TEMPHPOUT_DEV < tempFluidLimit => FANCOIL
						-- tempFluidLimit < TEMPHPOUT_DEV < tempFluidLimit+2 => FULLPOWER
						-- TEMPHPOUT_DEV > tempFluidLimit+2 or TEMPHPIN_DEV > tempFluidLimit => HALFPOWER

						-- check that fluid is not decreasing abnormally
						if (tempHPout>HP['HPout']) then
							if (tempHPout>=HP['HPout']+1) then
								HP['HPout']=tempHPout 
								if (HP['HPout']>=TEMP_WINTER_HP_MAX+2) then
									log(TELEGRAM_LEVEL,"Fluid temperature is too high!! "..HP['HPout'].."°C")
									decLevel()
									decLevel()
								end
							end
						elseif (tempHPout<HP['HPout']-1) then
							HP['HPout']=tempHPout
							if (otherdevices[HPSummer]=='On') then 
								log(TELEGRAM_LEVEL, HPSummer.." was On => disable it")
								commandArray[HPSummer]='Off'
							end
							if (HP['HPout']<=TEMP_SUMMER_HP_MIN) then
								--fluid temperature is decreasing below a reasonable value => send alert
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is very low!! "..HP['HPout'].."°C")
								decLevel()
								decLevel()
							end
						end
						if (levelOld~=0 and HPPower<100 and tempFluidLimit<otherdevices[TEMPHPOUT_DEV]+4) then
							log(E_DEBUG,"tempFluidLimit near outlet water temperature => avoid pump ON if heat pump will never start heating!")
							HP['t']=HP['t']+1
							if (HP['t']>=3) then
								--more than 3 minutes without heating => stop HP
								decLevel()
								decLevel()
							end
						elseif (HPPower>200) then
							HP['t']=0
						end
					else -- Summer
						-- check that fluid is not increasing/decreasing abnormally
						if (tempHPout<HP['HPout']) then
							if (tempHPout<HP['HPout']-1) then
								HP['HPout']=tempHPout 
								if (HP['HPout']<=TEMP_SUMMER_HP_MIN-2) then
									log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is too low!! "..HP['HPout'].."°C")
								end
							end
						elseif (tempHPout>HP['HPout']+1) then
							HP['HPout']=tempHPout
							if (otherdevices[HPSummer]=='Off' and otherdevices[HPOn]=='On') then 
								-- heat pump was ON, but heat pump Summer input was Off: that's strange, in summer season!
								log(TELEGRAM_LEVEL,HPSummer.." was Off => enable it")
								commandArray[HPSummer]='On'
							end
							if (HP['HPout']>=30) then
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is too high!! "..HP['HPout'].."°C")
							end
						end
						if (tempHPout>tempFluidLimit) then
							-- must cool!
							if (prodPower>=prodPower_incLevel and HP['Level']<levelMax) then
								-- enough power from photovoltaic to increase level
								incLevel()
							end
						elseif (tempHPout<HPZ['tf']) then
							log(E_INFO,"Fluid temperature to radiant/coil < "..tempFluidLimit.." => switch to radiant temperature")
							if (HP['Level']>2) then decLevel() end
						end
					end
				else
					-- if (HP['Level']==0
					
				end -- if (HP['Level']>0
				HPZ['tf']=tempHPout -- save the current tempHPout value
			else	--avgPower>=POWER_MAX: decrement level
				log(E_INFO,"Too much power consumption => decrease Heat Pump level")
				decLevel()
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			-- if (HPmode == 'Winter' and HP['otmin']<4 and (tempDerivate*8)<diffMax) then
			if (HPmode == 'Winter' and HP['otmin']<4 and (timenow.month<3 or timenow.month>10) and (tempDerivate*4)<diffZoneAlwaysOn) then
				-- room temperature is decreasing: turn ON heat pump at minimum level, but only in the winter
				log(E_INFO,"Room temperature is decreasing: start HeatPump with Level="..LEVEL_ON)
				HP['Level']=LEVEL_ON
			elseif (HP['Level']>LEVEL_OFF)  then 
				-- temperature and humidity are OK
				log(E_INFO,"All zones are in temperature! RHMax="..rhMax)
				decLevel() 
			end
		end
	else
		log(E_DEBUG,'No power meter installed')
	end

	if (GasHeater~=nil and GasHeater~='' and otherdevices[GasHeater]~=nil and HPmode == 'Winter') then
		-- boiler exists: activate it during the night if outdoorTemperature<GHoutdoorTemperatureMax and if diffMax>=GHdiffMax
		if (otherdevices[GasHeater]=='On') then
			-- add some histeresys to prevent gas heater switching ON/OFF continuously
			GHdiffMax=GHdiffMax-0.1
			GHoutdoorTemperatureMax=GHoutdoorTemperatureMax+1
			GHoutdoorHumidityMin=GHoutdoorHumidityMin-2
		end
		-- starts gas heater only few hours before 8:00 (because gas heater takes a short time to heat the fluid, in comparison to HP)
		-- starts GH only if outdoor temperature is low and (outdoor humidity is high, or diffMax is high (HP is not able to heat enough))
		if (outdoorHumidity<GHoutdoorHumidityMin) then
			-- start gas heater only if diffMax > GHdiffMax+0.4 (we trust in heat pump!)
			GHdiffMax=GHdiffMax+0.4
		end
		if (minutesnow<GHtimeMax and minutesnow>=GHtimeMin and diffMax>=GHdiffMax and outdoorTemperature<GHoutdoorTemperatureMax and diffMax>=GHdiffMax) then
			-- high humidity: prefer to start gas heate
			HP['Level']=LEVEL_OFF	-- force heat pump off and use only gas heater, in the night
			if (otherdevices[GasHeater]~='On') then
				log(E_INFO,"Night, low outdoor temperature, high humidity => Starts gas heater")
				gasHeaterOn=1
				deviceOn(GasHeater,HP,'DG')
				-- enable devices that must be enabled when gas heater is On
				for n,v in pairs(GHdevicesToEnable) do
					commandArray[v]='On'
				end
			end
		else
			if (otherdevices[GasHeater]~='Off' and (HP['dGH']~=nil and HP['dGH']=='a')) then
				deviceOff(GasHeater,HP,'DG')
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
end -- heatingCoolingEnabled=1


-- now scan DEVlist and enable/disable all devices based on the current level HP['Level']
if (HPmode == 'Winter') then 
	devLevel=2 
	levelMax=LEVEL_WINTER_MAX_NIGHT
	if (tempFluidLimit<=25) then
		compressorPerc=25
	elseif (tempFluidLimit>=40) then
		compressorPerc=60
	else
		-- compressorPerc=25+(60-25)/(40-25)*(tempFluidLimit-25)
		compressorPerc=25+2.33*(tempFluidLimit-25)
	end
	if (minutesnow>=HPNightEnd and minutesnow<HPNightStart and peakPower()==false) then
		-- during the day
		compressorPerc=compressorPerc*1.5	-- increase power during the day	
		if (prodPower>0) then				-- indeed increase power in case of extra power from photovoltaic
			if (compressorPerc<HP['CP']) then		-- prodPower>0 and compressorPerc<old value => set to old value
				compressorPerc=HP['CP']
			end
			compressorPerc=compressorPerc+prodPower/30
		end
	end
elseif (HPmode == 'Summer') then
	devLevel=4
	if (otherdevices[HPLevel]=='Dehum') then
		-- Dehumidification -> set HP to the minimum level
		levelMax=1
	else
		levelMax=LEVEL_SUMMER_MAX
		if (minutesnow>=HPNightStart or minutesnow<HPNightEnd) then
			levelMax=LEVEL_SUMMER_MAX_NIGHT
		end
	end
	compressorPerc=HP['CP']	-- fetch current compressorPerc and modify it to meet the prodPower
	compressorPerc=compressorPerc+(prodPower-500)/30	-- try have 500W exported
	if (compressorPerc<5) then
		-- no enough power: set heat pump to minimum, and disable VMC DEHUMIDIFY if enabled
		compressorPerc=5
		deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	end
else
	devLevel=2	-- default: Winter
end	
if (HP['OL']~=0) then
	-- overlimit on : track power
	compressorPerc=HP['CP']+(prodPower-500)/30	-- keep 500W free
	log(E_DEBUG,"OverLimit ON: compressorPerc="..compressorPerc.." HP[CP]="..HP['CP'].." deltaCP="..prodPower/30)
	if (HP['Level']==0 and otherdevices[HPLevel]~='Off') then incLevel() end
end
if (HP['Level']>levelMax) then HP['Level']=levelMax end

-- set compressor power
if (compressorPerc==nil) then compressorPerc=10 end
if (compressorPerc>100) then compressorPerc=100 end
if (compressorPerc<0) then compressorPerc=10 end
compressorPerc=math.floor(compressorPerc)
ret=os.execute('mbpoll -m rtu -a 1 -b 9600 -r 16388 /dev/ttyUSBheatpump '..compressorPerc*10)	-- send compressor frequency percentage*10
if (ret ~= true) then 
	HP['mb']=HP['mb']+1;
	if (HP['mb']>=60) then
		log(E_CRITICAL,"Modbus communication with heatpump does not work")
		HP['mb']=0
	else
		log(E_ERROR,"mbpoll return "..tostring(ret))
	end
else
	HP['mb']=0
end

for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	--log(E_DEBUG,"DevName="..v[1].."	devLevel="..v[devLevel].." CurrentLevel="..HP['Level'].." levelMax="..levelMax )
	if (v[devLevel]<255) then -- if devLevel is set to 255, device should be ignored
		-- v[devLevel]=START level
		-- v[devLevel+1]=STOP level   e.g. HeatPump_HalfPower: start level=1, stop level=2, so this device should be activated only when HP['level']==1
		if (HP['Level']>=v[devLevel+1] or HP['Level']<v[devLevel]) then
			-- this device has a level > of current level => disable it
			deviceOff(v[1],HP,n)
		else
			-- this device has a level <= of current level => enable it
			deviceOn(v[1],HP,n)
		end
	end
end

updateValves() -- enable/disable the valve for each zone


-- other customizations....
-- Make sure that radiant circuit is enabled when outside temperature goes down, or in winter, because heat pump starts to avoid any damage with low temperatures

if (outdoorTemperature<=4 or (HPmode=='Winter' and HP['Level']>LEVEL_OFF) or (HPmode=='Summer' and HP['Level']>=1) or GasHeaterOn==1) then
	if (otherdevices['Valve_Radiant_Coil']~='On') then
		commandArray['Valve_Radiant_Coil']='On'
		HP['trc']=0
	end
else
	HP['trc']=HP['trc']+1
	if (otherdevices['Valve_Radiant_Coil']~='Off' and HP['trc']>=3) then
		commandArray['Valve_Radiant_Coil']='Off'
	end
end


if (otherdevices[HPLevel]=='Dehum') then
    -- force dehumidification only
	if (otherdevices['Valve_Radiant_Coil']~="Off") then commandArray['Valve_Radiant_Coil']="Off"	end -- disable radiant => use only MVHR or fan coils
	tempHPout=tonumber(otherdevices[TEMPHPOUT_DEV])
	if (tempHPout>TEMP_SUMMER_HP_MIN) then	
		log(E_INFO,"Set heatpump to fancoil mode")
		commandArray['HeatPump_Fancoil']='On'
	else
		log(E_INFO,"Set heatpump to radiant mode")
		commandArray['HeatPump_Fancoil']='Off'
	end
	deviceOn(VENTILATION_COIL_DEV,HP,'DC')
	if (tempHPout<=18) then	-- activate chiller only if fluid temperature from heat pump is cold enough
		deviceOn(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	elseif (tempHPout>=20) then
		deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	end
	if (tempHPout>=18) then commandArray['HeatPump_HalfPower']='Off' end
elseif (HP['Level']==0) then
	deviceOff(VENTILATION_COIL_DEV,HP,'DC')
	deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
elseif (HPmode=='Summer') then
	-- Summer, and Level~=0
	if (HP['Level']>=1) then
		if (tempHPout<=17) then	-- activate chiller only if fluid temperature from heat pump is cold enough
			if (prodPower>800) then deviceOn(VENTILATION_COIL_DEV,HP,'DC') end
			if (prodPower>1800) then deviceOn(VENTILATION_DEHUMIDIFY_DEV,HP,'DD') end
		elseif (tempHPout>=18) then
			deviceOff(VENTILATION_COIL_DEV,HP,'DC')
			deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
		end
	else		
		deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	end
	if (prodPower<0) then 
		if (otherdevices[VENTILATION_DEHUMIDIFY_DEV]=="On") then
			deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD') 
		elseif (otherdevices[VENTILATION_COIL_DEV]=="On") then
			deviceOff(VENTILATION_COIL_DEV,HP,'DC')
		else
			decLevel();
		end
	end
end


if (HP['Level']>0) then
	-- set tempHPout on the heat pump machine
	if (HPmode=='Summer') then
		if (tempFluidLimit<TEMP_SUMMER_HP_MIN) then
			tempFluidLimit=TEMP_SUMMER_HP_MIN
		end
	else -- Winter
		if (HPPower<100 and HPPower>500) then
			-- not heating: increase tempFluidLimit to start 
			tempFluidLimit=tempFluidLimit+2
		end
	if (tempFluidLimit>TEMP_WINTER_HP_MAX) then
			tempFluidLimit=TEMP_WINTER_HP_MAX
		end
	end
	heatpumptemp=string.format("%.0f", tempFluidLimit*10)
	os.execute('mbpoll -m rtu -a 1 -b 9600 -r '..modbusFluidTempBase..' /dev/ttyUSBheatpump '..heatpumptemp..' '..heatpumptemp)	-- send setpoint using Modbus
end

-- save variables
diffMax=string.format("%.2f", diffMax)
diffMaxText=' diff='..diffMax..'°C'
if (HP['OL']~=0) then diffMaxText=' OverLimit' end
log(E_INFO,'Level:'..levelOld..'->'..HP['Level']..' GH='..gasHeaterOn..diffMaxText..' Compr/HP/Grid='..compressorPerc..'%/'..HPPower..'W/'..avgPower..'W SP/Out/In='..string.format("%.1f", tempFluidLimit)..'/'..tempHPout..'/'..tempHPin..'°C OutdoorTemp now/min/max='..outdoorTemperature..'/'..HP['otmin']..'/'..HP['otmax']..'°C')
commandArray['UpdateDevice'] = HPStatusIDX..'|0|Level:'..levelOld..'->'..HP['Level']..diffMaxText.."\n SP/Out/In="..string.format("%.1f", tempFluidLimit)..'/'..tempHPout..'/'..tempHPin..'°C Compressor='..compressorPerc..'%'
HP['Limit']=tempFluidLimit
HP['CP']=compressorPerc
commandArray['Variable:zHeatPump']=json.encode(HP)
commandArray['Variable:zHeatPumpZone']=json.encode(HPZ)
--log(E_DEBUG,'zHeatPump='..json.encode(HP))
--log(E_DEBUG,'zHeatPumpZone='..json.encode(HPZ))

::mainEnd::

return commandArray
