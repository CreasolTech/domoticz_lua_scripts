-- script_time_hotwater.lua for Domoticz 
-- Author: CreasolTech https://www.creasol.it

-- This LUA script manage the Hot Water Heat Pump (controlled by Modbus) to optimize own consumption from photovoltaic
-- Optionally it's possible to use a relay to enable power supply to the HW heat pump (to avoid power consumption during the night)

dofile "scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

DEBUG_LEVEL=E_INFO
DEBUG_LEVEL=E_DEBUG		-- remove "--" at the begin of line, to enable debugging
DEBUG_PREFIX="HotWater: "

commandArray={}

dofile "scripts/lua/config_hotwater.lua"
function hwTurnOff() -- turn Off the heatpump
	if (setPoint>HW_SP_OFF or hwPower>50) then
		log(E_INFO,"Hot Water switched On -> Off: set SetPoint to a very low value to stop boiler")
		setPointNew=HW_SP_OFF-10
		setPoint=setPointNew+1
	elseif (setPoint<HW_SP_OFF) then
		log(E_INFO,"Hot Water Off: set SetPoint to HW_SP_OFF")
		setPointNew=HW_SP_OFF
	end
end



-- in peak hours => OFF
-- between 12:00 and Sunset:
--   between 12:00 and 14:00 ON only if enough power is available from photovoltaic
--   after 14:00, ON

mode=otherdevices[HW_MODE]
if (HW_MODE=='' or otherdevices[HW_MODE]==nil) then
	log(E_ERROR, "Please create a selector switch with Off, On, Auto states")
	return commandArray
end

if (HW_POWERSUPPLY~='') then
	if (otherdevices[HW_POWERSUPPLY]==nil) then
		log(E_WARNING,"HotWater power supply defined, but device does not exist: "..HW_POWERSUPPLY)
		goto hotwaterEnd
	elseif (otherdevices[HW_POWERSUPPLY]=='Off') then
		-- at 4:00 turn On relay to supply the heatpump, to measure the internal water temperature
		if (timeNow.hour==HW_NIGHT_CHECKHOUR and timeNow.min==0 and mode=='Auto') then
			commandArray[HW_POWERSUPPLY]='On'	-- activate the hotwater heatpump in the night to be sure that water temperature is sufficient for the morning
			log(E_INFO,"HotWater power supply On to check water tank temperature")
		elseif (mode=='On') then
			commandArray[HW_POWERSUPPLY]='On'	-- activate the hotwater heatpump in the night to be sure that water temperature is sufficient for the morning
			log(E_INFO,"HotWater mode is On => activate relay to supply the HotWater heat pump")
		else
			log(E_DEBUG,"HotWater power supply disabled: exit")
		end
		goto hotwaterEnd
	end
end

log(E_DEBUG,"====================== "..DEBUG_PREFIX.." ============================")
setPoint=tonumber(otherdevices[HW_SETPOINT])
if (timeNow.month>=11 or timeNow.month<=4) then HW_SP_MIN=HW_SP_MIN_WINTER end	-- in Winter, higher HW_SP_MIN than in Summer
if (setPoint==nil) then
	log(E_WARNING,"Hardware disabled: exit!")
	goto hotwaterEnd
end
setPointNew=setPoint
hwPower=getPowerValue(otherdevices[HW_POWER])

if (mode=='Off') then
	hwTurnOff()
elseif (mode=='On') then
	if (setPoint<HW_SP_MIN) then
		log(E_INFO,"Hot Water switched On")
		setPointNew=HW_SP_MIN
	end
