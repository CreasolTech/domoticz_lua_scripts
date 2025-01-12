#!/bin/bash
# Written by Creasol - https://www.creasol.it
# When called by domoticz or executed from the shell, it extract a snapshot from IPCAMs (from camera snapshot, if available, or from media stream)
# and send it by Telegram.
# Prerequisites: 
# apt-get update; apt-get install ffmpeg imagemagick curl jq
#Syntax: scripts/lua/alarm_sendsnapshot.sh IP_Camera1 IP_Camera2 Message
#for example: scripts/lua/alarm_sendsnapshot.sh 192.168.3.205 192.168.3.206 PIR_Garage

DEBUG=0		# Set to 0 to disable verbose output to the log, or 1 to enable verbosity

function log () {
	echo "`date '+%H:%M:%S.%N'` $*" >>/tmp/alarm_sendsnapshot.log
}

ipcamera1=$1
ipcamera2=$2
message=$3

log `date`
log "$0 $ipcamera1 $ipcamera2 $message" 

. /home/pi/domoticz/scripts/lua/globalvariables.lua 2>/dev/null  # some variables and functions common to all scripts

TELEGRAMSCRIPT='/home/pi/domoticz/scripts/telegramSendText.sh'

#SNAPURL='http://192.168.3.201:8088/snap.jpg'  #snapshot URL: if camera does not support snapshot, comment this variable
#MEDIAURL='192.168.3.201:554/mpeg4cif' #low quality stream
MEDIAURL1="${ipcamera1}/mpeg4cif"	#high quality stream

MEDIAURL2="${ipcamera2}/mpeg4cif"	#high quality stream

#Used to get light status, and set lights ON before snapshot and OFF after a while...
DOMOTICZ_URL='http://127.0.0.1:8080'

#get image snapshot, if available, or build a snapshot from video stream
if [ -n "${ipcamera1}" ]; then
	if [ -n "$SNAPURL1" ]; then
		#IPCam supported snapshot
		curl -s -o /tmp/alarm_snapshot.jpg ${SNAPURL1} #Get snapshot from IP camera (if supported)
	elif [ -n "$MEDIAURL1" ]; then
		#IPCam does not support snapshot
		#Use ffmpeg to extract snapshot from media stream (if camera does not support snapshot)
		rm /tmp/alarm_snapshot1_$$.*	2>/dev/null #remove done file, if exists, start ffmpeg to get the snapshot from media stream, then write file .done to mark snapshot available
		#ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames 200 /tmp/alarm_snapshot1_$$.mp4 && touch /tmp/alarm_snapshot1_$$.done &
		# 2x speed  (0.50): set to 0.25 to get 4x speed
		if [ a$DEBUG == a1 ]; then
			log "exec ffmpeg for camera1: ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames 120 -filter:v "setpts=0.50*PTS" /tmp/alarm_snapshot1_$$.mp4 ; touch /tmp/alarm_snapshot1_$$.done"
			( ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames 120 -filter:v "setpts=0.50*PTS" /tmp/alarm_snapshot1_$$.mp4 ; touch /tmp/alarm_snapshot1_$$.done ) >>/tmp/alarm_snapshot1.log 2>&1 &
			log "end of ffmpeg for camera1"
		else
			( ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames 120 -filter:v "setpts=0.50*PTS" /tmp/alarm_snapshot1_$$.mp4 ; touch /tmp/alarm_snapshot1_$$.done ) >>/tmp/alarm_snapshot1.log 2>&1 &
		fi
	fi
fi

if [ -n ${ipcamera2} ]; then
	if [ -n "$SNAPURL2" ]; then
		#IPCam supported snapshot
		curl -s -o /tmp/alarm_snapshot.jpg ${SNAPURL2} #Get snapshot from IP camera (if supported)
	elif [ -n "$MEDIAURL2" ]; then
		#IPCam does not support snapshot
		#Use ffmpeg to extract snapshot from media stream (if camera does not support snapshot)
		rm /tmp/alarm_snapshot2_$$.*	2>/dev/null #remove done file, if exists, start ffmpeg to get the snapshot from media stream, then write file .done to mark snapshot available
		#ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames 200 /tmp/alarm_snapshot2_$$.mp4 && touch /tmp/alarm_snapshot2_$$.done &
		# 2x speed  (0.50): set to 0.25 to get 4x speed
		if [ a$DEBUG == a1 ]; then
			log "exec ffmpeg for camera2"
			( ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames 120 -filter:v "setpts=0.50*PTS" /tmp/alarm_snapshot2_$$.mp4 ; touch /tmp/alarm_snapshot2_$$.done )  >>/tmp/alarm_snapshot2.log 2>&1 &
			log "end of ffmpeg for camera2"
		else
			( ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames 120 -filter:v "setpts=0.50*PTS" /tmp/alarm_snapshot2_$$.mp4 ; touch /tmp/alarm_snapshot2_$$.done )  >>/tmp/alarm_snapshot2.log 2>&1 &
		fi
	fi
fi
sleep 24
if [ -n "${ipcamera1}" ]; then
	#wait for snapshot1
	if [ $DEBUG -eq 1 ]; then
		log "waiting for /tmp/alarm_snapshot1_$$.done ..."
	fi
	for (( i=12; $i>0; i-- )); do
		if [ -r /tmp/alarm_snapshot1_$$.done ]; then
			log `ls -l	/tmp/alarm_snapshot1_$$*`
			#extract image region
#				convert -geometry 960 /tmp/alarm_snapshot1_$$.jpg /tmp/alarm_snap.jpg
			#send picture by telegram
			datetime=`date "+%x %T"`
			#${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" /tmp/alarm_snap.jpg
			${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" 'none' /tmp/alarm_snapshot1_$$.mp4
			break
		else
			sleep 1
		fi
	done
	if [ $i -eq 0 ]; then
		log "Error: snapshot1 not received"
	fi
fi
if [ -n "${ipcamera2}" ]; then
	#wait for snapshot2
	if [ $DEBUG -eq 1 ]; then
		log "waiting for /tmp/alarm_snapshot2_$$.done ..."
	fi
	for (( i=12; $i>0; i-- )); do
		if [ -r /tmp/alarm_snapshot2_$$.done ]; then
			log `ls -l	/tmp/alarm_snapshot2_$$*`
			#extract image region
#				convert -geometry 960 /tmp/alarm_snapshot2_$$.jpg /tmp/alarm_snap.jpg
			#send picture by telegram
			datetime=`date "+%x %T"`
			#${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" /tmp/alarm_snap.jpg
			${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" 'none' /tmp/alarm_snapshot2_$$.mp4
			break
		else
			sleep 1
		fi
	done
	if [ $i -eq 0 ]; then
		log "Error: snapshot2 not received"
	fi
fi
if [ "a$DEBUG" != "a0" ]; then 
	rm /tmp/alarm_snapshot1_$$.*
	rm /tmp/alarm_snapshot2_$$.*
fi
