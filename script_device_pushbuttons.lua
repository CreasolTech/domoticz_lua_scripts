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

DOMOTICZ_URL="http://127.0.0.1:8080"    -- Domoticz URL (used to create variables using JSON URL
debug=0			-- 0 => don't write debug information on log. 1 =>  write some information to the Domoticz log

commandArray = {}

timeNow=os.time()	-- current time in seconds

function checkVar(varname,vartype,value)
    -- check if a user variable already exists in Domoticz: if not exist, create a variable with defined type and value
    -- type=
    -- 0=Integer
    -- 1=Float
    -- 2=String
    -- 3=Date in format DD/MM/YYYY
    -- 4=Time in format HH:MM
    local url
    if (uservariables[varname] == nil) then
        print('Created variable ' .. varname..' = ' .. value)
        url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=' .. varname .. '&vtype=' .. vartype .. '&vvalue=' .. value
        -- openurl works, but can open only 1 url per time. If I have 10 variables to initialize, it takes 10 minutes to do that!
        -- commandArray['OpenURL']=url
        os.execute('curl "'..url..'"')
        uservariables[varname] = value;
    end
end


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
 	print("Pushbutton hold for "..timeNow-PB[devName].." seconds")
	return timeNow-PB[devName]
end



-- loop through all the changed devices
for devName,devValue in pairs(devicechanged) do
	if (debug > 0) then print('EVENT: devname="'..devName..'" and value='..devValue) end
	if (devName:sub(1,7)=='esplab_' and devName:sub(1,10)~='esplab_Out') then
		-- esp lab used to test creDomESP1 boards
		-- if all inputs are 1, activate relays outputs
		if (otherdevices['esplab_In1']=='On' and otherdevices['esplab_In3']=='On' and otherdevices['esplab_SCL']=='On' and otherdevices['esplab_SDA']=='On' and otherdevices['esplab_1wire']=='On') then
			commandArray['esplab_Out1']='On'
			commandArray['esplab_Out2']='On'
			commandArray['esplab_Out3']='On'
			commandArray['esplab_Out4']='On'
			commandArray['esplab_OutSSR']='On'
		elseif (otherdevices['esplab_In1']=='Off' and otherdevices['esplab_In3']=='Off' and otherdevices['esplab_SCL']=='Off' and otherdevices['esplab_SDA']=='Off' and otherdevices['esplab_1wire']=='Off') then
			commandArray['esplab_Out1']='Off'
			commandArray['esplab_Out2']='Off'
			commandArray['esplab_Out3']='Off'
			commandArray['esplab_Out4']='Off'
			commandArray['esplab_OutSSR']='Off'
		end
	end

	if (devName:sub(1,10)=='domtest_IN') then
		-- esp lab used to test creDomESP1 boards
		-- if all inputs are 1, activate relays outputs
		local bitmask=0
		if (otherdevices['domtest_IN1']=='Off') then bitmask=bitmask+1; end
		if (otherdevices['domtest_IN2']=='Off') then bitmask=bitmask+2; end
		if (otherdevices['domtest_IN3']=='Off') then bitmask=bitmask+4; end
		if (otherdevices['domtest_IN4']=='Off') then bitmask=bitmask+8; end
		if (otherdevices['domtest_IN5']=='Off') then bitmask=bitmask+16; end
		if (otherdevices['domtest_IN6']=='Off') then bitmask=bitmask+32; end

		print(string.format('INPUT MASK=0x%02x',bitmask))
		if (otherdevices['domtest_IN1']=='Off' and otherdevices['domtest_IN2']=='Off' and otherdevices['domtest_IN3']=='Off' and otherdevices['domtest_IN4']=='Off' and otherdevices['domtest_IN5']=='Off' and otherdevices['domtest_IN6']=='Off') then
			commandArray['domtest_OUT1']='On AFTER 1'
			commandArray['domtest_OUT2']='On AFTER 2'
			commandArray['domtest_OUT3']='On AFTER 3'
--			commandArray['domtest_SSR']='On AFTER 4'
		elseif (otherdevices['domtest_IN1']=='On' and otherdevices['domtest_IN2']=='On' and otherdevices['domtest_IN3']=='On' and otherdevices['domtest_IN4']=='On' and otherdevices['domtest_IN5']=='On' and otherdevices['domtest_IN6']=='On') then
			commandArray['domtest_OUT1']='Off'
			commandArray['domtest_OUT2']='Off'
			commandArray['domtest_OUT3']='Off'
--			commandArray['domtest_SSR']='Off'
		end
	end

	-- pushbutton that toggles lights ON/OFF when push quickly, and turn lights OFF when push for more than 2 seconds
	if (devName=='PULSANTE SUD luci esterne') then -- PULSANTE SUD luci estern = device name for outdoor lights pushbutton switch
		-- 1 short pulse => toggles lights ON/OFF
		-- 1 long pulse => lights OFF
		PBinit(devName)	-- read zPushButton variable into PB[] and add this devName if not exists 
		if (devValue=='Off') then
			-- pushbutton released
			-- compute pulse length
			pulseLen=timeElapsed(devName)
			if (debug>0) then print("EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s") end
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
			if (debug>0) then print("EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s") end
			if (pulseLen<=1) then
				-- short pulse, toggle ventilation ON/OFF
				if (otherdevices['VMC_Rinnovo']=='Off') then		-- VMC_Rinnovo = device name for controlled mechanical ventilation
					commandArray['VMC_Rinnovo']='On FOR 30 MINUTES'
				else
					commandArray['VMC_Rinnovo']='Off'
				end
			elseif (pulseLen>=2 and pulseLen<=3) then
				commandArray['Ricircolo ACS']='On FOR 30 seconds'	-- Ricircolo ACS = device name for hot water recirculation pump
			elseif (pulseLen>=5 and pulseLen<=7) then
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
			if (debug>0) then print("EVENT: pushbutton released, pulseLen="..tostring(pulseLen).."s") end
			if (pulseLen<=1) then
				-- short pulse, toggle heater ON/OFF
				if (otherdevices['VMC_Rinnovo']=='Off') then		-- VMC_Rinnovo = device name for controlled mechanical ventilation
					commandArray['VMC_Rinnovo']='On FOR 30 MINUTES'
				else
					commandArray['VMC_Rinnovo']='Off'
					commandArray['VMC_Ricircolo']='Off'
					commandArray['VMC_Deumidificazione']='Off'
					commandArray['VMC_CaldoFreddo']='Off'
				end
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
	end
end
if PB~=nil then	-- PB variable was read and used => update the corresponding variable in domoticz
	commandArray['Variable:zPushButton']=json.encode(PB)
end
return commandArray
