-- script_time_pun.lua
-- Script che preleva una volta al giorno il prezzo zonale, e calcola il rimborso che sarà praticato dal GSE
-- Autore: CreasolTech www.creasol.it

-- local zona=Nord
-- https://www.mercatoelettrico.org/It/MenuBiblioteca/Documenti
-- blob:https://gme.mercatoelettrico.org/645c3f15-c3f2-42cd-bf11-5e617dd6c07b

-- Script to load day-ahead electricity and gas prices into Domoticz historic variables, as a base for further processing.
-- New electricity prices are available every day at 13:00 for the coming 24 hrs. These are base prices. Providers of dynamic electricity contracts will add their surcharges and government taxes to it.
-- API documentation at: https://transparency.entsoe.eu/content/static_content/Static%20content/web%20api/Guide.html
--    1) Register for an account at https://transparency.entsoe.eu/dashboard/show and send an email with subject "Restful API access" and your account email address in the body to transparency@entsoe.eu
--    2) After receipt of their confirmation, go into your account and generate your token.
--    3) Update variables and idx's on the lines below (including EUtoken which you just generated!)

-- Device idx's
local idxStroomP1                   = <idx>
local idxGasP1                      = <idx>
local idxSolar                      = <idx>
local idxCurrentDynamicStroomPrice  = <idx>
local idxDynamicStroomCosts         = <idx>
local idxDynamicSolarRevenue        = <idx>
local idxCurrentDynamicGasPrice     = <idx>
local idxDynamicGasCosts            = <idx>
local idxEnergyCosts                = <idx>
local idxVirtualEnergyCosts         = <idx>
local idxlowPriceIndex1             = <idx>
local idxlowPriceIndex2             = <idx>
local idxlowPriceIndex3             = <idx>
local idxlowPriceIndex4             = <idx>

-- variables for EU market prices gas and electricity
local UrlStart                      = 'https://web-api.tp.entsoe.eu/api?'           -- EU electricity API - launch the EU electricity API get request
local DocType                       = 'A44'                                         -- EU electricity API - day ahead prices document type 
local PriceRegion                   = '10YNL----------L'                            -- EU electricity API - region is set to The Netherlands (adapt to your need as per API documentation)
local EUtoken                       = 'f9eb2b55-708b-4464-ae62-6d1185435b44'        -- EU electricity API - API token
local GASUrlStart                   = 'https://api.energyzero.nl/v1/energyprices?'  -- Gas API website
local usageType                     = 2                                             -- Gas

