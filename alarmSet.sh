#!/bin/bash
# Written by Creasol https://creasol.it/products
# set a variable indicating the state of the alarm
# Called by some scenes

echo ================================================================= >>/tmp/alarmSet.log
echo $* >>/tmp/alarmSet.log
echo "pid=$$" >> /tmp/alarmSet.log
date >>/tmp/alarmSet.log
whoami >>/tmp/alarmSet.log
ps aux >>/tmp/alarmSet.log

. /home/pi/domoticz/scripts/lua/globalvariables.lua # some variables common to all scripts


#device idx (check Setup -> Devices) of all sirens, buzzers, lights that must be disabled when alarm is disactivated, separated by a space
#In case of alarm, sirens, lights, buzzers, are activated. Disabling the alarm by pushbutton or smartphone, the following devices will be switched-OFF
SIREN_IDX="154 52 259 239 261 828 831"	

alarmLevel=$1

if [ $# -eq 1 ]; then
	if [[ "a$alarmLevel" == "a1" || "a$alarmLevel" == "a2" || "a$alarmLevel" == "a4" || "a$alarmLevel" == "a8" || "a$alarmLevel" == "a16" ]]; then
#		1=ALARM_OFF
#		2=ALARM_DAY
#		4=ALARM_NIGHT
#		8=ALARM_AWAY
#		16=ALARM_TEST
		if [ $alarmLevel==8 ]; then alarmLevel=2; fi	#DEBUG: avoid setting ALARM_AWAY
		#set variable alarmLevel to the new level (Off, Day, Night, Away)
		curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=updateuservariable&vname=alarmLevel&vtype=0&vvalue=$alarmLevel"
		#set variable alarmLevelNew to 1 to indicate the alarmLevel was changed
		curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=updateuservariable&vname=alarmLevelNew&vtype=0&vvalue=1"
		if [[ "a$alarmLevel" == "a1" || "a$alarmLevel" == "a16" ]]; then
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



