-- scripts/lua/power.lua - Called by script_device_master.lua
-- Written by Creasol, https://creasol.it linux@creasol.it
-- Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions
--   1. Send notification when consumed power is above a threshold (to avoid power outage)
--   2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid
--   3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored
--   4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
--      green LED flashes 1..M times if photovoltaic produces up to 1..M kWatt
--

-- At least a device with "Power" in its name has changed: let's go!

DEBUG_LEVEL=E_WARNING
DEBUG_LEVEL=E_INFO
--DEBUG_LEVEL=E_DEBUG

dofile "scripts/lua/config_power.lua"		-- configuration file

-- ENABLE THE FOLLOWING LINE, BUT ONLY THE FIRST TIME TO CREATE GridPower variable, then disable it to save execution time
--checkVar('GridPower',0,0) -- check that uservariable at1 exists, else create it with type 0 (integer) and value 0

timeNow=os.date("*t")

function PowerInit()
	if (Power==nil) then Power={} end
	if (Power['th1']==nil) then Power['th1']=0 end
	if (Power['th2']==nil) then Power['th2']=0 end
	if (Power['a']==nil) then Power['a']=0 end
	if (Power['u']==nil) then Power['u']=0 end
	if (Power['d']==nil) then Power['d']=0 end
	if (Power['min']==nil) then Power['min']=0 end	-- current time minute: used to check something only 1 time per minute
	if (Power['EV']==nil) then Power['EV']=0 end	-- EV Charge power
	if (Power['L1']==nil and HOYMILES_ID~='') then Power['L1']=6000 end	-- Inverter1 power limit
	if (Power['D1']==nil and HOYMILES_ID~='') then Power['D1']=0 end	-- Delay (in minutes) since last power limit setup
	if (Power['HL']==nil and HOYMILES_ID~='') then Power['HL']=HOYMILES_LIMIT_MAX end	-- Hoymiles power limit
	if (Power['HS']==nil and HOYMILES_ID~='') then Power['HS']=0 end	-- Inverter producing status (0=Off, 1=On) 
	if (Power['Ht']==nil and HOYMILES_ID~='') then Power['Ht']=0 end	-- time, since epoch, when hoymiles inverter limit was set
	if (Power['H1']==nil and HOYMILES_ID~='') then Power['H1']=0 end	-- energy measured every 15 minutes on inverter1
	if (Power['HI']==nil and HOYMILES_ID~='') then Power['HI']=0 end	-- exported energy measured on grid
	if (Power['Hm']==nil and HOYMILES_ID~='') then Power['Hm']=0 end	-- exported energy measured on grid
	--if (PowerAux==nil) then PowerAux={} end
end	

function EVSEInit()
	if (EVSE==nil) then EVSE={} end
	if (EVSE['T']==nil) then EVSE['T']=0 end	-- EVSE: absolute time used to compute when power can stay over Threshold1 and below Threshold2 (27% over the contractual power)
	if (EVSE['t']==nil) then EVSE['t']=0 end	-- EVSE: time the EVSE is over Threshold2, to determine if charging must be stopped
	if (EVSE['S']==nil) then EVSE['S']='Dis' end	-- EVSE: last state
end

function evseSetGreenPower(Er, Et)	-- Er=green energy used to charge the vehicle in the last Et seconds
	local Eo=getEnergyValue(otherdevices_svalues[EVSE_RENEWABLE])	-- old renewable energy value
	local Pr=Er*3600/Et			-- current renewable power
	local Pc=getPowerValue(otherdevices[EVSE_POWERMETER])
	local Prperc=0
	--log(E_DEBUG,"EVSE: greenPower: Eo="..Eo.." Pr="..Pr.." Pc="..Pc)
	if (Pc>0) then Prperc=math.floor(Pr*100/Pc) end
	-- if (Prperc>100) then Prperc=100 end
	table.insert(commandArray,	{['UpdateDevice'] = otherdevices_idx[EVSE_RENEWABLE].."|0|"..Pr..';'..tostring(Eo+Er)})	-- Update EVSE_greenPower
	table.insert(commandArray,{['UpdateDevice'] = otherdevices_idx[EVSE_RENEWABLE_PERCENTAGE].."|0|"..Prperc})			-- Update EVSE_green/total percentage
	log(E_DEBUG,"EVSE: greenPower="..Pr.." "..Prperc.."%")
end

function setAvgPower() -- store in the user variable avgPower the building power usage
	if (uservariables['avgPower']==nil) then
		-- create a Domoticz variable, coded in json, within all variables used in this module
		avgPower=currentPower
		url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=avgPower&vtype=0&vvalue='..tostring(currentPower)
		os.execute('curl -m 1 "'..url..'"')
		-- initialize variable
	else
		avgPower=tonumber(uservariables['avgPower'])
	end
	log(E_DEBUG,"currentPower="..currentPower.." Usage="..Power['u'].." EV="..Power['EV'])
	avgPower=(math.floor((avgPower*11 + currentPower - Power['u'] - Power['EV'])/12)) -- average on 12*5s=60s
	powerChanged=true
