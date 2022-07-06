#!/bin/bash
# Written by Creasol - https://www.creasol.it
# When called by domoticz or executed from the shell, it extract a snapshot from IPCAM (from camera snapshot, if available, or from media stream)
# and send it by Telegram.
# Optionally, before sunrise or after sunset, activates lights before snapshot.
# Prerequisites: 
# apt-get update; apt-get install ffmpeg imagemagick curl jq

. /home/pi/domoticz/scripts/lua/globalvariables.lua # some variables common to all scripts

TELEGRAMTEXT='Doorbell'
TELEGRAMSCRIPT='/home/pi/domoticz/scripts/lua/telegramSendText.sh'

#SNAPURL='http://192.168.1.201:8088/snap.jpg'  #snapshot URL: if camera does not support snapshot, comment this variable
#MEDIAURL='192.168.1.201:554/mpeg4cif' #low quality stream
MEDIAURL='192.168.3.201:554/mpeg4'	#high quality stream
MEDIAUSER='admin'
MEDIAPASS='iuafio'
#Telegram picture snapshot: 420x210
PICTURE_REGION=1200x600+450+0  #extract picture 1400x800px, starting from offset 520x+0y
#PICTURE_REGION=500x200+228+40  #extract picture 500x200px, starting from offset 228x+40y
PICTURE_SCALE=800 #width of picture that we should want to get on Telegram

#Used to get light status, and set lights ON before snapshot and OFF after a while...
DOMOTICZ_URL='http://127.0.0.1:8080'
START_SCENEIDX=8	# Scene that is activated as soon as the button is pressed
#LIGHT1_IDX=0		# lights disabled: do not turn lights ON before getting snapshot, during the night
LIGHT1_IDX=32		# idx of the light that must get ON when someone ring the doorbell
LIGHT1_SCENEIDX=2	# idx of the scene that activates light1 for 300s or so.
			# Scene must be created by hand: add a scene, assign a name, add the light device and set Off Delay to 300 or other value
LIGHT2_IDX=34		# idx of additional light that must get ON (set to 0 to disable) 
LIGHT2_SCENEIDX=3	# idx of the scene that activates light2 for 300s or os. Set to 0 to disable
			# Scene must be created by hand: add a scene, assign a name, add the light device and set Off Delay to 300 or other value
DELAY_BEFORE_SNAPSHOT=0.1 #Delay from turning lights ON and get a snapshot, to permit CCD stabilization. Possible values: 0 (disabled), 0.5 (half second), 1.5 (1.5s), 2 (2s),...			

#If defined, start a scene immediately (e.g. to enable DVR registration or displays/monitors connected to DVR)
if [ -n "${START_SCENEIDX}" ]; then
	curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=switchscene&switchcmd=On&idx=${START_SCENEIDX}" >/dev/null
fi

#get image snapshot, if available, or build a snapshot from video stream
if [ -n "$SNAPURL" ]; then
	#IPCam supported snapshot
	curl -s -o /tmp/snapshot.jpg ${SNAPURL} #Get snapshot from IP camera (if supported)
else
	#IPCam does not support snapshot
	#Use ffmpeg to extract snapshot from media stream (if camera does not support snapshot)
	ffmpeg -loglevel quiet -rtsp_transport tcp -y -i rtsp://${MEDIAUSER}:${MEDIAPASS}@${MEDIAURL} -vframes 1 /tmp/snapshot.jpg
fi
#extract image region
convert -extract ${PICTURE_REGION} -scale ${PICTURE_SCALE} /tmp/snapshot.jpg /tmp/snap.jpg
#send picture by telegram
datetime=`date "+%x %T"`
${TELEGRAMSCRIPT} ${TELEGRAM_CHATID} "${datetime} - ${TELEGRAMTEXT}" /tmp/snap.jpg

if [ ${LIGHT1_IDX} -gt 0 ]; then
	time=`curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=getSunRiseSet" | jq '.ServerTime' |cut -d' ' -f2|cut -d: -f1-2 |tr -d ':' |sed 's/^0*//'`
	sunrise=`curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=getSunRiseSet" | jq '.Sunrise' |tr -d ':"' |sed 's/^0*//'`
	sunset=`curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=getSunRiseSet" | jq '.Sunset' |tr -d ':"' |sed 's/^0*//'`

	#time=2300 ####DEBUG: time=23:00 to force lights on
	turnOn=0
	if (( ${time} < ${sunrise} || ${time} > ${sunset} )); then 
		#night time
		if [ ${LIGHT1_IDX} -gt 0 ]; then
			#get status of LIGHT1_IDX light
			light1status=`curl -s "${DOMOTICZ_URL}/json.htm?type=devices&rid=${LIGHT1_IDX}" | jq '.result[0].Data' |tr -d \"`
			if [ "a${light1status}" == "aOff" ]; then
				#switch scene for light1 ON
				curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=switchscene&switchcmd=On&idx=${LIGHT1_SCENEIDX}" >/dev/null
				turnOn=1
			fi
		fi
		if [ ${LIGHT2_IDX} -gt 0 ]; then
			#get status of LIGHT2_IDX light
			light2status=`curl -s "${DOMOTICZ_URL}/json.htm?type=devices&rid=${LIGHT2_IDX}" | jq '.result[0].Data' |tr -d \"`
			if [ "a${light2status}" == "aOff" ]; then
				#switch scene for light2 ON
				curl -s "${DOMOTICZ_URL}/json.htm?type=command&param=switchscene&switchcmd=On&idx=${LIGHT2_SCENEIDX}" >/dev/null
				turnOn=2
			fi
		fi
	fi
	if [ ${turnOn} -gt 0 ]; then
		sleep ${DELAY_BEFORE_SNAPSHOT}
	fi
fi
