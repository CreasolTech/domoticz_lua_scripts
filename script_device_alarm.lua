-- scripts/lua/script_device_alarm.lua
-- Written by Creasol, https://creasol.it/ linux@creasol.it
--
--

commandArray = {}


if (uservariables['alarmLevelNew']~=nil and uservariables['alarmLevelNew']==0 and uservariables['alarmLevel']~=nil) then
	-- alarmLevel not changed
	-- skip parsing file if changed devices are not MCS,PIR,TAMPER,SIREN,ALARM
	found=0
	foundMcs=0
	foundPir=0
	foundTamper=0
	foundSiren=0
	foundAlarm=0
	for devName,devValue in pairs(devicechanged) do
		if devName:sub(1,3)=='MCS' then
			foundMcs=1 
			found=1	
		elseif devName:sub(1,3)=='PIR' then
			foundPir=1
			found=1
		elseif devName:sub(1,6)=='TAMPER' then
			foundTamper=1
			found=1
			break	-- found tamper => this need our attention
		elseif devName:sub(1,5)=='SIREN' then
			foundSiren=1
			found=1
		elseif devName:sub(1,5)=='ALARM' then
			foundAlarm=1
			found=1
		elseif devName:sub(1,5)=="Light" then
			found=1
		end
	end
	if (found==0 or (uservariables['alarmLevel']==ALARM_OFF and (foundTamper+foundAlarm)==0)) then 
		-- return if nothing has been found, or alarm is off and only MCS/PIR/SIREN has been changed
		do return commandArray end
	end
end

------------------------------------- changed device is MCS,PIR,TAMPER,SIREN or ALARM* ---------------------------------
dofile "scripts/lua/config_alarm.lua"

-- Function called when alarm is activated in Day mode
function alarmDayOn()
	commandArray['Group:AlarmDay']='On'
	for i,ledDev in pairs(LEDS_ON) do
		if (otherdevices[ledDev]~=nil and otherdevices[ledDev]~='On') then
			commandArray[ledDev]='On FOR 3 SECONDS'
		end
	end
end

-- Function called when alarm is disactivated
function alarmDayOff()
	commandArray['Group:AlarmDay']='Off'
	for i,ledDev in pairs(LEDS_OFF) do
		if (otherdevices[ledDev]~=nil and otherdevices[ledDev]~='On') then
			commandArray[ledDev]='On FOR 3 SECONDS'
		end
	end
end

-- Function called when alarm is activated in Night mode
function alarmNightOn()
	commandArray['Group:AlarmNight']='On'
	for i,ledDev in pairs(LEDS_ON) do
		if (otherdevices[ledDev]~=nil and otherdevices[ledDev]~='On') then
			commandArray[ledDev]='On FOR 3 SECONDS'
		end
	end
end

-- Function called when alarm is disactivated
function alarmNightOff()
	commandArray['Group:AlarmNight']='Off'
	for i,ledDev in pairs(LEDS_OFF) do
		if (otherdevices[ledDev]~=nil and otherdevices[ledDev]~='On') then
			commandArray[ledDev]='On FOR 3 SECONDS'
		end
	end
end

-- function called when a sensor has been activated, to activate the alarm notification and sirens
function alarmOn(sensorType, sensorItem, sensorName, sensorDelay)
	log(E_ERROR,"Alarm activated by "..sensorName)
	if (alarmLevel>ALARM_DAY) then
		alarmStatus=STATUS_ALARM
	elseif (alarmLevel==ALARM_DAY) then
		-- custom rules to avoid alarm in such cases
		-- if someone enters the garage, stop sending ALERT for next 120s 
		if ((sensorName=='PIR_Garage' or sensorName:sub(1,16)=='MCS_Garage_Porta') and (timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Magazzino'])<120 or timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Pranzo'])<120)) then
			return	-- skip alarm
		end
	end
	urloff=''
	for siren,sirenRow in pairs(SIRENlist) do
		if ((sirenRow[2]&alarmLevel)~=0) then
			-- activate this siren
			if (alarmLevel==ALARM_DAY) then
				if (timeNow>ZA['SirDis']) then
					-- send a short pulse to internal sirens: enable siren ON using JSON, and use commandArray to disable siren.
					url=DOMOTICZ_URL..'/json.htm?type=command&param=switchlight&idx='..otherdevices_idx[sirenRow[1]]..'&switchcmd=On'
					os.execute('curl "'..url..'"')
					cmd='Off'
					urloff=urloff..DOMOTICZ_URL..'/json.htm?type=command&param=switchlight&idx='..otherdevices_idx[sirenRow[1]]..'&switchcmd=Off|'
				end
			else
				log(E_INFO,"Activate "..sirenRow[1])
				cmd="On"
				if (sirenRow[3]>0 and sensorDelay>=3) then cmd=cmd.." AFTER "..sensorDelay end
				if (sirenRow[4]>=1) then cmd=cmd.." FOR "..sirenRow[4] end
			end
			commandArray[sirenRow[1]]=cmd
		end
	end
	if (alarmLevel==ALARM_DAY) then
		for url in string.gmatch(urloff, "([^|]+)") do
			os.execute('curl "'..url..'"')
		end
	end
	--[[
	if (alarmLevel>ALARM_DAY) then
		-- sleep for 100-200ms to get a stronger signal from internal sirens
		-- socket=require("socket") does not work
		-- socket.sleep(0.5)	
		-- os.execute('sleep 2') does not work
	end
	]]
