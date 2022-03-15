-- Lua script for Domoticz, controlling the heating/cooling system by a heat pump supplied by electric grid + photovoltaic system.
-- Designed to consume as most as possible energy from photovoltaic
-- Written by Creasol, https://www.creasol.it , linux@creasol.it
--
-- Please assure that
-- 127.0.0.1 is enabled to connect without authentication, in Domoticz -> Configuration -> Settings -> Local Networks (e.g. 127.0.0.1;192.168.1.*)
--
commandArray={}

dofile "/home/pi/domoticz/scripts/lua/config_heatpump.lua"

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
	if (HP['otmin']==nil) then HP['otmin']=10 end	-- outodorTemperatureMin
	if (HP['otmax']==nil) then HP['otmax']=10 end	-- outodorTemperatureMin
	if (HP['Level']==nil) then HP['Level']=0 end
	if (HP['SPoff']==nil) then HP['SPoff']=0 end
	if (HP['HPout']==nil) then HP['HPout']=0 end	-- tempHPout temperature
	if (HP['t']==nil) then HP['t']=0 end			-- when HP works at max level, the level can be reduced only if the system ask to reduce it for at least 5 minutes
	if (HP['trc']==nil) then HP['trc']=0 end		-- disable the Valve_Radiant_Coil after 3 minutes from HeatPump going OFF
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
else 
	avgPower=500 -- power meter does not exist: set avgPower to 500W by default
end
prodPower=0-avgPower

