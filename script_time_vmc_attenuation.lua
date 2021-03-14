-- control ventilation attenuation if (VMC_rinnovo==On or VMC_CaldoFreddo==On) and alarmLevel==4 (Night) : during night, ventilation must work at minimum 
commandArray={}
-- alarmLevel==4 => ALARM_NIGHT (someone is sleeping) 
-- if ventilation is ON during the night => activate attenuation to reduce ventilation noise
if (uservariables['alarmLevel']==4 and (otherdevices['VMC_Rinnovo']=='On' or otherdevices['VMC_CaldoFreddo']=='On')) then
	if (otherdevices['VMC_Attenuazione']~='On') then
		commandArray['VMC_Attenuazione']='On'
	end
else
	if (otherdevices['VMC_Attenuazione']~='Off') then
		commandArray['VMC_Attenuazione']='Off'
	end
end
return commandArray
