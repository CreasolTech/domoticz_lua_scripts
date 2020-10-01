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
timenow = os.date("*t")

--[[
-- don't run this script when sun is not producing
if (timenow.hour<=(timeofday['SunriseInMinutes']/60) or timenow.hour>(timeofday['SunsetInMinutes']/60)) then
	-- don't need to switch off electric heaters after SunSet, because already photovoltaic stops producing before sunset so all heaters have been automatically disabled
	do return commandArray end
end
]]

--DEBUG=1
DEBUG=0
DOMOTICZ_URL="http://127.0.0.1:8080"    -- Domoticz URL (used to create variables using JSON URL
PowerMeter={'PowerMeter'}
ledsGreen={'Led_Cucina_Green'}	-- green LEDs that show power production
ledsRed={'Led_Cucina_Red'}		-- red LEDs that show power usage
ledsWhite={'Light_Night_Led','Led_Camera_White','Led_Camera_Ospiti_White','Led_Camera_Ospiti_WhiteLow'}	-- White LEDs that will be activated in case of blackout. List of devices configured as On/Off switches
ledsWhiteSelector={'Led_Cucina_White'}	-- White LEDs that will be activated in case of blackout. List of devices configured as Selector switches
blackoutDevice='Supply_HeatPump'	-- device used to monitor the 230V voltage. Off in case of power outage (blackout)

if (DEBUG>1) then
	PowerThreshold={ --DEBUG values
		1000,  	-- available power (Italy: power+10%)
		1300,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		80,		-- send alert after 4800s (80minutes)
		10		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
	}
else
	PowerThreshold={
		5400,  	-- available power (Italy: power+10%)
		6300,	-- threshold (Italy: power+27%), power over available_power and lower than this threshold is available for max 90 minutes
		4800,	-- send alert after 4800s (80minutes)
		60		-- above threshold, send notification in 60 seconds (or the energy meter will disconnect in 120s
	}
end

PowerMeterAlerts={
	{'PowerMeterBuzzer','Off','On'},
}

-- devices that can be disconnected in case of overloading, specified in the right priority (the first device is the first to be disabled in case of overload)
overloadDisconnect={ -- syntax: device name, command to disable, command to enable
	{'HeatPump_Fancoil','Off','On'},	-- heat pump, high temperature
	{'HeatPump_FullPower','Off','On'},	-- heat pump, full power
	{'HeatPump','Off','On'},			-- heat pump (general)
	{'Irrigazione','Off','On'},			-- garden watering pump
}

Heaters={	-- from the highest priority to the lowest priority
	-- device name , power , 1 if should be enabled automatically when renewable sources produce more than secified power or 0 if this is just used to disconnect load preventing power outage, temperature device, max temperature
	{'Pranzo_Stufetta',950,1,'Temp_Cucina',22},			-- 1000W heater connected to DOMESP1
	{'Bagno_Scaldasalviette',450,1,'Temp_Bagno',22},	-- 450W heater connected to DOMBUS1
}




function log(text)
	if (DEBUG>0) then
		print('Power: '..text)
	end
end

function PowerInit()
	if (Power==nil) then Power={} end
	if (Power['th1Time']==nil) then Power['th1Time']=0 end
	if (Power['th2Time']==nil) then Power['th2Time']=0 end
	if (Power['above']==nil) then Power['above']=0 end
	if (Power['usage']==nil) then Power['usage']=0 end
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
		if (on) then
			log("Activate sould alert "..pma[1])
			commandArray[pma[1]]=pma[3]
		else
			commandArray[pma[1]]=pma[2]
		end
	end
end

function scanHeaters()
	devOn=''	-- used to store a ON device that can be turned off if forced==1
	devPower=0
	Power['usage']=0	--recompute currently used power
	-- extract the name of the last device in Heaters that is ON
	for k,loadRow in pairs(Heaters) do
		if (otherdevices[loadRow[1]]=='On') then
			devAuto=0
			devKey='Heater'..k
			if (Power[devKey]~=nil and Power[devKey]=='auto') then
				devAuto=1
				devOn=loadRow[1]
				devPower=loadRow[2]
				log("devOn="..devOn.." devPower="..devPower.." devAuto="..devAuto)
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

function powerDisconnect(forced) 
	-- disconnect the last device in Heater table, that is ON. Return 0 in case of no devices to be disconnected
	scanHeaters()
	if (devOn=='') then
		-- TODO: try to disable overloadDisconnect devices
		return 0
	elseif (devAuto~=0 or forced~=0) then
		log('disconnect '..devOn..' to save '..devPower..'W')
		commandArray[devOn]='Off'
		Power[devKey]='off/man'
		Power['usage']=Power['usage']-devPower
		if (Power['usage']<0) then 
			Power['usage']=0
		end
		return 1
	end
end

for devName,devValue in pairs(devicechanged) do
	if (devName==PowerMeter[1]) then
		currentPower=999999
		for str in devValue:gmatch("[^;]+") do
			currentPower=tonumber(str)
			break
		end
		if (currentPower>-20000 and currentPower<20000) then
			-- currentPower is good
			getPower() -- get Power variable from zPower domoticz variable (coded in JSON format)

			
			log("currentPower="..currentPower.." Used_by_heaters="..Power['usage'])
			-- update LED statuses
			-- red led when power usage >=0 (1=>1000W, 2=>2000W, ...)
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
				l=math.floor(currentPower/1000)*10	-- 1=1000..1999W, 2=2000..2999W, ...
			else
				l=0	-- used power >0 => turn off green leds
			end
			for k,led in pairs(ledsRed) do
				if (otherdevices_svalues[led]~=tostring(l)) then
					commandArray[led]="Set Level "..tostring(l)
				end
			end

			toleratedUsagePower=0
			if (timenow.month<=3 or timenow.month>=10) then 
				toleratedUsagePower=300	-- from October to March, activate electric heaters even if the usage power will be >0W but <300W
			end

			if (currentPower<PowerThreshold[1]) then
				-- low power consumption => reset threshold timers, used to count from how many seconds power usage is above thresholds
				Power['th1Time']=0
				Power['th2Time']=0
--				currentPower=-1200
--				log('currentPower='..currentPower)
				if (currentPower>toleratedUsagePower+100) then
					-- disconnect only if power remains high for more than 5*2s
					if (Power['above']>5) then 
						powerDisconnect(0) 
						Power['above']=0
					else
						Power['above']=Power['above']+1
					end
				else
					Power['above']=0
					if (timenow.sec>=53 and currentPower>-600) then
						-- if HeatPump is on, and HP['level']<LEVEL_MAX (heatpump fullpower == Off), disable electric heaters to permit script_time_heatpump.lua to increase heatpump power level
						if (otherdevices['HeatPump_Fancoil']=='Off'  and Power['usage']-currentPower>800) then
							powerDisconnect(0)
						end
					elseif (timenow.sec<=40 and currentPower<0) then
						-- renewable sources are producing more than current consumption: activate extra loads
						log("sec="..timenow.sec.." currentPower="..currentPower.." => check electric heaters....")
						availablePower=0-currentPower
						if (uservariables['HeatPumpWinter']==1) then
							-- check electric heaters
							for k,loadRow in pairs(Heaters) do
								log("Temperature "..loadRow[4].."="..otherdevices[loadRow[4]].." < "..loadRow[5].."??")
								if (otherdevices[loadRow[1]]=='Off' and (loadRow[2]-toleratedUsagePower)<availablePower and tonumber(otherdevices[loadRow[4]])<loadRow[5]) then
									-- enable this new load
									log('Enable load '..loadRow[1]..' that needs '..loadRow[2]..'W')
									commandArray[loadRow[1]]='On'
									Power['Heater'..k]='auto'
									scanHeaters()
									Power['usage']=Power['usage']+loadRow[2]
									break
								end
							end --for
						end	
						--TODO: if a lower priority device is enabled, maybe it's possible to disable it and enable a higher priority device that needs more power tha lower priority device
					end
				end 
			elseif (currentPower<PowerThreshold[2]) then
				-- power consumption a little bit more than available power => long intervention time, before disconnecting
				log("Power<PowerThreshold[2]")
				Power['th2Time']=0
				if (Power['th1Time']==0) then
					Power['th1Time']=os.time()
				elseif ((os.time()-Power['th1Time'])>PowerThreshold[3]) then
					-- can I disconnect anything?
					if (powerDisconnect(1)==0) then
						-- nothing to disconnect
						powerMeterAlert(1)	-- send alert
					end
				end
			else
				log("Power>PowerThreshold[2]")
				if (Power['th2Time']==0) then
					Power['th2Time']=os.time()
				elseif ((os.time()-Power['th2Time'])>PowerThreshold[4]) then
					-- can I disconnect anything?
					-- very high power consumption: short intervention time before power outage
					if (powerDisconnect(1)==0) then
						-- nothing to disconnect
						log("nothing to disconnect")
						powerMeterAlert(1)  -- send alert
					end
				end
			end	-- currentPower has a right value
			-- save variables in Domoticz, in a json variable Power
			-- log("commandArray['Variable:zPower']="..json.encode(Power))
			commandArray['Variable:zPower']=json.encode(Power)
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
-- in case of blackout, turn ON white LEDs on DomBusTH devices

return commandArray
