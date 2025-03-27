-- LUA script for Domoticz, used to manage one or more pushbutton switches
-- Two kinds of management: 
-- The first pushbutton toggles outdoor lights ON/OFF with short pulse, and switches lights OFF with long pulse
-- The second pushbutton toggle an electric heater ON/OFF with short pulse, activate a second device with 2-3s pulse, activate a third device with a 5-6s pulse on pushbutton switch
--
-- Written by Creasol, https://www.creasol.it linux@creasol.it
-- 
-- Domoticz passes information to scripts through a number of global tables
--
-- devicechanged contains state and svalues for the device that changed.
--   devicechanged['yourdevicename'] = state 
--   devicechanged['svalues'] = svalues string 
--
-- otherdevices, otherdevices_lastupdate and otherdevices_svalues are arrays for all devices: 
--   otherdevices['yourotherdevicename'] = "On"
--   otherdevices_lastupdate['yourotherdevicename'] = "2015-12-27 14:26:40"
--   otherdevices_svalues['yourotherthermometer'] = string of svalues
--
-- uservariables and uservariables_lastupdate are arrays for all user variables: 
--   uservariables['yourvariablename'] = 'Test Value'
--   uservariables_lastupdate['yourvariablename'] = '2015-12-27 11:19:22'
--
-- other useful details are contained in the timeofday table
--   timeofday['Nighttime'] = true or false
--   timeofday['SunriseInMinutes'] = number
--   timeofday['Daytime'] = true or false
--   timeofday['SunsetInMinutes'] = number
--   globalvariables['Security'] = 'Disarmed', 'Armed Home' or 'Armed Away'
--
-- To see examples of commands see: http://www.domoticz.com/wiki/LUA_commands#General
-- To get a list of available values see: http://www.domoticz.com/wiki/LUA_commands#Function_to_dump_all_variables_supplied_to_the_script
--
-- Based on your logic, fill the commandArray with device commands. Device name is case sensitive. 
--
--startTime=os.clock() --DEBUG

DEBUG_LEVEL=E_ERROR			
DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="Pushbuttons: "

timeNow=os.time()

function PBinit(name)
	if (PB==nil) then 
		PB={} 
		PB['created']=1
		-- check for existance of a json encode variables, within a table of variables
		json=require("dkjson")
		if (uservariables['zPushButton'] == nil) then
			-- initialize variable
			checkVar('zPushButton',2,json.encode(PB))
		else
			PB=json.decode(uservariables['zPushButton'])
		end
	end
	if (PB[name]==nil) then PB[name]=timeNow end
end

function timeElapsed(devName) 
 	log(E_INFO,"Pushbutton hold for "..timeNow-PB[devName].."s")
	return timeNow-PB[devName]
end

