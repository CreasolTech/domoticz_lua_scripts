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
dofile "scripts/lua/config_heatpump_emmeti.lua"
DEBUG_LEVEL=E_INFO
--DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="HeatPump: "

-- Initialize the HP domoticz variable (json coded, within several state variables)
function HPinit()
	if (HP==nil) then HP={} end
	if (HP['otmin']==nil) then HP['otmin']=10 end	-- outodorTemperatureMin
	if (HP['otmax']==nil) then HP['otmax']=10 end	-- outodorTemperatureMin
	if (HP['Level']==nil) then HP['Level']=0 end
	if (HP['CP']==nil) then HP['CP']=0 end			-- compressorPerc
	if (HP['HPout']==nil) then HP['HPout']=0 end	-- TEMPHPOUT_DEV temperature
	if (HP['trc']==nil) then HP['trc']=0 end		-- disable the Valve_Radiant_Coil after 3 minutes from HeatPump going OFF
	if (HP['OL']==nil) then HP['OL']=0 end			-- OverLimit: used to overheat or overcool
	if (HP['toff']==nil) then HP['toff']=0 end		-- time the heat pump is in OFF state
	if (HP['EV']==nil) then HP['EV']=0 end			-- >0 while charging, decreased when EV stops charging
	if (HP['S']==nil) then HP['S']=0 end			-- Supply timeout: used to enable/disable relay to feed power to the heat pump (disabling power when inactive, to save energy consumption)
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
	-- check valveStateDiff and update valve status for each zone
	local overlimitTempAdd=0
	local valves=0
	if (HP['OL']~=0) then overlimitTempAdd=overlimitTemp end	-- overlimit => set the overlimit temperature to add to "diff" for each zone
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
			valveStateTmp[v[ZONE_VALVE] ]='Off'	
		end
		-- update commandArray only when valve status have changed
		--[[
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='' and valveStateTmp[v[ZONE_VALVE] ]~=nil and otherdevices[v[ZONE_VALVE] ]~=valveStateTmp[v[ZONE_VALVE] ]) then
			if (valveStateTmp[v[ZONE_VALVE] ] == 'On' and HPlevel~='Dehum') then
				deviceOn(v[ZONE_VALVE],HP,'v'..n)
			else
				deviceOff(v[ZONE_VALVE],HP,'v'..n)
			end
			-- log(E_DEBUG,'**** Valve for zone '..v[ZONE_NAME]..' changed to '..valveStateTmp[ v[ZONE_VALVE] ])
		end
--]]
		if (v[ZONE_VALVE]~=nil and v[ZONE_VALVE]~='') then  -- valve exists 
			-- log(E_DEBUG, 'Valve '..v[ZONE_VALVE]..' diff='..valveStateDiff[n]..' overlimit='..overlimitTempAdd)
			--   zone must be heated/cooled                 Not dehumidifaction        heatpump is on
			if ((valveStateDiff[n]+overlimitTempAdd)>0 and HPlevel~='Dehum' and otherdevices[ DEVlist[1][1] ]~='Off') then -- must be on
                deviceOn(v[ZONE_VALVE],HP,'v'..n)
				valves=valves+1
            else
                deviceOff(v[ZONE_VALVE],HP,'v'..n)
            end
		end
		-- TODO: if one valve is On, activate the main valve
	end 
	if (valves>0) then
		deviceOn(HPValveGeneral,HP,'vg')	-- enable general valve, to heat the second floor
	else
		deviceOff(HPValveGeneral,HP,'vg')	-- valves are all off => disable general valve
	end
end

