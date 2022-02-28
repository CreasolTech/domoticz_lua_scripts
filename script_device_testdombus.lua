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
--startTime = os.clock() --DEBUG
dofile "/home/pi/domoticz/scripts/lua/globalvariables.lua"  -- some variables common to all scripts
dofile "/home/pi/domoticz/scripts/lua/globalfunctions.lua"  -- some functions common to all scripts

DEBUG_LEVEL=E_INFO			
DEBUG_PREFIX="TestDomBus: "

commandArray = {}

timeNow=os.time()	-- current time in seconds

-- loop through all the changed devices
for devName,devValue in pairs(devicechanged) do
	log(E_DEBUG,'EVENT: devname="'..devName..'" and value='..devValue)

	-------------------------------- Start of section that is not useful: ignore or remove it! --------------------------------------
	if (devName:sub(1,7)=='esplab_' and devName:sub(1,10)~='esplab_Out' and devName:sub(1,11)~='esplab_AnIn') then
		-- esp lab used to test creDomESP1 boards
		-- if all inputs are 1, activate relays outputs
		print("Device "..devName.." = "..devValue)
		if (otherdevices['esplab_SCL']=='On' and otherdevices['esplab_SDA']=='On' and otherdevices['esplab_1wire']=='On') then
			print("*** ESPLAB ON ***")
			commandArray['esplab_Out1']='On'
			commandArray['esplab_Out2']='On AFTER 0.4 SECONDS'
			commandArray['esplab_Out3']='On AFTER 0.8 SECONDS'
			commandArray['esplab_Out4']='On AFTER 1.2 SECONDS'
			commandArray['esplab_OutSSR']='On AFTER 1.4 SECONDS'
		elseif (otherdevices['esplab_SCL']=='Off' and otherdevices['esplab_SDA']=='Off' and otherdevices['esplab_1wire']=='Off') then
			print("*** ESPLAB OFF ***")
			commandArray['esplab_Out1']='Off'
			commandArray['esplab_Out2']='Off AFTER 0.4 SECONDS'
			commandArray['esplab_Out3']='Off AFTER 0.8 SECONDS'
			commandArray['esplab_Out4']='Off AFTER 1.2'
			commandArray['esplab_OutSSR']='Off AFTER 1.4'
		end
	end

	if (devName:sub(1,19)=='dombus - [Hff01] IN') then
		-- esp lab used to test creDomESP1 boards
		-- if all inputs are 1, activate relays outputs
		local bitmask=0
		if (otherdevices['dombus - [Hff01] IN1']=='Off') then bitmask=bitmask+1; end
		if (otherdevices['dombus - [Hff01] IN2']=='Off') then bitmask=bitmask+2; end
		if (otherdevices['dombus - [Hff01] IN3']=='Off') then bitmask=bitmask+4; end
		if (otherdevices['dombus - [Hff01] IN4']=='Off') then bitmask=bitmask+8; end
		if (otherdevices['dombus - [Hff01] IN5']=='Off') then bitmask=bitmask+16; end
		if (otherdevices['dombus - [Hff01] IN6']=='Off') then bitmask=bitmask+32; end

		print(string.format('INPUT MASK=0x%02x',bitmask))
		if (bitmask==0x3f) then
			commandArray['dombus - [Hff01] OUT1 Relay']='On AFTER 1'
			commandArray['dombus - [Hff01] OUT2 Relay']='On AFTER 2'
			commandArray['dombus - [Hff01] OUT3 Relay/SSR']='On AFTER 3'
--			commandArray['dombus - [Hff01] SSR']='On AFTER 4'
		elseif (bitmask==0x00) then
			commandArray['dombus - [Hff01] OUT1 Relay']='Off'
			commandArray['dombus - [Hff01] OUT2 Relay']='Off'
			commandArray['dombus - [Hff01] OUT3 Relay/SSR']='Off'