else
	-- mode==Auto
	setPointNew=HW_SP_OFF	-- Default: OFF
	-- get electricity price from HP dictionary
	-- HP['p'] =  electricity price now
    -- HP['P'] =  electricity price average
    -- HP['Pp'] = electricity price average

	json=require("dkjson")
	HP=json.decode(uservariables['zHeatPump'])

	if (peakPower()) then 
		if (setPoint>HW_SP_OFF) then
			setPointNew=HW_SP_OFF
		end
		log(E_DEBUG, "Peak => setPoint="..setPointNew)
	else
		-- during the night, check that temperature is enough for shower in the morning
		if (otherdevices[HW_POWERSUPPLY]=='On' and timeNow.hour>=HW_NIGHT_CHECKHOUR and timeNow.hour<=(HW_NIGHT_CHECKHOUR+2)) then	-- during the night
			if (tonumber(otherdevices[HW_TEMPWATER_TOP])<HW_SP_MIN) then
				setPointNew=HW_SP_MIN	-- set to 42°C
			else
				-- turn Off the heat pump
				hwTurnOff()
				hwPower=getPowerValue(otherdevices[HW_POWER])
				if (hwPower<10) then
					commandArray[HW_POWERSUPPLY]='Off'	-- turn Off the relay supplying hotwater heatpump
				end
			end
		elseif (timeofday["Daytime"] and timeNow.hour>=12) then
			-- during the day
			gridPower=getPowerValue(otherdevices[GRID_POWER_DEV])  	-- Grid power meter
			pvPower=getPowerValue(otherdevices[PV_POWER_DEV])		-- Photovoltaic on the roof
			pvGardenPower=getPowerValue(otherdevices[PVGARDEN_POWER_DEV])		-- Photovoltaic on the roof
			if (uservariables['avgPower']~=nil) then
				avgPower=tonumber(uservariables['avgPower'])
				if (gridPower<avgPower) then
					gridPower=avgPower	-- gridPower=-200W, avgPower=600W => keep gridPower=600W
				end
			end
			availablePower=hwPower-gridPower-500
			tempWaterBot=tonumber(otherdevices[HW_TEMPWATER_BOTTOM])
			tempWaterTop=tonumber(otherdevices[HW_TEMPWATER_TOP])
			if (timedifference(otherdevices_lastupdate[HW_TEMPWATER_TOP])>3600 and timeNow.min==6) then
				log(E_CRITICAL, "Lo scaldacqua non risponde da piu di 1 ora\nRiavviare il raspberry da Domoticz -> Configurazione -> Piu opzioni -> Riavvia il sistema")
			end
			log(E_DEBUG, "DAY: gridPower="..gridPower.." pvPower="..pvPower.." pvGarden="..pvGardenPower.." hwPower="..hwPower.." tempWaterBot="..tempWaterBot)
			
			-- With no solar production:
			-- From 4 to 6 => HW_SP_MIN
			-- From 6 to 10 => HW_SP_OFF
			-- From 10 to 13 => HW_SP_MIN
			-- From 13 ...   => HW_SP_NORMAL
			--
			-- With solar production:
			-- From 10 to 12 => HW_SP_NORMAL
			-- From 12 to .. => HW_SP_MAX

			if (availablePower>0) then
				-- power available from photovoltaic
				-- Check if energy price goes low
				if (timeNow.hour>=12) then
					log(E_DEBUG,"Available power and time >= 12:00 => HW_SP_MAX")
					setPointNew=HW_SP_MAX
					-- if electricity price <= 0 => increase setpoint
					print(HP['p'])
				else
					-- before 12:00
--					if (gridPower+pvPower<0) then
--						log(E_DEBUG,"Available power and PV in the garden is producing too much")
--						setPointNew=HW_SP_MAX
--					else
						log(E_DEBUG,"Available power and time < 12:00 => HW_SP_NORMAL")
						setPointNew=HW_SP_NORMAL
--					end
				end
			else
				-- no available power from photovoltaic 
				if (timeNow.hour>=13) then 
					log(E_DEBUG,"No solar power and time >= 13:00 => HW_SP_NORMAL")
					setPointNew=HW_SP_NORMAL
				elseif (timeNow.hour>=10) then
					if (tempWaterTop<HW_SP_MIN) then
						log(E_DEBUG,"No solar power and time between 10:00 and 13:00 => HW_SP_MIN")
						setPointNew=HW_SP_MIN
					end
				end
			end
			if (setPointNew>HW_SP_OFF and otherdevices[EVSTATE_DEV]=='Ch' and timeNow.hour<15) then
				log(E_DEBUG,"EV is charging: reduce setpoint to HW_SP_OFF")
				hwTurnOff()
			end
			if (setPointNew>setPoint and hwPower<100) then
				log(E_DEBUG,"HotWater is OFF and setPoint has been increased from "..setPoint.." to "..setPointNew)
				-- if HP_TEMPWATER_BOT + 15 > setPointNew => increase setPointNew to force start
				if (tempWaterBot<setPointNew and tempWaterBot>=(setPointNew-15)) then
					log(E_DEBUG,"tempWaterBot="..tempWaterBot.." => Increase setpoint to tempWaterBot+15+1 to force heat pump start")
					setPointNew=tempWaterBot+15+1
				end
			elseif (setPointNew<setPoint and hwPower>100) then
				-- request to turn off the hotwater boiler: decrease the setpoint gradually to avoid continuous ON/OFF in case of clouds

				if (setPoint-2>=setPointNew) then 
					setPointNew=setPoint-2 
				else
					setPointNew=setPoint-1
				end
				log(E_DEBUG,"Decrease SetPoint "..setPoint.." -> "..setPointNew)
			end
		else
			-- before 12:00
			log(E_DEBUG,"Before 12:00, setPointNew="..setPointNew)
			if (otherdevices[EVSTATE_DEV]=='Ch') then
				if (hwPower>50) then 
					log(E_DEBUG,"EV is charging: turn OFF boiler")
					hwTurnOff()
				end
			end
		end
	end
end
log(E_DEBUG,"Hot Water setpoint: "..setPoint.." -> "..setPointNew)

if (setPointNew ~= setPoint) then
	commandArray[1]={['UpdateDevice']=tostring(otherdevices_idx[HW_SETPOINT])..'|1|'.. setPointNew}
end

::hotwaterEnd::
return commandArray