-- loop through all the changed devices
for devName,devValue in pairs(devicechanged) do
	log(E_INFO,'EVENT: '..devName..'='..devValue)

	--[[
	-- remove the previous line to enable this section:
	-- when GARAGE_SENSOR has been activated, enable GARAGE_LIGHT for GARAGE_LIGHT_TIME seconds
	-- also, use GARAGE_PUSHBUTTON to toggle light ON/OFF
	SENSOR='Garage Sensor'
	PUSHBUTTON='Garage Pushbutton'
	LIGHT='Garage Light'
	LIGHT_TIME=180
	if (devName==SENSOR and commandArray[LIGHT]==nil) then
		-- SENSOR activation while pushbutton has not been pressed/released => turn ON light, or reload light timer to LIGHT seconds
		commandArray[LIGHT]='On for '..LIGHT_TIME..' seconds'
	end
	if (devName==PUSHBUTTON and devValue=='On') then
		if (otherdevices[LIGHT]=='Off') then
			-- light was OFF => turn ON
			commandArray[LIGHT]='On for '..LIGHT_TIME..' seconds'
		else
			-- light was ON => turn OFF
			commandArray[LIGHT]='Off'
		end
	end


	]]  -- remove this line to enable the section above

	-- pushbutton that toggles lights ON/OFF when push quickly, and turn lights OFF when push for more than 2 seconds
	if (devName=='PULSANTE SUD luci esterne') then -- PULSANTE SUD luci estern = device name for outdoor lights pushbutton switch
		-- 1 short pulse => toggles lights ON/OFF
		-- 1 long pulse => lights OFF
		PBinit(devName)	-- read zPushButton variable into PB[] and add this devName if not exists 
		if (devValue=='Off') then
			-- pushbutton released
			-- compute pulse length
			pulseLen=timeElapsed(devName)
			log(E_INFO,"EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s")
			if (pulseLen<=1 and otherdevices['LightOut2']=='Off') then
				-- short pulse, and commanded device is OFF => ON
				commandArray['LightOut2']='On FOR 15 MINUTES'
				commandArray['LightOut3']='On FOR 15 MINUTES'
			else
				-- long pulse, or commanded device was ON
				commandArray['LightOut2']='Off'
				commandArray['LightOut3']='Off'
			end
		else
			-- devValue==On => store the current date/time in PB array
			PB[devName]=timeNow 
		end
	end

	-- pushbutton in the bathroom: 
	-- short pulse => toggles ON/OFF the electric heater
	-- 2 seconds pulse => starts hot-water recirculating pump
	-- 5 seconds => starts controlled mechanical ventilation
	if (devName=='PULSANTE_Bagno') then	-- PULSANTE_Bagno = device name for pushbutton switch in the bathroom
		-- short pulse => toggles scaldasalviette ON/OFF
		-- 2s pulse => enable ricircolo acqua calda sanitaria
		-- 4s pulse => enable VMC
		PBinit(devName)	-- read zPushButton variable into PB[] and add this devName if not exists 
		if (devValue=='Off') then
			-- pushbutton released
			-- compute pulse length
			pulseLen=timeElapsed(devName)
			log(E_INFO,"EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s")
			if (pulseLen<=1) then
				-- short pulse, toggle ventilation ON/OFF
				if (otherdevices['VMC_Rinnovo']=='Off') then		-- VMC_Rinnovo = device name for controlled mechanical ventilation
					commandArray['VMC_Rinnovo']='On'
				else
					commandArray['VMC_Rinnovo']='Off'
				end
			elseif (pulseLen>=2 and pulseLen<=3) then
				commandArray['Ricircolo ACS']='On FOR 150'	-- Ricircolo ACS = device name for hot water recirculation pump
			elseif (pulseLen>=4 and pulseLen<=7) then
				if (otherdevices['Bagno_Scaldasalviette']~='Off') then -- Bagno_Scaldasalviette = device name for electric heater
					commandArray['Bagno_Scaldasalviette']='Off'
				else
					commandArray['Bagno_Scaldasalviette']='On'
				end
			end
		else
			-- devValue==On => store the current date/time in PB array
			PB[devName]=timeNow 
		end
	end

	--[[
	if (devName=='BagnoPT_Touch') then	-- PULSANTE_Bagno = device name for pushbutton switch in the bathroom
		-- short pulse => toggles VMC
		-- 2s pulse => enable ricircolo acqua calda sanitaria
		PBinit(devName)	-- read zPushButton variable into PB[] and add this devName if not exists 
		if (devValue=='Off') then
			-- pushbutton released
			-- compute pulse length
			pulseLen=timeElapsed(devName)
			log(E_INFO,"EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s")
			if (pulseLen<=1) then
				-- short pulse, toggle ventilation ON/OFF
				if (otherdevices['VMC_Rinnovo']=='Off') then		-- VMC_Rinnovo = device name for controlled mechanical ventilation
					commandArray['VMC_Rinnovo']='On'
				else
					commandArray['VMC_Rinnovo']='Off'
				end
			elseif (pulseLen>=2 and pulseLen<=3) then
				commandArray['Ricircolo ACS']='On FOR 25 seconds'	-- Ricircolo ACS = device name for hot water recirculation pump
			end
		else
			-- devValue==On => store the current date/time in PB array
			PB[devName]=timeNow 
		end
	end
	--]]

	-- pushbutton in the bathroom: 
	-- short pulse => toggles ON/OFF the electric heater
	-- 2 seconds pulse => starts hot-water recirculating pump
	-- 5 seconds => starts controlled mechanical ventilation
	if (devName=='PULSANTE_Cottura') then	-- PULSANTE_Bagno = device name for pushbutton switch in the bathroom
		-- short pulse => toggles scaldasalviette ON/OFF
		-- 2s pulse => enable ricircolo acqua calda sanitaria
		-- 4s pulse => enable VMC
		PBinit(devName)	-- read zPushButton variable into PB[] and add this devName if not exists 
		if (devValue=='Off') then
			-- pushbutton released
			-- compute pulse length
			pulseLen=timeElapsed(devName)
			log(E_INFO,"EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s")
			if (pulseLen<=1) then
				-- short pulse, toggle heater ON/OFF
				if (otherdevices['VMC_Rinnovo']=='Off') then		-- VMC_Rinnovo = device name for controlled mechanical ventilation
					commandArray['VMC_Rinnovo']='On'
				else
					commandArray['VMC_Rinnovo']='Off'
					commandArray['VMC_Ricircolo']='Off'
					commandArray['VMC_Deumidificazione']='Off'
					commandArray['VMC_CaldoFreddo']='Off'
				end
			elseif (pulseLen>=2 and pulseLen<=3) then
				log(E_INFO,"Attiva Ricircolo ACS per 60s")
				commandArray['Ricircolo ACS']='On FOR 60'	-- Ricircolo ACS = device name for hot water recirculation pump
			elseif (pulseLen>=4 and pulseLen<=6) then
				log(E_INFO,"Attiva Ricircolo ACS per 150s")
				commandArray['Ricircolo ACS']='On FOR 150'	-- Ricircolo ACS = device name for hot water recirculation pump
			end
		else
			-- devValue==On => store the current date/time in PB array
			PB[devName]=timeNow 
		end
	end

	-- now, update LED status to show the ventilation machine status
	if (devName:sub(1,4)=='VMC_') then
		-- one ventilation device has changed
		-- 1 flash if CMV air renewal is ON
		-- 2 flashes if CMV dehumidifier is ON
		-- 3 flashes if both functions are ON
		ledVMCstatus=0
		if (otherdevices['VMC_Rinnovo']=='On') then ledVMCstatus=ledVMCstatus+10 end			
		if (otherdevices['VMC_Deumidificazione']=='On') then ledVMCstatus=ledVMCstatus+20 end
		if (otherdevices_svalues['Led_Cucina_White']~=tostring(ledVMCstatus)) then		-- led device on DomBusTH , configured in Selection mode with levels 0..3
			print("ledVMCstatus=="..tostring(ledVMCstatus).." otherdevices_svalues[Led_Cucina_White]="..otherdevices_svalues['Led_Cucina_White'])
			commandArray['Led_Cucina_White']="Set Level "..tostring(ledVMCstatus)
		end
		if (otherdevices_svalues['BagnoPT_LedW']~=tostring(ledVMCstatus)) then		-- led device on DomBusTH , configured in Selection mode with levels 0..3
			commandArray['BagnoPT_LedW']="Set Level "..tostring(ledVMCstatus)
		end
	end
end
if PB~=nil then	-- PB variable was read and used => update the corresponding variable in domoticz
	commandArray['Variable:zPushButton']=json.encode(PB)
end

--print("pushbutton end: "..os.clock()-startTime) --DEBUG
