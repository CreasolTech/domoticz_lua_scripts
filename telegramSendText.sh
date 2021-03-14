#!/bin/bash
. /home/pi/domoticz/scripts/lua/globalvariables.lua # some variables common to all scripts

function printsyntax () {
	echo "Syntax: $0 chatid	text [picture]"
	echo "Send text, or text + picture, to telegram chat"
	echo "e.g. $0 123456789 \"Look at the photo....\" snaphost.jpg"
}

chat_id=$1
msg=$2
picture=$3
video=$4
if [ $# -eq 2 ]; then
	curl -s --data chat_id=${chat_id} --data-urlencode "text=${msg}"  "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" >/dev/null
elif [ $# -eq 3 ]; then
	curl -s -X POST -F chat_id=${chat_id} -F photo="@${picture}" -F caption="${msg}" "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendPhoto" 
elif [ $# -eq 4 ]; then
	curl -s -X POST -F chat_id=${chat_id} -F video="@${video}" -F caption="${msg}" "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendVideo" 
else
	printsyntax
fi
