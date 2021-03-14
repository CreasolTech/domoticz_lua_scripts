#!/bin/bash
# Written by Creasol https://creasol.it/products
# set a variable indicating the state of the alarm
# Called by some scenes

. /home/pi/domoticz/scripts/lua/globalvariables.lua # some variables common to all scripts


#device idx (check Setup -> Devices) of all sirens that must be disabled when alarm is disactivated, separated by a space
SIREN_IDX="154 52 72 73 259 239 261 828 831"	

if [ $# -eq 1 ]; then
	if [[ "a$1" == "a1" || "a$1" == "a2" || "a$1" == "a4" || "a$1" == "a8" || "a$1" == "a16" ]]; then
#		1=ALARM_OFF
#		2=ALARM_DAY
#		4=ALARM_NIGHT
#		8=ALARM_AWAY
#		16=ALARM_TEST
		curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=updateuservariable&vname=alarmLevel&vtype=0&vvalue=$1"
		curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=updateuservariable&vname=alarmLevelNew&vtype=0&vvalue=1"
		if [[ "a$1" == "a1" || "a$1" == "a16" ]]; then
			# set alarm to OFF or TEST
			#disable sirens, if on, so updating the device calls script_device_alarm.lua that restore alarmStatus.
			for idx in ${SIREN_IDX}; do
				curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=switchlight&idx=${idx}&switchcmd=Off" 2>&1 >>/tmp/alarm.log	
			done
			curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=updateuservariable&vname=alarmStatus&vtype=0&vvalue=0"
		fi
	else
		echo "Argument error: should be 1, 2, 4, 8 or 16"
	fi
else
	echo "Syntax error: should be called with 1 argument set to 1, 2, 4, 8 or 16"
fi



