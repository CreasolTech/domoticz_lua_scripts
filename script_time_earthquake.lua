-- Original script from User mojso: see https://www.domoticz.com/forum/viewtopic.php?t=41380
-- This scripts gets earthquake info from www.seismicportal.eu for a defined area
-- Then updates dummy alert sensor with Time, Location, Magnitude, Depth, Distance 
-- It takes the first entry (= the most recent one) and therefore runs every 5 minutes.
-- 21-03-2024 Version with some modifications by Jan Peppink, https://ict.peppink.nl
--	Make use of alert device in stead of text device.
--	Set alert color based on configurable distance.
-- 	Added links to source and map also in the device.
-- 	2024-05-08: write as lua script by CreasolTech, using globalvariables and globalfunctions
-- 	Sends notifications by Telegram

commandArray={}

local timeNow=os.date('*t')
if ((timeNow.min % 5)~=0) then return commandArray end	-- exec script every 5 minutes

dofile "scripts/lua/globalvariables.lua"
dofile "scripts/lua/globalfunctions.lua"

DEBUG_LEVEL=E_WARNING
DEBUG_LEVEL=E_DEBUG
DEBUG_PREFIX="EarthQuake: "
EARTHQUAKE_DEV="EarthQuake"	-- Create this text device by yourself!
MAXRADIUS=4					-- used to restrict data from the earthquake source
MAXDISTANCE=600				-- Max distance in km
MINMAGNITUDE=2.5			-- Min Richter magnitude
TELEGRAMMAGNITUDE=3			-- Min magnitude to send notification on smartphone
LATITUDE=45.88				-- Your latitude
LONGITUDE=12.18				-- Your longitude

--globalvariables
-- Set to your environment and preference
local mailto = 'yourname@example.com'     -- Set E-mail adres to sent to.
local alertIdx = n		-- Set to the idx of the Virtual Alert sensor you have to create for this script

if (otherdevices[EARTHQUAKE_DEV]==nil) then
	log(E_ERROR,"Please create a text device named "..EARTHQUAKE_DEV)
	return commandArray
end
local lastalertText = otherdevices[EARTHQUAKE_DEV]	-- Holds string of the previous round.
local alertText = ''

--Adjust these variables to get information about the place you want
local qMinmag = 2
local lTimediff = 3600  -- your local time 3600 equal +1 UTC time

-- Define distance for ALERTLEVEL colors
-- From dClose to radiusq ALERTLEVEL_GREY
local dClose = 750          -- From distance dCloser to dClose ALERTLEVEL_YELLOW
local dCloser = 500         -- From distance dClosest to dCloser ALERTLEVEL_ORANGE
local dClosest = 250        -- From distance 0 to closest ALERTLEVEL_RED

-- Local Functions go here =============
function titleCase( first, rest )
	return first:upper()..rest:lower()
end

-- Calculate distance using Haversine formula
local function calculateDistance(lat1, lon1, lat2, lon2)
	local R = 6371 -- Earth radius in kilometers
	local dLat = math.rad(lat2 - lat1)
	local dLon = math.rad(lon2 - lon1)
	local a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2)
	local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
	local distance = R * c
	return distance
end

-- Now start to do something ============
local fd=io.popen('curl -s "https://www.seismicportal.eu/fdsnws/event/1/query?limit=10&lat='..LATITUDE..'&lon='..LONGITUDE..'&minradius=0&maxradius='..MAXRADIUS..'&format=json&minmag='..MINMAGNITUDE..'"')
local response=assert(fd:read('*a'))
-- response = json data with list of earthquakes
json=require("dkjson")
local q=json.decode(response)
local qMag = tonumber(q.features[1].properties.mag)
local qRegion = tostring(q.features[1].properties.flynn_region)
local qTimeString = tostring(q.features[1].properties.time)
local qLat = tonumber(q.features[1].properties.lat)
local qLon = tonumber(q.features[1].properties.lon)
local qDepth = tonumber(q.features[1].properties.depth)

--local t = string.sub(cuando, 1,10)
local t = os.time{year=tonumber(qTimeString:sub(1,4)), 
month=tonumber(qTimeString:sub(6,7)), 
day=tonumber(qTimeString:sub(9,10)), 
hour=tonumber(qTimeString:sub(12,13)), 
min=tonumber(qTimeString:sub(15,16)), 
sec=tonumber(qTimeString:sub(18,19))}
-- local atLocalTime = os.date('%H:%M %a %d %B %Y', t + lTimediff) 
-- local atUTCtime = os.date('%H:%M %a %d %B %Y', t)
local atLocalTime = os.date('%d-%m-%Y %H:%M ', t + lTimediff) 
local atUTCtime = os.date('%d-%m-%Y %H:%M ', t)
-- %d-%m-%Y  %H:%M 
qRegion = string.gsub(qRegion, "(%a)([%w_']*)", titleCase)

local distance = calculateDistance(LATITUDE, LONGITUDE, qLat, qLon)
-- Round the distance to the nearest kilometer
local roundedDistance = math.floor(distance + 0.5)

--Set and format the new alertText
local alertText = tostring(  atLocalTime .. ' ' .. qRegion .. '\n' .. 'Mag: ' .. qMag .. '. Depth:' .. qDepth .. 'km Distance: ' .. roundedDistance .."km.\n"..'Location: <a href="https://maps.google.com/?q=' .. qLat .. ',' .. qLon .. '" target="_new">Map</a>')

--[[
--Set and format the new mail message				
local message = tostring('Location: ' .. qRegion .. '<br>' ..
'Magnitude: ' .. qMag .. '<br>' ..
'Depth: ' .. qDepth .. 'km<br>' ..
'UTC Time: ' .. atUTCtime .. '<br>' ..
'Locale Time: ' .. atLocalTime .. '<br>' ..
'Distance: ' .. roundedDistance .. 'km.<br>'..
'Coordinates: ' .. qLat .. ','.. qLon .. '<br>' ..
'<a href="https://maps.google.com/?q=' .. qLat .. ',' .. qLon .. '">Location</a>' .. '<br>' ..
'<a href="https://www.seismicportal.eu/">Source</a>' .. '<br>')
]]

-- Only update and sent message when info has changed. and 
if (alertText ~= lastalertText and roundedDistance <= MAXDISTANCE) then
	commandArray['UpdateDevice']=otherdevices_idx[EARTHQUAKE_DEV]..'|'.. math.floor(qMag-1) ..'|'..alertText
	local priority=E_INFO
	if (qMag>=TELEGRAMMAGNITUDE) then
		priority=E_CRITICAL
	end
	log(priority,"Mag="..qMag.." Dist="..roundedDistance.."km "..qRegion.."\nhttps://maps.google.com/?q=" .. qLat .. ',' .. qLon )
end			
return commandArray
