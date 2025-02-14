-- Script to load day-ahead electricity prices into Domoticz historic variables, as a base for further processing.
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
-- Usage: the information about electricity price, hour by hour, can be used for:
-- * compute the cost of imported energy
-- * compute the profit for exporting energy to the grid
-- * manage the heat pump power to reduce power consumption when energy cost is higher
--   for example configuring the heat pump to work at setPower*averagePrice/currentPrice
--   where averagePrice/currentPrice is computed in this way:
--	 math.floor(tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', 24))*100/tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', timeNow.hour)))/100
--	    integer(        averagePrice (24th item in the entsoe_today variable)   *100/         currentPrice (timeNow.hour = current hour)  )                     /100
--
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
end
if ((timeNow.min%5)==0) then
	-- update device with current price
	price=tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', timeNow.hour))
	print("entsoe: updating device "..ENTSOE_DEV.." with price="..price)
	commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_DEV].."|".. price .."|" .. price}

	price=(price+ENTSOE_ELPRICE_SPREAD)*ENTSOE_ELPRICE_MULTIPLY_FACTOR+ENTSOE_ELPRICE_OFFSET	-- compute total cost of energy, including fees, VAT, fixed costs ...
	commandArray[#commandArray+1]={['UpdateDevice']=otherdevices_idx[ENTSOE_ELPRICE_DEV].."|".. price .."|" .. price}
elseif (timeNow.hour>=15 and (timeNow.min%13)==0 and uservariables['entsoe_tomorrow']=='') then
	-- fetch new data from entsoe (no more than 1 time every 13 minutes)
	local periodStart=os.date("%Y%m%d", os.time()) .. "2300"	-- TODO: UTC time?
	local periodEnd=os.date("%Y%m%d", os.time()+86400) .. "2300"
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
	--dump(handler.root,0)	-- dump xml structure

	local s=""
	local ts=os.date("%Y-%m-%d ", os.time()+86400)	-- tomorrow
	local h=0		-- hour
	local hh=""		-- hour in "00" "01" "23" format
	local hp=0		-- hour corresponding with position
	fd=0			-- compute avg price per MWh
	for i, p in pairs(handler.root.Publication_MarketDocument.TimeSeries.Period.Point) do
		-- print("i="..i.." Position="..p.position.." Price="..p["price.amount"])
		hp=math.floor((p.position-1)/4)
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
		price=math.floor(p["price.amount"])/1000
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


return commandArray

