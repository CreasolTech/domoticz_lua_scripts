-- This scripts gets earthquake info from www.seismicportal.eu for a defined area
-- It runs every 5 minutes, and gets the most recent earthquakecent info displaying 
--   Time, Location, Magnitude, Depth, Distance on an alert device that should be 
--   created manually.

-- Requirements: lua-dkjson lua-md5
--
-- Written by Paolo Subiaco https://www.creasol.it/domotics
-- Original script from User mojso: see https://www.domoticz.com/forum/viewtopic.php?t=41380
-- 21-03-2024 Version with some modifications by Jan Peppink, https://ict.peppink.nl
--	Make use of alert device in stead of text device.
--	Set alert color based on configurable distance.
-- 	Added links to source and map also in the device.
-- 	2024-05-08: write as lua script by CreasolTech, using globalvariables and globalfunctions
-- 	Sends notifications by Telegram

commandArray={}

local DEBUG=0
--DEBUG=1	-- enable debugging (execute every minute instead of every 5)
local timeNow=os.date('*t')
if ((timeNow.min % 5)~=0 and DEBUG==0) then return commandArray end	-- exec script every 5 minutes

dofile "scripts/lua/globalvariables.lua"
dofile "scripts/lua/globalfunctions.lua"

DEBUG_LEVEL=E_WARNING
DEBUG_LEVEL=E_DEBUG		-- uncomment to get more messages in the log
DEBUG_PREFIX="EarthQuake: "
EARTHQUAKE_DEV="EarthQuake"	-- Create this text device by yourself!
MAXRADIUS=8					-- used to restrict data from the earthquake source (default 4)
MAXDISTANCE=1000			-- Max distance in km
MINMAGNITUDE=3.5			-- Min Richter magnitude
TELEGRAMMAGNITUDE=4.2		-- Min magnitude to send notification on smartphone
LATITUDE=45.88				-- Your latitude
LONGITUDE=12.18				-- Your longitude
MAXAGE=24					-- Remove quakes earthquakes older than MAXAGE hours
LOCALTIMEDIFF=3600			-- Difference time from UTC (3600 for GMT+1)

if (DEBUG~=0) then 
	MAXAGE=240
	MAXDISTANCE=2000
end


if (otherdevices[EARTHQUAKE_DEV]==nil) then
	log(E_ERROR,"Please create a text device named "..EARTHQUAKE_DEV)
	return commandArray
end
local lastalertText = otherdevices[EARTHQUAKE_DEV]	-- Holds string of the previous round.
local alertText = ''

--Adjust these variables to get information about the place you want

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
	return math.floor(distance+0.5)
end

-- Now start to do something ============
local fd=io.popen('curl -s "https://www.seismicportal.eu/fdsnws/event/1/query?limit=10&lat='..LATITUDE..'&lon='..LONGITUDE..'&minradius=0&maxradius='..MAXRADIUS..'&format=json&minmag='..MINMAGNITUDE..'"')
local response=assert(fd:read('*a'))
io.close(fd)
-- response = json data with list of earthquakes
json=require("dkjson")
local q=json.decode(response)
if (q==nil) then 
	log(ERROR,"Error: empty response from the seismicportal.eu website")
	return commandArray
end
local qMag = tonumber(q.features[1].properties.mag)
local qRegion = tostring(q.features[1].properties.flynn_region)
local qTimeString = tostring(q.features[1].properties.time)
local qLat = tonumber(q.features[1].properties.lat)
local qLon = tonumber(q.features[1].properties.lon)
local qDepth = tonumber(q.features[1].properties.depth)
local qUnid = tostring(q.features[1].properties.unid)

local checkText=qTimeString..qLat..qLon..qDepth..qMag
-- create a Domoticz variable if zEarthQuake does not exist
checkVar('zEarthQuake',2,"")
if (uservariables['zEarthQuake']==checkText.."AAAA" and DEBUG==0) then return commandArray end	-- earthquake alert already processed
-- new alert, or debug is active
commandArray["Variable:zEarthQuake"]=checkText

--local t = string.sub(cuando, 1,10)
local t = os.time{year=tonumber(qTimeString:sub(1,4)), 
month=tonumber(qTimeString:sub(6,7)), 
day=tonumber(qTimeString:sub(9,10)), 
hour=tonumber(qTimeString:sub(12,13)), 
min=tonumber(qTimeString:sub(15,16)), 
sec=tonumber(qTimeString:sub(18,19))}

if ((os.time()-t)<MAXAGE*3600) then
	local atLocalTime = os.date('%d-%m-%Y %H:%M ', t + LOCALTIMEDIFF) 
	-- %d-%m-%Y  %H:%M 
	qRegion = string.gsub(qRegion, "(%a)([%w_']*)", titleCase)

	local distance = calculateDistance(LATITUDE, LONGITUDE, qLat, qLon)
	
	fd=io.popen('curl -s "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=16&lat='..qLat..'&lon='..qLon..'"')
	local response=assert(fd:read('*a'))
	io.close(fd)
	-- response = json data with location information
	local q=json.decode(response)
	local address=''
	if (q ~= nil and q.address ~= nil and q.address.village ~= nil and q.address.county ~= nil) then 
		address = q.address.village..', '..q.address.county
	end
	if (string.len(address)<6) then address=qRegion end
	
	--Set and format the new alertText
	local alertText = tostring(  atLocalTime .. ' ' .. address .. '\n' .. 'Mag: ' .. qMag .. '. Depth:' .. qDepth .. 'km Distance: ' .. distance ..'km. <a href="https://maps.google.com/?q=' .. qLat .. ',' .. qLon .. '" target="_new" style="color: blue;">Map</a> <a href="https://www.seismicportal.eu/eventdetails.html?unid=' .. qUnid .. '" target="new" style="color: blue;">Detail</a>')

	-- Only update and sent message when info has changed. and 
	if (DEBUG~=0 or (alertText ~= lastalertText and distance <= MAXDISTANCE)) then
		commandArray['UpdateDevice']=otherdevices_idx[EARTHQUAKE_DEV]..'|'.. math.floor(qMag-1) ..'|'..alertText
		local priority=E_INFO
		if (qMag>=TELEGRAMMAGNITUDE) then
			priority=E_CRITICAL
		end
		log(priority,"Mag="..qMag.." Dist="..distance.."km "..address.."\nhttps://maps.google.com/?q=" .. qLat .. ',' .. qLon )
	end
elseif (otherdevices[EARTHQUAKE]~='Nothing') then
	-- event age is older than MAXAGE => remove it
	commandArray['UpdateDevice']=otherdevices_idx[EARTHQUAKE_DEV]..'|0|Nothing'
end			
return commandArray
