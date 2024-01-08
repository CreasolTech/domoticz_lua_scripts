-- script_time_selfconsumption.lua
-- Script that computes every minute the following data, managing one or more generation systems (photovoltaic on roof, on garden, wind, ...):
-- 	TotalProduced energy/power		(the array POWERMETER_GENS in config_power.lua contains the list of meters measuring power for each plant)
-- 	SelfConsumption power			totalProduced-exportedPower
-- 	TotalConsumption energy/power	selfConsumption+importedPower
--	SelfConsumption percentage		selfConsumption/TotalProduced
--	SelfSufficiency percentage		selfConsumption/TotalConsumption

-- The following variables should be defined in config_power.lua:
-- PowerMeterImport='PowerMeter Import'         	-- Meter measuring import power
-- PowerMeterExport='PowerMeter Export'         	-- Meter measuring export power
-- POWERMETER_GENS={'PV_PowerMeter', 'PV_Garden'}  	-- list of devices measuring power from renewable plants (PV on the roof, PV on the garden, wind, ...)

-- The following 5 devices have to be created manually, and will be filled by the script
-- POWERMETER_USAGE='Power_Used'                   	-- Electric+Counter virtual device (to be created manually)
-- POWERMETER_PROD='Power_Produced'                	-- Electric+Counter virtual device (to be created manually)
-- POWERMETER_SELF='Power_SelfConsumption'         	-- Electric+Counter virtual device (to be created manually)
-- PERCENTAGE_SELF='Perc_SelfConsumption'          	-- Percentage virtual device (to be created manually)
-- PERCENTAGE_SUFF='Perc_SelfSufficiency'          	-- Percentage virtual device (to be created manually)

-- Written by Creasol https://github.com/CreasolTech/domoticz_lua_scripts


INTERVAL=1	-- minutes before calculating value. 5, in my case, because SolarEdge cloud gives values every 5 minutes
			-- INVERVAL should be a divisor of 60 (e.g. 1, 2, 3, 4, 5, 6, 10, 12, 15, ....)

commandArray={}
timeNow=os.date('*t')
if (timeNow.min % INTERVAL)~=0 then return commandArray end	

dofile 'scripts/lua/globalvariables.lua'
dofile 'scripts/lua/globalfunctions.lua'
dofile 'scripts/lua/config_power.lua'

DEBUG_LEVEL=E_INFO
DEBUG_LEVEL=E_DEBUG		-- verbose log with debugging information
DEBUG_PREFIX="SelfConsumption: "

function SCinit() 
	if (SC==nil) then SC={} end
end

json=require("dkjson")
-- check that variable zSelfConsumption exists
if (uservariables['zSelfConsumption'] == nil) then
    SCinit()    --init SC table
    checkVar('zSelfConsumption',2,json.encode(SC))
else
    SC=json.decode(uservariables['zSelfConsumption'])
    SCinit()    -- check that all variables in HP table are initialized
end

local power=0
local energy=0
local producedEnergy=0
local producedPower=0
local exportedEnergy=0
local importedEnergy=0
local totalEnergy=0
local selfPerc=100
local suffPerc=0

log(E_DEBUG,"===== Calculate SelfConsumption and SelfSufficiency =====")
for devNum,devName in pairs(POWERMETER_GENS) do
	energy=getEnergyValue(otherdevices_svalues[devName])
	power=getPowerValue(otherdevices_svalues[devName])
	if (SC['p'..devNum]==nil) then
		diff=0
	else
		diff=energy-SC['p'..devNum]
	end
	SC['p'..devNum]=energy
	producedEnergy=producedEnergy+diff
	producedPower=producedPower+power
	log(E_DEBUG,devName..": "..otherdevices_svalues[devName].." Energy="..diff.."Wh Power=".. power .."W")
end
commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[POWERMETER_PROD].."|0|".. producedPower ..";"..producedEnergy}

-- now compute the exported energy
exportedEnergy=getEnergyValue(otherdevices_svalues[PowerMeterExport])
if (SC['ex']==nil) then
	diff=0
else
	diff=exportedEnergy-SC['ex']
end
SC['ex']=exportedEnergy
exportedEnergy=diff

-- compute self-consumption
energy=producedEnergy-exportedEnergy -- energy=self consumption
if (producedEnergy>0) then 
	selfPerc=math.floor(100*energy/producedEnergy + 0.5)
end
commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[POWERMETER_SELF].."|0|".. math.floor(energy*60/INTERVAL) ..";"..energy}
commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[PERCENTAGE_SELF].."|0|".. selfPerc}

-- now compute the imported energy to compute the self-sufficiency
importedEnergy=getEnergyValue(otherdevices_svalues[PowerMeterImport])
if (SC['im']==nil) then
	diff=0
else
	diff=importedEnergy-SC['im']
end
SC['im']=importedEnergy
importedEnergy=diff

-- self-sufficiency=self-consumption/(self-consumption+import)
totalEnergy=energy+importedEnergy	-- total usage energy in the last INTERVAL
suffPerc=math.floor(100*energy/totalEnergy + 0.5)
commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[POWERMETER_USAGE].."|0|".. math.floor(totalEnergy*60/INTERVAL) ..";"..totalEnergy+getEnergyValue(otherdevices_svalues[POWERMETER_USAGE])}
commandArray[#commandArray + 1]={['UpdateDevice']=otherdevices_idx[PERCENTAGE_SUFF].."|0|".. suffPerc}

log(E_INFO,"TotalConsumption="..totalEnergy.."Wh TotalProduction="..producedEnergy.."Wh SelfConsumption="..energy.."Wh "..selfPerc.."% SelfSufficiency="..suffPerc.."%")
--log(E_DEBUG,"Save zSelfConsumption="..json.encode(SC))
commandArray['Variable:zSelfConsumption']=json.encode(SC)
return commandArray
