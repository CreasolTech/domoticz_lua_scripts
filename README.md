## Domoticz lua scripts, by Creasol https://www.creasol.it/domotics

In this repository you can find several LUA scripts and config files for Domoticz, the easy and powerful open-source home automation system controller.

More information, scripts, application notes, examples are available at https://www.creasol.it/support/domotics-home-automation-and-diy

Description of some products made by our company (DomBusTH, DomBus12, DomBus23, DomBus31, ...) are available at https://www.creasol.it/products/domotics and https://store.creasol.it/en/11-domotics


[![alt DomBusTH image](https://images.creasol.it/creDomBusTH1_200.jpg "DomBusTH rear view: module with temp+humidity sensors, 3 LEDs, 4 I/O, 2 outputs, 1 analog input")](https://www.creasol.it/CreasolDomBusTH)
[![alt DomBusTH image](https://images.creasol.it/creDomBusTH2_200.jpg "DomBusTH front view with white led, red/green led, temperature + humidity sensor")](https://www.creasol.it/CreasolDomBusTH)
[![alt DomBus12 image](https://images.creasol.it/creDomBus12_400.png "DomBus12: 7 I/Os + 2 open-drain outputs that can be connected to 2 external relays")](https://www.creasol.it/CreasolDomBus12)
[![alt DomBus23 image](https://images.creasol.it/creDomBus23_400.png "DomBus23: 2 N.O. relay outputs, 1 mosfet output for 12-24V LED dimming or other DC loads, 2 analog outputs 0-10V, 2 GPIO, 2 low voltage opto-inputs 5-40V, 1 230Vac opto input")](https://www.creasol.it/CreasolDomBus23)
[![alt DomBus31 image](https://images.creasol.it/creDomBus31_400.png "DomBus31: low power module with 6 N.O. relay outputs + 2 N.O./N.C. relay outputs")](https://www.creasol.it/CreasolDomBus31)

[![alt DomBusEVSE image](https://images.creasol.it/creDomBusEVSE_200.png "DomBusEVSE: electric vehicle charging module, to build a smart wallbox by yourself")](https://www.creasol.it/CreasolDomBusEVSE)
[![alt DomBus32 image](https://images.creasol.it/creDomBus32_200.png "DomBus32: 3 relay outputs, 3 AC inputs, 5 I/Os")](https://www.creasol.it/CreasolDomBus32)
[![alt DomBus34 image](https://images.creasol.it/creDomBus34_200.png "DomBus34: 2 relay outputs, 1 AC inputs, 2 I/Os, 1 Modbus to connect up to 4 energy meters")](https://www.creasol.it/CreasolDomBus34)
[![alt DomBus36 image](https://images.creasol.it/creDomBus36_400.png "DomBus36: 12 relay outputs")](https://www.creasol.it/DomBus36)
[![alt DomBusEVSE to make your smart wallbox for electric vehicle charging](https://images.creasol.it/creDomBusEVSE_adv1_400.png "DomBusEVSE can be used to make your Smart Wallbox to charge your electric car with load balancing")](https://www.creasol.it/DomBusEVSE)



Some scripts require that you install the dkjson package, with the command __apt install lua-dkjson__

All scripts are free to use, with absolute no warranty. Use them at your own risk. 

All global variables and functions are stored in the files globalvariables.lua and globalfunctions.lua.


### Support or Contact
For any requests, you can join DomBus channel on Telegram, https://t.me/DomBus 


## Script POWER 
File: script_device_power.lua  and  config_power.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions

  1. Send notification when consumed power is above a threshold (to avoid power outage)
  2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid
  3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored
  4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
     green LED flashes 1..M times if photovoltaic produces up to 1..M kW 

## Script to control the EMMETI Mirai heat pump in a smart way
Files: script_time_heatpump_emmeti.lua and config_heatpump_emmeti.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

This script is designed for radiant systems: 
* it measures the temperature in each room, computes a derivative of a temperature to states if the house is warming or not (PID control) and
regulates the heat pump power to satisfy the warming/cooling needs for the best comfort.
* it's possible to define peak hours where power consumption should be limited, to give your contribution for electricity grid stabilization
* if photovoltaic or wind generator is available, try to consume most energy from it, improving own consumption
* for each room it's possible to define a period where the set-temperature can be reduced (in Winter, or increased in Summera)
[![alt Optimized management of Heat Pump EMMETI Mirai](https://images.creasol.it/heatpump_emmeti_modbus_solar_power_tracking.png "Heat pump optimized management with this script")](https://www.creasol.it/DomBusTH)


## Script for heat pump and gas heater
Files: script_time_heatpump.lua  and  heatpump_conf.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

This script manages the heat pump, adjusting power and fluid temperature to meet the building demand.

If a photovoltaic system is installed, with a power meter measuring the power exchanged with the electric grid, 
during the summer the heat pump will try to work only when extra power from photovoltaic is produce. No power => heat pump off or at minimum level.

During the winter, the heat pump will work expecially during the day, when external temperature is high, and regulates the fluid temperature smartly
to get the heat pump consuming the most energy from photovoltaic and working hard when external temperature is high, and works at minimum (or off) when
the external temperature does not permit to get an high efficiency


## Script for alarm system
Files: script_device_alarm.lua  alarm_config.lua  alarm_sendsnapshot.sh  and  alarmSet.sh

Destination directory: DOMOTICZ_DIR/scripts/lua

Scripts that manages a burglar alarm system: magnetic contact sensors on doors/windows/blinds, PIRs and radars, tampers, sirens.

Full notifications on Telegram and 3 working modes fully configurable:

* DAY: it shortly activates internal sirens when a door/window opens or a PIR is activated
* NIGHT: in case of alarm, only activates the internal sirens and turns ON some lights.
* AWAY: in case of alarm, both internal and external sirens are activated. 

External sirens delay when alarm is activated on some configurable sensors (for example, main door), record short videos when 
external sensors have been activated (when someone or a cat walk outside), presence light will be managed when AWAY alarm is active, between
Sunset and Sunrise, to simulate that someone is inside the house.

More info at https://www.creasol.it/freeBurglarAlarm

## Fire detector scripts
Files: script_time_fireAlarm.lua  config_fireAlarm.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

LUA script that load the rooms information from config_fireAlarm.lua and for any room
if Temperature > averageTemperature + deltaT => fire alarm detected => send notification by Telegram


## Script that check rain and wind
File: script_time_rainCheck.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Silly script that check the raining rate, and if above 8mm/h disable external socket in the garden (connected to the Xmas tree!!)

Also, checks wind speed and direction and disable ventilation when wind speed is zero or wind comes from south or west, where there are few building using
wood stoves generating bad smoke smell.

## Script to get data from Fronius inverter
File: script_time_fronius.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Simple script that every minute fetch data, by http, from Fronius solar inverter.


## DomBus modules for Domoticz, Home Assistant, Node-RED, OpenHAB, ...
**DomBus are domotic modules, optimized for very low power consumption and high reliability, with inputs, outputs and sensors** (temperature, relative humidity, distance).

All modules are available with *DomBus protocol*, a special multi-master protocol that permits to exchange commands between modules as KNX does. *DomBus* protocol is well supported
by *Domoticz*, and have a limited support on *Home Assistant*.

Some modules are also available with *Modbus protocol*, a standard master-slave protocol where the controller have to poll slaves module to get their state, and that is compatible 
with almost any smart home controller (Home Assistant, OpenHAB, ioBroker, node-RED, and much more).

DomBus modules can be connected together by **wired bus**, using a **common alarm shielded cable within 4 wires**:
* 2x0.22mm² wires for data
* 2x0.5mm² wires for 12-14Vdc power supply

Using a 13.6V power supply with a lead acid backup battery permits to get **domotic system working even in case of power outage**: this is perfect even for alarm systems.

Actually the following modules are supported:
* [DomBusTH](https://www.creasol.it/CreasolDomBusTH): **Temperature + Relative Humidity sensors, red + green + white LEDs, 4 GPIO, 2 open-drain outputs, 1 analog input**
* [DomBus12](https://www.creasol.it/CreasolDomBus12): **7 GPIO, 2 open-drain outputs**
* [DomBus23](https://www.creasol.it/CreasolDomBus23): **2 N.O. relay outputs, 1 mosfet output** (for 12-24V LED dimming or other DC loads), **2 analog outputs 0-10V, 2 GPIO, 2 low voltage opto-inputs (5-40V), 1 230Vac opto input**
* [DomBus31](https://www.creasol.it/CreasolDomBus31): DIN rail module, very low power consumption module with **6 N.O. relay outputs + 2 N.O./N.C. relay outputs**
* [DomBus32](https://www.creasol.it/DomBus32): DIN rail module with **3 relay outputs, 3 AC inputs, 5 I/Os**
* [DomBus34](https://www.creasol.it/DomBus34): DIN rail module with **2 relay outputs, 1 AC inputs, 2 I/Os, 1 Modbus to connect up to 4 energy meters**
* [DomBus36](https://www.creasol.it/DomBus36): DIN rail module with **12 relay outputs**
* [DomBusEVSE](https://www.creasol.it/creDomBusEVSE): **electric vehicle charging** module, to build a **Smart WALLBOX** by yourself

Modules and components are developed by Creasol, https://www.creasol.it/domotics


## Example of a domotic system managing lights, door bell, alarm, heat pump, ventilation, irrigation, ...

![alt Domotic system using DomBus modules](https://images.creasol.it/AN_domoticz_example2.png "Example of a domotic system managing lights, door bell, alarm, heat pump, ventilation, irrigation, ...")


## Lua script that sends a message to Telegram channel/group/user
```
    -- script_time_example.lua  : simple example script that write a message to Telegram channel/group if temperature is less than 5
    commandArray={}
    dofile "script/lua/globalvariables.lua" -- read a file with some variables, including Telegram API key and ChatID
    dofile "script/lua/globalfunctions.lua" -- read a file with some functions
    if (tonumber(otherdevices['Temp_outdoor']) < 5) then  -- check that Temp_outdoor temperature sensor is >=5 Celsius, or send a notice to Telegram
    	telegramNotify("Low temperature: bring flowers inside")	-- send message by Telegram
    end
    return commandArray
```


## Custom icons for Domoticz
* [batteryMin.zip](https://docs.creasol.it/domoticz_custom_icon_batteryMin.zip) : battery level min (used for EVehicles)
* [batteryMax.zip](https://docs.creasol.it/domoticz_custom_icon_batteryMax.zip) : battery level max (used for EVehicles)
