-- scripts/lua/script_device_power.lua
-- Written by Creasol, https://creasol.it linux@creasol.it
-- Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions
--   1. Send notification when consumed power is above a threshold (to avoid power outage)
--   2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid
--   3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored
--   4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
--      green LED flashes 1..M times if photovoltaic produces up to 1..M kWatt
--

commandArray={}

dofile "/home/pi/domoticz/scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "/home/pi/domoticz/scripts/lua/globalfunctions.lua"  -- some functions common to all scripts
dofile "/home/pi/domoticz/scripts/lua/config_power.lua"		-- configuration file

timenow = os.date("*t")

function PowerInit()
	if (Power==nil) then Power={} end
	if (Power['th1Time']==nil) then Power['th1Time']=0 end
	if (Power['th2Time']==nil) then Power['th2Time']=0 end
	if (Power['above']==nil) then Power['above']=0 end
	if (Power['usage']==nil) then Power['usage']=0 end
	if (Power['disc']==nil) then Power['disc']=0 end
end	

function getPowerValue(devValue)
	-- extract the power value from string "POWER;ENERGY...."
	for str in devValue:gmatch("[^;]+") do
		return tonumber(str)
	end
end

function setAvgPower() -- store in the user variable avgPower the building power usage
	if (uservariables['avgPower']==nil) then
		-- create a Domoticz variable, coded in json, within all variables used in this module
		avgPower=currentPower
		url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=avgPower&vtype=0&vvalue='..tostring(currentPower)
		os.execute('curl "'..url..'"')
		-- initialize variable
	else
		avgPower=uservariables['avgPower']
	end
	commandArray['Variable:avgPower']=tostring(math.floor((avgPower*14 + currentPower - Power['usage'] )/15)) -- average on 15*2s=30s
end


function getPower() -- extract the values coded in JSON format from domoticz zPower variable, into Power dictionary
	if (Power==nil) then
		-- check variable zPower
		json=require("dkjson")
		if (uservariables['zPower']==nil) then
			-- create a Domoticz variable, coded in json, within all variables used in this module
			PowerInit()	-- initialize Power dictionary
			url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=zPower&vtype=2&vvalue='
			os.execute('curl "'..url..'"')
			-- initialize variable
		else
			Power=json.decode(uservariables['zPower'])
		end
		PowerInit()
	end
end

function powerMeterAlert(on)
	for k,pma in pairs(PowerMeterAlerts) do
		if (on~=0) then
			if (otherdevices[ pma[1] ]~=pma[3]) then
				log(E_INFO,"Activate sould alert "..pma[1])
				commandArray[ pma[1] ]=pma[3]
			end
		else
			-- OFF command
			if (otherdevices[ pma[1] ]~=pma[2]) then
				log(E_INFO,"Disable sould alert "..pma[1])
				commandArray[ pma[1] ]=pma[2]
			end
		end
	end
end

function scanHeaters()
	devOn=''	-- used to find a ON-device that can be turned off if forced==1
	devPower=0
	Power['usage']=0	--recompute currently used power
	-- extract the name of the last device in Heaters that is ON
	for k,loadRow in pairs(Heaters) do
		if (otherdevices[loadRow[1]]=='On') then
			devAuto=0
			devKey='H'..k
			if (Power[devKey]~=nil and Power[devKey]=='auto') then
				devAuto=1
				devOn=loadRow[1]
				devPower=loadRow[2]
				log(E_INFO,"devOn="..devOn.." devPower="..devPower.." devAuto="..devAuto)
			else
				-- current device was enabled manually, not enabled from script_device_power.lua
				if (devOn=='') then
					devOn=loadRow[1]
					devPower=loadRow[2]
				end
			end
			Power['usage']=Power['usage']+devPower
		end
	end
end

function powerDisconnect(forced,msg) 
	-- disconnect the last device in Heater table, that is ON. Return 0 in case that no devices have been disconnected
	scanHeaters()
	if (devOn=='') then
		if (forced~=0) then
			-- TODO: try to disable overloadDisconnect devices
			for k,loadRow in pairs(overloadDisconnect) do
				if (otherdevices[ loadRow[1] ]=='On') then
					log(E_WARNING, msg..': disconnect '..loadRow[1])
					commandArray[ loadRow[1] ]=loadRow[2]
					Power['disc']=os.time()
					return 1
				end
			end
		end
		return 0
	elseif (devAuto~=0 or forced~=0) then
		log(E_WARNING, msg..': disconnect '..devOn..' to save '..devPower..'W')
		commandArray[devOn]='Off'
		Power[devKey]='off/man'
		Power['usage']=Power['usage']-devPower
		if (Power['usage']<0) then 
			Power['usage']=0
		end
		Power['disc']=os.time()
		return 1
	end
end

currentPower=10000000 -- dummy value (10MW)
for devName,devValue in pairs(devicechanged) do
	if (PowerMeter~='') then
		-- use PowerMeter device, measuring instant power (goes negative in case of exporting)
		if (devName==PowerMeter) then
			currentPower=getPowerValue(devValue)
		end
	else
		-- use PowerMeterImport and PowerMeterExport (if available)
		if ((PowerMeterImport~='' and devName==PowerMeterImport) or (PowerMeterExport~='' and devName==PowerMeterExport)) then
			currentPower=getPowerValue(otherdevices[PowerMeterImport])
			log(E_DEBUG,"PowerMeterImport exists => currentPower="..currentPower)
			if (PowerMeterExport~='') then 
				currentPower=currentPower-getPowerValue(otherdevices[PowerMeterExport]) 				
				log(E_DEBUG,"PowerMeterExport exists => currentPower="..currentPower)
			end
		end
	end
	-- if blackout, turn on white leds in the building!
	if (devName==blackoutDevice) then
		print("========== BLACKOUT: "..devName.." is "..devValue.." ==========")
		getPower()
		if (devValue=='Off') then -- blackout
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
		end
	end
