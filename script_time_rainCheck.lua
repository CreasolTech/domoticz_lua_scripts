-- control rain, wind, ....
RAINDEV='Rain'
WINDDEV='Wind'
commandArray={}

-- extract the rain rate (otherdevices[dev]="rainRate;rainCounter")
for str in otherdevices[RAINDEV]:gmatch("[^;]+") do
	rainRate=tonumber(str)/40;
	break
end

-- If it's raining, disable the 230V socket in the garden
dev='Prese_Giardino'
if (otherdevices[dev]=='On' and rainRate>8) then -- more than 8mm/h
	print("Device "..dev.." is On while raining (rainRate="..rainRate..") => turn OFF")
	commandArray[dev]='Off'
end
return commandArray
