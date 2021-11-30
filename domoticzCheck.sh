#!/bin/bash
#check that domoticz is running, and restart it if no process is running since TIME_DOMOTICZ_UNAVAILABLE minutes
#this script must be called by /etc/rc.local : put the following line in /etc/rc.local, before "exit 0" removing the first character #
#/usr/local/sbin/domoticzCheck.sh &

TIME_DOMOTICZ_UNAVAILABLE=5	#minutes: restart domoticz if unavailable since 5 minutes
count=0
while [ 1 ]; do
	if [ -z "`pidof domoticz`" ]; then
		count=$(( $count + 1 ))
		if [ $count -ge $TIME_DOMOTICZ_UNAVAILABLE ]; then
			#echo "Restart domoticz after 5 minutes it is off"
			echo "`date` : Restart domoticz because not active since ${TIME_DOMOTICZ_UNAVAILABLE} minutes" >>/tmp/domoticzCheck.log
			service domoticz restart
		fi
	else
		count=0
	fi
	sleep 60
done

