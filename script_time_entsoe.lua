-- Script to load day-ahead electricity prices into Domoticz historic variables, as a base for further processing.
-- Also get the solar photovoltaic forecast from api.forecast.solar (PVGIS)
--
-- New prices are available every day at 15:00 for the coming 24 hrs.
-- These are base prices. Providers of dynamic electricity contracts will add their surcharges and government taxes to it.
-- API documentation at: https://transparency.entsoe.eu/content/static_content/Static%20content/web%20api/Guide.html
-- To get this data yourself (it is free):
--    1) Register for an account at https://transparency.entsoe.eu/dashboard/show
--    2) Send an email to transparency@entsoe.eu with subject "Restful API access" and your registered email address in the body : 
--       you'll get an email within 3 working days
--    3) Then, login to transparency platform, go to "My account settings" and generate a token.
--    4) Store the token in the variable ENTSOE_TOKEN below
--
--	Create a new virtual device to store current ENTSO-e price: from Setup -> Hardware panel -> Create virtual device), select "Custom" type with 
--	  name "Electricity Price" (or another name that you have to write on ENTSOE_DEV below)
--	Enter "Utility" panel, click on Edit button for the last created device (Electricity Price) and set Axis label to € (or your currency)
--
--	Create a new virtual device to store your price per kWh (including taxes, ...): from Setup -> Hardware panel -> Create virtual device), 
--	  select "Custom" type with name "Electricity Consumer Price" (or another name that you have to write on ENTSOE_ELPRICE_DEV below)
--	Enter "Utility" panel, click on Edit button for the last created device (Electricity Consumer Price) and set Axis label to € (or your currency)
--	Enter Setup -> Settings -> Meters/Counters and set Electricity Price Device: Electricity Consumer Price . In this way Domoticz will compute exactly the 
--  cost of your consumed energy
--
--  Also, type the command  cd DOMOTICZDIR; ln -s scripts/lua/XmlParser.lua
--  for example cd /home/pi/domoticz; ln -s scripts/lua/XmlParser.lua
--	
-- Usage: the information about electricity price, hour by hour, can be used for:
-- * compute the cost of imported energy
-- * compute the profit for exporting energy to the grid
-- * manage the heat pump power to reduce power consumption when energy cost is higher
--   for example configuring the heat pump to work at setPower*averagePrice/currentPrice
--   where averagePrice/currentPrice is computed in this way:
--	 math.floor(tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', 24))*100/tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', timeNow.hour)))/100
--	    integer(        averagePrice (24th item in the entsoe_today variable)   *100/         currentPrice (timeNow.hour = current hour)  )                     /100
--
-- Credits:
-- Based on dzVents script by WillemD61
-- Rewritten in plain LUA by CreasolTech

commandArray={}

--if (otherdevices ~= nil) then return commandArray end -- prevent execution from Domoticz

timeNow = os.date("*t")

