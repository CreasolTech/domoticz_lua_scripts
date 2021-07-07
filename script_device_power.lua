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
	if (Power['min']==nil) then Power['min']=0 end	-- current time minute: used to check something only 1 time per minute
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
		avgPower=tonumber(uservariables['avgPower'])
	end
	avgPower=(math.floor((avgPower*14 + currentPower - Power['usage'] )/15)) -- average on 15*2s=30s
	commandArray['Variable:avgPower']=tostring(avgPower)
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
	if (PowerAux==nil) then
		-- check variable zPower
		json=require("dkjson")
		if (uservariables['zPowerAux']==nil) then
			-- create a Domoticz variable, coded in json, within all variables used in this module
			PowerAux={}	-- initialize PowerAux dictionary
			url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=zPowerAux&vtype=2&vvalue='
			os.execute('curl "'..url..'"')
			-- initialize variable
		else
			PowerAux=json.decode(uservariables['zPowerAux'])
		end
		PowerInit()
		if (uservariables['zHeatPump']~=nil) then
			HP=json.decode(uservariables['zHeatPump'])  -- get HP[] with info from HeatPump
		else
			HP['Level']=1  -- HP dictionary does not exist: set HP['Level'] to the default value (1 to simulate that heat pump is ON)
		end
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

function scanDEVauxlist()
	devOn=''	-- used to find a ON-device that can be turned off if forced==1
	devPower=0
	Power['usage']=0	--recompute currently used power
	-- extract the name of the last device in Heaters that is ON
	for k,loadRow in pairs(DEVauxlist) do
		if (otherdevices[loadRow[1]]=='On') then
			devAuto=0
			devKey='a'..k
			if (PowerAux[devKey]~=nil and PowerAux[devKey]=='auto') then
				devAuto=1
				devOn=loadRow[1]
				devPower=loadRow[4]
				log(E_INFO,"devOn="..devOn.." devPower="..devPower.." devAuto="..devAuto)
			else
				-- current device was enabled manually, not enabled from script_device_power.lua
				if (devOn=='') then
					devOn=loadRow[1]
					devPower=loadRow[4]
				end
			end
			Power['usage']=Power['usage']+devPower
		end
	end
end

