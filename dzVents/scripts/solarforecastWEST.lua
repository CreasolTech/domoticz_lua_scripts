-- solarforecast dzVents script
-- This script should be placed in domoticz/scripts/dzVents/scripts , and use the forecast.solar free (public) API to get PV Wh production for the next 24-48 hours.
-- It does not need to register to the website.
-- See the CONFIGURATION section below 
return {
  on = {
    timer = {
        'at *:56' 	-- execute every hour, at xx:54
    },
    httpResponses = {
      'solarforecastWEST' -- must match with the callback passed to the openURL command
    }
  },
  logging = {
    level = domoticz.LOG_INFO,
    marker = 'get solar forecast',
  },
  execute = function(domoticz, item)

      -- #############################  CONFIGURATION ###########################
	  -- You have to manually create two devices (Setup -> Hardware -> Add virtual device):
	  -- 1. device type "Managed counter" and set it as "Energy generated". Its IDX should be written in the idxSolarForecastCounter variable below
	  -- 2. device type "Custom sensor", with axis set to "Wh". Its IDX should be written in the idxSolarForecast variable below

      local idxSolarForecastCounter=2482  	-- device with 24h forecast: type 'Managed counter', Energy generated
      local idxSolarForecast=2483  			-- device holding the forecast for the next hour: type 'Custom sensor', axis: 'Wh'
	  local latLonDeclineAzimuthPower='45.8812/12.1833/15/90/4.5'		-- your latitude, longitude, PV declination, PV azimuth, PV power separated by slash
	  -- 45.8812/12.1833/15/90/4.5 means 4.5kWp photovoltaic, 15° inclination, 90° azimuth => west direction (-90° => east). Coordinates: 45.xxx latitude, 12.xxx longitude
	  --
      -- ##########################  END of CONFIGURATION ########################


    if (item.isTimer) then
		print("WEST")
      domoticz.openURL({
        url = 'https://api.forecast.solar/estimate/watthours/period/'..latLonDeclineAzimuthPower,
        method = 'GET',
        callback = 'solarforecastWEST', -- see httpResponses above.
      })
    end

    if (item.isHTTPResponse) then

      if (item.ok) then
        --domoticz.log('item.data ' .. item.data .. '***************************', domoticz.LOG_INFO)
        
        if (item.isJSON) then
            domoticz.utils.dumpTable(item)
            
            local messagetype=item.json.message["type"]
            domoticz.log("message type" .. messagetype, domoticz.LOG_INFO) 
            
            if messagetype=="success" then
                local currentHR=os.date("%Y-%m-%d %H:00:00")
                local oneHRahead=os.date("%Y-%m-%d %H:00:00",os.time()+1*60*60)
                local twoHRahead=os.date("%Y-%m-%d %H:00:00",os.time()+2*60*60)
                local forecastCurrentHR=tonumber(item.json.result[currentHR])
                if forecastCurrentHR==nil then
                    forecastCurrentHR=0 
                end    
                local forecastOneHR=tonumber(item.json.result[oneHRahead])
                if forecastOneHR==nil then
                    forecastOneHR=0 
                end    
                local forecastTwoHR=tonumber(item.json.result[twoHRahead])    
                if forecastTwoHR==nil then
                    forecastTwoHR=0 
                end    
                domoticz.log("solar forecast for next three hours :" .. forecastCurrentHR .. "+" .. forecastOneHR .. " + " .. forecastTwoHR .. " WattHR", domoticz.LOG_INFO) 
                domoticz.devices(idxSolarForecast).updateCustomSensor(forecastOneHR)
                
                local updateHour=0
                for id = 1, 24 do
                    if id<10 then
                        updateHour="0"..tostring(id)
                    else 
                        updateHour=tostring(id)
                    end    
                    domoticz.devices(idxSolarForecastCounter).updateHistory(os.date("%Y-%m-%d ")..updateHour..":00:00","0;0")
                    domoticz.devices(idxSolarForecastCounter).updateHistory(os.date("%Y-%m-%d ",os.time()+24*60*60)..updateHour..":00:00","0;0")
                end    
                    
                local response=item.json.result
                for datehour,value in pairs(response) do
                    domoticz.log("solar forecast date "..domoticz.utils.stringSplit(datehour)[1].." hour "..domoticz.utils.stringSplit(domoticz.utils.stringSplit(datehour)[2],":")[1].." value "..value,domoticz.LOG_INFO)
                    local previousHour=domoticz.utils.stringSplit(domoticz.utils.stringSplit(datehour)[2],":")[1]-1
                    if previousHour<10 then 
                        previousHour="0"..tostring(previousHour)
                    else
                        previousHour=tostring(previousHour)
                    end    
                    domoticz.log("previousHour "..previousHour)    
                    if value>0 then
                        sensorDateHour=domoticz.utils.stringSplit(datehour)[1].." "..domoticz.utils.stringSplit(domoticz.utils.stringSplit(datehour)[2],":")[1]..":00:00"
                        sValueStr="0;"..value
                        domoticz.log("sensorDateHour "..sensorDateHour.." sValueStr "..sValueStr,domoticz.LOG_INFO)
                        domoticz.devices(idxSolarForecastCounter).updateHistory(sensorDateHour,sValueStr)
                        if sensorDateHour==currentHR then
                            domoticz.devices(idxSolarForecastCounter).updateCounter(value)
                        end    
                    end       
                end
            else
                domoticz.log("no successfull message", domoticz.LOG_INFO)
            end    
        else
            domoticz.log('is not json', domoticz.LOG_INFO) 
        end    
      else
        domoticz.log('There was a problem handling the request', domoticz.LOG_INFO)
        domoticz.log(item, domoticz.LOG_INFO)
      end

    end

  end
}
