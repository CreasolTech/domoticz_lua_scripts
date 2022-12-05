#!/bin/bash
# Written by Creasol https://creasol.it/products linux@creasol.it
# Ping one host to check that router works correctly. If it stop working for 5 minutes, activate/disactivate a relay on Domoticz to reset router
#

ROUTER_RELAY_IDX="680" 		#device idx (Domoticz Settings->Devices) of the relay to activate/disactivate in case of missing internet connection	
ROUTER_RELAY_RESET="On"		#On to enable router relay, Off to disable router relay in case of missing internet connection
ROUTER_RELAY_RESTORE="Off"	#On/Off value in normal mode for the domoticz output
ROUTER_RELAY_RESET_TIME=10	#Seconds to keep router in reset 
ROUTER_BOOTING_TIME=100		#Seconds: time needed by router to start and establish a connection
NETWORK_SERVER1=8.8.8.8		#Send ping to this host
NETWORK_SERVER2=1.1.1.1		#If the first does not work, try to send ping to this host
NETWORK_CHECK_INTERVAL=20	#seconds: interval to send pings (must be > 3s)
NETWORK_RESET_AFTER=80		#seconds: if pings to the two servers fail for this time, initiate a router reset.
DOMOTICZ_URL='http://127.0.0.1:8080' 	#Domoticz URL
LOGFILE="/tmp/netwatchdog.log"
DEBUG=0						# 0=normal function. 1=print messages on the console, and avoid resetting anything



if [ $DEBUG -ne 0 ]; then
	NETWORK_RESET_AFTER=15	#reduce time before sending the reset command to 30s
#	NETWORK_SERVER1=1.2.3.4	#set an invalid IP that does not answer to ping, to simulate internet down
#	NETWORK_SERVER2=5.6.7.8	#set an invalid IP that does not answer to ping, to simulate internet down
fi

if [ ${NETWORK_CHECK_INTERVAL} -lt 3 ]; then
	echo "Error: NETWORK_CHECK_INTERVAL must be >=3 seconds"
	exit
fi
#check that curl exists
which curl >/dev/null
if [ $? -ne 0 ]; then
	echo "Error: please install curl package (e.g. sudo apt install curl )"
	exit
fi

function setCurrentDateTime() {
	internetBlocked=`date +%s`
}

function domoticzReset() {
	# initiate a reset
	echo "`date` Initiate reset command to Domoticz...." >>$LOGFILE
	cmd="curl -s ${DOMOTICZ_URL}/json.htm?type=command&param=switchlight&idx=${ROUTER_RELAY_IDX}&switchcmd=${ROUTER_RELAY_RESET}"
	if [ ${DEBUG} -ne 0 ]; then 
		echo "Exec: $cmd"
		$cmd
	else
		$cmd >>$LOGFILE
	fi

	#wait
	sleep ${ROUTER_RELAY_RESET_TIME}

	# restore relay to normal function
	cmd="curl -s ${DOMOTICZ_URL}/json.htm?type=command&param=switchlight&idx=${ROUTER_RELAY_IDX}&switchcmd=${ROUTER_RELAY_RESTORE}"
	if [ ${DEBUG} -ne 0 ]; then 
		echo "Exec: $cmd"
		$cmd
	else
		$cmd >/dev/null
	fi

	#wait for router boooting time
	echo "`date` Wait ${ROUTER_BOOTING_TIME}s for router restarting..." >>$LOGFILE
	sleep ${ROUTER_BOOTING_TIME}	# wait for router to start 

	setCurrentDateTime	# set internetBlocked=current time
}

if [ $DEBUG -ne 0 ]; then
	echo "Debug mode: skip waiting for ROUTER_BOOTING_TIME (${ROUTER_BOOTING_TIME}s)"
else
	sleep ${ROUTER_BOOTING_TIME}	# wait for router to start 
fi
setCurrentDateTime	# set internetBlocked=current time

#loop forever
while [ 1 ]; do
	pingfailed=0
	if [ $DEBUG -ne 0 ]; then
		ping -c1 -w1 ${NETWORK_SERVER1} |grep "bytes from"
	else
		ping -c1 -w1 ${NETWORK_SERVER1} >/dev/null
	fi
	if [ $? -ne 0 ]; then
		# ping failure: try second server
		echo "`date` Ping to ${NETWORK_SERVER1} failed" >>$LOGFILE
		if [ $DEBUG -ne 0 ]; then
			ping -s1450 -c1 -w1 ${NETWORK_SERVER2} |grep "bytes from"
		else
			ping -s1450 -c1 -w1 ${NETWORK_SERVER2} >/dev/null
		fi
		if [ $? -ne 0 ]; then
			pingfailed=1
			# ping failure even to the second server
			echo "`date` Ping to ${NETWORK_SERVER2} failed" >>$LOGFILE
			# check internetBlocked
			if (( $(( `date +%s` - ${internetBlocked} )) > ${NETWORK_RESET_AFTER} )); then
				domoticzReset
			fi
		else
			setCurrentDateTime	# set internetBlocked=current time
		fi
	else
		setCurrentDateTime	# set internetBlocked=current time
	fi
	if [ $DEBUG -ne 0 ]; then
		if [ $pingfailed -eq 1 ]; then
			# print stat
			echo "Time since last successfull ping: $(( `date +%s` - ${internetBlocked} ))"
		fi
	fi
	sleep ${NETWORK_CHECK_INTERVAL}
done