function powerDisconnect(forced,msg) 
	-- disconnect the last device in Heater table, that is ON. Return 0 in case that no devices have been disconnected
	scanDEVauxlist()
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
		PowerAux[devKey]='off/man'
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
		log(E_WARNING,"========== BLACKOUT: "..devName.." is "..devValue.." ==========")
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
	prodPower=0-currentPower
	getPower() -- get Power variable from zPower domoticz variable (coded in JSON format)
	setAvgPower()
	incMinute=0	-- zero if script was executed not at the start of the current minute
	if (Power['min']~=timenow.min) then
		-- minute was incremented
		Power['min']=timenow.min
		incMinute=1 -- minute incremented => set this variable to exec some checking and functions
	end


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
		-- check electric vehicles
		if (incMinute==1) then 
			for k,evRow in pairs(eVehicles) do
				-- evRow[1]=ON/OFF device
				-- evRow[2]=charging power
				-- evRow[3]=current battery level
				-- evRow[4]=min battery level (charge to that level using imported energy!)
				-- evRow[5]=max battery level (stop when battery reached that level)
				if (otherdevices[ evRow[1] ]==nil or otherdevices[ evRow[4] ]==nil or otherdevices[ evRow[5] ]==nil) then
					log(E_WARNING,"EV: invalid device names in eVehicles structure, row number "..k)
				else
					if (Power['ev'..k]==nil) then
						Power['ev'..k]=0  --initialize counter, incremented every minute when there is not enough power from renewables to charge the vehicle
					end
					evPower=evRow[2]
					batteryMin=tonumber(otherdevices[ evRow[4] ])
					batteryMax=tonumber(otherdevices[ evRow[5] ])
					if (evRow[3]~='' and otherdevices[ evRow[3] ]~=nil) then
						-- battery state of charge is a device
						batteryLevel=tonumber(otherdevices[ evRow[3] ])	-- battery level device exists
					elseif (uservariables[ evRow[3] ]~=nil) then
						-- battery state of charge is a variable
						batteryLevel=tonumber(uservariables[ evRow[3] ])
					else
						-- battery state of charge not available
						batteryLevel=50	-- battery level device does not exist => set to 50%
					end
					if (otherdevices[ evRow[1] ]=='Off') then
						-- not charging
						if (avgPower+evPower<PowerThreshold[1] and batteryLevel<batteryMax) then
							-- it's possible to charge without exceeding electricity meter threshold, and current battery level < battery max
							toleratedUsagePowerEV=evPower/4*(1-(batteryLevel-batteryMin)/(batteryMax-batteryMin))
							log(E_DEBUG,"EV: not charging, avgPower="..avgPower.." toleratedUsagePowerEV="..toleratedUsagePowerEV)
							if (batteryLevel<batteryMin or (avgPower+evPower)<toleratedUsagePowerEV) then
								-- if battery level > min level => charge only if power is available from renewable sources
								log(E_INFO,"EV: start charging - batteryLevel="..batteryLevel.."<"..batteryMin.." or ("..avgPower.."+"..evPower.."<0)")
								deviceOn(evRow[1],Power,'de'..k)
								Power['ev'..k]=0	-- counter
							end
						end
					else
						-- charging
						if (batteryLevel>=batteryMin) then
							if (batteryLevel>=batteryMax) then
								-- reached the max battery level
								log(E_INFO,"EV: stop charging: reach the max battery level")
								deviceOff(evRow[1],Power,'de'..k)
							else
								-- still charging: check available power
								toleratedUsagePowerEV=evPower/2*(1-(batteryLevel-batteryMin)/(batteryMax-batteryMin))
								log(E_DEBUG,"EV: charging with batteryLevel>batteryMin, avgPower="..avgPower.." toleratedUsagePowerEV="..toleratedUsagePowerEV)
								if (avgPower>toleratedUsagePowerEV) then
									-- too much power consumption -> increment counter and stop when counter is high
									Power['ev'..k]=Power['ev'..k]+1	
									log(E_INFO,"EV: no enough energy from renewables since "..Power['ev'..k].." minutes")
									if (Power['ev'..k]>5) then
										log(E_INFO,"EV: stop charging")
										deviceOff(evRow[1],Power,'de'..k)
									end
								else
									log(E_DEBUG,"EV: enough energy to charge! ")
									Power['ev'..k]=0	-- enough energy from renewable => reset counter
								end
							end
						else
							-- batteryLevel < battery min level
							log(E_DEBUG,"EV: battery level lower than min value "..batteryMin)
						end
					end
				end
			end


			------------------------------------ check DEVauxlist to enable/disable aux devices (when we have/haven't got enough power from photovoltaic -----------------------------
			if (DEVauxlist~=nil) then
				log(E_DEBUG,"Parsing DEVauxlist...")
				if (uservariables['HeatPumpWinter']=="1") then 
					devCond=5 
					devLevel=2
				else 
					devCond=8 
					devLevel=3
				end
				for n,v in pairs(DEVauxlist) do
					if (otherdevices[ v[devCond] ]~=nil) then
						-- check timeout for this device (useful for dehumidifiers)
						s=""
						if (v[12]~=nil and PowerAux['s'..n]~=nil and PowerAux['s'..n]>0) then
							s=" ["..PowerAux['s'..n].."/"..v[12].."m]"
						end

						log(E_INFO,"Aux "..otherdevices[ v[1] ]..": "..v[1] .." (" .. v[4].."/"..prodPower.."W)"..s)
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
									deviceOff(v[1],PowerAux,'a'..n)
									log(TELEGRAM_LEVEL,"Timeout reached for "..v[1]..": device was stopped")
								end
							end
						end
						-- change state only if previous heatpump level match the current one (during transitions from a power level to another, power consumption changes)
						if (otherdevices[ v[1] ]~='Off') then
							-- device is ON
							log(E_DEBUG,'Device is not Off: '..v[1]..'='..otherdevices[ v[1] ])
							prodPower=prodPower-v[4]
							log(E_DEBUG,prodPower.."<-100 or "..
							HP['Level'].."<"..v[devLevel].." or "..cond.."=="..v[devCond+1] )
							if (prodPower<-100 or HP['Level']<v[devLevel] or cond==v[devCond+1] ) then
								if (v[12]~=nil) then
									if (PowerAux['s'..n]==nil) then PowerAux['s'..n]=0 end
									PowerAux['s'..n]=PowerAux['s'..n]+1
									if (PowerAux['s'..n]>=v[12]) then
										-- stop device because conditions are not satisfied for more than v[12] minutes
										deviceOff(v[1],PowerAux,'a'..n)
										prodPower=prodPower+v[4]    -- update prodPower, adding the power consumed by this device that now we're going to switch off
										prodPower=prodPower+v[4]
										PowerAux['s'..n]=0
									end
								else
									deviceOff(v[1],PowerAux,'a'..n)
									prodPower=prodPower+v[4]    -- update prodPower, adding the power consumed by this device that now we're going to switch off
									prodPower=prodPower+v[4]
								end
							else
								-- device On, and can remain On
								if (v[12]~=nil) then
									PowerAux['s'..n]=0
								end
							end
						else
							-- device is OFF
							-- print(prodPower.." "..v[4])
							log(E_DEBUG,auxTimeout.."<"..auxMaxTimeout.." and "..prodPower..">="..v[4]+100 .."and "..cond.."~="..v[devCond+1].." and "..HP['Level']..">="..v[devLevel])
							if (auxTimeout<auxMaxTimeout and prodPower>=(v[4]+100) and cond~=v[devCond+1] and HP['Level']>=v[devLevel]) then
								deviceOn(v[1],PowerAux,'a'..n)
								prodPower=prodPower-v[4]    -- update prodPower
								prodPower=prodPower-v[4]  -- update prodPower
							end
						end
					end
				end
			end -- DEVauxlist exists
		end -- every 1 minute

		--	currentPower=-1200
		limit=toleratedUsagePower+100
		if (currentPower>limit) then
			-- disconnect only if power remains high for more than 5*2s
			if (Power['above']>=5) then 
				powerDisconnect(0,"currentPower>"..limit.." for more than 10 seconds") 
				Power['above']=0
			else
				Power['above']=Power['above']+1
				log(E_DEBUG, "currentPower > toleratedUsagePower+100 for "..(Power['above']*2).."s")
			end
		else
			-- usage power < than first threshold
			Power['above']=0
			if (timenow.sec<=40 and currentPower<0) then
				-- exported power  => activate any load?
				if (timenow.month>=10 or timenow.month<=4) then
					-- winter: check electric heaters
					for k,loadRow in pairs(Heaters) do
						-- log(E_INFO, "Temperature "..loadRow[4].."="..otherdevices[loadRow[4]].." < "..loadRow[5].."??")
						if (otherdevices[loadRow[1]]=='Off' and (loadRow[2]-toleratedUsagePower)<prodPower and tonumber(otherdevices[loadRow[4]])<loadRow[5]) then
							-- enable this new load
							log(E_INFO, 'Enable load '..loadRow[1]..' that needs '..loadRow[2]..'W')
							commandArray[loadRow[1]]='On'
							Power['H'..k]='auto'
							scanDEVauxlist()
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
	commandArray['Variable:zPowerAux']=json.encode(PowerAux)
	log(E_DEBUG,"currentPower="..currentPower.." avgPower="..avgPower.." Used_by_heaters="..Power['usage'])
end


return commandArray