end

function alarmOff() 
	for siren,sirenRow in pairs(SIRENlist) do
		commandArray[sirenRow[1]]='Off'
	end
	log(E_WARNING,"Alarm restored")
	alarmStatus=STATUS_OK
end


function sensorChanged(sensorType, sensorItem, sensorDelay, sensorOn, sensorName) 
	-- sensorType=='mcs', 'pir', 'tamper'
	-- sensorItem==number of record in MCSlist or PIRlist or TAMPERlist
	-- Note that MCSlist is divided in 2 structure, 32 records each. Also, each record has 2 sensor, window + blind
	local enabledTAMPER,enabledPIR,enabledMCS1,enabledMCS2
	sensorItemMask = 1<<(sensorItem-1)
	if (sensorType=='tamper') then
		if (sensorOn==1) then
			-- sensor gets On (Open)
			enabledTAMPER=ALARMlist[alarmLevel][2];
			if ((sensorItemMask&enabledTAMPER)~=0) then
				-- sensorItem is enabled for the current alarmLevel 
				alarmTAMPER=(sensorItemMask|alarmTAMPER) -- set bitfield alarmTAMPER with the current tamper mask
				-- if (DEBUG_LEVEL>=1) then print("ALARM: alarmTAMPER="..string.format("0x%x",alarmTAMPER).." alarmStatus="..alarmStatus) end
				if (alarmStatus~=STATUS_ALARM) then
					-- activate alarm
					alarmOn(sensorType, sensorItem, sensorName, 0)
				end
			end
		else
			-- sensor gets Off (Closed)
			alarmTAMPER=((~sensorItemMask)&alarmTAMPER)
			alarmTAMPERchanged=1 --TODO: a cosa serve?
			-- TODO: check alarmStatus and disable alarm if needed

		end
	elseif (sensorType=='mcs') then
		if (sensorOn==1) then
			-- log(E_INFO,sensorName..' On')
			-- sensor gets On (Open)
			-- check if that sensor is enabled or not
			if (sensorItem>32) then 
				sensorItemMask=(1<<(sensorItem-33))
				enabledMCS2=ALARMlist[alarmLevel][5]
				if ((sensorItemMask&enabledMCS2)~=0) then
					alarmMCS2=(sensorItemMask|alarmMCS2)
					-- if (DEBUG_LEVEL>=3) then print("ALARM: alarmMCS2="..string.format("0x%x",alarmMCS2).." alarmStatus="..alarmStatus) end
					if (alarmStatus~=STATUS_ALARM) then
						-- activate alarm
						alarmOn(sensorType, sensorItem, sensorName, MCSlist[sensorItem][3])
					end
				end	
			else
				enabledMCS1=ALARMlist[alarmLevel][4]
				if ((sensorItemMask&enabledMCS1)~=0) then
					alarmMCS1=(sensorItemMask|alarmMCS1)
					-- if (DEBUG_LEVEL>=3) then print("ALARM: alarmMCS1="..string.format("0x%x",alarmMCS1).." alarmStatus="..alarmStatus) end
					if (alarmStatus~=STATUS_ALARM) then
						-- activate alarm
						alarmOn(sensorType, sensorItem, sensorName, MCSlist[sensorItem][3])
					end
				end	
			end
		else
			-- sensor gets Off (Closed)
			if (sensorItem<=32) then
				alarmMCS1=((~sensorItemMask)&alarmMCS1)
			else
				alarmMCS2=((~sensorItemMask)&alarmMCS2)
			end
			alarmMCSchanged=1 --TODO: a cosa serve?
			-- if ALARM_DAY and (window/door is open and blind has been closed) => disable siren for 120s
			if (alarmLevel==ALARM_DAY and otherdevices[ MCSlist[sensorItem][1] ]~=nil and otherdevices[ MCSlist[sensorItem][1] ]=='Open' and otherdevices[ MCSlist[sensorItem][2] ]~=nil and  otherdevices[ MCSlist[sensorItem][2] ]=='Closed') then
				ZA['SirDis']=timeNow+60	-- disable siren for 120s
			end
			-- TODO: check alarmStatus and disable alarm if needed
			
		end
	elseif (sensorType=='pir') then
		if (sensorOn==1) then
			-- log(E_INFO,sensorName..' On')
			-- PIR sensor gets On (movement detected)
			-- check if that sensor is enabled or not
			enabledPIR=ALARMlist[alarmLevel][3]
			if ((sensorItemMask&enabledPIR)~=0) then
				alarmPIR=(sensorItemMask|alarmPIR) -- add the current PIR to the list of PIRs that started an alarm
				-- if (DEBUG_LEVEL>=3) then print("ALARM: alarmMCS1="..string.format("0x%x",alarmMCS1).." alarmStatus="..alarmStatus) end
				if (alarmStatus~=STATUS_ALARM) then
					-- activate alarm?
					-- custom check: disable PIR notification if ALARM_DAY and (MCS_Garage_Porta_Magazzino or MCS_Garage_Porta_Pranzo) has changed recently
					if (alarmLevel~=ALARM_DAY or (timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Magazzino'])>120 and timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Pranzo'])>120)) then
						alarmOn(sensorType, sensorItem, sensorName, PIRlist[sensorItem][2])
					end
				end
			end	
		else
			-- sensor gets Off (Closed)
			if (sensorItem<=32) then
				alarmMCS1=((~sensorItemMask)&alarmMCS1)
			else
				alarmMCS2=(~(sensorItemMask)&alarmMCS2)
			end
			alarmMCSchanged=1 --TODO: a cosa serve?
			-- TODO: check alarmStatus and disable alarm if needed
		end
	end
