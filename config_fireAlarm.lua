-- scripts/lua/config_fireAlarm.lua - Configuration file for the fire alarm script
-- Written by CreasolTech, https://www.creasol.it
--
ROOMS={
-- 	 RoomName			SensorName		incTemperature	maxTemperature
	{"Kitchen", 		"Temp_Cucina", 			0.4, 	30},
	{"Living",			"Temp_Soggiorno",		0.4, 	30},
	{"Office",			"Temp_Studio",			0.6, 	30},
	{"Laundry",			"Temp_Lavanderia",		2, 		32},		-- DS1820 sensor behind the washer machine socket
	{"Garage",			"Temp_Garage",			0.6, 	35},
--	{"Wallbox",			"Temp_Wallbox",			0.3, 	30},
	{"Cellar",			"TempRH_Cantina",		0.4, 	24},
	{"Bathroom",		"Temp_Bagno",			1, 		30},
	{"Bedroom",			"Temp_Camera",			0.4, 	30},
	{"Bedroom2",		"TempRH_Camera",		0.6, 	30},
	{"BedroomVale",		"Temp_Camera_Valentina",0.4, 	30},
	{"BedroomGuests",	"Temp_Camera_Ospiti",	0.4, 	30},
	{"IroningRoom",		"Temp_Stireria",		1.5, 	35},	-- DS1820 sensor behind the power outlet connected to iron machine
	{"Attic",			"Temp_Attic",			1.2, 	40},
	{"Attic2",			"Meteo_Attic",			1.2, 	40},
	{"SolarInverter",	"Inverter - Temperature", 10, 	70}
}
