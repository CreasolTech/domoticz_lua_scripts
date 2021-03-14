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
        url=DOMOTICZ_URL..'/json.htm?type=command&param=adduservariable&vname=' .. varname .. '&vtype=' .. vartype .. '&vvalue=' .. value
        -- openurl works, but can open only 1 url per time. If I have 10 variables to initialize, it takes 10 minutes to do that!
        -- commandArray['OpenURL']=url
        os.execute('curl "'..url..'"')
        uservariables[varname] = value;
    end
end