ENTSOE_DEV="Electricity Price"	-- Name of the Managed Counter device where prices are stored
ENTSOE_ELPRICE_DEV="Electricity Consumer Price"	-- total cost of imported energy now 
ENTSOE_ELPRICE_SPREAD=0.0195				-- Electricity Price Now = (ElectricityPrice+ENTSOE_ELPRICE_SPREAD) * ENTSOE_ELPRICE_MULTIPLY_FACTOR + ENTSOE_ELPRICE_OFFSET
ENTSOE_ELPRICE_MULTIPLY_FACTOR=1.21			-- Electricity Price Now = (ElectricityPrice+ENTSOE_ELPRICE_SPREAD) * ENTSOE_ELPRICE_MULTIPLY_FACTOR + ENTSOE_ELPRICE_OFFSET
ENTSOE_ELPRICE_OFFSET=0.09103908			-- Electricity Price Now = (ElectricityPrice+ENTSOE_ELPRICE_SPREAD) * ENTSOE_ELPRICE_MULTIPLY_FACTOR + ENTSOE_ELPRICE_OFFSET
-- In Italy, for residential houses, kWh price may be computed as ( (ENTSOE_price + SPREAD)*1.1 + DISPATCH*1.1 + TAXES )*1.1
--        where SPREAD=supplier profit, 1.1 is a factor to take into account grid losses (10%), last 1.1 to take into account 10% VAT (22% for non-residential buildings)
--        Italy, January 2025:  (ENTSOE_PRICE (PUN) + SPREAD) * 1.1 * 1.1 + (0.019478*1.1 + 0.008828 + 0.029809 + 0.0227) * 1.1
ENTSOE_TOKEN=""	-- write here the token get from transparency.entsoe.eu (see description above)
local ENTSOE_ZONE="10Y1001A1001A73I"
--[[
    "AL": "10YAL-KESH-----5",
    "AM": "10Y1001A1001B004",
    "AT": "10YAT-APG------L",
    "AZ": "10Y1001A1001B05V",
    "BA": "10YBA-JPCC-----D",
    "BE": "10YBE----------2",
    "BG": "10YCA-BULGARIA-R",
    "BY": "10Y1001A1001A51S",
    "CH": "10YCH-SWISSGRIDZ",
    "CZ": "10YCZ-CEPS-----N",
    "DE": "10Y1001A1001A83F",
    "DE-LU": "10Y1001A1001A82H",
    "DK": "10Y1001A1001A65H",
    "DK-DK1": "10YDK-1--------W",
    "DK-DK2": "10YDK-2--------M",
    "EE": "10Y1001A1001A39I",
    "ES": "10YES-REE------0",
    "FI": "10YFI-1--------U",
    "FR": "10YFR-RTE------C",
    "GB": "10YGB----------A",
    "GB-NIR": "10Y1001A1001A016",
    "GE": "10Y1001A1001B012",
    "GR": "10YGR-HTSO-----Y",
    "HR": "10YHR-HEP------M",
    "HU": "10YHU-MAVIR----U",
    "IE": "10YIE-1001A00010",
    "IE(SEM)": "10Y1001A1001A59C",
    "IT": "10YIT-GRTN-----B",
    "IT-BR": "10Y1001A1001A699",
    "IT-CA": "10Y1001C--00096J",
    "IT-CNO": "10Y1001A1001A70O",
    "IT-CSO": "10Y1001A1001A71M",
    "IT-FO": "10Y1001A1001A72K",
    "IT-NO": "10Y1001A1001A73I",
    "IT-PR": "10Y1001A1001A76C",
    "IT-SACOAC": "10Y1001A1001A885",
    "IT-SACODC": "10Y1001A1001A893",
    "IT-SAR": "10Y1001A1001A74G",
    "IT-SIC": "10Y1001A1001A75E",
    "IT-SO": "10Y1001A1001A788",
    "LT": "10YLT-1001A0008Q",
    "LU": "10YLU-CEGEDEL-NQ",
    "LV": "10YLV-1001A00074",
    "MD": "10Y1001A1001A990",
    "ME": "10YCS-CG-TSO---S",
    "MK": "10YMK-MEPSO----8",
    "MT": "10Y1001A1001A93C",
    "NL": "10YNL----------L",
    "NO": "10YNO-0--------C",
    "NO-NO1": "10YNO-1--------2",
    "NO-NO2": "10YNO-2--------T",
    "NO-NO3": "10YNO-3--------J",
    "NO-NO4": "10YNO-4--------9",
    "NO-NO5": "10Y1001A1001A48H",
    "PL": "10YPL-AREA-----S",
    "PT": "10YPT-REN------W",
    "RO": "10YRO-TEL------P",
    "RS": "10YCS-SERBIATSOV",
    "RU": "10Y1001A1001A49F",
    "RU-KGD": "10Y1001A1001A50U",
    "SE": "10YSE-1--------K",
    "SE-SE1": "10Y1001A1001A44P",
    "SE-SE2": "10Y1001A1001A45N",
    "SE-SE3": "10Y1001A1001A46L",
    "SE-SE4": "10Y1001A1001A47J",
    "SI": "10YSI-ELES-----O",
    "SK": "10YSK-SEPS-----K",
    "TR": "10YTR-TEIAS----W",
    "UA": "10YUA-WEPS-----0",
    "UA-IPS": "10Y1001C--000182",
    "XK": "10Y1001C--00100H",
]]
local URL='https://web-api.tp.entsoe.eu/api?documentType=A44'  -- the API website

