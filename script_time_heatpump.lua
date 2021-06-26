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

function heatPumpOn()
	if (otherdevices['HeatPump']=='Off') then
		if (uservariables['HeatPumpWinter']==1) then
			deviceOff('HeatPump_Summer',HP,'D4')
		else
			deviceOn('HeatPump_Summer',HP,'D4')
		end
		deviceOff('HeatPump_Fancoil',HP,'D3')
		deviceOff('HeatPump_FullPower',HP,'D2')
		deviceOn('HeatPump',HP,'D1')
	end
end

function heatPumpOff(timeOff)
	deviceOff('HeatPump',HP,'D1')
	deviceOff('HeatPump_Fancoil',HP,'D3')
	deviceOff('HeatPump_FullPower',HP,'D2')
	deviceOff('HeatPump_Summer',HP,'D4')
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
	log(E_INFO,"Shift")
	-- shift temperatures in HPZ['tn'] and compute new tempDerivate
	HPZ['t4']=HPZ['t3']
	HPZ['t3']=HPZ['t2']
	HPZ['t2']=HPZ['t1']
	HPZ['t1']=HPZ['t0']
	-- HPZ['t0']=otherdevices[TempZoneAlwaysOn]
	HPZ['t0']=HPZ['temp']
	HPZ['gr']=math.floor((HPZ['t0']-HPZ['t1'])/0.01+(HPZ['t1']-HPZ['t2'])/0.0125+(HPZ['t2']-HPZ['t3'])/0.015+(HPZ['t3']-HPZ['t4'])/0.02)/200
else
	HPZ['temp']=math.floor((HPZ['temp']*15+otherdevices[TempZoneAlwaysOn])/0.16)/100
end
tempDerivate=HPZ['gr']


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
		log(E_CRITICAL,'Zone '..n..': relative humidity device '..v[ZONE_RH_DEV]..' defined in config_heatpump.lua but does not exist')
	end
	if (v[ZONE_VALVE] and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE] ]==nil) then
		log(E_CRITICAL,'Zone '..n..': valve device '..v[ZONE_VALVE]..' defined in config_heatpump.lua but does not exist')
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
	usagePower=uservariables['avgPower']	-- use the average power instead of instant power!
else 
	usagePower=500 -- power meter does not exist: set usagePower to 500W by default
end
prodPower=0-usagePower

if (uservariables['HeatPumpWinter']==0 and uservariables['HeatPumpSummer']==0) then
	-- Both heating and cooling are disabled
	HP['Level']=LEVEL_OFF
	heatingCoolingEnabled=0
	level_max=0
