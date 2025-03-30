
dofile("scripts/lua/globalvariables.lua") -- some variables common to all scripts
dofile("scripts/lua/globalfunctions.lua") -- some functions common to all scripts

LightOnDeviceNames={'LightOut_Portico','LightOut_NordOvest','LightOut_Portico_Sud','LightOut_Est','LightOut_Nord','LightOut_Terrazzo'}	-- device names of lights that should be turned on after sunset
LightOffDeviceNames={'LightOut_Terrazzo','LightOut_NordOvest','LightOut1','LightOut_Portico','LightOut_Portico_Sud','LightOut_Est','LightOut2','LightOut3','LightOut_Nord'}	-- device names of lights that should be turned off at sunrise
commandArray={}
newvalue=0

log(E_INFO,'---------------------------------- nightLights ---------------------------------------------')

function setMinutesOff()
--	commandArray['Variable:vNightLightsOff']=timeofday['SunriseInMinutes']-math.random(20, 40) -- after 5.30 switch lights off, even in the Winter
	newvalue= math.min(timeofday['SunriseInMinutes'], 360) - math.random(30,45) -- after 7:00 switch lights off, even in the Winter
	-- telegramNotify('Night lights: will be OFF at ' .. min2hours(newvalue))
	commandArray['Variable:vNightLightsOff'] = tostring(newvalue)

end
function setMinutesOn()
	newvalue= timeofday['SunsetInMinutes'] + math.random(25,30)
	-- telegramNotify('Night lights: will be ON at ' .. min2hours(newvalue))
	commandArray['Variable:vNightLightsOn'] = tostring(newvalue)
end

timeNow = os.date("*t")
minutesnow = timeNow.min + timeNow.hour * 60
if (uservariables['vNightLightsOn'] == nil) then 
	telegramNotify('Error: variable vNightLightsOn not defined')
	setMinutesOn() 
	return commandArray
else
	minutesOn = uservariables['vNightLightsOn']
end
if (uservariables['vNightLightsOff'] == nil) then 
	telegramNotify('Error: variable vNightLightsOff not defined')
	setMinutesOff() 
	return commandArray
else
	minutesOff = uservariables['vNightLightsOff']
end

log(E_INFO,'minutesnow=' .. minutesnow .. ' and minutesOn=' .. minutesOn .. ' and minutesOff=' .. minutesOff)

if (minutesnow == minutesOn) then
	delay=3
	for i,d in pairs(LightOnDeviceNames) do
		delay=math.random(delay,delay+30)
		commandArray[d] = 'On AFTER '..delay
	end
	setMinutesOff()
	telegramNotify('Night lights ON: will be OFF at ' .. min2hours(newvalue))
elseif (minutesnow==minutesOff or (minutesnow==minutesOff+15 and (otherdevices[LightOffDeviceNames[1] ]~='Off' or otherdevices[LightOffDeviceNames[7] ]~='Off'))) then
	delay=3
	for i,d in pairs(LightOffDeviceNames) do
		delay=math.random(delay,delay+30)
		commandArray[d] = 'Off AFTER '..delay
	end
	setMinutesOn()
	-- telegramNotify('Night lights OFF: will be ON at ' .. min2hours(newvalue))
end
----------------------------- custom rules ------------------------
-- turn on the light outside bedroom when alarm is activated during the night
if (otherdevices['LightOut_Terrazzo']=='Off' and uservariables['alarmLevel']>1 and (timeNow.hour>=23 or timeNow.hour<4)) then
	commandArray['LightOut_Terrazzo']='On'
end

--------------------------- ending.... ----------------------------
return commandArray