if (HPmode ~= 'Winter' and HPmode ~= 'Summer') then
	-- Both heating and cooling are disabled
	HP['Level']=LEVEL_OFF
	levelOld=LEVEL_OFF	
	heatingCoolingEnabled=0
	levelMax=0
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
		levelMax=LEVEL_WINTER_MAX-1 -- max value for HP['Level']
		if (prodPower>1000 or (HP['Level']==LEVEL_WINTER_MAX and (avgPower<200 or instPower<200))) then
			-- extra energy from photovoltaic => enable full power
			levelMax=LEVEL_WINTER_MAX
		end
		-- diffMaxHigh is used to define when room temperature is distant from the set point
	 	-- diffMaxHigh=0.3	-- if diffMax<diffMaxHigh, temperature is near the set point
		-- reduce diffMaxHigh if outdoor temperature is low (to use higher temperatures to heat the building)
		diffMaxHigh=0.3+(HP['otmin']/40)+HP['otmax']/60

		diffMaxHigh_power=500	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)

		prodPower_incLevel=300		--minimum production power to increment level
		spOffset=OVERHEAT
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
		diffMaxHigh_power=200	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)
		prodPower_incLevel=1000		--minimum production power to increment level
		spOffset=OVERCOOL
	end
	realdiffMax=-10
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0		-- max value of relative humidity

	-- rhMax=70    -- DEBUG: force RH to a high value to force dehumidification

	zonesOn=0	-- number of zones that are ON
	-- HP['SPoff']==offset added to set point based on available energy, to overheat/overcool in case of extra energy
	if (HP['SPoff']==0) then
		if (peakPower()==false and (prodPower>1200 or (HPmode == 'Winter' and (prodPower>0 or instPower<0 --[[ or HP['Level']==LEVEL_WINTER_MAX ]] )))) then	-- more than 800W fed to the electrical grid, or more than 1000W avg power (excluding power used by aux loads, that can be disconnected)
			HP['SPoff']=spOffset	-- increase setpoint by OVERHEAT parameter to overheat, in case of extra available energy
			log(E_INFO,"Enable OverHeating/Cooling")
		end
	else
		log(E_INFO,"SPoff != 0")
		if ((HPmode == 'Summer' and prodPower<0) or (HPmode == 'Winter' and avgPower>500 and instPower>500)) then
			HP['SPoff']=0
			log(E_INFO,"Disable OverHeating/Cooling")
		end
	end
	
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
		diff=realdiff+HP['SPoff']										-- tempSet-temp+temperatureOffsetZone+temperatureOffsetGlobal
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
			log(E_INFO,valveState..' zone='..v[ZONE_NAME]..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..v[ZONE_NAME]]..'+'..temperatureOffset..'+('..HP['SPoff']..') diff='..diff)
		else
			log(E_DEBUG,valveState..' zone='..v[ZONE_NAME]..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..v[ZONE_NAME]]..'+'..temperatureOffset..'+('..HP['SPoff']..') diff='..diff)
		end
	end
	
	log(E_INFO,'tempDerivate='..tempDerivate..' diffMax='..diffMax..' diffMaxHigh='..diffMaxHigh..' RHMax='..rhMax)


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
		
		if (minutesnow<timeofday['SunriseInMinutes']+180 and diffMax<diffMaxHigh) then 
			-- in the morning, if temperature is not so distant from the setpoint, try to not consume from the grid
			diffMaxHigh_power=0 
		end
		-- In the morning, if room temperature is almost ok, try to export power to help the electricity grid
		if (diffMax<diffMaxHigh and peakPower()) then
			log(E_INFO,"Try to export energy")
			diffMax=-10
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
					tempFluidLimit=28
					-- if outdoor temperature > 28 => tempFluidLimit-=(outdoorTemperature-28)/3
					-- outdoorTemperatureMin<10 => if min outdoor temperature is low, increase the fluid temperature from heatpump
					tempFluidLimit=tempFluidLimit+(10-HP['otmin'])/4+diffMax*8-tempDerivate*10 -- Tf=30+(10-outdoorTempMin)/4+deltaT*10+tempDerivate*10   otmin=-6, deltaT=0.4 => Tf=30+4+3.2=37.2°C
					if (tempFluidLimit>TEMP_WINTER_HP_MAX) then
						tempFluidLimit=TEMP_WINTER_HP_MAX
					end
				elseif (HPmode == 'Summer') then
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
				if (prodPower>prodPower_incLevel) then
					-- more available power => increment level
					if (HP['Level']>=levelMax) then
						-- already at full power => increase fluid temperature in Winter, or decrease in the Summer
						if (HPmode == 'Winter') then
							tempFluidLimit=tempFluidLimit+2
						else
							tempFluidLimit=tempFluidLimit-1
						end
					elseif (HP['Level']==0) then
						-- start heat pump
						incLevel()
					end
				else
					-- prodPower<prodPower_incLevel
					-- no extra power from photovoltaic
					log(E_DEBUG,"No enough power from PV")
					if (HPmode == 'Winter') then
						-- winter
						if (diffMax>diffMaxHigh or (diffMax>0 and (monthnow>10 or monthnow<4))) then
							-- too much difference from set point => start heating even in case there is not enough power from PV
							log(E_DEBUG,"Too far from setpoint")
							if (HP['Level']==0) then incLevel() end
						else
							-- diffMax<diffMaxHigh: rooms almost in temperature
							if (monthnow>=4 and monthnow<=10) then
								if (HP['Level']>0) then 
									log(E_INFO,"From Apr to Oct, no enough power from PV and rooms almost in temperature => decLevel")
									decLevel() 
								end	-- From Apr to Oct, turn off Heat Pump if no available power from PV 
							else
								-- from November to March, keep heat pump ON, but at low power (rooms are almost in temperature)
								if (HP['Level']>1) then
									log(E_INFO,"From Nov to Mar, no enough power from PV and rooms almost in temperature => Level=2 or 1")
									decLevel()
								end
							end
						end
					else
						-- summer
						if (avgPower>diffMaxHigh_power) then
							-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)
							log(E_DEBUG,"Decrease heatpump power")
							decLevel()
						end
					end
				end
	
				if (HP['Level']>0) then
					-- regulate fluid tempeature in case of max Level 
					if (HPmode == 'Winter') then
						-- tempHPout < tempFluidLimit => FANCOIL
						-- tempFluidLimit < tempHPout < tempFluidLimit+2 => FULLPOWER
						-- tempHPout > tempFluidLimit+2 or tempHPin > tempFluidLimit => HALFPOWER

						-- check that fluid is not decreasing abnormally
						if (tonumber(otherdevices[tempHPout])>HP['HPout']) then
							if (tonumber(otherdevices[tempHPout])>=HP['HPout']+1) then
								HP['HPout']=tonumber(otherdevices[tempHPout]) 
								if (HP['HPout']>=TEMP_WINTER_HP_MAX+2) then
									log(TELEGRAM_LEVEL,"Fluid temperature is too high!! "..HP['HPout'].."°C")
								end
							end
						elseif (tonumber(otherdevices[tempHPout])<HP['HPout']-1) then
							HP['HPout']=tonumber(otherdevices[tempHPout])
							if (otherdevices[HPSummer]=='On') then 
								log(TELEGRAM_LEVEL, HPSummer.." was On => disable it")
								commandArray[HPSummer]='Off'
							end
							if (HP['HPout']<=TEMP_SUMMER_HP_MIN) then
								--fluid temperature is decreasing below a reasonable value => send alert
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is very low!! "..HP['HPout'].."°C")
							end
						end
						if (tonumber(otherdevices[tempHPout])<=(tempFluidLimit-1)) then
							-- must heat!
							if (HP['Level']<LEVEL_WINTER_FANCOIL) then 
								log(E_INFO,"Fluid temperature is low => must heat!")
								incLevel()
							elseif (HP['Level']<levelMax and ( --[[ ((timenow.hour>=23 or timenow.hour<7) and inverterMeter~='' and HP['otmax']<5) or ]] prodPower>=prodPower_incLevel or diffMax>=diffMaxHigh)) then
								log(E_INFO,"Enable full power!")
								incLevel()
							end
						else
							-- fluid temperature > tempFluidLimit-1 => assure that heatpump power is low
							if (HP['Level']>LEVEL_WINTER_FANCOIL) then
								log(E_INFO,"Fluid temperature almost equal to limit => reduce power")
								decLevel()
							end
							if (tonumber(otherdevices[tempHPout])>tempFluidLimit+2 or tonumber(otherdevices[tempHPin])>tempFluidLimit) then
								log(E_INFO,"Fluid temperature to radiant/coil > "..tempFluidLimit.." => switch to radiant temperature")
								while (HP['Level']>=LEVEL_WINTER_FANCOIL) do decLevel() end
							end
						end
					else -- Summer
						-- check that fluid is not increasing/decreasing abnormally
						if (tonumber(otherdevices[tempHPout])<HP['HPout']) then
							if (tonumber(otherdevices[tempHPout])<HP['HPout']-1) then
								HP['HPout']=tonumber(otherdevices[tempHPout]) 
								if (HP['HPout']<=TEMP_SUMMER_HP_MIN-2) then
									log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is too low!! "..HP['HPout'].."°C")
								end
							end
						elseif (tonumber(otherdevices[tempHPout])>HP['HPout']+1) then
							HP['HPout']=tonumber(otherdevices[tempHPout])
							if (otherdevices[HPSummer]=='Off' and otherdevices[HPOn]=='On') then 
								-- heat pump was ON, but heat pump Summer input was Off: that's strange, in summer season!
								log(TELEGRAM_LEVEL,HPSummer.." was Off => enable it")
								commandArray[HPSummer]='On'
							end
							if (HP['HPout']>=30) then
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is too high!! "..HP['HPout'].."°C")
							end
						end
						if (tonumber(otherdevices[tempHPout])>tempFluidLimit) then
							-- must cool!
							if (prodPower>=prodPower_incLevel and HP['Level']<levelMax) then
								-- enough power from photovoltaic to increase level
								incLevel()
