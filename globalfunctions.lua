-- Functions that are useful for all scripts
-- Written by Paolo Subiaco - https://www.creasol.it
--
function telegramNotify(msg)
    os.execute('curl --data chat_id='..TELEGRAM_CHATID..' --data-urlencode "text='..msg..'"  "https://api.telegram.org/bot'..TELEGRAM_TOKEN..'/sendMessage" ')
end

function log(level, msg)
	if (DEBUG_LEVEL==nil) then DEBUG_LEVEL=E_ERROR end
	if (TELEGRAM_LEVEL==nil) then TELEGRAM_LEVEL=E_CRITICAL end
	if (DEBUG_PREFIX==nil) then DEBUG_PREFIX="" end

    if (DEBUG_LEVEL>=level) then
        print(DEBUG_PREFIX..msg)
    end
    if (TELEGRAM_LEVEL>=level) then
        local chatid=TELEGRAM_CHATID
        if (chatid) then
            telegramNotify(DEBUG_PREFIX..msg)
        end
    end
end

function min2hours(mins)
    -- convert minutes in hh:mm format
    return string.format('%02d:%02d',mins/60,mins%60)
end

function timedifference (s)
    year = string.sub(s, 1, 4)
    month = string.sub(s, 6, 7)
    day = string.sub(s, 9, 10)
    hour = string.sub(s, 12, 13)
    minutes = string.sub(s, 15, 16)
    seconds = string.sub(s, 18, 19)
    t1 = os.time()
    t2 = os.time{year=year, month=month, day=day, hour=hour, min=minutes, sec=seconds}
    difference = os.difftime (t1, t2)
    return difference
end

function jsoncmd(cmd) 
	-- use curl to send a json cmd to domoticz
	local fd=io.popen('curl "'..DOMOTICZ_URL..'/json.htm?'..cmd..'"','r')
	local res=fd:read("*a")
	fd:close()
	return res	-- return result in json format (string)
end
	
function checkVar(varname,vartype,value)
    -- check if create, if not exist, a variable with defined type and value
    -- type=
    -- 0=Integer
    -- 1=Float
    -- 2=String
    -- 3=Date in format DD/MM/YYYY
    -- 4=Time in format HH:MM
    local url
    if (uservariables[varname] == nil) then
        telegramNotify('Created variable ' .. varname..' = ' .. value)
        jsoncmd('type=command&param=adduservariable&vname=' .. varname .. '&vtype=' .. vartype .. '&vvalue=' .. value)
        uservariables[varname] = value;
    end
end


function deviceOn(devName,table,index)
    -- if devname is off => turn it on
    if (otherdevices[devName]~='On') then
        log(E_DEBUG,"deviceOn("..devName..")")
        commandArray[devName]='On'  -- switch on
        table[index]='a'    -- store in HP that device was automatically turned ON (and can be turned off)
    end
end

function deviceOff(devName,table,index)
    -- if devname is on and was enabled by this script => turn it off
    -- if devname was enabled manually, for example to force heating/cooling, leave it ON.
    if (otherdevices[devName]~='Off') then
        v='a'
        if (table[index]~=nil) then v=table[index] end
        if (v=='a') then
            log(E_DEBUG,"deviceOff("..devName..")")
            commandArray[devName]='Off' -- switch off
            table[index]=nil -- store in HP that device was automatically turned ON (and can be turned off)
        else
            log(E_DEBUG,"deviceOff("..devName..") but table["..index.."]="..v.." => OFF command refused")
        end
    end
end

function peakPower()
	if (timenow==nil) then timenow = os.date("*t") end
	if ((timenow.month>=6 and timenow.month<=7 and (timenow.hour>=7 and timenow.hour<8) and tonumber(otherdevices['Clouds_today'])<70) or
		(((timenow.month>=3 and timenow.month<=4) or (timenow.month>=8 and timenow.month<=9)) and (timenow.hour>=7 and timenow.hour<10) and tonumber(otherdevices['Clouds_today'])<70)) then
		return true
	else
		return false
	end
end