function setOutletTemp(temp)
	if (HPmode == 'Winter') then
		commandArray[#commandArray+1]={['UpdateDevice']=tostring(HPTempWinterMinIDX)..'|1|'.. temp}			-- min outlet temperature (e.g. 35°C)
		commandArray[#commandArray+1]={['UpdateDevice']=tostring(HPTempWinterMaxIDX)..'|1|'.. temp+10}		-- max outlet temperature (e.g. 45°C)
	elseif (HPmode == 'Summer') then
		commandArray[#commandArray+1]={['UpdateDevice']=tostring(HPTempSummerMinIDX)..'|1|'.. temp}
		commandArray[#commandArray+1]={['UpdateDevice']=tostring(HPTempSummerMaxIDX)..'|1|'.. temp+2}
	end
end

monthnow = tonumber(os.date("%m"))
timeNow = os.date("*t")
minutesnow = timeNow.min + timeNow.hour * 60

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

if (timeNow.min==1 or timeNow.min==31) then
	-- shift temperatures in HPZ['tn'] and compute new tempDerivate
	HPZ['t4']=HPZ['t3']
	HPZ['t3']=HPZ['t2']
	HPZ['t2']=HPZ['t1']
	HPZ['t1']=HPZ['t0']
	-- HPZ['t0']=otherdevices[TempZoneAlwaysOn]
	HPZ['t0']=HPZ['temp']
	HPZ['gr']=math.floor((HPZ['t2']-HPZ['t3'])*50+(HPZ['t1']-HPZ['t2'])*150+(HPZ['t0']-HPZ['t1'])*300)/250
else
	temp=HPZ['temp']
	HPZ['temp']=tonumber(string.format('%.3f', (HPZ['temp']*9+tonumber(otherdevices[TempZoneAlwaysOn]))/10))
	log(E_DEBUG,"Tcucina="..otherdevices[TempZoneAlwaysOn].." Temp="..temp.." -> "..HPZ['temp'])
end
tempDerivate=HPZ['gr']

log(E_DEBUG, "HPZ[t.]=".. HPZ['t3'] .." -> ".. HPZ['t2'] .." -> ".. HPZ['t1'] .." -> ".. HPZ['t0'])
log(E_DEBUG, "tempDerivate=".. string.format('%.3f',(HPZ['t2']-HPZ['t3'])*0.2) .." + ".. string.format('%.3f',(HPZ['t1']-HPZ['t2'])*0.6) .." + ".. string.format('%.3f',(HPZ['t0']-HPZ['t1'])*1.2) .." = ".. tempDerivate) 


levelOld=HP['Level']	-- save previous level
diffMax=0

for n,v in pairs(zones) do	-- check that temperature setpoint exist
	-- n=zone name, v=CSV separated by | containing tempsensor and electrovalve device name
	-- checkVar('TempSet_'..v[ZONE_NAME],1,21)
	-- TODO: create thermostat?
	if (otherdevices[v[ZONE_TEMP_DEV] ]==nil) then
		log(E_ERROR,'Zone '..v[ZONE_NAME]..': temperature sensor '..v[ZONE_TEMP_DEV]..' does not exist')
	end
	if (v[ZONE_RH_DEV] and v[ZONE_RH_DEV]~='' and otherdevices[v[ZONE_RH_DEV] ]==nil) then
		log(E_ERROR,'Zone '..v[ZONE_NAME]..': relative humidity device '..v[ZONE_RH_DEV]..' defined in config_heatpump.lua but does not exist')
	end
	if (v[ZONE_VALVE] and v[ZONE_VALVE]~='' and otherdevices[v[ZONE_VALVE] ]==nil) then
		log(E_ERROR,'Zone '..v[ZONE_NAME]..': valve device '..v[ZONE_VALVE]..' defined in config_heatpump.lua but does not exist')
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

-- fd=io.popen("mbpoll -mrtu -a1 -b9600 -0 -1 -c1 -r8974 -l10 /dev/ttyUSBheatpump|tail -n 2|head -n 1|awk '{print $2}'")	-- read outlet water temperature
-- tempHPout=tonumber(fd:read("*a")) 	-- temp * 0.1°C
-- io.close(fd)
tempHPout=tonumber(otherdevices[HPTempOutlet])
if (tempHPout==nil or tempHPout<=-10 or tempHPout>50) then
	log(E_DEBUG,"Error reading outlet water from HeatPump plugin!")
	tempHPout=tonumber(otherdevices[TEMPHPOUT_DEV])
end
tempHPin=tonumber(otherdevices[TEMPHPIN_DEV])
if (otherdevices[HPTempOutletComputed]==nil) then
	tempHPoutComputed=tempHPout
else
	tempHPoutComputed=tonumber(otherdevices[HPTempOutletComputed])
end

valveState=''
valveStateTmp={}	-- temporarily state for valve
valveStateDiff={}	-- diff time for each zone (may be decreased by overlimitTemp to activate zones in case of extra power available from photovoltaic)
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
	instPower=getPowerValue(otherdevices[powerMeter])
	evsolar=getPowerValue(otherdevices['EV Solar'])		-- EV charging power from solar
	evgrid=getPowerValue(otherdevices['EV Grid'])		-- EV charging power from grid
	avgPower=uservariables['avgPower']	-- use the average power instead of instant power!
	avgPower=(avgPower+instPower)/2	-- instead of using average power, it's better to check also the current power.
else 
	avgPower=500 -- power meter does not exist: set avgPower to 500W by default
end
avgPower=math.floor(avgPower)
prodPower=0-avgPower
gridVoltage=0
if (GRID_VOLTAGE~='') then
	gridVoltage=tonumber(otherdevices[GRID_VOLTAGE])
end

if (heatpumpMeter~='' and otherdevices[heatpumpMeter]~=nil) then
	-- heat pump power meter exists, returning value "usagePower;totalEnergy"
	HPPower=getPowerValue(otherdevices[heatpumpMeter])
else 
	HPPower=0 -- power meter does not exist
end

-- set outdoorTemperatureMin (reset every midnight)
if (minutesnow==0 or HP['otmin']==nil or HP['otmin']>outdoorTemperature) then 
	HP['otmin']=outdoorTemperature
end
-- set outdoorTemperatureMax (reset every noon)
if (minutesnow==720 or HP['otmax']==nil or HP['otmax']<outdoorTemperature) then 
	HP['otmax']=outdoorTemperature
end


HPlevel='Off'	--default: heat pump OFF
HPforce='Day'		--default: heat pump active during the day
if (HPmode ~= 'Winter' and HPmode ~= 'Summer') then
	-- Both heating and cooling are disabled
	HP['Level']=LEVEL_OFF
	heatingCoolingEnabled=0
elseif (HPLevel==nil or otherdevices[HPLevel]==nil) then
	log(E_WARNING,'Please create a virtual device, Selector Switch, with levels "Off", "Auto", "Dehum", "Night", "DehumNight"')
else
	HPlevel=otherdevices[HPLevel]
	if (HPlevel=="Night") then
		HPlevel="Auto"
		HPforce="Night"
	elseif (HPlevel=="DehumNight") then
		HPlevel="Dehum"
		HPforce="Night"
	end
	if (HPlevel=='Dehum' and HPmode~='Summer') then
		-- Dehumidification selected in Winter mode
		-- cannot dry in Winter mode => cancel dehumidification level
		commandArray[#commandArray +1]={[HPLevel]='Set Level: 0'}	-- 0=Off
		HPlevel="Off"
	end
end

-- compressorPercOld=HP['CP']	-- get the compressorPerc used before
if (otherdevices[HPCompressorNow]==nil) then
	compressorPercOld=50	-- TODO: Stupid value
else
	compressorPercOld=tonumber(otherdevices[HPCompressorNow])	-- get current compressor level
end
compressorPerc=compressorPercOld
targetPower=0
CompressorMin=6
CompressorMax=100

inverter2Power=0	-- PVGarden inverter
if (inverter2Meter~='' and otherdevices[inverter2Meter]~=nil) then
	-- inverter2Meter device exists: extract power (skip energy or other values, separated by ;)
	inverter2Power=getPowerValue(otherdevices[inverter2Meter])
end

if (EVSTATE_DEV~='') then
	if (otherdevices[EVSTATE_DEV]=='Ch') then -- charging
		if (HP['EV']<2) then
			HP['EV']=HP['EV']+1
		end
		-- Also, if EVUPDATE_DEV lastupdate is older than 24minutes, issue a EVUPDATE to refresh EV information
		if (EVUPDATE_DEV~=nil and otherdevices_lastupdate[EVUPDATE_DEV]~=nil and timedifference(otherdevices_lastupdate[EVUPDATE_DEV])>1440) then
			commandArray[EVUPDATE_DEV]='On'
		end
	else -- not charging
		if (HP['EV']>0) then
			HP['EV']=HP['EV']-1
			if (HP['EV']==0 and HPlevel=='Off') then 
				log(E_INFO,"EV: Enable Heat Pump because EV has finished charging")
				commandArray[#commandArray +1]={[HPLevel]='Set Level: 10'}	-- 10=Auto
				HPlevel='Auto'
			end
		end
	end
end

if (HPlevel~="Off") then
	-- Auto or Dehum
	heatingCoolingEnabled=1
	-- Heating or cooling is enabled
	-- initialize some variables, depending by the HPmode variable)
	log(E_INFO,'============================ '..HPmode..': '..HPlevel..' '..HPforce..' ================================')
	if (HPmode == 'Winter') then
		-- Heating enabled
		zone_start=ZONE_WINTER_START	-- offset on zones[] structure
		zone_stop=ZONE_WINTER_STOP
		zone_offset=ZONE_WINTER_OFFSET
		zone_weight=ZONE_WINTER_WEIGHT
		-- diffMaxTh is used to define when room temperature is distant from the set point
	 	-- diffMaxTh=0.1	-- if diffMax<diffMaxTh, temperature is near the set point
		-- reduce diffMaxTh if outdoor temperature is low (to use higher temperatures to heat the building)
		diffMaxTh=((HP['otmin']-4)/40)+HP['otmax']/160
		if (timeNow.hour<3 or timeNow.hour>=20) then
			-- in the morning, or in the night, no problem if the temperature is far from setpoint
			diffMaxTh=diffMaxTh+0.1
			log(E_INFO,"Morning or Night: diffMaxTh increased to "..diffMaxTh)
		end
		if (timeNow.yday>=41 and timeNow.yday<320 and timeNow.hour<9) then
			if (CLOUDS_TODAY~='' and otherdevices[CLOUDS_TODAY]~=nil and tonumber(otherdevices[CLOUDS_TODAY])<=60) then
				-- during night, after 10 Feb with sunny weather => do not start heatpump if possible
				diffMaxTh=diffMaxTh+0.2
				log(E_INFO,"Night, from 10 Feb to 15 Nov, and Sunny => increase diffMaxTh to "..diffMaxTh)
			end
			if (timeNow.yday>=71 and timeNow.yday<305) then
				-- during night, between 10 Mar and 1 Nov => do not start heatpump in the night
				diffMaxTh=diffMaxTh+0.5
				log(E_INFO,"Night, from 10 Mar to 1 Nov => increase diffMaxTh to "..diffMaxTh)
			end
		end
		if (diffMaxTh<0.05) then diffMaxTh=0.05 end

		overlimitTemp=OVERHEAT		-- max overheat temperature
		overlimitPower=500			-- minimum power to start overheating	
		overlimitDiff=0.2			-- forced diffmax value
		prodPowerOn=300				-- minimum extra power to turn ON the heatpump
		gridPowerMin=300			-- minimum power from the grid, even when PV is producing
		if (timeNow.yday>=41 and timeNow.yday<320) then gridPowerMin=0 end	-- don't use power from grid in Spring and Autumn!
		TargetPowerMin=math.floor(510+(890/14)*(7-outdoorTemperature)) -- computed based on heat pump datasheet
		TargetPowerMax=3000
	else
		-- Cooling enabled
		zone_start=ZONE_SUMMER_START	-- offset on zones[] structure
		zone_stop=ZONE_SUMMER_STOP
		zone_offset=ZONE_SUMMER_OFFSET
		zone_weight=ZONE_SUMMER_WEIGHT
		-- cooling enabled only if consumed power is < 200 Watt. It's tolerated to consume more than 200W only if room temperature > setpoint + 2°C
		diffMaxTh=2		-- if diffMax<diffMaxTh, temperature is near the set point
		overlimitTemp=OVERCOOL		-- max overheat temperature
		overlimitPower=2500			-- minimum power to start overheating	
		overlimitDiff=0.2			-- forced diffmax value
		prodPowerOn=1000			-- minimum extra power to turn ON the heatpump
		gridPowerMin=0
		TargetPowerMin=math.floor(510+(890/14)*(outdoorTemperature-25)) -- computed based on heat pump datasheet
		TargetPowerMax=1500
		CompressorMax=50
	end
	diffMax=-10	-- max weighted difference between room setpoint and temperature
	rhMax=0		-- max value of relative humidity

	-- rhMax=70    -- DEBUG: force RH to a high value to force dehumidification

	zonesOn=0	-- number of zones that are ON
	
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
		if (timeNow.hour < v[zone_start] or timeNow.hour >= v[zone_stop]) then
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
		if (otherdevices['SetPoint_'..v[ZONE_NAME] ]) then
			setpoint=tonumber(otherdevices['SetPoint_'..v[ZONE_NAME] ])
		else
			log(E_ERROR,"Please create thermostat with name SetPoint_"..v[ZONE_NAME])
		end
		diff=math.floor((setpoint+temperatureOffset-temp)*100)/100;	-- tempSet-temp+temperatureOffsetZone
		if (HPmode ~= 'Winter') then
			-- summer => invert diff
			diff=0-diff			-- TempSet+offset(nighttime)+offset(power)-Temp	increased when there is extra power from PV
		end
		diff=diff*v[zone_weight]    -- compute the weighted difference between room temperature and setpoint
		valveStateDiff[n]=diff
		if (diff>diffMax) then
			diffMax=diff	-- store in diffMax the maximum value of room difference between setpoint and temperature 
		end
		if (v[ZONE_TEMP_DEV]==TempZoneAlwaysOn) then
			diffZoneAlwaysOn=diff	-- diff calculated on the zone that is always on
		end
		log(E_INFO,string.format('diff=% .2f RH=%-2d Temp=%.2f SP=%2.1f%+2.1f %s', diff, rh, temp, setpoint, temperatureOffset, v[ZONE_NAME]))
	end
	diffMax=math.floor(diffMax*100)/100
	if (HPforce=="Night") then
		diffMax=diffMax+2	-- force starting
	end

	-- diffMax=-0.56 --DEBUG

	log(E_INFO,'tempDerivate='..tempDerivate..' diffMax='..diffMax..' diffMaxTh='..diffMaxTh..' RHMax='..rhMax..' HPforce='..HPforce)
	if (tempDerivate<0) then
		diffMax=diffMax-tempDerivate*4	-- if room temperature is decreasing, in winter, it's better to start heater early
		log(E_INFO,"tempDerivate<0 => increase diffMax to "..diffMax)
	else
		diffMax=diffMax-tempDerivate	-- room is reaching the setPoint
		log(E_INFO,"tempDerivate>0 => decrease diffmax to "..diffMax)
	end


	-- Also, I have to consider the availability of power from photovoltaic
	if (otherdevices[powerMeter]~=nil) then
		-- power meter exists, returning value "usagePower;totalEnergy"
		-- Also, script_device_power.lua is writing the user variable avgPower with average consumed power in the minute
		inverterPower=0
		if (inverterMeter ~= '' and otherdevices[inverterMeter]~=nil) then
			-- inverterMeter device exists: extract power (skip energy or other values, separated by ;)
			inverterPower=getPowerValue(otherdevices[inverterMeter])
			inverter1Power=inverterPower
		end
		inverterPower=inverterPower+inverter2Power
		log(E_INFO,"AveragePower:"..uservariables['avgPower'].."W InstPower="..instPower.."W From PV:"..inverterPower.."W")


		-- In the morning, if room temperature is almost ok, try to export power to help the electricity grid
		if (peakPower()) then
			if (prodPower>inverter1Power) then	-- check that I'm not exporting more power than photovoltaic on the roof
				log(E_INFO,"Use only power from secondary PV: prodPower ".. prodPower .." -> "..(prodPower-inverter1Power))
				prodPower=prodPower-inverter1Power	-- use only power from secondary PV system
				if (prodPower>300) then HP['Level']=LEVEL_ON end
			else
				log(E_INFO,"Reduce diffMax to try exporting energy in the peak hours")
				if ((timeNow.month>=11 or timeNow.month<3) and timeNow.hour<12) then
					diffMax=diffMax-0.1	-- in Winter, in the morning
				else
					diffMax=diffMax-0.3 -- in Summer or in the night peak hours
				end
			end
		elseif (timeNow.yday>=71 and timeNow.yday<305 and timeNow.hour<9) then
			diffMax=diffMax-0.3
			log(E_INFO,"Night, from 10 Mar to 1 Nov => reduce diffMax to "..diffMax)
		else
			-- during the day, not in peak hours
			prodPower=prodPower+gridPowerMin -- makes the heat pump using at least gridPowerMin Watt from the grid, even while overheating
			if (prodPower>2000) then
				log(E_INFO,"Extra power => extra overlimit")
				overlimitTemp=overlimitTemp+0.3
			end
		end
		if (diffMax<=diffMaxTh and diffMax+overlimitTemp>0) then
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
				log(E_INFO,"Peak time or EV is charging => disable heat pump OverLimit")
				HP['OL']=0
				diffMax=0
				if (HPmode == 'Winter') then setOutletTemp(35) end
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
					if (HP['OL']>=4 and prodPower<100 and tonumber(otherdevices[HPTempWinterMin])>30) then 
						log(E_INFO,"Reduce min outlet temperature because there is not enough power in overlimit mode")
						if (HPmode == 'Winter') then setOutletTemp(tonumber(otherdevices[HPTempWinterMin]-1)) end
					end
					if (HP['OL']>10) then -- more than 10 minutes with insufficient power
						-- stop overheating
						HP['OL']=0
						diffMax=0
						if (HPmode == 'Winter') then setOutletTemp(35) end
					end
				end
			end
		end
		
		if (diffMax>0) then
			if (EVPOWER_DEV~=nil and EVPOWER_DEV~='') then
				-- A device measuring electric vehicle charging power exists
				-- POWER_MAX is a variable with the maximum power that the electricity meter can supply forever
				-- Increase POWER_MAX by power used by EV charger (Heat Pump has higher priority, so the EV charger should reduce its current/power)
				POWER_MAX=POWER_MAX+getPowerValue(otherdevices[EVPOWER_DEV])
			end
			if (avgPower<POWER_MAX) then
				-- must heat/cool!
				-- check that fluid is not too high (Winter) or too low (Summer), else disactivate HeatPump_Fancoil output (to switch heatpump to radiant fluid, not coil fluid temperature
				
				if (HPmode == 'Winter') then
					-- targetPower computed based on outdoor temperature min and max
					targetPower=math.floor(((12-HP['otmin'])^1.5)*22 + ((24-HP['otmax'])^1.6)*4)
					log(E_INFO,"targetPower="..targetPower.." computed based on otmin and otmax")
					if (diffMax>diffMaxTh+0.1) then
						if (timeNow.hour>=10 and timeNow.hour<17) then
							-- increase power to recover the comfort state
							targetPower=math.floor(targetPower+(diffMax-diffMaxTh-0.1)*2000)
							log(E_INFO,"targetPower="..targetPower.." increased due to diffMax>diffMaxTh+0.1 (daylight)")
						else
							-- increase power to recover the comfort state
							targetPower=math.floor(targetPower+(diffMax-diffMaxTh-0.1)*800)
							log(E_INFO,"targetPower="..targetPower.." increased due to diffMax>diffMaxTh+0.1")
						end
					end
					
					-- if sunny, in the morning, reduce target power (then increase if photovoltaic produce more than house usage)
					if (CLOUDS_TODAY~='' and otherdevices[CLOUDS_TODAY]~=nil and tonumber(otherdevices[CLOUDS_TODAY])<=50 and diffMax<diffMaxTh and timeNow.hour<14) then
						-- Sunny !!
						targetPower=targetPower-300 -- Try to use energy from photovoltaic, reducing power during the night
						log(E_INFO,"targetPower-=300 because it is Sunny and diffMax is low")
						if (peakPower()) then -- try to export power
							log(E_INFO,"targetPower-=300 peakPower()")
							targetPower=targetPower-300 
						end
					end 
					
					-- between 10 and 17 increase power by 300 + k*diffMax²
					if (timeNow.hour>=10 and timeNow.hour<17) then
						log(E_INFO,"targetPower+=300 between 10 and 17")
						targetPower=targetPower+300
						if (timeNow.hour>=12) then 
							targetPower=targetPower+math.floor(diffMax*diffMax*2000)	-- Adjust targetPower based on diffMax value
							log(E_INFO,"targetPower="..targetPower.." computed based on diffMax² after 12:00")
						end
					elseif (timeNow.hour<8 or timeNow.hour>=20) then	-- during the night reduce power if diffMax near zero
						if (diffMax<diffMaxTh and tempDerivate>=0) then
							--rooms almost in temperature, in the night
							targetPower=TargetPowerMin
							log(E_INFO,"targetPower="..targetPower.." reduced because rooms almost in temperature")
						else
							targetPower=math.floor(targetPower*0.8)
							log(E_INFO,"targetPower="..targetPower.." reduced by 20% because night time")
						end

					end

					-- use all available power from photovoltaic
					if (targetPower<HPPower+prodPower and (EVSTATE_DEV=='' or otherdevices[EVSTATE_DEV]~='Ch')) then --more power available
						targetPower=HPPower+prodPower -- increase targetPower because there more power is available from photovoltaic
						log(E_INFO,"targetPower="..targetPower.." increased due to available prodPower")
						if (timeNow.yday>=75 and timeNow.yday<310) then
							if (targetPower>1800) then
								if (gridVoltage<245) then
									targetPower=1800
									log(E_INFO,"targetPower="..targetPower.." limited to 1800 in Autumn and Spring")
								else
									log(E_INFO,"targetPower="..targetPower.." NOT limited due to high grid voltage="..gridVoltage)
								end
							end
						end
					end
					-- verify that targetPower is >= TargetPowerMin (or the heat pump will switch off)
					if (targetPower<TargetPowerMin) then targetPower=TargetPowerMin end -- avoid heatpump going off
				elseif (HPmode == 'Summer') then
					-- during the Summer
					-- targetPower computed based on outdoor temperature min and max
					if (HP['otmax']>=28 and HP['otmin']>=16) then
						targetPower=math.floor(((HP['otmax']-28)^1.5)*22 + ((HP['otmin']-16)^1.6)*4)
					else
						targetPower=TargetPowerMin
					end
					log(E_INFO,"targetPower="..targetPower.." computed based on otmin and otmax")
					
					-- between 11 and 17 increase power by 300 + k*diffMax²
					if (timeNow.hour>=12 and timeNow.hour<16) then
						targetPower=targetPower+math.floor(diffMax*diffMax*1000)	-- Adjust targetPower based on diffMax value
						log(E_INFO,"targetPower="..targetPower.." computed based on diffMax² after 12:00")
					elseif (timeNow.hour<9 or timeNow.hour>=18) then	-- during the night reduce power if diffMax near zero
						if (diffMax<diffMaxTh and tempDerivate>=0) then
							--rooms almost in temperature, in the night
							diffMax=0	-- 
							log(E_INFO,"set diffMax=0 to disable heat pump, because rooms almost in temperature")
						else
							targetPower=math.floor(targetPower*0.8)
							log(E_INFO,"targetPower="..targetPower.." reduced by 20% because peak hours or night time")
						end

					end

					-- use all available power from photovoltaic
					if (targetPower<HPPower+prodPower and (EVSTATE_DEV=='' or otherdevices[EVSTATE_DEV]~='Ch')) then --more power available
						targetPower=HPPower+prodPower -- increase targetPower because there more power is available from photovoltaic
						log(E_INFO,"targetPower="..targetPower.." increased due to available prodPower")
					end
					-- verify that targetPower is >= TargetPowerMin (or the heat pump will switch off)
					if (targetPower<TargetPowerMin) then targetPower=TargetPowerMin end -- avoid heatpump going off
				end

				if (HP['OL']>0) then -- overlimit, but no power available
					targetPower=HPPower+prodPower
					log(E_INFO,"targetPower="..targetPower.." reduced because overlimit and prodPower<0. TargetPowerMin="..TargetPowerMin)
					if (targetPower<TargetPowerMin) then targetPower=TargetPowerMin end
				end
				if (targetPower>TargetPowerMax) then targetPower=TargetPowerMax end

			
				-- set compressorPerc
				if (HPPower<450) then
					-- Heat pump is not heating/cooling
					compressorPerc=math.floor(targetPower/28)	-- absolute percentage
					log(E_DEBUG,"compresorPerc="..compressorPerc.." (set to targetPower/28)")
				else
					-- Heat pump is heating/cooling: compute differential value
					diff=targetPower-HPPower
					if (diff>0) then
						compressorPerc=compressorPercOld+diff/60
						log(E_DEBUG,"compresorPerc="..compressorPerc.." (increased by diff/60)")
						if (compressorPerc>targetPower/25) then 
							compressorPerc=targetPower/25 
							log(E_DEBUG,"compresorPerc="..compressorPerc.." (limited to targetPower/25)")
						end
					else
						compressorPerc=compressorPercOld+diff/80
						log(E_DEBUG,"compresorPerc="..compressorPerc.." (decreased by diff/80)")
						if (compressorPerc<targetPower/40) then 
							compressorPerc=targetPower/40 
							log(E_DEBUG,"compresorPerc="..compressorPerc.." (downlimited to targetPower/40)")
						end
						if (timeofday['Nighttime'] and tonumber(otherdevices[HPTempWinterMin])>35) then
							if (HPmode == 'Winter') then setOutletTemp(35) end
							log(E_DEBUG,"Decrease TempWinterMin to 35°C")
						end
					end
				end
				if (HPmode == 'Winter' and prodPower>500 and tonumber(otherdevices[HPTempWinterMin])<40 and HPPower>=500 and (tempHPoutComputed-tempHPout)<3) then
					setOutletTemp(40)
					log(E_DEBUG,"Increase TempWinterMin to 40°C")
				end
				if (HP['Level']==LEVEL_OFF) then -- HP['Level']=LEVEL_OFF => Heat pump is OFF
					if (HPforce=="Night") then -- force heat pump ON, if diffTime>0
						HP['Level']=LEVEL_ON
					else -- Day
						-- diffMax>0, some power available (from grid or solar) => should I turn ON heating/cooling?
						if (diffMax>=diffMaxTh or (timeNow.hour>=9 and prodPower>targetPower)) then
							HP['Level']=LEVEL_ON
						end
					end
				end

				if (HP['Level']>=LEVEL_ON) then
					-- regulate fluid tempeature in case of max Level 
					if (HPmode == 'Winter') then
						-- check that fluid is not decreasing abnormally
						if (tempHPout>HP['HPout']) then
							if (tempHPout>=HP['HPout']+1) then
								HP['HPout']=tempHPout 
								if (HP['HPout']>=TEMP_WINTER_HP_MAX+2) then
									log(TELEGRAM_LEVEL,"Fluid temperature is too high!! "..HP['HPout'].."°C")
									HP['Level']=LEVEL_OFF
								end
							end
						elseif (tempHPout<HP['HPout']-1) then
							HP['HPout']=tempHPout
							if (otherdevices[HPSummer]=='On') then 
								log(TELEGRAM_LEVEL, HPSummer.." was On => disable it")
								commandArray[HPSummer]='Off'
							end
							if (HP['HPout']<=TEMP_SUMMER_HP_MIN and otherdevices[HPOn]=='On') then	-- fluid temperature low and heatpump is on
								--fluid temperature is decreasing below a reasonable value => send alert
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is very low!! "..HP['HPout'].."°C")
								HP['Level']=LEVEL_OFF
							end
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
							if (HP['HPout']>=30 and HP['Level']==0) then
								log(TELEGRAM_LEVEL,"Fluid temperature from heat pump is too high!! "..HP['HPout'].."°C")
							end
						end
					end
				else
					-- if (HP['Level']==LEVEL_OFF

					
				end -- if (HP['Level']>0
				HPZ['tf']=tempHPout -- save the current tempHPout value
			else	--avgPower>=POWER_MAX: decrement level
				log(E_INFO,"Too much power consumption => decrease Heat Pump level")
				--HP['Level']=LEVEL_OFF
			end
		elseif (diffMax<0) then
			-- diffMax<=0 => All zones are in temperature!
			if (HP['Level']>LEVEL_OFF)  then 
				-- temperature and humidity are OK
				log(E_INFO,"All zones are in temperature! RHMax="..rhMax)
				HP['Level']=LEVEL_OFF
			end
		elseif (diffMax>=0 and peakPower()==false and HP['toff']>=90) then
			log(E_DEBUG,"Start heat pump, because off for more than 90 minutes and peakPower()==false")
			HP['Level']=LEVEL_ON
		end
	else
		log(E_DEBUG,'No power meter installed')
	end
	log(E_DEBUG,"diffMax="..diffMax.." diffMaxTh="..diffMaxTh.." prodPower="..prodPower.." prodPowerOn="..prodPowerOn)

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
			HP['Level']=LEVEL_OFF
		end
	end
else
	-- HPlevel==Off
	heatingCoolingEnabled=0
	HP['Level']=LEVEL_OFF
end 

if (HP['EV']>=2 and HPlevel~='Off') then
	if (diffMax<0.15 or HP['OL']~=0) then 
		log(E_INFO,"EV: Disable Heat Pump because EV is charging and diffMax<0.15 or HP[OL]~=0")
		HPlevel='Off'
		heatingCoolingEnabled=0
		HP['Level']=LEVEL_OFF
	else
		HP['EV']=1 --retry next minute
	end
end

-- now scan DEVlist and enable/disable all devices based on the current level HP['Level']
if (HPmode == 'Summer') then
	if (otherdevices[HPSummer]~='On' and HP['Level']>0) then
		commandArray[HPSummer]='On'
	end
	devLevel=4	-- used to select the proper column in DEVlist structure
	compressorPerc=compressorPercOld+(prodPower-500)/30	-- try have 500W exported
	if (compressorPerc<5) then
		-- no enough power: set heat pump to minimum, and disable VMC DEHUMIDIFY if enabled
		compressorPerc=5
		deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	end
	if (minutesnow>=timeofday['SunsetInMinutes'] or minutesnow<timeofday['SunriseInMinutes']) then
		if (compressorPerc>30) then compressorPerc=30 end	-- avoid too noise in the night
	end
else
	devLevel=2	-- default: Winter. Column in DEVlist structure
end	
if (HP['OL']~=0 and heatingCoolingEnabled~=0) then
	-- overlimit on : track power
	compressorPerc=math.floor(compressorPercOld+(prodPower-500)/30)
	log(E_DEBUG,"OverLimit ON: compressorPerc="..compressorPerc.." Old="..compressorPercOld)
	if (HP['Level']==0 and otherdevices[HPLevel]~='Off') then HP['Level']=LEVEL_ON end
end

if (compressorPerc==nil) then compressorPerc=10 end
if (otherdevices[HPLevel]=='Dehum' or otherdevices[HPLevel]=='DehumNight') then compressorPerc=15 end	-- heat pump must go at very low level, because it should only supply the dehumidifier VMC

if (compressorPerc>CompressorMax) then 
	compressorPerc=CompressorMax 
elseif (compressorPerc<CompressorMin) then 
	compressorPerc=CompressorMin 
else
	compressorPerc=math.floor(compressorPerc)
end
if (compressorPerc~=compressorPercOld) then
	commandArray[HPCompressor]="Set Level "..tostring(compressorPerc)
end

for n,v in pairs(DEVlist) do
	-- n=table index
	-- v={deviceName, winterLevel, summerLevel}
	if (v[devLevel]<255) then -- if devLevel is set to 255, device should be ignored
		-- v[devLevel]=START level
		-- v[devLevel+1]=STOP level   e.g. HeatPump_HalfPower: start level=1, stop level=2, so this device should be activated only when HP['level']==1
		if (HP['Level']>=v[devLevel+1] or HP['Level']<v[devLevel]) then
			-- this device has a level > of current level => disable it
			if (HP[n]~=nil) then log(E_DEBUG,"HP[d"..n.."]="..HP["d"..n]) end
			deviceOff(v[1],HP,"d"..n)
			commandArray[ v[1] ]="Off"
		else
			-- this device has a level <= of current level => enable it
			deviceOn(v[1],HP,"d"..n)
		end
	end
end
updateValves() -- enable/disable the valve for each zone


-- other customizations....
-- Make sure that radiant circuit is enabled when outside temperature goes down, or in winter, because heat pump starts to avoid any damage with low temperatures

if ((outdoorTemperature<=4 or tonumber(otherdevices['Temp_GarageVerde'])<=4) or (HPmode=='Winter' and HP['Level']>LEVEL_OFF) or (HPmode=='Summer' and HP['Level']>=1 and otherdevices[HPLevel]~='Dehum' and otherdevices[HPLevel]~='DehumNight') or GasHeaterOn==1) then
	if (otherdevices[HPValveRadiantCoil]~='On') then
		commandArray[HPValveRadiantCoil]='On'
		HP['trc']=0
	end
else
	HP['trc']=HP['trc']+1
	if (otherdevices[HPValveRadiantCoil]~='Off' and HP['trc']>=3) then
		commandArray[HPValveRadiantCoil]='Off'
	end
end

if (HP['Level']==0) then
	deviceOff(VENTILATION_COIL_DEV,HP,'DC')
	deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
elseif (HPmode=='Summer') then
	-- Summer, and Level~=0
	if (HP['Level']>=1) then
		if (prodPower+evsolar>800) then deviceOn(VENTILATION_COIL_DEV,HP,'DC') end
		if (tempHPout<=17 and (tempHPin<=17 or (tempHPin<20 and (HPlevel=='Auto' or HPlevel=='Night'))) and prodPower+evsolar>1800) then	-- activate chiller only if fluid temperature from heat pump is cold enough
			deviceOn(VENTILATION_DEHUMIDIFY_DEV,HP,'DD') 
		elseif (tempHPout>=18) then
			-- if (otherdevices[HPLevel]~='Dehum') then deviceOff(VENTILATION_COIL_DEV,HP,'DC') end
			deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
		end
		if (HPlevel=='Dehum' or HPlevel=='DehumNight') then
			if (tonumber(otherdevices[HPTempSummerMin])~=14) then
				setOutletTemp(14)
				log(E_ERROR,"Set TempSummerMin to 14°C")
			end
		else
			if (tonumber(otherdevices[HPTempSummerMin])~=15) then
				setOutletTemp(15)
				log(E_ERROR,"Set TempSummerMin to 15°C")
			end
		end
	else		
		deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD')
	end
	if (prodPower<0) then 
		if (otherdevices[VENTILATION_DEHUMIDIFY_DEV]=="On") then
			deviceOff(VENTILATION_DEHUMIDIFY_DEV,HP,'DD') 
		else
			HP['Level']=LEVEL_OFF;
		end
	end
end

if (HP['Level']>0 or outdoorTemperature<=4 or tonumber(otherdevices['Temp_GarageVerde'])<=4) then
	HP['toff']=0
	if (otherdevices[HPRelay]=='Off') then
		commandArray[HPRelay]='On'	-- Activate relay feeding power supply to the heat pump
	end
else
	HP['toff']=HP['toff']+1
	if (HP['toff']>60) then HP['toff']=60 end
	if (HP['toff']>=30 and otherdevices[HPRelay]~='Off') then commandArray[HPRelay]='Off' end -- Remove power supply to the heat pump (to save energy consumption)
	log(E_DEBUG,"HP[toff]="..HP['toff'])
end

-- save variables
diffMax=string.format("%.2f", diffMax)
diffMaxText=' dT='..diffMax..'°C'
if (HP['OL']~=0) then diffMaxText=' OverLimit' end
log(E_INFO,'L:'..levelOld..'->'..HP['Level']..diffMaxText..' dT/dt='..tempDerivate..' TP='..targetPower..'W HP/Grid='..HPPower..'W/'..avgPower..'W Compr='..compressorPercOld..'->'..compressorPerc..'% Out/In='..tempHPout..'->'..tempHPoutComputed..'/'..tempHPin..'°C Now/min/max='..outdoorTemperature..'/'..HP['otmin']..'/'..HP['otmax']..'°C')
log(E_DEBUG,'------------------------------------------------')
commandArray[#commandArray+1]={['UpdateDevice'] = HPStatusIDX..'|0|L:'..levelOld..'->'..HP['Level']..diffMaxText.." dT/dt="..tempDerivate.." TP="..targetPower.."W\nOut/In="..tempHPout..'/'..tempHPin..'°C Comp='..compressorPerc..'%'}

if (HP['Level']==0) then
	hpstat='Off '
else
	hpstat='On '
end
if (otherdevices['eNiro: EV battery level']~=nil) then
	carsoc=otherdevices['eNiro: EV battery level']..'% '..otherdevices['eNiro: EV range']..'km'
else
	carsoc="unknown"
end


commandArray[#commandArray+1] = {['UpdateDevice']=HPStatus2IDX..'|0|HeatPump '..hpstat..diffMaxText.." dT/dt="..tempDerivate..'\nPV Garden: '..inverter2Power..'W Inv.Limit: '..otherdevices['PVGarden_Limit']..'%\nCar:'..carsoc..' P='..evsolar..'+'..evgrid..' V='..gridVoltage}
HP['CP']=compressorPerc
--print("commandArray="..commandArray[#commandArray])
commandArray['Variable:zHeatPump']=json.encode(HP)
commandArray['Variable:zHeatPumpZone']=json.encode(HPZ)

--log(E_DEBUG,'zHeatPump='..json.encode(HP))
--log(E_DEBUG,'zHeatPumpZone='..json.encode(HPZ))

::mainEnd::

return commandArray
