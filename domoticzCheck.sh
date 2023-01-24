#!/bin/bash
#check that domoticz is running, and restart it if no process is running since TIME_DOMOTICZ_UNAVAILABLE minutes
#this script must be called by /etc/rc.local : put the following line in /etc/rc.local, before "exit 0" removing the first character #
#/usr/local/sbin/domoticzCheck.sh &

TIME_DOMOTICZ_UNAVAILABLE=5			#minutes: restart domoticz if unavailable since 5 minutes
CHECK_PLUGINS=1						#check that all python plugins are running correctly
DOMOTICZ_LOG=/var/log/domoticz.log	#domoticz log file
DOMOTICZ_LOG_STRING='(WebServer.* thread seems to have ended unexpectedly| seems to have ended unexpectedly|received fatal signal 11)'	#regular expression (for egrep) to search in the last log lines to determines if a plugin has been stopped

count=0
loglinesold=0
loglinesnew=0
loglines=0

function logcount () {
	if [ -f "${DOMOTICZ_LOG}" ]; then
		loglinesold=${loglinesnew}
		loglinesnew=`wc -l ${DOMOTICZ_LOG}|cut -d ' ' -f 1`
		if [ "a${loglinesold}" == "a0" ]; then loglinesold=${loglinesnew} ; fi
		loglines=$(( ${loglinesnew} - ${loglinesold} ))
		if [ $loglines -lt 0 ]; then loglines=0; fi
	else
		loglines=0
	fi
}

logerrorscount=0
logcount
while [ 1 ]; do
	if [ -z "`pidof domoticz`" ]; then
		count=$(( $count + 1 ))
		echo "`date` : domoticz not running since ${count} minutes" >>/tmp/domoticzCheck.log
		if [ $count -ge $TIME_DOMOTICZ_UNAVAILABLE ]; then
			#echo "Restart domoticz after 5 minutes it is off"
			echo "`date` : Restart domoticz because not active since ${TIME_DOMOTICZ_UNAVAILABLE} minutes" >>/tmp/domoticzCheck.log
			service domoticz restart
		fi
	else
		# Domoticz process is running
		count=0
		if [ "a${CHECK_PLUGINS}" == "a1" ]; then
			logcount
			if [ $loglines -gt 0 ]; then
				# Check that domoticz_hyundai_kia plugin is running correctly
				if [ -n "`tail -n $loglines ${DOMOTICZ_LOG} |egrep \"${DOMOTICZ_LOG_STRING}\"`" ]; then
					logerrorscount=$(( $logerrorscount +1 ))
					if [ $logerrorscount -ge 5 ]; then
						echo "`date` : Restart domoticz because at least one plugin thread has ended"  >>/tmp/domoticzCheck.log
						#echo "Restarting domoticz because log file contain the selected string"
						service domoticz restart
						logerrorscount=0
					fi
				else
					#error message not found
					if [ $logerrorscount -gt 0 ]; then
						logerrorscount=$(( $logerrorscount -1 ))
					fi
				fi
				echo "logerrorscount=$logerrorscount"
			fi
		fi
	fi
	sleep 60
done

