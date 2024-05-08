-- script_time_hotwater.lua for Domoticz 
-- Author: CreasolTech https://www.creasol.it

-- This LUA script manage the Hot Water Heat Pump (controlled by Modbus) to optimize own consumption from photovoltaic

dofile "scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

DEBUG_LEVEL=E_INFO
DEBUG_LEVEL=E_DEBUG		-- remove "--" at the begin of line, to enable debugging
DEBUG_PREFIX="HotWater: "

commandArray={}

log(E_DEBUG,"====================== "..DEBUG_PREFIX.." ============================")
dofile "scripts/lua/config_hotwater.lua"


-- in peak hours => OFF
-- between 11:00 and Sunset:
--   between 11:00 and 13:00 ON only if enough power is available from photovoltaic
--   after 13:00, ON

setPoint=tonumber(otherdevices[HW_SETPOINT])
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
	if (peakPower()) then 
		if (setPoint>HW_SP_OFF) then
			setPointNew=HW_SP_OFF
		end
		log(E_DEBUG, "Peak => setPoint="..setPointNew)
	else
		if (timeofday["Nighttime"]) then
			if (setPoint>HW_SP_OFF) then
				setPoint=HW_SP_OFF
			end
			log(E_DEBUG, "Night time => setPoint="..setPointNew)
		else
			-- during the day
			if (timeNow.hour>=13 or (timeNow.hour>=11 and timeNow.wday>=2 and timeNow.wday<=4)) then
				-- after 13:00, or from Mon to Wed after 11:00
				gridPower=getPowerValue(otherdevices[GRID_POWER])
				hwPower=getPowerValue(otherdevices[HW_POWER])
				tempWaterBot=tonumber(otherdevices[HW_TEMPWATER_BOTTOM])
				log(E_DEBUG, "gridPower="..gridPower.." hwPower="..hwPower.." tempWaterBot="..tempWaterBot)
				if (otherdevices[EVSEON_DEV]=='Off' and (gridPower<-500 or (hwPower>100 and gridPower<100))) then 
					-- available power to start heat pump, or heat pump already running with enough power available
					setPointNew=HW_SP_NORMAL
					if (timeNow.hour>=12 and otherdevices[EVSTATE_DEV]~='Ch') then	
						setPointNew=HW_SP_MAX
					end
					if (setPointNew>setPoint and hwPower<100) then
						-- hot water heat pump is OFF
						-- if HP_TEMPWATER_BOT + 15 > setPointNew => increase setPointNew to force start
						if (tempWaterBot<setPointNew and tempWaterBot>=(setPointNew-15)) then
							setPointNew=tempWaterBot+15+1
						end
					end
					log(E_DEBUG, "Available power and EVSE is Off => setPoint="..setPointNew)
				else
					if (timeNow.hour<13) then
						setPointNew=HW_SP_MIN
					else
						setPointNew=HW_SP_NORMAL
						--setPointNew=HW_SP_MIN
					end
					log(E_DEBUG, "Power not available or EVSE is On => setPoint="..setPointNew)
				end
			end
		end
	end
end

if (setPointNew ~= setPoint) then
	commandArray[1]={['UpdateDevice']=tostring(otherdevices_idx[HW_SETPOINT])..'|1|'.. setPointNew}
end
return commandArray


