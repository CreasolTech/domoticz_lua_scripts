-- scripts/lua/config_fireAlarm.lua - Configuration file for the fire alarm script
-- Written by CreasolTech, https://www.creasol.it
--
ROOMS={
-- 	 RoomName			SensorName				incTemperature
	{"Kitchen", 		"Temp_Cucina", 			0.3},
	{"Living",			"Temp_Soggiorno",		0.3},
	{"Office",			"Temp_Studio",			0.3},
	{"Laundry",			"Temp_Lavanderia",		0.3},
	{"Garage",			"Temp_Garage",			0.3},
	{"Wallbox",			"Temp_Wallbox",			0.3},
	{"Cellar",			"TempRH_Cantina",		0.3},
	{"Bathroom",		"Temp_Bagno",			1},
	{"Bedroom",			"Temp_Camera",			0.3},
	{"Bedroom2",		"TempRH_Camera",		0.3},
	{"BedroomVale",		"Temp_Camera_Valentina",0.3},
	{"BedroomGuests",	"Temp_Camera_Ospiti",	0.3},
	{"IroningRoom",		"Temp_Stireria",		0.3},
	{"Attic",			"Temp_Sottotetto",		0.3},
	{"SolarInverter",	"Inverter - Temperature", 2}
}
