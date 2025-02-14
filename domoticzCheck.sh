#!/bin/bash
#check that domoticz is running, and restart it if no process is running since TIME_DOMOTICZ_UNAVAILABLE minutes
#this script must be called by /etc/rc.local : put the following line in /etc/rc.local, before "exit 0" removing the first character #
#/usr/local/sbin/domoticzCheck.sh &

TIME_DOMOTICZ_UNAVAILABLE=5			#minutes: restart domoticz if unavailable since 5 minutes
CHECK_PLUGINS=1						#check that all python plugins are running correctly
DOMOTICZ_LOG=/var/log/domoticz.log	#domoticz log file
DOMOTICZ_LOG_STRING='(WebServer.* thread seems to have ended unexpectedly|received fatal signal 11)'	#regular expression (for egrep) to search in the last log lines to determines if a plugin has been stopped
DOMOTICZ_LOG_STRING2='( seems to have ended unexpectedly|Domoticz and DomoticzEx modules both found in interpreter|Error: DDS238: Try=3)'      

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

function restartDomoticz () {
	if [ -n "`pidof domoticz`" ]; then
		killall domoticz
		sleep 10
	fi
	if [ -n "`pidof domoticz`" ]; then
		killall -9 domoticz
		sleep 10
	fi
	if [ $(( `date +%s` - $lastrestart )) -lt 600 ]; then
		mbpoll -b9600 -Pnone -o1 -mrtu -a3 -0 -1 -r0 -c2 /dev/ttyUSBheatpump
		if [ $? -ne 0 ]; then
			echo "Last restart less than 600s ago and mbpoll returns error => reboot!" >>/tmp/domoticzCheck.log
			/usr/sbin/reboot	
		fi
	fi

	#disable hyundai kia plugin
	sqlite3 /home/pi/domoticz/domoticz.db 'update Hardware set Enabled=0 where ID=31;'
	service domoticz restart
	lastrestart=`date +%s`
}

logerrorscount=0
logcount
lastrestart=0
while [ 1 ]; do
	if [ -z "`pidof domoticz`" ]; then
		count=$(( $count + 1 ))
		echo "`date` : domoticz not running since ${count} minutes" >>/tmp/domoticzCheck.log
	else
		# Domoticz process is running
		#check that web UI respond....
		curl -s -m5 http://127.0.0.1:8080 >/dev/null
		if [ $? -eq 28 ]; then
			echo "`date` : domoticz not responding" >>/tmp/domoticzCheck.log
			count=$(( $count + 2 ))
		else
			count=0
		fi
		if [ "a${CHECK_PLUGINS}" == "a1" ]; then
			logcount
			if [ $loglines -gt 0 ]; then
				# Check that domoticz_hyundai_kia plugin is running correctly
				ret=`tail -n $loglines ${DOMOTICZ_LOG} |egrep "${DOMOTICZ_LOG_STRING}"`
				ret2=`tail -n $loglines ${DOMOTICZ_LOG} |egrep "${DOMOTICZ_LOG_STRING2}"`
				if [ -n "$ret" ]; then
					logerrorscount=$(( $logerrorscount +1 ))
					if [ $logerrorscount -ge 2 ]; then
						echo -e "`date` : Restart domoticz because at more than 2 errors found:"  >>/tmp/domoticzCheck.log
						echo "$ret" >>/tmp/domoticzCheck.log
						echo "=====================================" >>/tmp/domoticzCheck.log
						#echo "Restarting domoticz because log file contain the selected string"
						service domoticz restart
						logerrorscount=0
					fi
				elif [ -n "${ret2}" ]; then
					logerrorscount=$(( $logerrorscount +1 ))
					if [ $logerrorscount -ge 10 ]; then
						echo "`date` : Restart domoticz because at least one plugin thread has ended:"  >>/tmp/domoticzCheck.log
						echo "${ret2}" >>/tmp/domoticzCheck.log
						echo "=====================================" >>/tmp/domoticzCheck.log
						restartDomoticz
						logerrorscount=0
					fi
				else
					#error message not found
					if [ $logerrorscount -gt 0 ]; then
						logerrorscount=$(( $logerrorscount -1 ))
					fi
					#echo "`date` : No errors"   >>/tmp/domoticzCheck.log
				fi
				if [ $logerrorscount -ne 0 ]; then
					echo "logerrorscount=$logerrorscount"   >>/tmp/domoticzCheck.log
				fi
			fi
		fi
	fi
	
	if [ $count -ge $TIME_DOMOTICZ_UNAVAILABLE ]; then
		#echo "Restart domoticz after 5 minutes it is off"
		echo "`date` : Restart domoticz because not active since ${TIME_DOMOTICZ_UNAVAILABLE} minutes" >>/tmp/domoticzCheck.log
		restartDomoticz
	fi

	# check that /var/log partition is not full
	df /var/log>/dev/null 2>&1
	if [ $? -eq 0 ]; then
		# partition exists
		perc=`df /var/log|tail -n 1|awk '{print $5}'|tr -d %`
		if [ $perc -gt 80 ];then
			# Erase the 5 greater files
			cd /var/log
			for file in `ls -Sr /var/log |tail -n 5`; do > $file; done
			#restart domoticz to flush logfile
			service rsyslog restart
			restartDomoticz
		fi
	fi
	# check that /tmp partition is not full
	df /tmp>/dev/null 2>&1
	if [ $? -eq 0 ]; then
		# partition exists
		perc=`df /tmp|tail -n 1|awk '{print $5}'|tr -d %`
		if [ $perc -gt 80 ];then
			# Erase the 10 greater files
			cd /tmp
			rm `ls -Sr /tmp |tail -n 10`
			#remove video and pictures
			rm *.mp4 *.jpg *.png 2>/dev/null
			# now restart domoticz to free the domoticz.log file and let domoticz write a new log
			restartDomoticz
		fi
	fi
	sleep 60
done

