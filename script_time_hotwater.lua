-- script_time_hotwater.lua for Domoticz 
-- Author: CreasolTech https://www.creasol.it

-- This LUA script manage the Hot Water Heat Pump (controlled by Modbus) to optimize own consumption from photovoltaic
-- Optionally it's possible to use a relay to enable power supply to the HW heat pump (to avoid power consumption during the night)

dofile "scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

DEBUG_LEVEL=E_INFO
--DEBUG_LEVEL=E_DEBUG		-- remove "--" at the begin of line, to enable debugging
DEBUG_PREFIX="HotWater: "

commandArray={}

dofile "scripts/lua/config_hotwater.lua"


-- in peak hours => OFF
-- between 12:00 and Sunset:
--   between 12:00 and 14:00 ON only if enough power is available from photovoltaic
--   after 14:00, ON

if (HW_POWERSUPPLY~='') then
	if (otherdevices[HW_POWERSUPPLY]==nil) then
		log(E_WARNING,"HotWater power supply defined, but device does not exist: "..HW_POWERSUPPLY)
		goto hotwaterEnd
	elseif (otherdevices[HW_POWERSUPPLY]=='Off') then
		log(E_DEBUG,"HotWater power supply disabled: exit")
		goto hotwaterEnd
	end
end

log(E_DEBUG,"====================== "..DEBUG_PREFIX.." ============================")
setPoint=tonumber(otherdevices[HW_SETPOINT])
if (setPoint==nil) then
	log(E_WARNING,"Hardware disabled: exit!")
	goto hotwaterEnd
end
setPointNew=setPoint
if (HW_MODE=='' or otherdevices[HW_MODE]==nil) then
	log(E_ERROR, "Please create a selector switch with Off, On, Auto states")
	return commandArray
end
mode=otherdevices[HW_MODE]
if (mode=='Off') then
	if (setPoint>HW_SP_OFF) then
		log(E_INFO,"Hot Water switched Off")
		setPointNew=HW_SP_OFF
	end
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
		if (timeofday["Daytime"] and timeNow.hour>=10) then
			-- during the day
			hwPower=getPowerValue(otherdevices[HW_POWER])
			gridPower=getPowerValue(otherdevices[GRID_POWER_DEV])  	-- Grid power meter
			pvPower=getPowerValue(otherdevices[PV_POWER_DEV])		-- Photovoltaic on the roof
			pvGardenPower=getPowerValue(otherdevices[PVGARDEN_POWER_DEV])		-- Photovoltaic on the roof
			availablePower=hwPower-gridPower-450
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
			if (setPointNew>=HW_SP_NORMAL and otherdevices[EVSTATE_DEV]=='Ch') then
				log(E_DEBUG,"EV is charging: reduce setpoint to HW_SP_NORMAL")
				setPointNew=HW_SP_NORMAL
			end
			if (setPointNew>setPoint and hwPower<100) then
				log(E_DEBUG,"HotWater is OFF and setPoint has been increased")
				-- if HP_TEMPWATER_BOT + 15 > setPointNew => increase setPointNew to force start
				if (tempWaterBot<setPointNew and tempWaterBot>=(setPointNew-15)) then
					log(E_DEBUG,"Increase setpoint to tempWaterBot+15+1 to force heat pump start")
					setPointNew=tempWaterBot+15+1
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


