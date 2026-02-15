#!/bin/bash
# Written by Creasol - https://www.creasol.it
# When called by domoticz or executed from the shell, it extract a snapshot from IPCAMs (from camera snapshot, if available, or from media stream)
# and send it by Telegram.
# Prerequisites: 
# apt-get update; apt-get install ffmpeg imagemagick curl jq
#Syntax: scripts/lua/alarm_sendsnapshot.sh IP_Camera1 IP_Camera2 Message
#for example: scripts/lua/alarm_sendsnapshot.sh 192.168.3.205 192.168.3.206 PIR_Garage

DEBUG=0		# Set to 0 to disable verbose output to the log, or 1 to enable verbosity
VIDEO_DURATION=20

function log () {
	echo "`date '+%H:%M:%S.%N'` $*" >>/tmp/alarm_sendsnapshot.log
}

ipcamera1=$1
ipcamera2=$2
message=$3
FRAMES=$(( $VIDEO_DURATION * 10 ))
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
file1mp4=/tmp/alarm_${ipcamera1}.mp4
file1log=/tmp/alarm_${ipcamera1}.log
file1done=/tmp/alarm_${ipcamera1}.done
file2mp4=/tmp/alarm_${ipcamera2}.mp4
file2log=/tmp/alarm_${ipcamera2}.log
file2done=/tmp/alarm_${ipcamera2}.done


function recentFile () {
	# check if a file exists, and if it's recent => return 1

	if [ -r $1 ]; then
		# file exists => check date
		current_time=$(date +%s)
		file_mtime=$(stat -c %Y "$1")
    	seconds=$((current_time - file_mtime))
		if [ $seconds -lt 60 ]; then
			# IPcam busy
			return 1
		else
			return 0
		fi
	else
		return 0
	fi	
}

#get image snapshot, if available, or build a snapshot from video stream
log "================== `date '+%D %T'`  alarm_sendsnapshot $* =================="
if [ -n "${ipcamera1}" ]; then
	if [ -n "$SNAPURL1" ]; then
		#IPCam supported snapshot
		curl -s -o /tmp/alarm_snapshot.jpg ${SNAPURL1} #Get snapshot from IP camera (if supported)
	elif [ -n "$MEDIAURL1" ]; then
		#IPCam does not support snapshot
		recentFile ${file1mp4} 	# check if mp4 file already exists and is newer than 60s => busy cam => return 1
		if [ $? -ne 0 ]; then
			# cannot get the current camera stream: already in use
			echo "Camera ${ipcamera1} is busy => skip recording" >>${file1log}
			ipcamera1=''
		else
			rm $file1done 2>/dev/null
			if [ a$DEBUG == a1 ]; then
				log "ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames ${FRAMES} -filter:v 'setpts=0.50*PTS' ${file1mp4}"
				( ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames ${FRAMES} -filter:v 'setpts=0.50*PTS' ${file1mp4} ; touch ${file1done} ) >>${file1log} 2>&1 &
	#			( openRTSP -Q -4 -d ${VIDEO_DURATION} -u ${IPCAM_USER} ${IPCAM_PASS} rtsp://${MEDIAURL1} >${file1mp4} 2>${file1log} ; touch ${file1done} ) &
				log "End of ffmpeg for camera1"
			else
				( ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL1} -frames ${FRAMES} -filter:v "setpts=0.50*PTS" ${file1mp4} ; touch ${file1done} ) >>${file1log} 2>&1 &
	#			( openRTSP -d ${VIDEO_DURATION} -u ${IPCAM_USER} ${IPCAM_PASS} rtsp://${MEDIAURL1} >${file1mp4} 2>${file1log} ; touch ${file1done} ) &
			fi
		fi
	fi
fi

if [ -n ${ipcamera2} ]; then
	if [ -n "$SNAPURL2" ]; then
		#IPCam supported snapshot
		curl -s -o /tmp/alarm_snapshot.jpg ${SNAPURL2} #Get snapshot from IP camera (if supported)
	elif [ -n "$MEDIAURL2" ]; then
		recentFile ${file2mp4} 	# check if mp4 file already exists and is newer than 60s => busy cam => return 1
		if [ $? -ne 0 ]; then
			# cannot get the current camera stream: already in use
			echo "Camera ${ipcamera2} is busy => skip recording" >>${file2log}
			ipcamera2=''
		else
			rm $file2done 2>/dev/null
			if [ a$DEBUG == a1 ]; then
				log "ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames ${FRAMES} -filter:v 'setpts=0.50*PTS' ${file2mp4}"
				( ffmpeg -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames ${FRAMES} -filter:v 'setpts=0.50*PTS' ${file2mp4} ; touch ${file2done} ) >>${file2log} 2>&1 &
	#			( openRTSP -d ${VIDEO_DURATION} -u ${IPCAM_USER} ${IPCAM_PASS} rtsp://${MEDIAURL2} >${file2mp4} 2>${file2log} ; touch ${file2done} ) &
				log "End of ffmpeg for camera2"
			else
				( ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${IPCAM_USER}:${IPCAM_PASS}@${MEDIAURL2} -frames ${FRAMES} -filter:v "setpts=0.50*PTS" ${file2mp4} ; touch ${file2done} ) >>${file2log} 2>&1 &
	#			( openRTSP -d ${VIDEO_DURATION} -u ${IPCAM_USER} ${IPCAM_PASS} rtsp://${MEDIAURL2} >${file2mp4} 2>${file2log} ; touch ${file2done} ) &
			fi
		fi
	fi
fi
sleep ${VIDEO_DURATION}
if [ -n "${ipcamera1}" ]; then
	#wait for snapshot1
	if [ $DEBUG -eq 1 ]; then
		log "waiting for ${file1done} ..."
	fi
	for (( i=12; $i>0; i-- )); do
		if [ -r ${file1done} ]; then
			log `ls -l	/tmp/alarm_${ipcamera1}*`
			#extract image region
#				convert -geometry 960 /tmp/alarm_snapshot1_$$.jpg /tmp/alarm_snap.jpg
			#send picture by telegram
			datetime=`date "+%x %T"`
			#${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" /tmp/alarm_snap.jpg
			${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" 'none' ${file1mp4}
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
		log "waiting for ${file2done} ..."
	fi
	for (( i=12; $i>0; i-- )); do
		if [ -r ${file2done} ]; then
			log `ls -l	/tmp/alarm_${ipcamera2}*`
			#extract image region
#				convert -geometry 960 /tmp/alarm_snapshot2_$$.jpg /tmp/alarm_snap.jpg
			#send picture by telegram
			datetime=`date "+%x %T"`
			#${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" /tmp/alarm_snap.jpg
			${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${message}" 'none' ${file2mp4}
			break
		else
			sleep 1
		fi
	done
	if [ $i -eq 0 ]; then
		log "Error: snapshot2 not received"
	fi
fi
if [ "a$DEBUG" == "a0" ]; then 
	rm ${file1mp4} ${file1done} 2>/dev/null
	rm ${file2mp4} ${file2done}	2>/dev/null
fi