end


function getPower() -- extract the values coded in JSON format from domoticz zPower variable, into Power dictionary
	if (Power==nil) then
		-- check variable zPower
		json=require("dkjson")
		if (uservariables['zPower']==nil) then
			-- create a Domoticz variable, coded in json, within all variables used in this module
			PowerInit()	-- initialize Power dictionary
			url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=zPower&vtype=2&vvalue='
			os.execute('curl -m 1 "'..url..'"')
			-- initialize variable
		else
			Power=json.decode(uservariables['zPower'])
		end
		PowerInit()
		PowerChanged=false
	end	
	if (PowerAux==nil) then
		-- check variable zPower
		json=require("dkjson")
		if (uservariables['zPowerAux']==nil) then
			-- create a Domoticz variable, coded in json, within all variables used in this module
			log(E_INFO,"ERROR: creating variable zPowerAux")
			PowerAux={}	-- initialize PowerAux dictionary
			url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=zPowerAux&vtype=2&vvalue='
			os.execute('curl -m 1 "'..url..'"')
			-- initialize variable
		else
			PowerAux=json.decode(uservariables['zPowerAux'])
			if (otherdevices['Pranzo_Stufetta']=='On' and PowerAux['f1']==nil) then
				log(E_INFO,"ERROR, Pranzo_Stufetta On manually")
			end
		end
		PowerInit()
	else
		log(E_INFO,"PowerAux!=nil")
		log(E_INFO,"PowerAux="..json.encode(PowerAux))
	end

	if (uservariables['zHeatPump']~=nil) then
		HP=json.decode(uservariables['zHeatPump'])  -- get HP[] with info from HeatPump
	end
	if (HP==nil or HP['Level']==nil) then
		HP={}
		HP['Level']=1
	end

	if (EVSE==nil) then
		-- check variable zPower
		json=require("dkjson")
		if (uservariables['zEVSE']==nil) then
			-- create a Domoticz variable, coded in json, within all variables used in this module
			EVSEInit()	-- initialize Power dictionary
			url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=zEVSE&vtype=2&vvalue='
			os.execute('curl -m 1 "'..url..'"')
			-- initialize variable
		else
			EVSE=json.decode(uservariables['zEVSE'])
		end
		EVSEInit()
	end	

end

function powerMeterAlert(on)
	for k,pma in pairs(PowerMeterAlerts) do
		if (on~=0) then
			if (otherdevices[ pma[1] ]~=pma[3]) then
				log(E_INFO,"Activate sound alert "..pma[1])
				commandArray[ pma[1] ]=pma[3]
			end
		else
			-- OFF command
			if (otherdevices[ pma[1] ]~=pma[2]) then
				--log(E_DEBUG,"Disable sound alert "..pma[1])
				commandArray[ pma[1] ]=pma[2]
			end
		end
	end
end

function powerDisconnect() 
	-- disconnect the last device in Heater table, that is ON. Return 0 in case that no devices have been disconnected
	disc=0	-- number of devices that will be disconnected
	for k,f in pairs(DeviceToDisconnect) do
		-- log(E_WARNING,"Device "..f[1].." = "..otherdevices[ f[1] ])
		if (otherdevices[ f[1] ]~=f[2]) then
			log(E_CRITICAL, "Potenza="..currentPower..": Disconnesso "..f[1])
			commandArray[ f[1] ]=f[2]
			disc=1
			break
		end
	end
	if (disc==0) then
		log(E_ERROR, "No loads available for disconnection")
	end
	return disc
end

currentPower=10000000 -- dummy value (10MW) used to determine if currentPower has changed or not
HPmode=otherdevices[HPMode]	-- 'Off', 'Winter' or 'Summer'
if (HPmode==nil) then 
	HPmode='Off' 
	log(E_INFO,"You should create a selector switch named "..HPMode.." with 3 levels: Off, Winter, Summer")
end

getPower() -- get Power, PowerAUX, HP, EVSE structures from domoticz variables (coded in JSON format)
incMinute=0	-- zero if script was executed not at the start of the current minute
if (Power['min']~=timeNow.min) then
	-- minute was incremented
	Power['min']=timeNow.min
	PowerChanged=true	-- force saving Power[]
	incMinute=1 -- minute incremented => set this variable to exec some checking and functions
	if (Power['D1']<9) then Power['D1']=Power['D1']+1 end	-- time since last power limit command
end

inverter1Power=math.floor(getPowerValue(otherdevices['PV_PowerMeter']))
inverter2Power=getPowerValue(otherdevices['PVTracker_PowerMeter'])

