## Domoticz lua scripts, by Creasol https://www.creasol.it/domotics

In this repository you can find several LUA scripts and config files for Domoticz, the easy and powerful open-source home automation system controller.

More information, scripts, application notes, examples are available at https://www.creasol.it/support/domotics-home-automation-and-diy

Description of some products made by our company (DomBusTH, DomBus12, DomBus23, DomBus31, ...) are available at https://www.creasol.it/products/domotics and https://store.creasol.it/en/11-domotics

Some scripts require that you install the dkjson package, with the command __apt install lua-dkjson__

All scripts are free to use, with absolute no warranty. Use them at your own risk.


### Support or Contact
For any requests, you can join DomBus channel on Telegram, https://t.me/DomBus 


## Script POWER 
File: scripts/lua/script_device_power.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions

  1. Send notification when consumed power is above a threshold (to avoid power outage)

  2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid

  3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored

  4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
     green LED flashes 1..M times if photovoltaic produces up to 1..M kW 

## Script for heat pump and gas heater
File: scripts/lua/script_time_heatpump.lua and heatpump_conf.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

This script manages the heat pump, adjusting power and fluid temperature to meet the building demand.
If a photovoltaic system is installed, with a power meter measuring the power exchanged with the electric grid, 
during the summer the heat pump will try to work only when extra power from photovoltaic is produce. No power => heat pump off or at minimum level.
During the winter, the heat pump will work expecially during the day, when external temperature is high, and regulates the fluid temperature smartly
to get the heat pump consuming the most energy from photovoltaic and working hard when external temperature is high, and works at minimum (or off) when
the external temperature does not permit to get an high efficiency


## Script for alarm system
File: scripts/lua/script_device_alarm.lua alarm_config.lua alarm_sendsnapshot.sh and alarmSet.sh

Destination directory: DOMOTICZ_DIR/scripts/lua

Scripts that manages a burglar alarm system: magnetic contact sensors on doors/windows/blinds, PIRs and radars, tampers, sirens.
Full notifications on Telegram and 3 working modes fully configurable:
DAY: it shortly activates internal sirens when a door/window opens or a PIR is activated
NIGHT: in case of alarm, only activates the internal sirens and turns ON some lights.
AWAY: in case of alarm, both internal and external sirens are activated. 
External sirens delay when alarm is activated on some configurable sensors (for example, main door), record short videos when 
external sensors have been activated (when someone or a cat walk outside), presence light will be managed when AWAY alarm is active, between
Sunset and Sunrise, to simulate that someone is inside the house.


## Script that check rain and wind
File: scripts/time/rainCheck.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Silly script that check the raining rate, and if above 8mm/h disable external socket in the garden (connected to the Xmas tree!!)
Also, checks wind speed and direction and disable ventilation when wind speed is zero or wind comes from south or west, where there are few building using
wood stoves generating bad smoke smell.

## DomBus modules for Domoticz and Home Assistant
Domotic modules, optimized for very low power consumption and high reliability, with inputs, outputs and sensors (temperature, relative humidity, distance).

DomBus modules can be connected together by wired bus, using a common alarm shielded cable within 4 wires:
* 2x0.22mm² wires for data
* 2x0.5mm² wires for 12-14Vdc power supply

Using a 13.6V power supply with a lead acid backup battery permits to get domotic system working even in case of power outage: this is perfect even for alarm systems.

Actually the following modules are supported:
* [DomBus1](https://www.creasol.it/CreasolDomBus1): 2-3 N.O. relay outputs, 6 digital inputs, 1 230Vac opto-input
* [DomBus12](https://www.creasol.it/CreasolDomBus12): 7 GPIO, 2 open-drain outputs
* [DomBus23](https://www.creasol.it/CreasolDomBus23): 2 N.O. relay outputs, 1 mosfet output (for 12-24V LED dimming or other DC loads), 2 analog outputs 0-10V, 2 GPIO, 2 low voltage opto-inputs (5-40V), 1 230Vac opto input
* [DomBus31](https://www.creasol.it/CreasolDomBus31): low power module with 6 N.O. relay outputs + 2 N.O./N.C. relay outputs
* [DomBusTH](https://www.creasol.it/CreasolDomBusTH): Temperature + Relative Humidity sensors, red + green + white LEDs, 4 GPIO, 2 open-drain outputs, 1 analog input

Modules and components are developed by Creasol, https://www.creasol.it/domotics

## Example of a domotic system managing lights, door bell, alarm, heat pump, ventilation, irrigation, ...

![alt Domotic system using DomBus modules](https://images.creasol.it/AN_domoticz_example2.png "Example of a domotic system managing lights, door bell, alarm, heat pump, ventilation, irrigation, ...")


## Custom icons for Domoticz
* domoticz_custom_icon_batteryMin.zip : battery level min (used for EVehicles)
* domoticz_custom_icon_batteryMax.zip : battery level max (used for EVehicles)
