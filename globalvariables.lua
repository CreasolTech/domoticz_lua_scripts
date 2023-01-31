TELEGRAM_CHATID="-1234567890123"
TELEGRAM_DEBUG_CHATID="12345678"
TELEGRAM_TOKEN="1234567890:abcdefghijkakdfjak239rjas9djf9jdfaf"
DOMOTICZ_URL="http://127.0.0.1:8080"	

-- used by alarm_sendsnapshot.sh to send fetch videos from ipcam and send by Telegram
IPCAM_USER="admin"
IPCAM_PASS="verysecret"

TEMPERATURE_OUTDOOR_DEV='TempOutdoor'		-- temperature from weather station (including relative humidity and, if available, pressure
RAINDEV='Rain'          -- name of device that shows the rain rate/level
WINDDEV='Wind'          -- name of device that shows the wind speed/gust
VENTILATION_DEV=''		-- controlled mechanical ventilation machine: Domoticz device to turn machine ON/OFF
VENTILATION_COIL_DEV="" -- coil to heat/cool air: will be activated only if Heat Pump is ON
VENTILATION_DEHUMIDIFY_DEV=''   -- dehumification command for the ventilation system
HEATPUMP_DEV=""         -- heat pump device On/Off state

-- Windguru - If interested, register your station to https://stations.windguru.cz/register.php?id_type=16 to publish data on WebGuru website
WINDGURU_USER=''        -- windguru station UID, if you want to publish your wind data on WindGuru website, else '' . 
WINDGURU_PASS='' 		-- windguru station password

-- Debug levels
E_CRITICAL=0
E_ERROR=1
E_WARNING=2
E_INFO=3
E_DEBUG=4