end

-- if currentPower~=10MW => currentPower was just updated => check power consumption, ....
if (currentPower>-20000 and currentPower<20000) then
	-- currentPower is good
	getPower() -- get Power variable from zPower domoticz variable (coded in JSON format)

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
	if (timenow.month<=3 or timenow.month>=10) then -- winter
		toleratedUsagePower=300	-- from October to March, activate electric heaters even if the usage power will be >0W but <300W
	end

	if (currentPower<PowerThreshold[1]) then
		log(E_DEBUG,"currentPower="..currentPower.." < PowerThreshold[1]="..PowerThreshold[1])
		-- low power consumption => reset threshold timers, used to count from how many seconds power usage is above thresholds
		Power['th1Time']=0
		Power['th2Time']=0
		--	currentPower=-1200
		limit=toleratedUsagePower+100
		if (currentPower>limit) then
			-- disconnect only if power remains high for more than 5*2s
			if (Power['above']>=5) then 
				powerDisconnect(0,"currentPower>"..limit.." for more than 10 seconds") 
				Power['above']=0
			else
				Power['above']=Power['above']+1
				log(E_INFO, "currentPower > toleratedUsagePower+100 for "..(Power['above']*2).."s")
			end
		else
			-- currentPower < 300W in Winter, and 0W in Summer
			Power['above']=0
			
--					if (timenow.sec>=53 and currentPower>-600) then
--						-- if HeatPump is on, and HP['level']<LEVEL_MAX (heatpump fullpower == Off), disable electric heaters to permit script_time_heatpump.lua to increase heatpump power level
--						if (otherdevices['HeatPump_Fancoil']=='Off'  and Power['usage']-currentPower>800) then
--							powerDisconnect(0)
--						end
--					elseif (timenow.sec<=40 and currentPower<0) then
			if (timenow.sec<=40 and currentPower<0) then
				-- renewable sources are producing more than current consumption: activate extra loads
				-- log(E_INFO, "sec="..timenow.sec.." currentPower="..currentPower.." => check electric heaters....")
				availablePower=0-currentPower
				if (uservariables['HeatPumpWinter']==1) then
					-- check electric heaters
					for k,loadRow in pairs(Heaters) do
						-- log(E_INFO, "Temperature "..loadRow[4].."="..otherdevices[loadRow[4]].." < "..loadRow[5].."??")
						if (otherdevices[loadRow[1]]=='Off' and (loadRow[2]-toleratedUsagePower)<availablePower and tonumber(otherdevices[loadRow[4]])<loadRow[5]) then
							-- enable this new load
							log(E_INFO, 'Enable load '..loadRow[1]..' that needs '..loadRow[2]..'W')
							commandArray[loadRow[1]]='On'
							Power['H'..k]='auto'
							scanHeaters()
							Power['usage']=Power['usage']+loadRow[2]
							break
						end
					end --for
				end	
				--TODO: if a lower priority device is enabled, maybe it's possible to disable it and enable a higher priority device that needs more power tha lower priority device
			end
			powerMeterAlert(0)
		end 
		powerMeterAlert(0)
	elseif (currentPower<PowerThreshold[2]) then
		-- power consumption a little bit more than available power => long intervention time, before disconnecting
		time=(os.time()-Power['th1Time'])
		log(E_WARNING, "Power>"..PowerThreshold[1].." for "..time.."s")
		Power['th2Time']=0
		if (Power['th1Time']==0) then
			Power['th1Time']=os.time()
		elseif (time>PowerThreshold[3]) then
			-- can I disconnect anything?
			time=os.time()-Power['disc']	-- disconnect devices every 50s
			if (powerDisconnect(1,"currentPower>"..PowerThreshold[1].." for more than "..PowerThreshold[3].."s")==0) then
				-- nothing to disconnect
				powerMeterAlert(1)	-- send alert
			else
				powerMeterAlert(0)
			end
		end
	else -- very high power consumption : short time to disconnect some loads
		time=(os.time()-Power['th2Time'])
		log(E_WARNING, "Power>"..PowerThreshold[2].." for "..time.."s")
		if (Power['th2Time']==0) then
			Power['th2Time']=os.time()
		elseif (time>PowerThreshold[4]) then
			-- can I disconnect anything?
			-- very high power consumption: short intervention time before power outage
			time=os.time()-Power['disc']	-- disconnect devices every 50s
			if (powerDisconnect(1,"currentPower>"..PowerThreshold[2].." for more than "..PowerThreshold[4].."s")==0) then
				-- nothing to disconnect
				powerMeterAlert(1)  -- send alert
				if ((time%20)==0) then log(E_CRITICAL,"Too much power consumption, and nothing to disconnect") end -- send alert by Telegram
			else
				powerMeterAlert(0)
			end

		end
	end	-- currentPower has a right value
	-- save variables in Domoticz, in a json variable Power
	-- log(E_INFO,"commandArray['Variable:zPower']="..json.encode(Power))
	commandArray['Variable:zPower']=json.encode(Power)
	setAvgPower()
	log(E_INFO,"currentPower="..currentPower.." avgPower="..avgPower.." Used_by_heaters="..Power['usage'])
end


return commandArray