--			commandArray['dombus - [Hff01] SSR']='Off'
		end
	end

	if (devName:sub(1,15)=='dombus - [ff12.') then
		-- creDomBus12 test
		if (devName:sub(21,22)=='1') then --IO1
			if (devValue=='Down') then
				commandArray['dombus - [ff12.5] IO5']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff12.5] IO5']='Off'
			end
		end
		if (devName:sub(21,22)=='2') then
			if (devValue=='Down') then
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
		if (devName:sub(21,22)=='3') then --IN3
			if (devValue=='Down') then
				commandArray['dombus - [ff12.5] IO5']='On'
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff12.5] IO5']='Off'
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
		if (devName:sub(21,22)=='4') then --IN4
			if (devValue=='Down') then
				commandArray['dombus - [ff12.5] IO5']='On'
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff12.5] IO5']='Off'
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
		if (devName:sub(21,22)=='7') then --IO7
			if (devValue=='Off') then
				commandArray['dombus - [ff12.5] IO5']='On'
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='On') then
				commandArray['dombus - [ff12.5] IO5']='Off'
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
		if (devName:sub(21,22)=='8') then --IO8
			if (devValue=='Off') then
				commandArray['dombus - [ff12.5] IO5']='On'
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='On') then
				commandArray['dombus - [ff12.5] IO5']='Off'
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
		if (devName:sub(21,22)=='9') then --IO9
			if (devValue=='Off') then
				commandArray['dombus - [ff12.5] IO5']='On'
				commandArray['dombus - [ff12.6] IO6']='On'
			elseif (devValue=='On') then
				commandArray['dombus - [ff12.5] IO5']='Off'
				commandArray['dombus - [ff12.6] IO6']='Off'
			end
		end
	end

	if (devName:sub(1,15)=='dombus - [ff23.') then
		-- creDomBus23 board test
		if (devName:sub(19,22)=='IO1') then --IO1
			if (devValue=='Off') then
				commandArray['dombus - [ff23.1] RL1']='On'
			else
				commandArray['dombus - [ff23.1] RL1']='Off'
			end
			commandArray['dombus - [ff23.3] MOS']='Set Level 0'
			commandArray['dombus - [ff23.4] V1/OD1']='Set Level 0'
			commandArray['dombus - [ff23.5] V2/OD2']='Set Level 0'
		end
		if (devName:sub(19,22)=='IO2') then
			print(otherdevices['dombus - [ff23.3] MOS'])
			print(otherdevices_svalues['dombus - [ff23.3] MOS'])
			if (devValue=='Off') then
				commandArray['dombus - [ff23.2] RL2']='On'
			else
				commandArray['dombus - [ff23.2] RL2']='Off'
			end
			level=tonumber(otherdevices_svalues['dombus - [ff23.3] MOS'])+25
			if (level>100) then level=0 end
			commandArray['dombus - [ff23.3] MOS']='Set Level '..tostring(level)
		end
		if (devName:sub(19,22)=='IN1') then
			level=tonumber(otherdevices_svalues['dombus - [ff23.4] V1/OD1'])+25
			if (level>100) then level=0 end
			commandArray['dombus - [ff23.4] V1/OD1']='Set Level '..tostring(level)
		end
		if (devName:sub(19,22)=='IN2') then
			level=tonumber(otherdevices_svalues['dombus - [ff23.5] V2/OD2'])+25
			if (level>100) then level=0 end
			commandArray['dombus - [ff23.5] V2/OD2']='Set Level '..tostring(level)
		end
	end


	if (devName:sub(1,19)=='dombus - [Hff51] IN') then
		-- esp lab used to test creDomESP1 boards
		-- if all inputs are 1, activate relays outputs
		local bitmask=0
		if (devName:sub(20,21)=='1') then --IN1
			if (devValue=='Down') then
				commandArray['dombus - [Hff51] LED Green']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [Hff51] LED Green']='Off'
			end
		end
		if (devName:sub(20,21)=='2') then
			if (devValue=='Down') then
				commandArray['dombus - [Hff51] Led White']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [Hff51] Led White']='Off'
			end
		end
		if (devName:sub(20,21)=='3') then --IN3
			if (devValue=='Down') then
				commandArray['dombus - [ff51.1] OUT1']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff51.1] OUT1']='Off'
			end
		end
		if (devName:sub(20,21)=='4') then --IN4
			if (devValue=='Down') then
				commandArray['dombus - [ff51.2] OUT2']='On'
			elseif (devValue=='Up') then
				commandArray['dombus - [ff51.2] OUT2']='Off'
			end
		end
	end


	-- DomBus31
	if (devName=='dombus - [Hff31] OUT1') then
		if (devValue=='On') then
			-- activate other relays in squence
			commandArray['dombus - [Hff31] OUT2']='On AFTER 0.5'
			commandArray['dombus - [Hff31] OUT3']='On AFTER 1'
			commandArray['dombus - [Hff31] OUT4']='On AFTER 1.5'
			commandArray['dombus - [Hff31] OUT5']='On AFTER 2'
			commandArray['dombus - [Hff31] OUT6']='On AFTER 2.5'
			commandArray['dombus - [Hff31] OUT7']='On AFTER 3'
			commandArray['dombus - [Hff31] OUT8']='On AFTER 3.5'
		else
			-- disactivate other relays
			commandArray['dombus - [Hff31] OUT2']='Off AFTER 0.5'
			commandArray['dombus - [Hff31] OUT3']='Off AFTER 1'
			commandArray['dombus - [Hff31] OUT4']='Off AFTER 1.5'
			commandArray['dombus - [Hff31] OUT5']='Off AFTER 2'
			commandArray['dombus - [Hff31] OUT6']='Off AFTER 2.5'
			commandArray['dombus - [Hff31] OUT7']='Off AFTER 3'
			commandArray['dombus - [Hff31] OUT8']='Off AFTER 3.5'
		end
	end
end
--print("testdombus: "..os.clock()-startTime)
return commandArray
