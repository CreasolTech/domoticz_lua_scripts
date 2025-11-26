-- check name of devices that have changed status, and call the appropriate script. Used to avoid calling all script_device_* scripts when a device changes status.

--ms=math.floor(os.clock()*1000)	-- ms=current time in ms

commandArray = {}

local run_alarm=0
local run_power=0
local run_pushbuttons=0
local run_dombustest=0
local run_testdombus=0
local run_ledLiving=0
for devName,devValue in pairs(devicechanged) do	-- scan all changed devices
	if (run_alarm==0 and devName:sub(1,3)=='MCS' or devName:sub(1,3)=='PIR' or devName:sub(1,6)=='TAMPER' or devName:sub(1,5)=='SIREN' or devName:sub(1,5)=='ALARM' or devName:sub(1,5)=="Light") then
		run_alarm=1
	elseif (run_power==0 and (devName:find("Power") or devName:find("Button")) or devName=='EV Current') then
		run_power=1
	elseif (run_pushbuttons==0 and (devName:sub(1,8)=='PULSANTE' or devName:sub(1,4)=='VMC_')) then
		run_pushbuttons=1
	elseif (run_testdombus==0 and (devName:sub(1,7)=='esplab_' or devName:sub(1,15)=='dombusLab - (ff')) then -- cancel these two lines: not needed! Only for testing
		run_testdombus=1
	elseif (devName=="LEDWhite_Living" and devValue=="On" and otherdevices["Relay_Apricancello"]~="On") then
		commandArray["Relay_Apricancello"]="On FOR 20 MINUTES" -- when pushing the touch button to turn ON lights in the garden, also enable GATE powersupply
--	else
--		print(devName.."="..devValue)	-- DEBUG: print all unused devices
	end
end

if (run_alarm==0 and run_power==0 and run_pushbuttons==0 and run_testdombus==0) then return commandArray end


--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Read type of event"); ms=newms -- print execution time
dofile "scripts/lua/globalvariables.lua"  -- load some variables common to all scripts
dofile "scripts/lua/globalfunctions.lua"  -- load some functions common to all scripts
--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Executed globalvariables/functions"); ms=newms -- print execution time


if (run_alarm==1 or uservariables['alarmLevelNew']~=0) then
	dofile "scripts/lua/alarm.lua"
	--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Executed alarm.lua"); ms=newms -- print execution time
end

if (run_power==1) then
	dofile "scripts/lua/power.lua"
--	dofile "scripts/lua/power2p1.lua"
	--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Executed power.lua"); ms=newms -- print execution time
end

if (run_pushbuttons==1) then
	dofile "scripts/lua/pushbuttons.lua"
	--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Executed pushbuttons.lua"); ms=newms -- print execution time
end

if (run_testdombus==1) then
	dofile "scripts/lua/testdombus.lua"
	--newms=math.floor(os.clock()*1000); print("master: [".. string.format("%3d", newms-ms) .." ms] Executed testdombus.lua"); ms=newms -- print execution time
end

return commandArray