------------------------------ SOLAR FORECAST for photovoltaic ------------------------------------
LATITUDE=45.1234		-- will be replaced by LATITUDE  written in globalvariables.lua, if exists
LONGITUDE=12.1234		-- will be replaced by LONGITUDE written in globalvariables.lua, if exists

-- PV={}	-- no photovoltaic system installed (empty table).
-- The following array list all installed photovoltaic systems (to take into account strings with different orientation)
PV={ -- kWp	 Azimuth Tilt InverterMaxkW
	{   2.7, -90,    15},	-- -90°=East, 15° declination, 2.7kWp
	{   4.5, 90,     15},	-- +90°=West, 15° declination, 4.5kWp
	{   1.66, 0,     60},	-- 0°=South, 60° declination, 1.66kWp
}


---------------------------------------------------------------------------------------------------------------------------------------------------

SCRIPTS_PATH="scripts/lua/" 

dofile(SCRIPTS_PATH .. "globalvariables.lua")	-- global configuration: ENTSOE_TOKEN may be defined in this lua configuration script
dofile(SCRIPTS_PATH .. "globalfunctions.lua")	-- some useful functions

if (uservariables['entsoe_today']==nil or uservariables['entsoe_tomorrow']==nil) then
	-- create user variables entsoe_today and entsoe_tomorrow
	checkVar('entsoe_today',2,'0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0')	-- 24 prices + average
	checkVar('entsoe_tomorrow',2,'')
	return commandArray
end

price=0	-- rounded price per kWh
if (timeNow.hour<13 and uservariables['entsoe_tomorrow']~=nil and uservariables['entsoe_tomorrow']~='') then
	-- rotate (normally at midnight) 
	print("entsoe: moving variable entsoe_tomorrow to entsoe_today")
	commandArray['Variable:entsoe_today']=uservariables['entsoe_tomorrow']
	commandArray['Variable:entsoe_tomorrow']=''
	uservariables['entsoe_today']=uservariables['entsoe_tomorrow']	-- copy also uservariables['today'] because will use later to write the price devices
end
if ((timeNow.min%5)==0) then
	-- update device with current price
	price=tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', timeNow.hour))
	if (price==nil) then 
		-- error getting price from entsoe_today variable
		print("entsoe: no prices in entsoe_today variable: "..uservariables['entsoe_today'])
		price=0 
	end
	print("entsoe: updating device "..ENTSOE_DEV.." with price="..price)
	commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_DEV].."|".. price .."|" .. price}

	price=(price+ENTSOE_ELPRICE_SPREAD)*ENTSOE_ELPRICE_MULTIPLY_FACTOR+ENTSOE_ELPRICE_OFFSET	-- compute total cost of energy, including fees, VAT, fixed costs ...
	commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_ELPRICE_DEV].."|".. price .."|" .. price}