end

function sirensAreOff() 
	local sirensOff=1
	for item,sirenRow in pairs(SIRENlist) do
		if (otherdevices[sirenRow[1]]=='On') then 
			sirensOff=0
			break
		end
	end
	return sirensOff
end


function checkDoorsWindowsBlindsOpen()  
	-- check if any MCS is open
	MCSopen=""
	for mcs,mcsRow in pairs(MCSlist) do
		if (mcsRow[1]~='' and (otherdevices[mcsRow[1]]=='On' or otherdevices[mcsRow[1]]=='Open')) then
			MCSopen=MCSopen..mcsRow[1].."\n"
		end
		if (mcsRow[2]~='' and (otherdevices[mcsRow[2]]=='On' or otherdevices[mcsRow[2]]=='Open')) then
			MCSopen=MCSopen..mcsRow[2].."\n"
		end
	end
	if (MCSopen~='') then
		log(E_WARNING,"Porte/Finestre/Scuri aperti:\n"..MCSopen)
	else
		log(E_WARNING,"Alarm Enabled")
	end
end

function lightsInit()
	if (lights==nil or (lights['dir']~="up" and lights['dir']~="down") or lights['now']<=0 or lights['new']<=0) then 
		lights={}
		lights['dir']='down'
		lights['now']=1
		lights['new']=2
		lights['on']=0
		lights['off']=0
	end
end

