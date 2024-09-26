-- Config file for script_time_hotwater.lua
-- Hot water heat pump, Emmeti EQ2021 with Modbus

HW_TEMPCOIL='HotWater - Temp coil'
HW_TEMPAIR_INLET='HotWater - Temp air inlet'
HW_TEMPWATER_TOP='HotWater - Temp tank top'
HW_TEMPWATER_BOTTOM='HotWater - Temp tank bottom'
HW_SETPOINT='HotWater - SetPoint Hot Water'
HW_POWER='PowerMeter HotWater'
HW_MODE='HotWater - Mode'	-- Off, On, Auto selector
GRID_POWER='PowerMeter Grid'
EVSTATE_DEV="EV State"

HW_SP_OFF=38
HW_SP_MIN=42
HW_SP_NORMAL=48
HW_SP_MAX=55

HW_POWERSUPPLY='HotWater - Supply'		-- Relay to enable powersupply to energy meter (DDS238) and boiler (avoid 3W standby consumption and is disconnected during storms)

timeNow=os.date('*t')