elseif (timeNow.hour>=15 and (timeNow.min%3)==0 and uservariables['entsoe_tomorrow']=='' ) then	
	-- fetch new data from entsoe (no more than 1 time every 13 minutes)
	--local now=os.date("!*t", os.time())	-- today
	local tomorrow=os.date("!*t", os.time()+86400)	-- tomorrow
	tomorrow.hour=0
	tomorrow.min=0
	tomorrow.sec=0
	local periodStart=os.date("%Y%m%d%H%M", os.time(tomorrow))   -- UTC time
    local periodEnd=os.date("%Y%m%d%H%M", os.time(tomorrow)+86400)

	local url=URL.."&securityToken="..ENTSOE_TOKEN.."&in_Domain="..ENTSOE_ZONE.."&out_Domain="..ENTSOE_ZONE.."&periodStart="..periodStart.."&periodEnd="..periodEnd
	-- print("entsoe: url="..url)
	local fd=io.popen("curl -s '"..url.."'")
	local response=assert(fd:read('*a'))
	-- print("entsoe: response="..response)
	io.close(fd)

	local xml2lua = require(SCRIPTS_PATH.."xml2lua")
	--Uses a handler that converts the XML to a Lua table
	local handler = require(SCRIPTS_PATH.."xmlhandler.tree")

	--Instantiates the XML parser
	local parser = xml2lua.parser(handler)
	parser:parse(response)
	print("response="..response)
	print(handler.root.Publication_MarketDocument,0)	-- dump xml structure

	local s=""
	local ts=os.date("%Y-%m-%d ", os.time()+86400)	-- tomorrow
	local h=0		-- hour
	local hh=""		-- hour in "00" "01" "23" format
	local hp=0		-- hour corresponding with position
	local dst=0		-- daylight saving time: 0=no, 1=yes, 2=entering DST, 3=leaving DST
	local startDate=handler.root.Publication_MarketDocument['period.timeInterval']['start']:match("T(%d%d:%d%d)Z")	-- start time in UTC returned by ENTSOe
	local stopDate=handler.root.Publication_MarketDocument['period.timeInterval']['end']:match("T(%d%d:%d%d)Z")		--  end  time in UTC returned by ENTSOe

	if (startDate == stopDate) then
		if (startDate==22) then
			dst=1   -- daylight saving time
		end
	elseif (startDate=="23:00" and stopDate=="22:00") then
		dst=2   -- entering dst time (in March)
	elseif (startDate=="22:00" and stopDate=="23:00") then
		dst=3   -- leaving dst time (in October)
	end


	fd=0			-- compute avg price per MWh
	for i, p in pairs(handler.root.Publication_MarketDocument.TimeSeries.Period.Point) do
		-- print("i="..i.." Position="..p.position.." Price="..p["price.amount"])
		hp=math.floor((p.position-1)/4)
		if (dst==2 and h>=2) then
			h=h+1    -- entering daylight saving time => hour 2->3
		elseif (dst==3 and h>=3) then
			h=h-1    -- leaving daylight saving time => hour 3->2
		end
		if (hp>h) then
			for h=h,hp-1 do
				-- print(" h="..h.." price="..price)
				fd=fd+price		-- avg price per kWh
				s=s..price..";"	-- realize a simple CSV string with prices: 123.12,124.11,110.2,
				if (h<=10) then hh="0" else hh="" end	-- i=1, 2, 3, 4, .. 23
				hh=hh .. h
				-- commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_DEV].."|0|".. price .."|"..ts..hh..":00:00"} -- does not work with LUA: only dzVents
				-- print("commandArray["..#commandArray.."]={['UpdateDevice']="..otherdevices_idx[ENTSOE_DEV].."|0|".. price .."|"..ts..hh..":00:00}")
			end
			h=hp
		end
		price=math.floor(p["price.amount"]+0.5)/1000
	end
	-- complete the series until 23:00
	for h=hp,23 do
		-- print(" h="..h.." price="..price)
		fd=fd+price     -- avg price per kWh
		s=s..price..";" -- realize a simple CSV string with prices: 123.12,124.11,110.2,
		if (h<=10) then hh="0" else hh="" end  -- i=1, 2, 3, 4, .. 23
		hh=hh .. h
		-- commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_DEV].."|0|".. price .."|"..ts..hh..":00:00"} -- does not work with LUA: only dzVents
		-- print("commandArray["..#commandArray.."]={['UpdateDevice']="..otherdevices_idx[ENTSOE_DEV].."|0|".. price .."|"..ts..hh..":00:00}")
	end
	fd=math.floor(fd*1000/24)/1000-- last item in user variable is the average price
	commandArray['Variable:entsoe_tomorrow']=s .. fd	-- save dayahead prices to the user variable, in format "123.12,124.11,110.2,..." (max length=255 chars)
end

if (next(PV)) then 
	-- PV not empty => photovoltaic system exists
	-- solar photovoltaic forecast
	if (uservariables['pv_today']==nil or uservariables['pv_tomorrow']==nil) then
		-- create user variables entsoe_today and entsoe_tomorrow
		checkVar('pv_today'		,2,'')	-- 24 energy production (in Wh) + total day production for today
		checkVar('pv_tomorrow'	,2,'')	-- 24 energy production (in Wh) + total day production for tomorrow
		return commandArray
	end

	if (timeNow.hour==0 and uservariables['pv_tomorrow']~='') then
		print("entsoe: initializing variables pv_today and pv_tomorrow")
		commandArray['Variable:pv_today']=uservariables['pv_tomorrow']
		commandArray['Variable:pv_tomorrow']=''
	elseif (timeNow.hour>=6 and uservariables['pv_tomorrow']=='') then
		-- get forecast
		print("entsoe: getting photovoltaic solar forecast")
		local pv_today={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
		local pv_tomorrow={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
		local pvToday=""
		local pvTomorrow=""
		local fd, response
		local pvf
		local day, hour, min
		local whToday=0
		local whTomorrow=0
		local json=require("dkjson")

		for k,v in pairs(PV) do
			url="https://api.forecast.solar/estimate/watthours/period/" .. LATITUDE .. "/" ..LONGITUDE .."/" .. v[3] .. "/" .. v[2] .."/" .. v[1]
			fd=io.popen("curl -s '"..url.."'")
			response=assert(fd:read('*a'))
			io.close(fd)
			-- response='{"result":{"2025-03-03 06:45:41":0,"2025-03-03 07:00:00":38,"2025-03-03 08:00:00":547,"2025-03-03 09:00:00":981,"2025-03-03 10:00:00":1312,"2025-03-03 11:00:00":1485,"2025-03-03 12:00:00":1510,"2025-03-03 13:00:00":1360,"2025-03-03 14:00:00":1087,"2025-03-03 15:00:00":768,"2025-03-03 16:00:00":440,"2025-03-03 17:00:00":194,"2025-03-03 18:00:00":74,"2025-03-03 18:00:33":0,"2025-03-04 06:43:51":0,"2025-03-04 07:00:00":44,"2025-03-04 08:00:00":538,"2025-03-04 09:00:00":944,"2025-03-04 10:00:00":1263,"2025-03-04 11:00:00":1436,"2025-03-04 12:00:00":1464,"2025-03-04 13:00:00":1322,"2025-03-04 14:00:00":1057,"2025-03-04 15:00:00":748,"2025-03-04 16:00:00":432,"2025-03-04 17:00:00":194,"2025-03-04 18:00:00":75,"2025-03-04 18:01:57":1},"message":{"code":0,"type":"success","text":"","pid":"h54B8q7C","info":{"latitude":45.8812,"longitude":12.1833,"distance":0,"place":"Via Monte Grappa, 31054 Pieve di Soligo Province of Treviso, Italy","timezone":"Europe/Rome","time":"2025-03-03T08:21:03+01:00","time_utc":"2025-03-03T07:21:03+00:00"},"ratelimit":{"zone":"IP 149.13.157.183","period":3600,"limit":12,"remaining":10}}}'
			
			pvf=json.decode(response)
			for ts, wh in pairs(pvf['result']) do
				-- ts="2025-03-03 07:00:00"
				-- wh=38
				-- print("entsoe pv: ts=".. ts .. " wh=" .. wh)
				day=tonumber(ts:sub(9,10))
				hour=tonumber(ts:sub(12,13))
				minSec=ts:sub(15,19)		-- string within minutes and seconds, like "01:57" : used to determine if this is the sunrise/sunset time (to be ignored) or not
				if (wh>1 and minSec=="00:00") then
					if (day==timeNow.day) then
						pv_today[hour+1]=pv_today[hour+1]+wh
						whToday=whToday+wh
					else
						pv_tomorrow[hour+1]=pv_tomorrow[hour+1]+wh
						whTomorrow=whTomorrow+wh
					end
				end
			end
		end
		for k,v in pairs(pv_today) do
			pvToday=pvToday..v..";"
		end
		pvToday=pvToday..whToday
		for k,v in pairs(pv_tomorrow) do
			pvTomorrow=pvTomorrow..v..";"
		end
		pvTomorrow=pvTomorrow..whTomorrow

		-- print("pv_today="..pvToday)
		-- print("pv_tomorrow="..pvTomorrow)
		commandArray['Variable:pv_today']=pvToday
		commandArray['Variable:pv_tomorrow']=pvTomorrow
	end
		
	return commandArray
end