else
	heatingCoolingEnabled=1
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


		-- diffMaxHigh is used to define when room temperature is distant from the set point
	 	-- diffMaxHigh=0.3	-- if diffMax<diffMaxHigh, temperature is near the set point
		-- reduce diffMaxHigh if outdoor temperature is low (to use higher temperatures to heat the building)
		diffMaxHigh=0.3+(HP['otmin']/40)+HP['otmax']/60

		diffMaxHigh_power=500	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)

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
		diffMaxHigh=2		-- if diffMax<diffMaxHigh, temperature is near the set point
		diffMaxHigh_power=200	-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)
		prodPower_incLevel=1000		--minimum production power to increment level
		prodPower_incLevel2=1200	--minimum production power to increment level by 2 steps
		spOffset=OVERCOOL
	end
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0		-- max value of relative humidity
	-- rhMax=70    -- DEBUG: force RH to a high value to force dehumidification

	zonesOn=0	-- number of zones that are ON
	-- HP['SPoff']==offset added to set point based on available energy, to overheat/overcool in case of extra energy
	if (HP['SPoff']==0) then
		if ((prodPower>1200 or (uservariables['HeatPumpWinter']==1 and prodPower>800))) then	-- more than 800W fed to the electrical grid
			HP['SPoff']=spOffset	-- increase setpoint by OVERHEAT parameter to overheat, in case of extra available energy
			log(E_INFO,"Enable OverHeating/Cooling")
		end
	else
		if ((uservariables['HeatPumpSummer']==1 and prodPower<0) or (uservariables['HeatPumpWinter']==1 and usagePower>200 and instPower>200)) then
			HP['SPoff']=0
			log(E_INFO,"Disable OverHeating/Cooling")
		end
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
		if (v[ZONE_TEMP_DEV]==TempZoneAlwaysOn) then
			temp=HPZ['temp']
		else
			temp=tonumber(otherdevices[ v[ZONE_TEMP_DEV] ])
		end
		diff=(uservariables['TempSet_'..n]+temperatureOffset+HP['SPoff'])-temp;
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
		if (valveState=='On') then
			log(E_INFO,valveState..' zone='..n..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..n]..'+'..temperatureOffset..'+('..HP['SPoff']..') diff='..diff)
		else
			log(E_DEBUG,valveState..' zone='..n..' RH='..rh..' Temp='..temp..' SP='..uservariables['TempSet_'..n]..'+'..temperatureOffset..'+('..HP['SPoff']..') diff='..diff)
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
		if (uservariables['HeatPumpWinter']==0 and rhMax>60 and HP['Level']==LEVEL_OFF and prodPower>1000) then
			-- high humidity: activate heatpump + ventilation + chiller (Level 1)
			incLevel()
		end
		
		if (minutesnow<timeofday['SunriseInMinutes']+180 and diffMax<diffMaxHigh) then 
			-- in the morning, if temperature is not so distant from the setpoint, try to not consume from the grid
			diffMaxHigh_power=0 
		end
		if (diffMax>0) then
			if (usagePower<POWER_MAX-1700) then
				-- must heat/cool!
				-- check that fluid is not too high (Winter) or too low (Summer), else disactivate HeatPump_Fancoil output (to switch heatpump to radiant fluid, not coil fluid temperature
				if (uservariables['HeatPumpWinter']==1) then
					-- make tempFluidLimit higher if rooms are cold
					tempFluidLimit=30
					-- if outdoor temperature > 28 => tempFluidLimit-=(outdoorTemperature-28)/3
					-- outdoorTemperatureMin<10 => if min outdoor temperature is low, increase the fluid temperature from heatpump
					tempFluidLimit=tempFluidLimit+(10-HP['otmin'])/4+diffMax*10-tempDerivate*10 -- Tf=30+(10-outdoorTempMin)/4+deltaT*10+tempDerivate*10   otmin=-6, deltaT=0.4 => Tf=30+4+3.2=37.2°C
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
				if (prodPower>prodPower_incLevel) then
					-- more available power => increment level
					if (HP['Level']>=level_max) then
						-- already at full power => increase fluid temperature in Winter, or decrease in the Summer
						if (uservariables['HeatPumpWinter']==1) then
							tempFluidLimit=tempFluidLimit+2
						else
							tempFluidLimit=tempFluidLimit-1
						end
					elseif (HP['Level']==0) then
						-- start heat pump
						incLevel()
					end
				elseif (usagePower>diffMaxHigh_power and (diffMax<diffMaxHigh or uservariables['HeatPumpWinter']==0)) then
					-- if usage power > diffMaxHigh_power, Level will be decreased in case of comfort temperature (diffMax<diffMaxHigh)
					decLevel()
				end
	
				if (HP['Level']>0) then
				-- regulate fluid tempeature in case of max Level 
					if (uservariables['HeatPumpWinter']==1) then
						-- tempHPout < tempFluidLimit => FANCOIL + FULLPOWER
						-- tempFluidLimit < tempHPout < tempFluidLimit+2 => FANCOIL
						-- tempHPout > tempFluidLimit+2 or tempHPin > tempFluidLimit => FANCOIL-1

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
								log(TELEGRAM_LEVEL,HPsummer.." was On => disable it")
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
							elseif (HP['Level']<LEVEL_WINTER_MAX and (((timenow.hour>=23 or timenow.hour<7) and inverterMeter~='' and HP['otmax']<5) or prodPower>=prodPower_incLevel or diffMax>=diffMaxHigh)) then
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
							if (prodPower>=prodPower_incLevel and HP['Level']<level_max) then
								-- enough power from photovoltaic to increase level
								incLevel()
							elseif (usagePower>diffMaxHigh_power) then
								-- not enough power from photovoltaic -> reduce heat pump level
								decLevel()
							end
						else
							log(E_INFO,"Fluid temperature to radiant/coil < "..tempFluidLimit.." => switch to radiant temperature")
							while (HP['Level']>=3) do decLevel() end
						end
					end
				end -- if (HP['Level']>0
				
				-- Control heat pump power, reducing level if no power is available and temperature is near the set point
				if (HP['Level']>1 and 
					diffMax<diffMaxHigh and 
					usagePower>diffMaxHigh_power and 
					inverterPower>2500 and 
					minutesnow>timeofday['SunriseInMinutes']+60 and 
					minutesnow<timeofday['SunsetInMinutes']-180) then
					log(E_INFO,"Almost in temperature => reduce power usage")
					decLevel()
				end
			elseif (usagePower>=POWER_MAX-500) then --usagePower>=POWER_MAX: decrement level
				decLevel()
			end
		else
			-- diffMax<=0 => All zones are in temperature!
			if (uservariables['HeatPumpWinter']==1 and (inverterMeter~='' and HP['otmax']<8 and (tempDerivate*4)<(diffMax-diffMaxHigh/2))) then
				-- temperature is decreasing: turn ON heat pump at minimum level, but only in the winter
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

	if (GasHeater~=nil and GasHeater~='' and otherdevices[GasHeater]~=nil and uservariables['HeatPumpWinter']==1) then
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
if (uservariables['HeatPumpWinter']==1) then devLevel=2 else devLevel=3 end	-- summer: use next field for device level
for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	log(E_DEBUG,"DevName="..v[1].." devLevel="..v[devLevel].." CurrentLevel="..HP['Level'].." level_max="..level_max )
	if (v[devLevel]<=level_max+1) then -- ignore devices configured to have a very high level
		if (HP['Level']>=v[devLevel]) then
			-- this device has a level <= of current level => enable it
			deviceOn(v[1],HP,'d'..n)
		else
			-- this device has a level > of current level => disable it
			deviceOff(v[1],HP,'d'..n)
		end
	end
end

updateValves() -- enable/disable the valve for each zone

-- now check heaters and dehumidifiers in DEVauxlist...
-- devLevel for DEVauxlist is the same as DEVlist -- if (uservariables['HeatPumpSummer']==1) then devLevel=3 else devLevel=2 end	-- summer: use next field for device level
if (uservariables['HeatPumpWinter']==1) then devCond=5 else devCond=8 end	-- devCond = field that contains the device name for condition used to switch ON/OFF device

-- Parse DEVauxlist to check if anything should be enabled or disabled
-- If heat pump level has changed, don't enable/disable aux devices because the measured prodPower may change 
availablePower=prodPower	
	-- compute the available power (disabling all aux devices)
for n,v in pairs(DEVauxlist) do
	if (otherdevices[ v[1] ]~='Off') then
		availablePower=availablePower+v[4]
	end
end
if (prodPower ~= availablePower) then log(E_INFO,"prodPower="..prodPower.." availablePower="..availablePower) end
for n,v in pairs(DEVauxlist) do
	if (otherdevices[ v[devCond] ]~=nil) then
		s=""
		if (v[12]~=nil and HP['s'..n]~=nil and HP['s'..n]>0) then
			s=" ["..HP['s'..n].."/"..v[12].."m]"
		end			
		log(E_INFO,"Aux "..otherdevices[ v[1] ]..": "..v[1] .." (" .. v[4].."/"..availablePower.."W)"..s)
		if (tonumber(otherdevices[ v[devCond] ])<v[devCond+2]) then cond=1 else cond=0 end
		log(E_DEBUG,v[1] .. ": is " .. tonumber(otherdevices[ v[devCond] ]) .." < ".. v[devCond+2] .."? " .. cond)
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
					deviceOff(v[1],HP,'a'..n)
					log(TELEGRAM_LEVEL,"Timeout reached for "..v[1]..": device was stopped")
				end
			end
		end
		-- change state only if previous heatpump level match the current one (during transitions from a power level to another, power consumption changes)
		if (otherdevices[ v[1] ]~='Off') then
			-- device is ON
			log(E_DEBUG,'Device is not Off: '..v[1]..'='..otherdevices[ v[1] ])
			availablePower=availablePower-v[4]
			if (prodPower<-100 or (HP['Level']<v[devLevel] and diffMax>0) or cond==v[devCond+1] ) then
				if (v[12]~=nil) then
					if (HP['s'..n]==nil) then HP['s'..n]=0 end
					HP['s'..n]=HP['s'..n]+1
					if (HP['s'..n]>=v[12]) then
						-- stop device because conditions are not satisfied for more than v[12] minutes
						deviceOff(v[1],HP,'a'..n)
						prodPower=prodPower+v[4]	-- update prodPower, adding the power consumed by this device that now we're going to switch off
						availablePower=availablePower+v[4]
						HP['s'..n]=0
					end
				else
					deviceOff(v[1],HP,'a'..n)
					prodPower=prodPower+v[4]	-- update prodPower, adding the power consumed by this device that now we're going to switch off
					availablePower=availablePower+v[4]
				end
			else
				-- device On, and can remain On
				if (v[12]~=nil) then
					HP['s'..n]=0
				end
			end
		else
			-- device is OFF
			-- print(prodPower.." "..v[4])
			log(E_DEBUG,auxTimeout.."<"..auxMaxTimeout.." and "..prodPower..">="..v[4]+100 .."and "..cond.."~="..v[devCond+1])
			if (auxTimeout<auxMaxTimeout and availablePower>=(v[4]+100) and cond~=v[devCond+1]) then
				deviceOn(v[1],HP,'a'..n)
				prodPower=prodPower-v[4] 	-- update prodPower
				availablePower=availablePower-v[4] 	-- update prodPower
			end
		end
	end
end

-- other customizations....
-- Make sure that radiant circuit is enabled when outside temperature goes down, or in winter, because heat pump starts to avoid any damage with low temperatures
if (outdoorTemperature<=4 or ((uservariables['HeatPumpWinter']==1 and (HP['Level']>LEVEL_OFF or GasHeaterOn==1)))) then
	if (otherdevices['Valve_Radiant_Coil']~='On') then
		commandArray['Valve_Radiant_Coil']='On'
	end
else
	if (otherdevices['Valve_Radiant_Coil']~='Off') then
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
