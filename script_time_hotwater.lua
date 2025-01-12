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
	if (setPoint>HW_SP_OFF) then
		log(E_INFO,"Hot Water switched On -> Off: set SetPoint to a very low value to stop boiler")
		setPointNew=HW_SP_OFF-10
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
		elseif (timeofday["Daytime"] and timeNow.hour>=10) then
			-- during the day
			hwPower=getPowerValue(otherdevices[HW_POWER])
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
			log(E_DEBUG, "DAY: gridPower="..gridPower.." pvPower="..pvPower.." pvGarden="..pvGardenPower.." hwPower="..hwPower.." tempWaterBot="..tempWaterBot)
			
			if (availablePower>0) then
				if (gridPower+pvPower<0) then
					log(E_DEBUG,"Available power and PV in the garden is producing too much")
					setPointNew=HW_SP_MAX
				elseif (timeNow.hour>=12) then
					log(E_DEBUG,"Available power and time >= 12")
					setPointNew=HW_SP_MAX
				else
					setPointNew=HW_SP_NORMAL
				end
			else
				if (timeNow.hour>=14) then 
					setPointNew=HW_SP_NORMAL
				else
					setPointNew=HW_SP_MIN
				end
			end
			if (setPointNew>HW_SP_OFF and otherdevices[EVSTATE_DEV]=='Ch') then
				log(E_DEBUG,"EV is charging: reduce setpoint to HW_SP_OFF")
				hwTurnOff()
			end
			if (setPointNew>setPoint and hwPower<100) then
				log(E_DEBUG,"HotWater is OFF and setPoint has been increased")
				-- if HP_TEMPWATER_BOT + 15 > setPointNew => increase setPointNew to force start
				if (tempWaterBot<setPointNew and tempWaterBot>=(setPointNew-15)) then
					log(E_DEBUG,"Increase setpoint to tempWaterBot+15+1 to force heat pump start")
					setPointNew=tempWaterBot+15+1
				end
			elseif (setPointNew<setPoint and hwPower>100) then
				-- request to turn off the hotwater boiler: decrease the setpoint gradually to avoid continuous ON/OFF in case of clouds
				log(E_DEBUG,"SetPoint "..setPoint.." -> "..setPointNew..": decrease it to "..setPoint-2)

				if (setPoint-2>=setPointNew) then 
					setPointNew=setPoint-2 
				else
					setPointNew=setPoint-1
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