if (incMinute==1) then
	-- every minute
	if ((timeNow.min%15)==0) then
		-- every 15 minutes
		if (timeNow.min==0 and timeNow.hour==0) then
			-- at midnight
			-- Download ENTSOE csv file with prices every 15 minutes
			os.execute("wget -O scripts/lua/bidq.csv https://images.creasol.it/IT_NORDq.csv")
		end
		-- read current price
		local file = io.open("scripts/lua/bidq.csv", "r")
		local fields = {}
		if file then
			local line = file:read("*line")  -- Legge solo la prima riga
			for f in string.gmatch(line, "([^,]+)") do
				table.insert(fields, f)
			end
		end
		-- extract current price and avgprice

		local price=fields[timeNow.hour*4+timeNow.min//15+1]
		local avgPrice=fields[96]
		checkVar('entsoe_price',1,0.1)
		checkVar('entsoe_avgPrice',1,0.1)
		commandArray['Variable:entsoe_price']=tostring(price)
		commandArray['Variable:entsoe_avgPrice']=tostring(avgPrice)
		log(E_INFO,"HOYMILES: CurrentPrice="..price.." AveragePrice="..avgPrice)
	end
end

for devName,devValue in pairs(devicechanged) do
	-- check for device named PowerMeter and update all DomBusEVSE GRIDPOWER virtual devices
	if (PowerMeter~='') then
		-- use PowerMeter device, measuring instant power (goes negative in case of exporting)
		if (devName==PowerMeter) then
			currentPower=getPowerValue(devValue)
			log(E_DEBUG,"currentPower1="..currentPower.." from devName="..PowerMeter.." devValue="..devValue)
		end
	else
		-- use PowerMeterImport and PowerMeterExport (if available)
		if ((PowerMeterImport~='' and devName==PowerMeterImport) or (PowerMeterExport~='' and devName==PowerMeterExport)) then
			currentPower=getPowerValue(otherdevices[PowerMeterImport])
			if (PowerMeterExport~='') then 
				currentPower=currentPower-getPowerValue(otherdevices[PowerMeterExport]) 				
			end
		end
	end

	if (EVPowerMeter ~= '') then
		-- get actual EV charging power
		if (devName==EVPowerMeter) then
			-- new value from the electric vehicle charging power meter
			Power['EV']=getPowerValue(devValue)
			log(E_INFO,"Power[EV]="..Power['EV'])
			powerChanged=true
			-- output current value to led status
			if (EVLedStatus ~= '') then
				l=(math.floor(Power['EV']/1000))*10	-- 0=0..999W, 1=1000..1999, 2=2000..2999W, ...
				for k,led in pairs(EVLedStatus) do
					if (otherdevices_svalues[led]~=tostring(l)) then
						commandArray[led]="Set Level "..tostring(l)
						log(E_DEBUG,"EV: ChargingPower >= " .. l/10 .. "kW => Set leds")
					end
				end
			end
		end
	end
	if (devName == 'EV Current') then
		if (batteryLevel==nil) then
			if (otherdevices_svalues['eNiro: EV battery level']~=nil) then
				batteryLevel=otherdevices_svalues['eNiro: EV battery level']
			else
				batteryLevel=unknown
			end
		end
		log(E_INFO, "V="..otherdevices['EV Voltage'].." => EVCurr="..otherdevices_svalues['EV Current'].."A (EVPower="..getPowerValue(otherdevices['EV Energy']).." GridPower="..getPowerValue(otherdevices['Grid Power']).." PV="..inverter1Power.."+"..inverter2Power.."W CarSoC="..batteryLevel.."%)" )
	end

	-- if blackout, turn on white leds in the building!
	if (devName==blackoutDevice) then
		log(E_WARNING,"========== BLACKOUT: "..devName.." is "..devValue.." ==========")
		if (devValue=='Off') then -- blackout
			log(E_WARNING, "Turn on white leds")
			for k,led in pairs(ledsWhite) do
				if (otherdevices[led]~=nil and otherdevices[led]~='0n') then
					commandArray[led]='On'
					Power['BL_'..k]='On'	-- store in a variable that this led was activated by blackout check
				end
			end
			for k,led in pairs(ledsWhiteSelector) do
				if (otherdevices_svalues[led]~=nil and otherdevices_svalues[led]~='1') then
					commandArray[led]="Set Level 1"
					Power['BLS_'..k]='On'	-- store in a variable that this led was activated by blackout check
				end
			end
			for k,buzzer in pairs(blackoutBuzzers) do
				if (otherdevices_svalues[buzzer]~=nil) then
					commandArray[buzzer]="On for 10"
				end
			end
		else -- power restored
			for k,led in pairs(ledsWhite) do
				if (otherdevices[led]~=nil and otherdevices[led]~='0ff' and (Power['BL_'..k]==nil or Power['BL_'..k]=='On')) then
					commandArray[led]='Off'
					Power['BL_'..k]=nil
				end
			end
			for k,led in pairs(ledsWhiteSelector) do
				if (otherdevices_svalues[led]~=nil and otherdevices_svalues[led]~='0' and (Power['BLS_'..k]==nil or Power['BLS_'..k]=='On')) then
					commandArray[led]="Set Level 0"
					Power['BLS_'..k]=nil
				end
			end
			for k,buzzer in pairs(blackoutBuzzers) do
				if (otherdevices_svalues[buzzer]~=nil) then
					commandArray[buzzer]="Off"
				end
			end
		end
	end
	if (devName=='Voltage_Battery') then
		-- check battery voltage, AC detector and disable internet router when battery voltage is very low
		batteryVoltage=tonumber(otherdevices_svalues['Voltage_Battery'])
		if (otherdevices[blackoutDevice]=='Off' and otherdevices['Router_WAN_Reset']=='Off' and batteryVoltage<12.4) then
			log(E_CRITICAL, "Blackout e tensione batteria bassa " .. batteryVoltage .." => tolgo alimentazione al router internet")
			commandArray['Router_WAN_Reset']='On'
		elseif (otherdevices[blackoutDevice]=='On' and otherdevices['Router_WAN_Reset']=='On') then
			log(E_CRITICAL, "Blackout restored => riabilito alimentazione al router internet")
			commandArray['Router_WAN_Reset']='Off'
		end
	end
	if (HOYMILES_ID~='' and devName==HOYMILES_VOLTAGE_DEV) then
		-- check when value have been modified last time
		hoymilesVoltage=tonumber(otherdevices[HOYMILES_VOLTAGE_DEV])
		if (otherdevices[EVSE_STATE_DEV]~='Ch') then
			-- not charging EV => modulate power
			newlimit=Power['HL'] -- newlimit = previous limit
			if (HOYMILES_LIMIT_VOLTAGE~=0) then
				if (hoymilesVoltage>=HOYMILES_LIMIT_VOLTAGE) then 
					-- determine how fast to increase power, depending by difference between hoymilesVoltage and HOYMILES_LIMT_VOLTAGE
					div=(hoymilesVoltage-HOYMILES_LIMIT_VOLTAGE)
					if div>3 then div=3 end						
					newlimit=math.floor((Power['HL']-(div*300)))
					if (newlimit<100) then newlimit=100 end
					log(E_DEBUG,"HOYMILES: Voltage "..hoymilesVoltage..">="..HOYMILES_LIMIT_VOLTAGE.." => Reduce inverter power from "..Power['HL'].." to "..newlimit.."W")
				else
					if (Power['HL']<HOYMILES_LIMIT_MAX) then
						-- determine how fast to increase power, depending by difference between hoymilesVoltage and HOYMILES_LIMT_VOLTAGE
						div=6-(HOYMILES_LIMIT_VOLTAGE-hoymilesVoltage)/2
						if div<2 then div=2 end						
						newlimit=math.floor((Power['HL']+(HOYMILES_LIMIT_MAX-Power['HL'])/div))
						if (newlimit>(HOYMILES_LIMIT_MAX-50)) then newlimit=HOYMILES_LIMIT_MAX end
						log(E_DEBUG,"HOYMILES: Voltage "..hoymilesVoltage.." <"..HOYMILES_LIMIT_VOLTAGE.." => Increase inverter power from "..Power['HL'].." to "..newlimit.."W")
					end
				end
			end
		else
			newlimit=HOYMILES_LIMIT_MAX	-- always MAX power if vehicle is charging
		end
		local cp=getPowerValue(otherdevices[PowerMeter])	-- Grid Power 
		local l1=INVERTER1_LIMIT_MAX	-- default value for inverter1 limit
		local export=0
		if (uservariables['entsoe_price']<=0) then	--check energy price
			-- Disable energy export!!
			-- Modify solaredge inverter power every minute (it's very slow due to the ramping feature that takes minutes!)
			l1=Power['L1']
			if (otherdevices[EVSE_STATE_DEV]=='Ch') then 
				-- while charging the vehicle, 
				if (tonumber(otherdevices['EV MinVoltage'])<=230) then
					-- EV MinVoltage is low => full speed charging
					export=1200
				else
					export=400
				end
			else
				export=100
			end
			if (uservariables['entsoe_price']==0)  then export=export+1000 end	-- Price not negative => increase export to prevent import!
			if (Power['D1']>5) then
				-- if cp=-2000W => set inverter limit to current inverter1 power - 2000
				-- Note: solaredge ramping is very slow => set every minute
				l1=inverter1Power+cp+(inverter2Power-400)+export
				log(E_INFO, "HOYMILES: set Inverter1 Limit="..l1)
			else
				if (math.abs(inverter1Power-l1)<100) then
					-- inverter reached the trip
					Power['D1']=9	-- inverter1 ready for another setpoint
					PowerChanged=true
				end
			end
			-- Set hoymiles inverter power to have zero export
			newlimit=math.floor(inverter2Power+cp+export)
			log(E_INFO, "HOYMILES: price<=0 gridPower="..string.format("%4d", cp).."W => Inv1 Power="..inverter1Power.." Limit="..l1.." | Inv2 Power="..inverter2Power.." Limit="..newlimit)
		else
			-- set inverter limit to avoid exporting too much power to the grid (max 6000W in Italy, in case of single phase)
			-- if (exported power > HOYMILES_TARGET_POWER) reduce inverter power
			if (cp-HOYMILES_TARGET_POWER<0) then		-- HOYMILES_TARGET_POWER=-6000 => Try to limit export to 6000W (no more than 6000W)
				newlimit=Power['HL']+cp-HOYMILES_TARGET_POWER
				log(E_WARNING, "HOYMILES: Exported power too high ("..(0-cp).."W), reduce inverter power to "..newlimit.."W")
			end
			-- Try to export no more than PV_PowerMeter (PV on the roof)
			e1=getEnergyValue(otherdevices['PV_PowerMeter'])
			ei=getEnergyValue(otherdevices['PowerMeter Export'])
			m=timeNow.min%15
			if (m==0 and Power['Hm']~=timeNow.min) then
				-- every 15 minutes: store the current produced and exported energy
				ep1=e1-Power['H1']	-- Energy produced by inverter1 in the last 15 minutes slot
				epi=ei-Power['HI']	-- Energy feed to grid in the last 15 minutes slot
				if (epi>ep1) then
					log(E_WARNING,"HOYMILES: in last 15 minutes, Invert1Energy=".. (e1-Power['H1']) .." < ExportedEnergy=".. (ei-Power['HI']))
				else
					log(E_INFO,"HOYMILES: in last 15 minutes, Invert1Energy=".. (e1-Power['H1']) .." >= ExportedEnergy=".. (ei-Power['HI']))
				end
				Power['H1']=e1
				Power['HI']=ei
				Power['Hm']=timeNow.min
				PowerChanged=true -- used to force saving Power[] array
			end
			ep1=e1-Power['H1']	-- Energy produced by inverter1 in the last 15 minutes slot
			epi=ei-Power['HI']	-- Energy feed to grid in the last 15 minutes slot
			-- dp=inverter1Power+100+cp	-- inverter1Power=600, cp=-1000 => dp=-300 => must reduce inverter2Power by 300W
			msg=""
			if (epi>=ep1+5-m and epi>0) then
				-- exporting too much energy
				nl=math.floor(((inverter2Power+inverter1Power+cp-100-(epi-ep1+0.5)*60/(15-m))+Power['HL'])/2)
				if (nl<newlimit) then
					newlimit=nl
				end
				if (epi>ep1) then msg=' <' end
			end
			log(E_INFO, "HOYMILES: inv1Energy="..ep1..msg.." ExportEnergy=".. math.floor(epi) .." V="..hoymilesVoltage.." Limit="..newlimit.."W")
		end
		if (newlimit>HOYMILES_LIMIT_MAX) then
			newlimit=HOYMILES_LIMIT_MAX
		elseif (newlimit<0) then
			newlimit=0	-- 100 Watt: avoid turning off the inverter completely
		end
		local newlimitPerc=math.floor(newlimit*100/HOYMILES_LIMIT_MAX)
		
		--log(E_INFO, "HOYMILES new limit="..newlimit.." old limit="..Power['HL'])
		if (newlimit~=Power['HL'] or (timeNow.min==0 and timeNow.sec>45)) then
			-- log(E_DEBUG,"HOYMILES: Voltage="..hoymilesVoltage.."V => Newlimit "..Power['HL'].."->"..newlimit.."W "..newlimitPerc.."%")
			os.execute('/usr/bin/mosquitto_pub -u '..MQTT_OWNER..' -P '..MQTT_PASSWORD..' -t '..HOYMILES_ID..' -m '..newlimit)
			Power['HL']=newlimit
			PowerChanged=true
			commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[HOYMILES_LIMIT_PERC_DEV].."|0|".. newlimitPerc}
		end
		-- check inverter1 limit
		if (l1<100) then
			l1=100	-- minimum limit value for the inverter1
		elseif (l1>6000) then
			l1=6000
		end
		if (l1 ~= Power['L1']) then
			local l1p=math.floor(l1*100/6000)
			log(E_INFO, "HOYMILES: send inverter1 limit="..l1p.."%")
			fd=io.popen("mbpoll -q -mtcp -a1 -p1502 -0 -1 -r61441 -l10 192.168.3.229 "..l1p)    -- send limit value, in %
			ret=tonumber(fd:read("*a"))    -- temp * 0.1°C
			io.close(fd)
			Power['L1']=l1
			Power['D1']=0		-- minute since last inverter changes
			PowerChanged=true	-- used to force saving the Power[] array
		end
	end
end

-- check that main powermeter is really working...
if (PowerMeter~="" and otherdevices_lastupdate[PowerMeter]~=nil and timedifference(otherdevices_lastupdate[PowerMeter])>60) then
	-- power meter is not working !!!!! Use PowerMeterImport and PowerMeterExport as backup grid power meter
	if (PowerMeterImport~='' and PowerMeterExport~='' and (devicechanged[PowerMeterImport]~=nil or devicechanged[PowerMeterExport]~=nil)) then
		currentPower=getPowerValue(otherdevices[PowerMeterImport])-getPowerValue(otherdevices[PowerMeterExport]) -- use PowerMeterImport and PowerMeterExport to determine current grid power
		log(E_WARNING, "Main power meter is broken: get grid power from PowerMeterImport-PowerMeterExport")
	end
end


-- if currentPower~=10MW => currentPower was just updated => check power consumption, ....
if (currentPower>-20000 and currentPower<20000) then
	-- currentPower is good
	commandArray['Variable:GridPower']=tostring(currentPower)

	prodPower=0-currentPower
	--[[
	if (DOMBUSEVSE_GRIDPOWER~=nil) then	-- update the DomBusEVSE virtual device used to know the current power from electricity grid
		for k,name in DOMBUSEVSE_GRIDPOWER do
			commandArray[name]=tostring(currentPower)..';0'
		end
	end
	]]
	setAvgPower()


	-- update LED statuses (on Creasol DomBusTH modules, with red/green leds)
	-- red led when power usage >=0 (1=> <1000W, 2=> <2000W, ...)
	-- green led when power production >0 (1 if <1000W, 2 if <2000W, ...)
	--
	if (currentPower<0) then
		-- green leds
		l=math.floor(1-currentPower/1000)*10	-- 1=0..999W, 2=1000..1999W, ...
	else
		l=0	-- used power >0 => turn off green leds
	end
	for k,led in pairs(ledsGreen) do
		if (otherdevices_svalues[led]~=tostring(l)) then
			commandArray[led]="Set Level "..tostring(l)
		end
	end

	if (currentPower>0) then
		-- red leds
		l=(math.floor(currentPower/1000)+1)*10	-- 1=0..999W, 2=1000..1999, 3=2000..2999W, ...
	else
		l=0	-- used power >0 => turn off green leds
	end
	for k,led in pairs(ledsRed) do
		if (otherdevices_svalues[led]~=tostring(l)) then
			commandArray[led]="Set Level "..tostring(l)
		end
	end

	toleratedUsagePower=0
	if (timeNow.month<=3 or timeNow.month>=10) then -- winter
		toleratedUsagePower=300	-- from October to March, activate electric heaters even if the usage power will be >0W but <300W
	end

	if (DOMBUSEVSE_GRIDPOWER~=nil) then	-- update the DomBusEVSE virtual device used to know the current power from electricity grid
		for k,name in pairs(DOMBUSEVSE_GRIDPOWER) do
			commandArray[name]=tostring(currentPower)..';0'
			log(E_DEBUG,"Update "..name.."="..currentPower)
		end
	end
	
	if (currentPower<PowerThreshold[1]) then
		log(E_DEBUG,"currentPower="..currentPower.." < PowerThreshold[1]="..PowerThreshold[1])
		-- low power consumption => reset threshold timers, used to count from how many seconds power usage is above thresholds
		if (incMinute==1) then --Power['ev'] used to force EV management now
			-- Every minute
			------------------------------------ check DEVauxlist to enable/disable aux devices (when we have/haven't got enough power from photovoltaic -----------------------------
			Power['u']=0		-- compute power delivered to aux loads
			if (DEVauxlist~=nil) then
				log(E_DEBUG,"Parsing DEVauxlist...")
				if (HPmode=='Winter') then
					devLevel=2	-- min HP['Level' to start this device if sufficient power from photovoltaic
				else
					devLevel=3	-- min HP['Level' to start this device if sufficient power from photovoltaic
				end
				for n,v in pairs(DEVauxlist) do
					-- load conditions to turn ON/OFF this aux device
					if (v[5]~='') then
						con=load("return "..v[5])	-- expression that needs to turn off device
					else
						con=load("return TRUE")
					end
					if (v[6]~='') then
						coff=load("return "..v[6])	-- expression that needs to turn off device
					else
						coff=load("return FALSE")
					end
					-- check timeout for this device (useful for dehumidifiers)
					s=""
					if (v[7]~=nil and PowerAux['s'..n]~=nil and PowerAux['s'..n]>0) then
						s=" ["..PowerAux['s'..n].."/"..v[7].."m]"
					end
					log(E_INFO,"Aux "..otherdevices[ v[1] ]..": "..v[1] .." (" .. v[4].."/"..prodPower.."W)"..s)

					auxTimeout=0
					auxMaxTimeout=1440
					if (v[7]~=nil and v[7]>0) then
						-- max timeout defined => check that device has not reached the working time = max timeout in minutes
						auxMaxTimeout=v[7]
						checkVar('Timeout_'..v[1],0,0) -- check that uservariable at1 exists, else create it with type 0 (integer) and value 0
						auxTimeout=uservariables['Timeout_'..v[1]]
						if (otherdevices[ v[1] ]~='Off') then
							-- device is actually ON => increment timeout
							auxTimeout=auxTimeout+1
							commandArray['Variable:Timeout_'..v[1]]=tostring(auxTimeout)
						end
					end
					-- change state only if previous heatpump level match the current one (during transitions from a power level to another, power consumption changes)
					if (otherdevices[ v[1] ]~='Off') then
						-- device was ON
						log(E_DEBUG,'Device was On: '..v[1]..'='..otherdevices[ v[1] ])
						if (auxTimeout>=auxMaxTimeout) then
							-- timeout reached -> send notification and stop device
							deviceOff(v[1],PowerAux,'a'..n)
							prodPower=prodPower+v[4]    -- update prodPower, adding the power consumed by this device that now we're going to switch off
							log(TELEGRAM_LEVEL,"Timeout reached for "..v[1]..": device was stopped")
						elseif (peakPower() or prodPower<-100 or (HP['Level']<v[devLevel] and HPmode~='Off') or coff()) then
							-- no power from photovoltaic, or heat pump is below the minimum level defined in config, or condition is not satisified, or OFF condition returns TRUE
							-- stop device because conditions are not satisfied
							deviceOff(v[1],PowerAux,'a'..n)
							prodPower=prodPower+v[4]    -- update prodPower, adding the power consumed by this device that now we're going to switch off
						else 
							-- device On, and can remain On
							Power['u']=Power['u']+v[4]
						end
					else
						-- device is OFF
						log(E_DEBUG,'Device was Off: '..v[1]..'='..otherdevices[ v[1] ])
						if (peakPower()==false and auxTimeout<auxMaxTimeout and prodPower>=(v[4]+100) and (HP['Level']>=v[devLevel] or HPmode=='Off') and con()) then
							deviceOn(v[1],PowerAux,'a'..n)
							prodPower=prodPower-v[4]  -- update prodPower
							Power['u']=Power['u']+v[4]
						end
					end
				end
			end -- DEVauxlist exists
		end -- every 1 minute

		--	currentPower=-1200
		limit=toleratedUsagePower+100
		if (currentPower<limit) then
			-- usage power < than first threshold
			Power['a']=0
			if (HPmode=='Winter') then
				devCond=5 
				devLevel=2
			else 
				devCond=8 
				devLevel=3
			end
			-- exported power  => activate fast loads?
			for n,v in pairs(DEVauxfastlist) do
				if (otherdevices[ v[devCond] ]~=nil) then
					log(E_DEBUG,"Auxfast "..otherdevices[ v[1] ]..": "..v[1] .." (" .. v[4].."/"..prodPower.."W)")
					if (tonumber(otherdevices[ v[devCond] ])<v[devCond+2]) then cond=1 else cond=0 end
					log(E_DEBUG,v[1] .. ": is " .. tonumber(otherdevices[ v[devCond] ]) .." < ".. v[devCond+2] .."? " .. cond)
					-- change state only if previous heatpump level match the current one (during transitions from a power level to another, power consumption changes)
					if (otherdevices[ v[1] ]~='Off') then
						-- device was ON
						log(E_DEBUG,'Device is not Off: '..v[1]..'='..otherdevices[ v[1] ])
						if (v[13]~='') then
							coff=load("return "..v[13])	-- expression that needs to turn off device
						else
							coff=load("return FALSE")
						end
						if (peakPower() or prodPower<-200 or (EVSEON_DEV~='' and otherdevices[EVSEON_DEV]=='On') or (HP['Level']<v[devLevel] and HPmode~='Off') or cond==v[devCond+1] or coff()) then
							-- no power from photovoltaic, or heat pump is below the minimum level defined in config, or condition is not satisified, or OFF condition returns TRUE or EVSE is on (vehicle in charging)
							-- stop device because conditions are not satisfied, or for more than v[11] minutes (timeout)
							deviceOff(v[1],PowerAux,'f'..n)
							prodPower=prodPower+v[4]    -- update prodPower, adding the power consumed by this device that now we're going to switch off
							Power['u']=Power['u']-v[4]
						-- else device On, and can remain On
						end
					else
						-- device is OFF
						log(E_DEBUG,prodPower..">="..v[4]+100 .." and "..cond.."~="..v[devCond+1].." and "..HP['Level']..">="..v[devLevel])
						if (v[12]~='') then
							con=load("return "..v[12])	-- expression that needs to turn on device
						else
							con=load("return 1")
						end
						log(E_DEBUG,prodPower..">=".. (v[4]) .." and "..cond.."~="..v[devCond+1] .." and (".. HP['Level'] ..">=".. v[devLevel] .." or "..HPmode.."=='Off') and "..tostring(con()))
						if (peakPower()==false and prodPower>=(v[4]) and cond~=v[devCond+1] and (HP['Level']>=v[devLevel] or HPmode=='Off') and con()) then
							deviceOn(v[1],PowerAux,'f'..n)
							prodPower=prodPower-v[4]  -- update prodPower
							Power['u']=Power['u']+v[4]
						end
					end
				end
			end
			powerMeterAlert(0)
		end 
		powerMeterAlert(0)
	end


	if (currentPower>PowerThreshold[1]) then
		Power['th1']=Power['th1']+POWERMETER_INTERVAL
		if (currentPower<PowerThreshold[2]) then
			-- power consumption a little bit more than available power => long intervention time, before disconnecting
			if (Power['th2']>=POWERMETER_INTERVAL) then Power['th2']=Power['th2']-POWERMETER_INTERVAL else Power['th2']=0 end
		else -- very high power consumption : short time to disconnect some loads
			Power['th2']=Power['th2']+POWERMETER_INTERVAL
			log(E_WARNING, "Power="..currentPower.." > "..PowerThreshold[2].." for "..Power['th2'].."/"..PowerThreshold[4].."s")
			if (Power['th2']>=PowerThreshold[4]) then
				-- can I disconnect anything?
				-- very high power consumption: short intervention time before power outage
				time=os.time()-Power['d']	-- disconnect devices every 10s
				if (time>=10 and powerDisconnect()==0) then
					-- nothing to disconnect
					powerMeterAlert(1)  -- send alert
					log(E_CRITICAL,"Potenza assorbita="..currentPower.."W: Pericolo di disconnessione. Spegnere elettrodomestici!") -- send alert by Telegram
				else
					-- one device has been disconnected
					powerMeterAlert(0)
					Power['d']=os.time()
				end
			end
		end
		log(E_WARNING, "Power="..currentPower.." > "..PowerThreshold[1].." for "..Power['th1'].."/"..PowerThreshold[3].."s")
		if (Power['th1']>=PowerThreshold[3]) then
			-- can I disconnect anything?
			time=os.time()-Power['d']	-- disconnect devices every 60s
			if (time>=60 and powerDisconnect()==0) then
				-- nothing to disconnect
				powerMeterAlert(1)	-- send alert
				log(E_CRITICAL,"Potenza assorbita="..currentPower.."W: Pericolo di disconnessione. Spegnere elettrodomestici!") -- send alert by Telegram
			else
				powerMeterAlert(0)
				Power['d']=os.time()
			end
		end
	else	
		-- currentPower has a right value
		if (Power['th1']>=POWERMETER_INTERVAL) then Power['th1']=Power['th1']-POWERMETER_INTERVAL else Power['th1']=0 end
		if (Power['th2']>=POWERMETER_INTERVAL) then Power['th2']=Power['th2']-POWERMETER_INTERVAL else Power['th2']=0 end
	end

	-- DEBUG: TRACKER WIND SENSOR
	--commandArray['dombusLab - (ffd0.d) Wind']='3'

	if (HOYMILES_ID~='' and (os.time()-Power['Ht'])>=10) then
		-- more than 10s since last time the hoymiles limit was set
		Power['Ht']=os.time()
		-- Now check that inverter is producing
		if (otherdevices[HOYMILES_PRODUCING_DEV]=='Off' and inverter2Power<100 and timeofday['Daytime'] and Power['HS']>=3) then
			-- inverter not producing
			local hoymilesVoltage=tonumber(otherdevices[HOYMILES_VOLTAGE_DEV])
			log(E_INFO,"HOYMILES: Inverter not producing, Power[HS]="..Power['HS'].." and hoymilesVoltage="..hoymilesVoltage.."V")
			if (hoymilesVoltage>=HOYMILES_LIMIT_VOLTAGE) then
				-- inverter not producing due to overvoltage => set a new limit and restart it
				newlimit=400	-- start inverter from 100W only to prevent overvoltage
				os.execute('/usr/bin/mosquitto_pub -u ' .. MQTT_OWNER .. ' -P ' .. MQTT_PASSWORD .. ' -t ' .. HOYMILES_ID .. ' -m ' .. newlimit)
				Power['HL']=newlimit
				log(E_WARNING,"HOYMILES: inverter not producing => restart now")
			end
			commandArray[HOYMILES_RESTART_DEV]='On'
			Power['HS']=0
		else
			if (Power['HS']<99) then 
				Power['HS']=Power['HS']+1
			end
		end
		PowerChanged=true
	end

	PowerChanged=true	-- force saving Power[] array in zPower variable
	commandArray['Variable:zEVSE']=json.encode(EVSE)
	commandArray['Variable:avgPower']=tostring(avgPower)
	log(E_DEBUG,"currentPower="..currentPower.." avgPower="..avgPower.." Used_by_heaters="..Power['u'])
	if (PowerAux~=nil) then
		log(E_DEBUG,"PowerAux="..json.encode(PowerAux))
	end
end -- if currentPower is set
if (PowerChanged and commandArray['Variable:zPower']==nil) then
	commandArray['Variable:zPower']=json.encode(Power)
end