--							elseif (avgPower>diffMaxHigh_power) then
--								-- not enough power from photovoltaic -> reduce heat pump level
--								log(E_INFO,"Not enough power from PV")
--								decLevel()
							end
						else
							log(E_INFO,"Fluid temperature to radiant/coil < "..tempFluidLimit.." => switch to radiant temperature")
							while (HP['Level']>1) do decLevel() end
						end
					end
				end -- if (HP['Level']>0
			else	--avgPower>=POWER_MAX: decrement level
				log(E_INFO,"Too much power consumption => decrease Heat Pump level")
				decLevel()
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			if (HPmode == 'Winter' and HP['otmin']<4 and (tempDerivate*8)<diffMax) then
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
	if (minutesnow>=HPNightStart or minutesnow<HPNightEnd) then
		-- during the night, go to the minimum level to reduce noise
		levelMax=LEVEL_WINTER_MAX_NIGHT
	end
elseif (HPmode == 'Summer') then
	devLevel=4 
	levelMax=LEVEL_SUMMER_MAX
	if (minutesnow>=HPNightStart or minutesnow<HPNightEnd) then
		levelMax=LEVEL_SUMMER_MAX_NIGHT
	end
end	
if (HP['Level']>levelMax) then
	log(E_INFO,"Reduce Level to levelMax="..levelMax)
	HP['Level']=levelMax
else
	log(E_INFO,"levelMax="..levelMax)
end
if (HP['Level']<levelOld) then
	-- decLevel requested => reduce level only after N minutes where the system ask to reduce level
	-- My heat pump works very bad if level switch between LEVEL_WINTER_MAX and LEVE_WINTER_MAX-1
	if (HP['t']==nil or HP['t']>=3) then
		HP['t']=0
	else
		HP['t']=HP['t']+1
	end
	log(E_INFO,"Level decrease requested, t="..HP['t'].."/3")
	HP['Level']=levelOld
	if (HP['t']==3) then
		-- in the last 5 minutes, the system requested to reduce heat pump level
		HP['t']=0
		HP['Level']=levelOld-1
	end
else
	HP['t']=0
end

for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	log(E_DEBUG,"DevName="..v[1].." devLevel="..v[devLevel].." CurrentLevel="..HP['Level'].." levelMax="..levelMax )
	if (v[devLevel]<255) then -- if devLevel is set to 255, device should be ignored
		-- v[devLevel]=START level
		-- v[devLevel+1]=STOP level   e.g. HeatPump_HalfPower: start level=1, stop level=2, so this device should be activated only when HP['level']==1
		if (HP['Level']>=v[devLevel+1] or HP['Level']<v[devLevel]) then
			-- this device has a level > of current level => disable it
			deviceOff(v[1],HP,'d'..n)
		else
			-- this device has a level <= of current level => enable it
			deviceOn(v[1],HP,'d'..n)
		end
	end
end

updateValves() -- enable/disable the valve for each zone


-- other customizations....
-- Make sure that radiant circuit is enabled when outside temperature goes down, or in winter, because heat pump starts to avoid any damage with low temperatures

if (outdoorTemperature<=4 or HP['Level']>LEVEL_OFF or GasHeaterOn==1) then
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


-- save variables
log(E_INFO,'Level:'..levelOld..'->'..HP['Level']..' GH='..gasHeaterOn..' HPLimit='..string.format("%.1f", tempFluidLimit)..' HPout='..otherdevices[tempHPout]..' HPin='..otherdevices[tempHPin]..' Outdoor='..otherdevices[tempOutdoor])
commandArray['Variable:zHeatPump']=json.encode(HP)
commandArray['Variable:zHeatPumpZone']=json.encode(HPZ)
log(E_DEBUG,'zHeatPump='..json.encode(HP))
log(E_DEBUG,'zHeatPumpZone='..json.encode(HPZ))

::mainEnd::

return commandArray