return {
	on = {  timer = {   'at *:45',                                                  -- Get new price arrays. Prices received are in UTC so 1 hour shift needed
	-- Prices are re-loaded every hour, to avoid using old prices when there is one error loading once per day.
	'at *:55',                                                  -- Determine cheapest hour frames and calculate the costs of the past hour (missing last minutes, added to next hour, except end of day)
	'at *:59' },                                                -- Store cost/revenue to corresponding devices, update current prices and set switches on/off

	httpResponses = {   'EUprices',                                         -- must match with the callback passed to the openURL command in the code below
	'EZGASprices', } },

	data =  {   StroomHourPrices            = { history = true, maxItems = 48 },
	NrRecordsStroom             = { initial = 24},
	GasDayPrices                = { history = true, maxItems = 24 },
	NrRecordsGas                = { initial = 24},
	PreviousHrCumStroomCosts    = { initial = 0},
	PreviousHrCumStroomNett     = { initial = 0},
	PreviousHrCumSolarRevenue   = { initial = 0},
	PreviousHrCumSolarNett      = { initial = 0},
	PreviousHrCumGasCosts       = { initial = 0},
	PreviousHrCumGasNett        = { initial = 0},
	lowPriceIndex1              = { initial = 0},
	lowPriceIndex2              = { initial = 0},
	lowPriceIndex3              = { initial = 0},
	lowPriceIndex4              = { initial = 0},
	SwitchOnTime1               = { initial = 0},
	SwitchOnTime2               = { initial = 0},
	SwitchOnTime3               = { initial = 0},
	SwitchOnTime4               = { initial = 0},
},

logging = { level   = domoticz.LOG_INFO,
marker  = 'EU and EZ day ahead prices', },

execute = function(domoticz, item)

	-- Variables
	local BTW                           = 21                                            -- BTW percentage
	local DayStroomFixed                = 0                                             -- Fixed daily costs electrcity (excl. BTW)
	local MonthStroomFixed              = -11.52892562                                  -- Fixed monthly costs electricity (excl. BTW)
	local kwhStroom                     = 0.128471074                                   -- Variable costs electricity (per KwH), on top of EU market price (excl. BTW) -> (0,128471074 + 0,003)/1,21
	local DayGasFixed                   = 0                                             -- Fixed daily costs gas (excl. BTW)
	local MonthGasFixed                 = 19.4214876                                    -- Fixed monthly costs gas (excl. BTW)
	local m3Gas                         = 0.531123967                                   -- Variable costs gas (per m3), on top of EU market price (excl. BTW)
	local Time                          = require('Time')
	local ContractEindDatum             = Time('2023-2-28 23:59:59')                    -- Einddatum huidige energiecontract
	if domoticz.time.compare(ContractEindDatum).compare < 0 then                        -- Tarieven na ContractEindDatum bij contractwijziging
		BTW                             = 21                                            -- BTW percentage
		DayStroomFixed                  = 0                                             -- Fixed daily costs electrcity (excl. BTW)
		MonthStroomFixed                = -11.52892562                                  -- Fixed monthly costs electricity (excl. BTW)
		kwhStroom                       = 0.128471074                                   -- Variable costs electricity (per KwH), on top of EU market price (excl. BTW)
		DayGasFixed                     = 0                                             -- Fixed daily costs gas (excl. BTW)
		MonthGasFixed                   = 19.4214876                                    -- Fixed monthly costs gas (excl. BTW)
		m3Gas                           = 0.531123967                                   -- Variable costs gas (per m3), on top of EU market price (excl. BTW)
	end

	local StroomHourPrices      = domoticz.data.StroomHourPrices
	local GasDayPrices          = domoticz.data.GasDayPrices
	local todayStroom           = domoticz.devices(idxStroomP1).counterToday
	local todayStroomreturn     = domoticz.devices(idxStroomP1).counterDeliveredToday
	local todayGas              = domoticz.devices(idxGasP1).counterToday
	local todaySolar            = domoticz.devices(idxSolar).counterToday
	local NrRecordsStroom       = domoticz.data.NrRecordsStroom
	local VarIndexStroom        = NrRecordsStroom-tonumber(os.date("%H"))                                                                   -- last price of day is index 1
	local NrRecordsGas          = domoticz.data.NrRecordsGas
	local VarIndexGas           = NrRecordsGas-tonumber(os.date("%H"))

	if (item.isTimer) then

		if (item.trigger == 'at *:59') then

			if (tonumber(os.date("%H")) == 23) then
				domoticz.devices(idxDynamicStroomCosts).updateCustomSensor(domoticz.data.PreviousHrCumStroomCosts)
				domoticz.devices(idxDynamicSolarRevenue).updateCustomSensor(domoticz.data.PreviousHrCumSolarRevenue)
				domoticz.devices(idxDynamicGasCosts).updateCustomSensor(domoticz.data.PreviousHrCumGasCosts)
				domoticz.devices(idxEnergyCosts).updateCustomSensor(domoticz.data.PreviousHrCumStroomCosts + domoticz.data.PreviousHrCumGasCosts)
				domoticz.devices(idxVirtualEnergyCosts).updateCustomSensor(domoticz.data.PreviousHrCumStroomCosts + domoticz.data.PreviousHrCumGasCosts)
			end
			-- copy dynamic price to device holding the current price
			local CurrentStroomPrice=tonumber(StroomHourPrices.get(VarIndexStroom - 1).data)/1000 + kwhStroom                               -- from EURO/MWh to EURO/kWh + (supplier) price per KwH
			local CurrentStroomPriceBTW = CurrentStroomPrice * (100 + BTW)/100
			domoticz.log('Current Dynamic Stroom price Euro/kWh: ' .. CurrentStroomPriceBTW,domoticz.LOG_INFO)
			domoticz.devices(idxCurrentDynamicStroomPrice).updateCustomSensor(CurrentStroomPriceBTW)

			if VarIndexGas < 3  then
				VarIndexGas = 1
			else
				VarIndexGas = VarIndexGas - 2                                                                                               -- -1 (dataset starts at 23:00) -1 (script runs 1 minute before :00)
			end

			local CurrentGasPrice=tonumber(GasDayPrices.get(VarIndexGas).data) + m3Gas                                                      -- Euro per m3, last price is for 00:00 to 01:00 next day.
			local CurrentGasPriceBTW = CurrentGasPrice * (100 + BTW)/100
			domoticz.log('Current Dynamic Gas price Euro/m3: ' .. CurrentGasPriceBTW,domoticz.LOG_INFO)
			domoticz.devices(idxCurrentDynamicGasPrice).updateCustomSensor(CurrentGasPriceBTW)

			--if tonumber(os.date("%H")) < 9 or tonumber(os.date("%H")) > 19 then
			--domoticz.notify('VarIndexGas','VarIndexGas: ' .. VarIndexGas .. ' (' .. NrRecordsGas .. ' records)',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
			--domoticz.notify('Dynamic Gas price','Gas price: ' .. CurrentGasPriceBTW,domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
			--end

			if tonumber(os.date("%H")) == NrRecordsStroom-1-domoticz.data.lowPriceIndex1 then                                               -- Set switches with 1 hour frame on
				--domoticz.notify('Goedkoopste tijdslot','Start goedkoopste tijdslot van 1 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex1 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur aan (1 uur frame)',domoticz.LOG_INFO)
				domoticz.data.SwitchOnTime1 = tonumber(os.date("%H"))
				--domoticz.devices('Name or idx switch').switchOn().checkFirst()
			end
			if tonumber(os.date("%H")) == NrRecordsStroom-1-domoticz.data.lowPriceIndex2 then                                               -- Set switches with 2 hour frame on
				--domoticz.notify('Goedkoopste tijdslot','Start goedkoopste tijdslot van 2 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex2 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur aan (2 uurs frame)',domoticz.LOG_INFO)
				domoticz.data.SwitchOnTime2 = tonumber(os.date("%H"))
			end
			if tonumber(os.date("%H")) == NrRecordsStroom-1-domoticz.data.lowPriceIndex3 then                                               -- Set switches with 3 hour frame on
				--domoticz.notify('Goedkoopste tijdslot','Start goedkoopste tijdslot van 3 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex3 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur aan (3 uurs frame)',domoticz.LOG_INFO)
				domoticz.data.SwitchOnTime3 = tonumber(os.date("%H"))
			end
			if tonumber(os.date("%H")) == NrRecordsStroom-1-domoticz.data.lowPriceIndex4 then                                               -- Set switches with 4 hour frame on
				--domoticz.notify('Goedkoopste tijdslot','Start goedkoopste tijdslot van 4 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex4 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur aan (4 uurs frame)',domoticz.LOG_INFO)
				domoticz.data.SwitchOnTime4 = tonumber(os.date("%H"))
			end

			if tonumber(os.date("%H")) == domoticz.data.SwitchOnTime1 + 1 then                                                              -- Set switches with 1 hour frame off
				--domoticz.notify('Goedkoopste tijdslot','Eind goedkoopste tijdslot van 1 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex1 + 1 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur uit (1 uur frame)',domoticz.LOG_INFO)
				--domoticz.devices('Name or idx switch').switchOff().checkFirst()
			end
			if tonumber(os.date("%H")) == domoticz.data.SwitchOnTime2 + 2 then                                                              -- Set switches with 2 hour frame off
				--domoticz.notify('Goedkoopste tijdslot','Eind goedkoopste tijdslot van 2 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex2 + 2 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur uit (2 uurs frame)',domoticz.LOG_INFO)
			end
			if tonumber(os.date("%H")) == domoticz.data.SwitchOnTime3 + 3 then                                                              -- Set switches with 3 hour frame off
				--domoticz.notify('Goedkoopste tijdslot','Eind goedkoopste tijdslot van 3 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex3 + 3 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur uit (3 uurs frame)',domoticz.LOG_INFO)
			end
			if tonumber(os.date("%H")) == domoticz.data.SwitchOnTime4 + 4 then                                                              -- Set switches with 4 hour frame off
				--domoticz.notify('Goedkoopste tijdslot','Eind goedkoopste tijdslot van 4 uur (index ' .. NrRecordsStroom-1-domoticz.data.lowPriceIndex4 + 4 .. ')',domoticz.PRIORITY_NORMAL,nil,nil,domoticz.NSS_TELEGRAM)
				domoticz.log('Zet schakelaars voor laden apparatuur uit (4 uurs frame)',domoticz.LOG_INFO)
			end

		else
			if (item.trigger == 'at *:55') then                                                                                             -- first calculate cumulative daily total and last hour electricity usage
				local todayStroomNett=domoticz.devices(idxStroomP1).counterToday-domoticz.devices(idxStroomP1).counterDeliveredToday
				local lastHrStroomNett = todayStroomNett - domoticz.data.PreviousHrCumStroomNett
				local lastHrStroomCosts = lastHrStroomNett * domoticz.devices(idxCurrentDynamicStroomPrice).sensorValue * (100 + BTW)/100   -- then calculate the costs and add to device
				local CumStroomCosts = domoticz.utils.round(domoticz.data.PreviousHrCumStroomCosts + lastHrStroomCosts,2)
				domoticz.devices(idxDynamicStroomCosts).updateCustomSensor(CumStroomCosts)
				domoticz.log('todayStroomNett: ' .. domoticz.devices(idxStroomP1).counterToday-domoticz.devices(idxStroomP1).counterDeliveredToday,domoticz.LOG_INFO)
				domoticz.log('counterToday: ' .. domoticz.devices(idxStroomP1).counterToday,domoticz.LOG_INFO)
				domoticz.log('counterDeliveredToday: ' .. domoticz.devices(idxStroomP1).counterDeliveredToday,domoticz.LOG_INFO)
				domoticz.log('lastHrStroomNett: ' .. lastHrStroomNett,domoticz.LOG_INFO)
				domoticz.log('lastHrStroomCosts: ' .. lastHrStroomCosts,domoticz.LOG_INFO)
				domoticz.log('CumStroomCosts: ' .. CumStroomCosts,domoticz.LOG_INFO)
				if (tonumber(os.date("%H"))==23) then                                                                                       -- if end of day, reset the cumulative daily totals 
				domoticz.data.PreviousHrCumStroomCosts = (DayStroomFixed+MonthStroomFixed/31) * (100 + BTW)/100
				domoticz.data.PreviousHrCumStroomNett = 0
			else
				domoticz.data.PreviousHrCumStroomCosts = CumStroomCosts
				domoticz.data.PreviousHrCumStroomNett = todayStroomNett
			end

			local todaySolarNett=domoticz.devices(idxSolar).counterToday
			local lastHrSolarNett = todaySolarNett - domoticz.data.PreviousHrCumSolarNett
			local lastHrSolarRevenue = lastHrSolarNett * domoticz.devices(idxCurrentDynamicStroomPrice).sensorValue * (100 + BTW)/100   -- then calculate the costs and add to device
			local CumSolarRevenue = domoticz.utils.round(domoticz.data.PreviousHrCumSolarRevenue + lastHrSolarRevenue,2)
			domoticz.devices(idxDynamicSolarRevenue).updateCustomSensor(CumSolarRevenue)
			domoticz.log('counterToday Solar: ' .. domoticz.devices(idxSolar).counterToday,domoticz.LOG_INFO)
			domoticz.log('lastHrSolarNett: ' .. lastHrSolarNett,domoticz.LOG_INFO)
			domoticz.log('lastHrSolarRevenue: ' .. lastHrSolarRevenue,domoticz.LOG_INFO)
			domoticz.log('CumSolarRevenue: ' .. CumSolarRevenue,domoticz.LOG_INFO)
			if (tonumber(os.date("%H"))==23) then                                                                                       -- if end of day, reset the cumulative daily totals 
			domoticz.data.PreviousHrCumSolarRevenue = 0
			domoticz.data.PreviousHrCumSolarNett = 0
		else
			domoticz.data.PreviousHrCumSolarRevenue = CumSolarRevenue
			domoticz.data.PreviousHrCumSolarNett = todaySolarNett
		end   

		local todayGasNett=domoticz.devices(idxGasP1).counterToday    	                                                            -- calculate cumulative daily total and last hour gas usage
		local lastHrGasNett = todayGasNett - domoticz.data.PreviousHrCumGasNett
		local lastHrGasCosts = lastHrGasNett * domoticz.devices(idxCurrentDynamicGasPrice).sensorValue * (100 + BTW)/100            -- then calculate the costs and add to device
		local CumGasCosts = domoticz.utils.round(domoticz.data.PreviousHrCumGasCosts + lastHrGasCosts,2)
		domoticz.devices(idxDynamicGasCosts).updateCustomSensor(CumGasCosts)
		domoticz.log('counterToday todayGasNett: ' .. domoticz.devices(idxGasP1).counterToday,domoticz.LOG_INFO)
		domoticz.log('lastHrGasNett: ' .. lastHrGasNett,domoticz.LOG_INFO)
		domoticz.log('lastHrGasCosts: ' .. lastHrGasCosts,domoticz.LOG_INFO)
		domoticz.log('CumGasCosts: ' .. CumGasCosts,domoticz.LOG_INFO)
		if (tonumber(os.date("%H"))==23) then                                                                                       -- if end of day, reset the cumulative daily totals
		domoticz.data.PreviousHrCumGasCosts = (DayGasFixed+MonthGasFixed/31) * (100 + BTW)/100
		domoticz.data.PreviousHrCumGasNett = 0
	else
		domoticz.data.PreviousHrCumGasCosts = CumGasCosts
		domoticz.data.PreviousHrCumGasNett = todayGasNett
	end

	local TotalCosts = tonumber(domoticz.utils.round((CumStroomCosts + CumGasCosts),2))
	local TotalUse = tonumber(domoticz.utils.round((TotalCosts + CumSolarRevenue),2))
	domoticz.devices(idxEnergyCosts).updateCustomSensor(TotalCosts)
	domoticz.devices(idxVirtualEnergyCosts).updateCustomSensor(TotalUse)
	domoticz.log('TotalCosts: ' .. TotalCosts,domoticz.LOG_INFO)
	domoticz.log('TotalUse: ' .. TotalUse,domoticz.LOG_INFO)

	-- Determine cheapest time frames in the next period
	local IndexStart, TimeStart, IndexEnd, TimeEnd, min, TimeFrame, currentSum
	local NrAvailablePrices = 8                                                                                                 -- # available records: max 10. Or # available records - records in the past - max Timeframe (4)
	if NrRecordsStroom - tonumber(os.date("%H")) - 4 - 1 < 10 then
		NrAvailablePrices = NrRecordsStroom - tonumber(os.date("%H")) - 4
	end
	for TimeFrame = 1, 4 do
		min = math.huge                                                                                                         -- starting point for minimum value (infinity)
		IndexStart = 0                                                                                                          -- index values for start timeframe with lowest price
		IndexEnd = 0                                                                                                            -- index values for end timeframe with lowest price

		for i = VarIndexStroom - NrAvailablePrices -1, VarIndexStroom - TimeFrame do
			currentSum = 0                                                                                                      -- temporary value for calculation lowest prices in time frames
			for IndexEnd = i, i + TimeFrame - 1 do
				currentSum = currentSum + tonumber(StroomHourPrices.get(IndexEnd).data)
			end
			if currentSum <= min then
				min = currentSum
				IndexEnd = i
				IndexStart = i + TimeFrame - 1
			end
		end

		if 24-IndexStart < 0 then
			TimeStart = 48-IndexStart
		else
			TimeStart = 24-IndexStart
		end
		if 24-IndexEnd < 0 then
			TimeEnd = 48-IndexEnd
		else
			TimeEnd = 24-IndexEnd
		end
		domoticz.log('Cheapest ' .. TimeFrame .. ' hour frame ' .. TimeStart .. ':00 uur (' ..tonumber(StroomHourPrices.get(IndexStart).data) .. ') tot  ' .. TimeEnd .. ':59 uur (' ..tonumber(StroomHourPrices.get(IndexEnd).data) .. ')',domoticz.LOG_INFO)
		if TimeFrame == 1 then
			domoticz.data.lowPriceIndex1 = IndexStart
			domoticz.devices(idxlowPriceIndex1).updateCustomSensor(TimeStart)
		elseif TimeFrame == 2 then
			domoticz.data.lowPriceIndex2 = IndexStart
			domoticz.devices(idxlowPriceIndex2).updateCustomSensor(TimeStart)
		elseif TimeFrame == 3 then
			domoticz.data.lowPriceIndex3 = IndexStart
			domoticz.devices(idxlowPriceIndex3).updateCustomSensor(TimeStart)
		elseif TimeFrame == 4 then
			domoticz.data.lowPriceIndex4 = IndexStart
			domoticz.devices(idxlowPriceIndex4).updateCustomSensor(TimeStart)
		end
	end

else                                                                                                                            -- at *:45: depending on launch hour, get current or tomorrow's data
	local PricePeriodStart=os.date("%Y%m%d",os.time()) .. "0000"                                                                -- range 00:00 to 23:00, this will return full day anyway
	local PricePeriodEnd=os.date("%Y%m%d", os.time() + 24*60*60) .. "2300"                                                      -- depending on time the script is launched, get current day and/or tomorrow's data
	local EUurl=UrlStart .. 'securityToken=' .. EUtoken .. '&documentType=' .. DocType .. '&in_Domain=' .. PriceRegion .. '&out_Domain=' .. PriceRegion .. '&periodStart=' .. PricePeriodStart .. '&periodEnd=' .. PricePeriodEnd
	domoticz.log("URL : " .. EUurl, domoticz.LOG_INFO)
	domoticz.openURL({  url         = EUurl,                                                                                    -- launch url
	method      = 'GET',
	callback    = 'EUprices', })                                                                            -- must match httpResponses above
	-- section to launch the EnergyZero gas prices API get request (UTC timing), run between 00:00 and 01:00
	local GasPricePeriodStart=os.date("%Y-%m-%d",os.time()) .. "T00:00:00.000Z"                                                 -- always get current day data. This first price is valid from 01:00 CET
	local GASPricePeriodEnd=os.date("%Y-%m-%d", os.time()) .. "T23:59:59.999Z"            	        
	local EZurl=GASUrlStart .. 'fromDate=' .. GasPricePeriodStart .. '&tillDate=' .. GASPricePeriodEnd .. '&interval=4&usageType=' .. usageType .. '&inclBtw=false'
	domoticz.log("URL : " .. EZurl, domoticz.LOG_INFO)
	domoticz.openURL({  url         = EZurl,                                                                                    -- launch url
	method      = 'GET',
	callback    = 'EZGASprices', })                                                                         -- must match httpResponses above
end		
			end	
		else 
			if (item.isHTTPResponse) then                                                                                                       -- response to openURL (HTTP GET) request was received
				if (item.trigger=="EUprices") then
					if (item.ok) then
						if (item.isXML) then                                                                                                    -- should be XML
							StroomHourPrices.reset()                                                                                            -- remove historic prices from previous run

							if #item.xml.Publication_MarketDocument.TimeSeries == 2 then
								domoticz.data.NrRecordsStroom = 48
								for TS = 1, 2 do
									for id = 1, 24 do
										if TS == 1 then
											domoticz.log('Stroom marktprijs vandaag vanaf ' .. id-1 .. ':00 uur: ' .. item.xml.Publication_MarketDocument.TimeSeries[TS].Period.Point[id]['price.amount']/1000 .. " (" .. domoticz.utils.round((item.xml.Publication_MarketDocument.TimeSeries[TS].Period.Point[id]['price.amount']/1000 + kwhStroom) * (100 + BTW) / 100,4) .. " incl.)",domoticz.LOG_INFO)
										else
											domoticz.log('Stroom marktprijs morgen vanaf ' .. id-1 .. ':00 uur: ' .. item.xml.Publication_MarketDocument.TimeSeries[TS].Period.Point[id]['price.amount']/1000  .. " (" .. domoticz.utils.round((item.xml.Publication_MarketDocument.TimeSeries[TS].Period.Point[id]['price.amount']/1000 + kwhStroom) * (100 + BTW) / 100,4) .. " incl.)",domoticz.LOG_INFO)
										end
										StroomHourPrices.add(item.xml.Publication_MarketDocument.TimeSeries[TS].Period.Point[id]['price.amount'])
									end
								end
							else
								domoticz.data.NrRecordsStroom = 24
								for id = 1, 24 do
									domoticz.log('Stroom marktprijs vanaf ' .. id-1 .. ':00 uur: ' .. item.xml.Publication_MarketDocument.TimeSeries.Period.Point[id]['price.amount']/1000  .. " (" .. domoticz.utils.round((item.xml.Publication_MarketDocument.TimeSeries.Period.Point[id]['price.amount']/1000 + kwhStroom) * (100 + BTW) / 100,4) .. " incl.)",domoticz.LOG_INFO)
									StroomHourPrices.add(item.xml.Publication_MarketDocument.TimeSeries.Period.Point[id]['price.amount'])
								end
							end
						else
							domoticz.log('No XML received', domoticz.LOG_INFO)
						end
					else
						domoticz.log('There was a problem handling the request. Item not ok', domoticz.LOG_INFO)
						if item.statusCode == 503 then
							domoticz.log('Electriciteitsprijzen tijdelijk niet beschikbaar ivm onderhoud. HTTP statuscode: ' .. item.statusCode .. ' - ' .. item.statusText, domoticz.LOG_INFO)
						else
							domoticz.log('Foutsituatie. HTTP statuscode: ' .. item.statusCode .. ' - ' .. item.statusText, domoticz.LOG_INFO)
						end
					end
				else                                                                                                                            -- trigger was not EU electricity prices but energyzero gas prices
					if (item.ok) then
						if (item.isJSON) then                                                                                                   -- should be JSON
							GasDayPrices.reset()                                                                                                -- remove historic prices from previous run
							domoticz.data.NrRecordsGas = #item.json.Prices
							for gasid = 1, domoticz.data.NrRecordsGas do                                                                        -- add prices from current day 01:00-02:00 to next day 00:00-01:00 intervals
								domoticz.log('Gas marktprijs vandaag vanaf: ' .. gasid .. ':00 uur: ' .. item.json.Prices[gasid].price .. " (" .. domoticz.utils.round((item.json.Prices[gasid].price + m3Gas) * (100 + BTW) / 100,4) .. " incl.)",domoticz.LOG_INFO)
								GasDayPrices.add(item.json.Prices[gasid].price)
							end
						else
							domoticz.log('No JSON received', domoticz.LOG_INFO)
						end
					else
						domoticz.log('There was a problem handling the request. Returned XML item is not ok.', domoticz.LOG_INFO)
						if item.statusCode == 503 then
							domoticz.log('Gasprijzen tijdelijk niet beschikbaar ivm onderhoud. HTTP statuscode: ' .. item.statusCode .. ' - ' .. item.statusText, domoticz.LOG_INFO)
						else
							domoticz.log('Foutsituatie. HTTP statuscode: ' .. item.statusCode .. ' - ' .. item.statusText, domoticz.LOG_INFO)
						end
					end
				end
			end
		end
	end

	return commandArray