function lightsNext()
	-- change lights[] table to the next light
	if ((lights['dir']=="down" and lights['new']<#ALARM_Lights) or (lights['dir']=='up' and lights['new']==1)) then
		print("dir="..lights['dir'].."  now="..lights['now'].." new="..lights['new'].." minore di "..#ALARM_Lights)
		lights['dir']="down"
		lights['now']=lights['new']
		lights['new']=lights['now']+1
		lights['off']=(secondsnow+math.random(ALARM_Lights[lights['now']][2],ALARM_Lights[lights['now']][3]))%86390
		lights['on']=lights['off']+math.random(ALARM_Lights[lights['now']][4],ALARM_Lights[lights['now']][5])
		if (math.abs(lights['on']-lights['off'])>ALARM_Lights[lights['now']][5]) then
			-- midnight?
			lights['on']=lights['off']
		end
	else
		print("dir="..lights['dir'].."  now="..lights['now'].." new="..lights['new'].." maggiore di "..#ALARM_Lights)
		lights['dir']="up"
		lights['now']=lights['new']
		lights['new']=lights['now']-1
		lights['off']=(secondsnow+math.random(ALARM_Lights[lights['now']][2],ALARM_Lights[lights['now']][3]))%86390
		lights['on']=lights['off']+math.random(ALARM_Lights[lights['now']][4],ALARM_Lights[lights['now']][5])
		if (math.abs(lights['on']-lights['off'])>ALARM_Lights[lights['now']][5]) then
			-- midnight?
			lights['on']=lights['off']
		end
	end
	local time=lights['off']-secondsnow	-- duration of ON time
	if (time<0) then time=time+86400 end
	print("Alarm lights: "..ALARM_Lights[lights['now']][1].." Off AFTER "..time)
	commandArray[ALARM_Lights[lights['now']][1]]="Off AFTER "..time
	-- check that next light will be turned ON before Sunrise-30min or after Sunset+20min
	if ((lights['on'] >=(timeofday['SunriseInMinutes']-30)*60) and (lights['on'] <= (timeofday['SunsetInMinutes']+20)*60)) then
		lights['on']=(timeofday['SunsetInMinutes']+20)*60 -- turn light again at SunSet+20 minutes
	end
	time=lights['on']-secondsnow	-- delay before turn on new light
	if (time<0) then time=time+86400 end
	print("Alarm lights: "..ALARM_Lights[lights['new']][1].." On AFTER "..time)
	commandArray[ALARM_Lights[lights['new']][1]]="On AFTER "..time
	commandArray['Variable:zAlarmLightOn1']=ALARM_Lights[lights['now']][1] -- store the light that is on in a variable, so it's possible to disable it easily when alarmLevel goes OFF
	commandArray['Variable:zAlarmLightOn2']=ALARM_Lights[lights['new']][1] -- store the light that is on in a variable, so it's possible to disable it easily when alarmLevel goes OFF
	commandArray["Variable:zAlarmLights"]=json.encode(lights)
end

function lightsCheck() -- check that zAlarmLights exists, if not init it and init lights[] dict
	timenow=os.date("*t")
	secondsnow = timenow.sec + timenow.min*60 + timenow.hour*3600
	json=require("json")
	if (uservariables['zAlarmLights']==nil) then
		lightsInit()	-- init lights table
		checkVar('zAlarmLights',2,json.encode(lights))
	else
		lights={}
		lights=json.decode(uservariables['zAlarmLights'])
		lightsInit()	-- check lights table
	end
	checkVar('zAlarmLightOn1',2,'')	-- used to store the light that is ON
	checkVar('zAlarmLightOn2',2,'')	-- used to store the light that is ON
end

function ZAinit()
	if (ZA==nil) then ZA={} end
	if (ZA['PIR_Gs']==nil) then ZA['PIR_Gs']=timeNow end		--time when PIR_G has been activated and video recording started
	if (ZA['PIR_SEs']==nil) then ZA['PIR_SEs']=timeNow end	--time when PIR_SE has been activated and video recording started
	if (ZA['PIR_SEn']==nil) then ZA['PIR_SEn']=0 end			--number of video recordings due to PIR_SE activations
	if (ZA['Button1']==nil) then ZA['Button1']=timeNow end	--time the Button1 has been pushed
	if (ZA['ButtonSU']==nil) then ZA['ButtonSU']=timeNow end	--time the ButtonSU has been pushed
	if (ZA['ButtonCO']==nil) then ZA['ButtonCO']=timeNow end	--time the ButtonCO has been pushed
	if (ZA['SirDis']==nil) then ZA['SirDis']=0 end			-- time of day when Siren will be enabled again in ALARM_DAY (used to disable siren while closing blinds
end

function grabVideoSE()  -- grab a video when PIR_SE has been activated
	ZA['PIR_SEn']=ZA['PIR_SEn']+1	-- increment variable that count the number of videos grabbed
	ZA['PIR_SEs']=timeNow			-- set the time of the current video
	os.execute("scripts/lua/alarm_sendsnapshot.sh 192.168.3.203 192.168.3.204 PIR_SudEst 2>&1 >/tmp/alarm_sendsnapshot_sud.log &")
end

--[[
Variables:
	alarmLevel:		0 => Disarmed
					1 => Home, only MCSs
					2 => Home, with some PIRs
					3 => Away (all MCSs and PIRs are enabled)
					4 => Test (all enabled, but sirens are disabled)

--]]

--[[
tc=next(devicechanged)
Panel=tostring(tc)
if (Panel == 'Keypad Alarm Level') then
--      set the group to the status of the switch
        if (devicechanged[Panel] == 'On') then
                print('AlarmPanel Arm Away')
                commandArray['Security Panel'] = 'Arm Away'
        else
                print('AlarmPanel Disarm')
                commandArray['Security Panel'] = 'Disarm'
                commandArray['Variable:AlarmDetected'] = '0'
                commandArray['Keypad Ack'] = 'On'
        end
end
--]]

timeNow=os.time()

-- create user variables, if not already exist. 
-- Also, create global variables instead of using domoticz user variables, and in the end update domoticz user variables if they have changed.

--        varname, vartype, default_value
checkVar('alarmLevelNew',0,0)				-- Set to On when alarm has been activated by a scene
checkVar('alarmLevel',0,ALARM_TEST)			
alarmLevel=uservariables['alarmLevel']		-- OFF, HOME, HOME_PIRS, AWAY, TEST
--if alarmLevel==ALARM_OFF then
--	-- alarm off => exit
--	return
--end

checkVar('alarmStatus',0,STATUS_OK)
alarmStatus=uservariables['alarmStatus']	-- OK, PREDELAY, ALARM
checkVar('alarmTAMPER',0,0)
alarmTAMPER=uservariables['alarmTAMPER']	-- bitmask with status of each tamper
checkVar('alarmPIR',0,0)
alarmPIR=uservariables['alarmPIR']			-- bitmask with status of each PIR
checkVar('alarmMCS1',0,0)
alarmMCS1=uservariables['alarmMCS1']		-- bitmask with status of each MCR (1..32)
checkVar('alarmMCS2',0,0)
alarmMCS2=uservariables['alarmMCS2']		-- bitmask with status of each MCR (33..64)
checkVar('alarmSiren',0,0)
alarmSiren=uservariables['alarmSiren']		-- bitmask with status of each siren

-- check for existance of a json encode variables, within a table of variables
json=require("dkjson")
if (uservariables['zAlarm'] == nil) then
    -- initialize variable
    ZAinit()    --init ZA table of variables
    -- create a Domoticz variable, coded in json, within all variables used in this module
    checkVar('zAlarm',2,json.encode(ZA))
else
    ZA=json.decode(uservariables['zAlarm'])
    ZAinit()    -- check that all variables in HP table are initialized
end

if not ALARMlist[alarmLevel] then
	-- alarmLevel not found: initialize to ALARM_TEST
	alarmLevel=ALARM_TEST
end

if (uservariables['alarmLevelNew']~=0) then
	commandArray['Variable:alarmLevelNew']='0'
	if (alarmLevel>=ALARM_DAY) then
		checkDoorsWindowsBlindsOpen()  -- check if any MCS is open
		if (alarmLevel==ALARM_AWAY) then
			-- turn light on in few minutes
			lightsCheck()
			lightsNext()
		end
	else
		-- alarmLevel==LEVEL_OFF or LEVEL_TEST
		log(E_WARNING,"Alarm Disabled")
	end
end

if (alarmStatus~=STATUS_OK and timedifference(uservariables_lastupdate['alarmStatus'])>120) then
	-- status ~= STATUS_OK for more than 60s
	-- if all SIRENs are off => call alarmOff to change state to alarmStatus
	print("alarmStatus~=STATUS_OK")
	if (sirensAreOff()==1) then alarmOff() end
end	

-- loop through all the changed devices
for devName,devValue in pairs(devicechanged) do
	-- check if devName is inside TAMPERlist, MCRlist or PIRlist
	-- devName should be something like TAMPER_name or MCS_name or PIR_name
	-- log(E_DEBUG,"ALARM: "..devName.." changed to "..devValue)
	if (devName:sub(1,3)=='MCS') then
		for item,mcsRow in pairs(MCSlist) do
			-- mcsRow[1] corresponds  to windows/door
			-- mcsRow[2], if exists, corresponds with blind associated with windows/door
			if devName==mcsRow[1] or devName==mcsRow[2] then
				log(E_INFO,devName.." changes to "..devValue)
				if (devValue=='On' or devValue=='Open') then
					-- alarm detected: window/door has been opened
					sensorChanged('mcs',item,0,1,devName)	-- activate alarm immediately, specifyting alarmType, item in the TAMPERlist, delay before activation of 
				else
					-- alarm restored (window/door has been closed)
					sensorChanged('mcs',item,0,0,devName)
				end
				break
			end
			-- custom features
			-- if MCS_Garage_Porta_Pranzo or MCS_Garage_Porta_Magazzino opens, turn on Light_Garage 
			if (timeofday['Nighttime']) then
				if (devName=='MCS_Garage_Porta_Pranzo' or devName=='MCS_Garage_Porta_Magazzino') then
					if (otherdevices[devName]=='Open') then
						if (otherdevices['Light_Garage']=='On') then
							commandArray['Light_Garage']='Off'
						else
							commandArray['Light_Garage']='On FOR 3 minutes'
						end
					else
						-- door has been closed
						if (timedifference(otherdevices_lastupdate[devName])>6 and otherdevices['Light_Garage']=='On') then
							commandArray['Light_Garage']='Off'
						end
					end
				end
			end
		end
	elseif (devName:sub(1,3)=='PIR') then 
		for item,pirRow in pairs(PIRlist) do
			if devName==pirRow[1] then
				log(E_INFO,devName.." changes to "..devValue)
				if (devValue=='On' or devValue=='Open') then
					-- alarm detected: PIR movement detected
					sensorChanged('pir',item,0,1,devName)	-- activate alarm immediately, specifyting alarmType, item in the TAMPERlist, delay before activation of 
				else
					-- alarm restored 
					sensorChanged('pir',item,0,0,devName)
				end
				break
			end
		end
		--custom features:
		-- if PIR on garage toggles, but the two doors to the garage were not opened => take some snapshots from the camera outside garage
		if (alarmLevel>=ALARM_OFF) then
			-- get snapshot only every 4 seconds (time to grab media stream and create pictures) if PIR is active but internal doors were closed for more than 5 minutes
			if (devName=='PIR_Garage' and devValue=='On' and (timeNow-ZA['PIR_Gs'])>=30) then -- ignore activations in less than 30s (because recording and sending 20s videos takes about 26s)
				if (timeofday['Nighttime']) then
					if (otherdevices['LightOut3']~='On') then commandArray['LightOut3']='On FOR 124 SECONDS' end
				end
				if (otherdevices['MCS_Garage_Porta_Pranzo']~='Open' and otherdevices['MCS_Garage_Porta_Magazzino']~='Open' and timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Pranzo'])>300 and timedifference(otherdevices_lastupdate['MCS_Garage_Porta_Magazzino'])>300) then
					if (alarmLevel>=ALARM_DAY) then
						os.execute("scripts/lua/alarm_sendsnapshot.sh 192.168.3.205 192.168.3.206 PIR_Garage 2>&1 >/tmp/alarm_sendsnapshot_garage.log &")
						ZA['PIR_Gs']=timeNow
					end
					if (otherdevices['Display_Lab_12V']~='On') then commandArray['Display_Lab_12V']="On FOR 2 MINUTES" end	-- activate display to check what happen
				end
			end
			if (devName=='PIR_SudEst') then
				-- extract the rain rate (otherdevices[dev]="rainRate;rainCounter")
				for str in otherdevices['Rain']:gmatch("[^;]+") do
					rainRate=tonumber(str);
					break
				end
				if (rainRate<1*40) then -- ignore PIR if it's raining! 1mm/h
					if (timeofday['Nighttime']) then
						if (otherdevices['LightOut2']~='On') then commandArray['LightOut2']='On FOR 120 SECONDS' end
						if (otherdevices['LightOut3']~='On') then commandArray['LightOut3']='On FOR 121 SECONDS' end
					end
					-- grab video only if South port has not been opened
					if (alarmLevel>=ALARM_DAY and otherdevices['MCS_Sud_Porta']~='Open' and timedifference(otherdevices_lastupdate['MCS_Sud_Porta'])>600 ) then
						diffTime=(timeNow-ZA['PIR_SEs']) -- seconds from last video
						-- ignore activations in less than 30s (because recording and sending 20s videos takes about 26s)
						-- grab max 2 consecutive videos, with minimum 30s of delay
						-- then wait that device stays stable OFF for at least 30 minutes
						if (diffTime>=30 and ZA['PIR_SEn']<2) then
							-- at least 30s, needed to grab a video
							grabVideoSE()
						elseif (timedifference(otherdevices_lastupdate['PIR_SudEst'])>1800) then
							ZA['PIR_SEn']=0
							grabVideoSE()
						end
					end
					-- activate display, but only if alarm is not active (it's useless to activate display if nobody is home)
					if (otherdevices['Display_Lab_12V']~='On' and alarmLevel<ALARM_NIGHT) then commandArray['Display_Lab_12V']="On FOR 2 MINUTES" end	-- activate display to check what happen
				end
			end
		end		
	elseif (devName:sub(1,6)=='TAMPER') then 
		for item,tamperRow in pairs(TAMPERlist) do
			if tamperRow[1]==devName then
				log(E_INFO,"ALARM: Tamper "..tamperRow[1].." changes to "..devValue)
				if (devValue=='On' or devValue=='Open') then
					-- alarm detected: tamper has been opened
					sensorChanged('tamper',item,0,1,devName)	-- activate alarm immediately, specifyting alarmType, item in the TAMPERlist, delay before activation of 
				else
					-- alarm restored (tamper has been closed)
					sensorChanged('tamper',item,0,0,devName)
				end
				break
			end
		end
	elseif (devName:sub(1,5)=='SIREN') then 
		if (devValue=='Off') then
			log(E_INFO,'Disable '..devName)
			if (alarmStatus~=STATUS_OK) then
				-- if all SIRENs are off => call alarmOff to change state to alarmStatus
				if (sirensAreOff()==1) then alarmOff() end
			end
		end
	elseif (devName:sub(1,5)=='ALARM') then
		if (devName:sub(7)=='Button1') then
			-- 1 short pulse => set alarmLevel to ALARM_NIGHT
			-- 1 long pulse  => set alarmLevel to ALARM_OFF
			-- 1 5s pulse => start external siren
			if (devValue=='Off') then
				-- compute pulse length
				pulseLen=timeNow-ZA[devName:sub(7)]	-- ZA['Button'] contains the date/time when pushbutton has been pushed
				print("Button hold for "..pulseLen.." seconds")
				if (pulseLen<=1) then
					
					-- else set alarmLevel=ALARM_NIGHT
					if (alarmLevel==ALARM_NIGHT) then 
				  		-- turn ON/OFF LEDs in bedroom
						if (otherdevices['Light_Night_Led']=='Off') then
							commandArray['Light_Night_Led']='On FOR 20 MINUTES'
						else
							commandArray['Light_Night_Led']='Off'
							commandArray['Led_Camera_White']='Off'
						end
					else
						alarmNightOn() -- Alarm not active or not in night mode => Activate alarm in night mode!!
					end
				elseif (pulseLen<=4) then
					-- 2-3s pulse => disactivate alarm
					alarmLevel=ALARM_OFF
					alarmNightOff()
				elseif (pulseLen>=5 and pulseLen<=7) then
					-- 5-7s pulse => activate external siren
					commandArray['SIREN_External']='On for 5 minutes'
				end
			else
				-- pushbutton just pushed => record the current time
				ZA[devName:sub(7)]=timeNow
			end		
		elseif (devName:sub(7)=='ButtonCO') then
			-- 1 short pulse => set alarmLevel to ALARM_NIGHT
			-- 1 long pulse  => set alarmLevel to ALARM_OFF
			if (devValue=='Off') then
				-- compute pulse length
				pulseLen=timeNow-ZA[devName:sub(7)]	-- ZA['Button'] contains the date/time when pushbutton has been pushed
				print("Button hold for "..pulseLen.." seconds")
				if (pulseLen<=1) then
					if (alarmLevel==ALARM_NIGHT) then 
				  		-- turn ON/OFF LEDs in bedroom
						if (otherdevices['Led_Camera_Ospiti_WhiteLow']=='Off') then
							commandArray['Led_Camera_Ospiti_WhiteLow']='On FOR 20 MINUTES'
						else
							commandArray['Led_Camera_Ospiti_WhiteLow']='Off'
						end
					else
						alarmNightOn() -- Alarm not active or not in night mode => Activate alarm in night mode!!
					end
				elseif (pulseLen<=4) then
					-- 2-3s pulse => disactivate alarm
					alarmLevel=ALARM_OFF
					alarmNightOff()
				elseif (pulseLen>=5 and pulseLen<=7) then
					-- 5-7s pulse => activate external siren
					commandArray['SIREN_External']='On for 5 minutes'
				end
			else
				-- pushbutton just pushed => record the current time
				ZA[devName:sub(7)]=timeNow
			end
		elseif (devName:sub(7)=='ButtonPC') then
			--twinbutton configured as selector switch
			print("ButtonPC="..devValue)
			if (devValue=='Down') then
				alarmLevel=ALARM_OFF
				if (otherdevices_scenesgroups['AlarmNight']=='On') then
					commandArray['Group:AlarmNight']='Off'
				end
				if (otherdevices_scenesgroups['AlarmAway']=='On') then
					commandArray['Group:AlarmDay']='Off'
				end
				alarmDayOff()
			elseif (devValue=='Up') then
				alarmDayOn()
			end
		else
			for item,otherRow in pairs(ALARM_OTHERlist) do
				if devName==otherRow[1] then
					-- check that alarmLevel matches the 2nd field of ALARM_OTHERlist
					if ((otherRow[2]&alarmLevel)~=0) then
						if (devValue==otherRow[3]) then
							log(E_ERROR,otherRow[4])
						elseif (devValue==otherRow[5]) then
							log(E_ERROR,otherRow[6])
						end
					end
				end
			end
		end
	end
end

-- if alarmLevel==ALARM_AWAY and NightTime => turn on/off some lights
-- lights['dir']="up" or "down"
-- lights['now']=current item in ALARM_Lights
-- lights['new']=next item in ALARM_Lights
-- lights['off']=time in seconds to turn off lights['now']
-- lights['on'] =time in seconds to turn on  lights['new']
if (timeofday["Nighttime"]==true and alarmLevel==ALARM_AWAY) then
--if (true) then
	lightsCheck()
	-- check if it's time to turn off lights['now']
	print("lightsoff="..lights['off'].." lightson="..lights['on'])
	if (lights['off']==0 and lights['on']==0) then
		lightsNext()
	else
		if (lights['off']>0 and (secondsnow>=lights['off'] or (lights['off']-secondsnow)>=43200)) then
			if (otherdevices[ALARM_Lights[lights['now']][1]]=='On') then
				commandArray[ALARM_Lights[lights['now']][1]]="Off"
			end
			lights['off']=0
			if (lights['on']==0) then
				-- lights['on'] expires before light["off"] => set new values
				lightsNext()
			end
		end
		if (lights['on']>0 and (secondsnow>=lights['on'] or (lights['on']-secondsnow)>=43200)) then
			if (otherdevices[ALARM_Lights[lights['new']][1]]=='Off') then
				commandArray[ALARM_Lights[lights['new']][1]]="On"
			end
			lights['on']=0
			if (lights['off']==0) then
				-- lights['on'] expires before light["off"] => set new values
				lightsNext()
			end
		end
	end
else
	-- check that no light are left ON, after disabling ALARM_AWAY
	if (uservariables['zAlarmLightOn1']~='') then
		-- light remained on => turn off
		commandArray[uservariables['zAlarmLightOn1']]='Off'
		commandArray['Variable:zAlarmLightOn1']=''
	end
	if (uservariables['zAlarmLightOn2']~='') then
		-- light remained on => turn off
		commandArray[uservariables['zAlarmLightOn2']]='Off'
		commandArray['Variable:zAlarmLightOn2']=''
	end
end

-- check which variables have changed, and update them in Domoticz
if (alarmLevel~=uservariables['alarmLevel']) then 	commandArray['Variable:alarmLevel']=tostring(alarmLevel) end
if (alarmStatus~=uservariables['alarmStatus']) then commandArray['Variable:alarmStatus']=tostring(alarmStatus) end
if (alarmTAMPER~=uservariables['alarmTAMPER']) then commandArray['Variable:alarmTAMPER']=tostring(alarmTAMPER) end
if (alarmPIR~=uservariables['alarmPIR'])	   then commandArray['Variable:alarmPIR']=tostring(alarmPIR) end
if (alarmMCS1~=uservariables['alarmMCS1'])	   then commandArray['Variable:alarmMCS1']=tostring(alarmMCS1) end
if (alarmMCS2~=uservariables['alarmMCS2'])	   then commandArray['Variable:alarmMCS2']=tostring(alarmMCS2) end
if (alarmSiren~=uservariables['alarmSiren']) then commandArray['Variable:alarmSiren']=tostring(alarmSiren) end
commandArray['Variable:zAlarm']=json.encode(ZA)

return commandArray
