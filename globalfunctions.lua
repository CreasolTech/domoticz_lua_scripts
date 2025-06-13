-- Functions that are useful for all scripts
-- Written by Paolo Subiaco - https://www.creasol.it
--
function telegramNotify(msg)
    os.execute('curl -m 1 --data chat_id='..TELEGRAM_CHATID..' --data-urlencode "text='..msg..'"  "https://api.telegram.org/bot'..TELEGRAM_TOKEN..'/sendMessage" &')
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
	local fd=io.popen('curl -m 1 "'..DOMOTICZ_URL..'/json.htm?'..cmd..'"','r')
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
        log(E_DEBUG,"deviceOn("..devName..","..index..")")
        commandArray[devName]='On'  -- switch on
        table[index]=1    -- store in HP that device was automatically turned ON (and can be turned off)
    end
end

function deviceOff(devName,table,index)
    -- if devname is on and was enabled by this script => turn it off
    -- if devname was enabled manually, for example to force heating/cooling, leave it ON.
    if (otherdevices[devName]~='Off') then
        v=0
        if (table[index]~=nil) then v=table[index] end
        log(E_DEBUG,"deviceOff("..devName..","..index..") and table[index]="..v)
        if (v~=0) then
            commandArray[devName]='Off' -- switch off
            table[index]=nil -- store in HP that device was automatically turned ON (and can be turned off)
        else
            log(E_DEBUG,"deviceOff("..devName..") but table["..index.."]=nil => OFF command refused")
        end
    end
end

function peakPower()
	if (timeNow==nil) then timeNow = os.date("*t") end
	if ((timeNow.month>=11 or timeNow.month<=3)) then
		if ((timeNow.hour>=7 and timeNow.hour<10) or (timeNow.hour>=17 and timeNow.hour<23)) then 
			-- tonumber(otherdevices['Clouds_today'])<70)
			return true
		end
	else -- from April to October
		if ((timeNow.hour>=7 and timeNow.hour<10) or (timeNow.hour>=18 and timeNow.hour<22)) then 
			-- tonumber(otherdevices['Clouds_today'])<70)
			return true
		end
	end
	return false
end

function getItemFromCSV(string, sep, n) -- Return the Nth item from the CSV string, using separator sep. Ex: getItemFromCSV("banana;apple;pear;mango", ";", 0)  returns "banana"
    i=0
    for str in string:gmatch("[^"..sep.."]+") do
        if (i==n) then
            return str
        end
        i=i+1
    end
    return ""   -- not found
end

function getPowerValue(devValue)
    -- extract the power value from string "POWER;ENERGY...."
    for str in devValue:gmatch("[^;]+") do
        return tonumber(str)
    end
end

function getEnergyValue(devValue)
    -- extract the power value from string "POWER;ENERGY...."
    local i=0
    for str in devValue:gmatch("[^;]+") do
        if (i==0) then
            i=1
        else
            return tonumber(str)
        end
    end
end

function dumpTable(o, level) -- dump table content: dump(table, 0)
    s=""
    for i=0,level*2 do
        s=s.." "
    end
    if type(o) == 'table' then
        local s = s..'{ '
        for k,v in pairs(o) do
            if type(k) ~= 'number' then k = '"'..k..'"' end
            io.write(s .. '['..k..'] = ')
            dump(v, level+1)
            print(',')
        end
        print('} ')
        return
    else
        io.write(tostring(o))
        return
    end
end
