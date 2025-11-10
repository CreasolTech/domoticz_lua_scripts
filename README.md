# Domoticz lua scripts, developed by Creasol https://www.creasol.it/domotics

In this repository you can find several LUA scripts and config files for Domoticz, the easy and powerful open-source home automation system controller.

More information, scripts, application notes, examples are available at https://www.creasol.it/support/domotics-home-automation-and-diy

Some scripts require that you install the dkjson package, with the command __apt install lua-dkjson__

All scripts are free to use, with absolute no warranty. Use them at your own risk. 

All global variables and functions are stored in the files globalvariables.lua and globalfunctions.lua.

** The scripts are used with out set of industrial and home automation system modules, made in Italy: for more info, check below! **

For any requests, you can [join DomBus channel on Telegram](https://t.me/DomBus)

## Script script_device_master.lua
This is a main script called every time a device changes state: it's optimized to 
* run quickly
* ignore useless device changes
* call the appropriate scripts associated to the changed devices: for example if the changed device is named PIR* or MCS* or SIREN* , the *alarm.lua* script will be called, while if the device is named power*, the *power.lua* script will be called.


## Script POWER 
File: *power.lua*  and  *config_power.lua*

Destination directory: *DOMOTICZ_DIR/scripts/lua*

Called by *script_device_master.lua* and triggered when a device containing *Power* or *Button* in its name changes state.

Used to check power from energy meter (SDM120, SDM230, ...) and performs the following actions

  1. Send notification when consumed power is above a threshold (to avoid power outage)
  2. Enabe/Disable electric heaters or other appliances, to reduced power consumption from the electric grid
  3. Emergency lights: turn ON some LED devices in case of power outage, and turn off when power is restored
  4. Show on DomBusTH LEDs red and green the produced/consumed power: red LED flashes 1..N times if power consumption is greater than 1..N kW; 
     green LED flashes 1..M times if photovoltaic produces up to 1..M kW 


## Script to computes self-consumption power and percentage, and self-sufficiency percentage
Files: script_time_selfconsumption.lua config_power.lua globalfunctions.lua globalvariables.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Called every minute

This is a mandatory script for those who have at least one reneable generation plant in their building.

It manages one or more energy production plants (photovoltaic on the roof, photovoltaic in the garden and or wind turbine, ...) **computing the total generated energy/power, total used energy/power, self-consumption energy/power, self-consumption percentage and self-sufficiency percentage**.

These are goods indicators to know if the building is optimized or not.

Detailed info are available at [www.creasol.it/SelfConsumption](https://www.creasol.it/SelfConsumption) page.


## Script that, every time a power meter changes, computes the sum of 2 or more power meters and feeds that value to the DomBusEVSE virtual device
Files: script_device_evsegridpower.lua

This simple script is meant to compute the total power from the grid and feed it to the DomBusEVSE module, EV charging system that must know the total power from the grid, to prevent
overloads and manage solar charging.
In case of 2 or 3 meters are used (for example, a meter for the house, a meter for the electric car, and another meter for the garage, it computes the total power.


## Script to control the EMMETI Mirai heat pump in a smart way
Files: heatpump.lua (script_time_heatpump_emmeti.lua) and config_heatpump_emmeti.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Called every minute

This script is designed for radiant systems: 
* it measures the temperature in each room, computes a derivative of a temperature to states if the house is warming or not (PID control) and 
regulates the heat pump power to satisfy the warming/cooling needs for the best comfort.
* it's possible to define peak hours where power consumption should be limited, to give your contribution for electricity grid stabilization
* if photovoltaic or wind generator is available, **try to consume most energy from renewable production plants**, improving self consumption
* for each room it's possible to define a period where the set-temperature can be reduced (in Winter, or increased in Summera)
[![alt Optimized management of Heat Pump EMMETI Mirai](https://images.creasol.it/heatpump_emmeti_modbus_solar_power_tracking.png "Heat pump optimized management with this script")](https://www.creasol.it/DomBusTH)


## Script for heat pump and gas heater
Files: script_time_heatpump.lua  and  heatpump_conf.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Called every minute

This script manages the heat pump, adjusting power and fluid temperature to meet the building demand.

If a photovoltaic system is installed, with a power meter measuring the power exchanged with the electric grid, 
during the summer the heat pump will try to work only when extra power from photovoltaic is produce. No power => heat pump off or at minimum level.

During the winter, the heat pump will work expecially during the day, when external temperature is high, and regulates the fluid temperature smartly
to get the heat pump consuming the most energy from photovoltaic and working hard when external temperature is high, and works at minimum (or off) when
the external temperature does not permit to get an high efficiency


## Script for alarm system
Files: alarm.lua (script_device_alarm.lua) alarm_config.lua  alarm_sendsnapshot.sh  and  alarmSet.sh

Destination directory: DOMOTICZ_DIR/scripts/lua

Called by *script_device_master.lua* and triggered when a device with name starting with *PIR* , *MCS* , *SIREN*, *TAMPER*, *ALARM* or *Light*, changes state, or when the variable *alarmLevelNew* is not zero (alarm started or stopped)

Scripts that manages a **burglar alarm system**: magnetic contact sensors on doors/windows/blinds, PIRs and radars, tampers, sirens.

**Full notifications on Telegram** and 3 working modes fully configurable:

* DAY: it shortly activates internal sirens when a door/window opens or a PIR is activated
* NIGHT: in case of alarm, only activates the internal sirens and turns ON some lights.
* AWAY: in case of alarm, both internal and external sirens are activated. 

Other features:

* External **sirens delay** when alarm is activated on some configurable sensors (for example, main door)
* **Records short videos when external sensors have been activated** (when someone or a cat walk outside)
* Recode short **videos to 2x speed**, and sends to **Telegram channel/group**
* **House presence lights** will be managed when AWAY alarm is active, between Sunset and Sunrise, to simulate that someone is inside the house.

More info at https://www.creasol.it/freeBurglarAlarm

## Fire detector scripts
Files: script_time_fireAlarm.lua  config_fireAlarm.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

LUA script that loads the rooms information from config_fireAlarm.lua and for any room
if Temperature > averageTemperature + deltaT => **fire alarm detected => send notification by Telegram**

More information available at [fire alarm page](https://www.creasol.it/en/support/domotics-home-automation-and-diy/fire-alarm-detection-with-domoticz-home-automation-system)


## Script that check rain and wind
File: script_time_rainCheck.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Called every minute

Script that checks the raining rate and wind speed, and performs several functions:

* If **raining rate is over 8mm/h, disable external socket in the garden** (connected to the Xmas tree!!).

* Checks wind speed and direction and **disable ventilation when wind speed is zero or wind comes from south or west, where there are few building using wood stoves generating bad smoke smell**.

* Sends weather telemetry to WindGuru

* Send **buzzer alert if a trash bin should be carried out**:
  * 1 beep (followed by 4s pause) for paper
  * 2 beeps (followed by 4s pause) for plastic/metal
  * 3 beeps (followed by 4s pause) for unsorted
  * 4 beeps (followed by 4s pause) for glass
  
  It's programmed to work with the [cheap DomBusTH module](https://www.creasol.it/DomBusTH) which can be placed in a blank cover (in a wallbox) and already provide a piezo buzzer output, red+green+white leds, touch sensor (simulating a pushbutton, that can be used to cancel the alarm), other 4 I/Os, temperature and humidity sensors.
[DomBusTH video](https://www.youtube.com/watch?v=6bJ_igU9jgo)

* **Enable/Disable gate power supply to reduce energy consumption and improve antitheft security**: check vehicle position to determine if it's approaching (gate should be enabled) or it's moving away (gate should be disabled).
In any case, the gate power supply is turned OFF when the alarm system is in NIGHT or AWAY mode.

## Script to get data from Fronius inverter
File: script_time_fronius.lua

Destination directory: DOMOTICZ_DIR/scripts/lua

Simple script that every minute fetch data, by http, from Fronius solar inverter.



## Script that show earthquakes alert and send Telegram notifications

File *script_time_earthquake.lua* , together with *globalvariables.lua* and *globalfunctions.lua*, can be used to get earthquakes alert on Domoticz and, if magnitude is stronger than a certain threshold, also sends alert on a Telegram channel or group.

![alt Show earthquakes alert on Domoticz home automation systems and telegram channel/group](https://images.creasol.it/earthquake_20240520.webp "Show earthquakes alert on Domoticz home automation systems and telegram channel/group")


## Script that update a virtual P1 meter from an existing general kWh meter measuring grid power

File *script_device_power2p1.lua* is a LUA script for Domoticz useful for the Energy Dashboard. 
It can be used to update a virtual P1 meter (that you have to create by yourself from Setup -> Hardware menu), writing the current power and energy (usage and return).
Also, the script can handle more generators (photovoltaic on roof, photovoltaic in the garden, wind generator, ...) compute the sum of the power to a virtual device, used by the Energy Dashboard.

Just copy this script in *scripts/lua* folder and update the 6 variables at the top of file.

![alt Example of a Domoticz Energy Dashboard](https://images.creasol.it/domoticz_energy_dashboard.png "Example of a Domoticz Energy Dashboard using the script_device_power2p1.lua script to update the virtual P1 meter")



## Script that fetches electricity energy price from ENTSO-e website (for your specific zone, if you reside in EU) and solar photovoltaic forecast

File *script_time_entsoe.lua* is a LUA script for Domoticz that:
* **fetches** every day, in the afternoon, the **day-ahead electricity prices for your zone**
* update a custom virtual device with the **current energy price (that changes every hour)**
* **compute your real energy cost (including taxes, fees, ...) and update a custom virtual device with that price**
* let Domoticz core to get electricity price from the last custom virtual device, so **Domoticz can show energy costs in the energy dashboard**
* **store in a user variable the energy price of the day, hour by hour, separated by semicolon, and in last position the average price**: in this way it's possible to include in automations the management of load devices (for example climate heat pump) to reduce or increase their power based on the current energy price. For example, **it's possible to set every hour the climate heat pump to work to a targetPower * averagePrice / currentPrice , to save energy when price is high and consume more energy when power is low**. Similar policy can be chosen to **charge the electric vehicle when energy cost is low**.
Although in Italy electric energy cost is based on the montly average price for 3 time slots (day, early morning/evening, night/Sunday), **we should aim to regulate the power consumed by our buildings to increase it when there is more availability and reduce it when there is less availability of electricity.**
* get today and tomorrow solar photovoltaic forecast (estimated energy hour by hour, and total)
* permits to specify one or more photovoltaic strings/systems (with different orientation) to get a precise forecast.
* write a user variable with hour-by-hour estimated energy and total daily energy for today and tomorrow.


### Installation

* Copy files script_time_entsoe.lua globalvariables.lua globalfunctions.lua to the DOMOTICZ/scripts/lua directory
* cd DOMOTICZ; ln -s scripts/lua/XmlParser.lua
* Edit script_time_entsoe.lua : you'll find a description of the procedure to register to ENTSO-e website, get a security token and create two custom devices

![alt Electricity hourly price and cost](https://images.creasol.it/domoticz_entsoe.webp?new "Electricity hourly price, cost, variable with the price hour by hour, and charts")


### Usage
By including the *script/lua/globalvariables.lua* and *script/lua/globalfunctions.lua* , it's possible to use the function 

* *tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', 24))* to get the current average electricity price
* *tonumber(getItemFromCSV(uservariables['entsoe_today'], ';', timeNow.hour))* to get the current electricity price
* *tonumber(getItemFromCSV(uservariables['pv_today'], ';', 24))* to get the total estimated solar energy, today

In the *script_time_heatpump_emmeti.lua* there are some example of how electricity price and solar production are used to limit or increase heat pump power to optimize own-consumption 

![alt Variables in CSV format with electriciy hourly price and solar photovoltaic forecast](https://images.creasol.it/heatpump_optimized_electricity_solar_forecast.webp?a=1 "Variables in CSV format with electriciy hourly price and solar photovoltaic forecast, suitable to control heat pump, EV charging, boiler, ... to optimize own consumption and reduce peak hours energy usage")

***

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











***

## Creasol DomBus modules

Below a list of modules, produced in Italy by Creasol, designed for high reliability and optimized for very very low power consumption.

[<img src="https://images.creasol.it/pdf2.png" alt="Video" style="vertical-align: middle;"> Download the PDF catalog!](https://www.creasol.it/catalog)


Our industrial and home automation modules are designed to be
* very low power &rArr; **10÷15mW with relays OFF**
* reliable &rArr; **no disconnections**
* wired network (bus) &rArr; **no radiofrequency interference, no battery to replace**

Modules are available in two versions:
1. with **DomBus proprietary protocol**, suitable for every type of DomBus modules, working with [Domoticz](https://www.domoticz.com) by using the Creasol DomBus plugin, and [Home Assistant](https://www.home-assistant.io), [OpenHAB](https://www.openhab.org), [Node-RED](https://nodered.org) ... by using the [DomBusGateway software, a DomBus 2 MQTT-AutoDiscovery interface](https://www.creasol.it/DomBusGateway)
2. with **Modbus standard protocol**, suitable for relays modules, EVSE and Dual Axis solar tracker, working with almost any building automation system supporting Modbus

What version is the best? DomBus version, because:

**Modbus** is a standard protocol Master/Slave: the controller must poll each module to get its status, so it's **not suitable to manage inputs and counters that change frequently**, but can be used to manage relay outputs or read inputs status every 2-5s

**DomBus** is a proprietary multi-master protocol where **each module is able to initiate the communication with the master** to notify, for example, an input change, with a short latency (<100ms) that permits to **manage alarm sensors in a reliable way**. Also, DomBus supports the so-called DCMD, **commands exchanged between modules as KNX does**, so it's possible to program simple automations that work between modules even if the domotic controller is OFF (for example, short pulse on button to toggle a light ON/OFF, 1s pulse to open the garage door, 2s pulse to turn OFF some lights, ...)


[Store website](https://store.creasol.it/domotics) - [Information website](https://www.creasol.it/domotics)

### Youtube video showing DomBus modules
[![Creasol DomBus modules video](https://images.creasol.it/intro01_video.png)](https://www.creasol.it/DomBusVideo)



### DomBusEVSE - EVSE module to build a Smart Wallbox / EV charging station
<a href="https://store.creasol.it/DomBusEVSE"><img src="https://images.creasol.it/creDomBusEVSE_plug_300.webp" alt="DomBusEVSE smart EVSE module to make a Smart Wallbox EV Charging station" style="float: left; margin-right: 2em;" align="left" /></a>
Complete solution to make a Smart EVSE, **charging the electric vehicle using only energy from renewable source (photovoltaic, wind, ...), or adding 25-50-75-100% of available power from the grid**.

* **Single-phase and three-phase**, up to 32A (8kW or 22kW)
* Needs external contactor, RCCB (protection) and EV cable
* Optional power meter to measure charging power, energy, voltage and power factor
* Optional power meter to measure the power usage from the grid (not needed if already exists)
* **Two max grid power thresholds** can be programmed: for example, in Italy who have 6kW contractual power can drain from the grid Max (6* 1.27)=7.6kW for max 90 minutes followed by (6* 1.1)=6.6kW for another 90 minutes: in this case **the EVSE module can drain ALL available power** when programmed to charge at 100% **minimizing the charge time and increasing the charging efficiency**.
* **Works without the domotic controller** (stand-alone mode), and **can also work in *managed mode*, with an automation in the home automation system setting the charging current**

<br clear="all"/>

### DomBusTH - Compact board to be placed on a blank cover, with temperature and humidity sensor and RGW LEDs
<a href="https://store.creasol.it/DomBusTH"><img src="https://images.creasol.it/creDomBusTH6_200.png" alt="DomBusTH domotic board with temperature and humidity sensor, 3 LEDs, 6 I/O" style="float: left; margin-right: 2em;" align="left" /></a>
Compact board, 32x17mm, to be installed on blank cover with a 4mm hole in the middle, to exchange air for the relative humidity sensor. It can be **installed in every room to monitor temperature and humidity, check alarm sensors, control blind motor UP/DOWN**, send notifications (using red and green leds) and activate **white led in case of power outage**.

Includes:
* temperature and relative humidity sensor
* red, green and white LEDs
* 4 I/Os configurable as analog or digital inputs, pushbuttons, counters (water, gas, S0 energy, ...), NTC temperature and ultrasonic distance sensors
* 2 ports are configured by default as open-drain output and can drive up to 200mA led strip (with dimming function) or can be connected to the external module DomRelay2 to control 2 relays; they can also be configured as analog/digital inputs, pushbuttons and distance sensors.
<br clear="all"/>

### DomBus12 - Compact domotic module with 9 I/Os
<a href="https://store.creasol.it/DomBus12"><img src="https://images.creasol.it/creDomBus12_400.webp" alt="DomBus12 domotic module with 9 I/O" style="float: left; margin-right: 2em;" align="left" /></a>
**Very compact, versatile and cost-effective module with 9 ports**. Each port can be configured by software as:
* analog/digital inputs
* pushbutton and UP/DOWN pushbutton
* counters (water, gas, S0 energy, ...)
* NTC temperature and ultrasonic distance sensors
* 2 ports are configured by default as open-drain output and can drive up to 200mA led strip (with dimming function) or can be connected to the external module DomRelay2 to control 2 relays.
<br clear="all"/>

### DomBus21 - Latching relays domotic module
<a href="https://store.creasol.it/DomBus21"><img src="https://images.creasol.it/creDomBus21_size_400.webp" alt="DomBus21 domotic module with 3 latching relays, 1 AC input and 4 low voltage inputs" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Very compact domotic module providing:
* **3x latching relays SPST, max current 15A (3kW): no power consumption when relays are On or Off!**
* 1x 230V AC opto-isolated input to detect 230V and power outage, with **zero-detection to switch relays/loads minimizing in-rush current**
* 4x I/O lines, configurable as analog/digital inputs, temperature/distance sensor, counter, meter, ...
<br clear="all"/>

### DomBus23 - Domotic module with many functions
<a href="https://store.creasol.it/DomBus23"><img src="https://images.creasol.it/creDomBus23_400.webp" alt="DomBus23 domotic module with many functions" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Versatile module designed to control **gate or garage door**.
* 2x relays SPST 5A
* 1x 10A 30V mosfet (led stripe dimming)
* 2x 0-10V analog output: each one can be configured as open-drain output to control external relay
* 2x I/O lines, configurable as analog/digital inputs, temperature/distance sensor, counter, ...
* 2x low voltage AC/DC opto-isolated inputs, 9-40V
* 1x 230V AC opto-isolated input
<br clear="all"/>

### DomBus31 - Domotic module with 8 relays
<a href="https://store.creasol.it/DomBus31"><img src="https://images.creasol.it/creDomBus31_400.webp" alt="DomBus31 domotic module with 8 relay outputs" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
DIN rail low profile module, with **8 relays and very low power consumption**:
* 6x relays SPST 5A
* 2x relays STDT 10A
* Only 15mW power consumption with all relays OFF
* Only 600mW power consumption with all 8 relays ON !!
<br clear="all"/>

### DomBus32 - Domotic module with 3 relays
<a href="https://store.creasol.it/DomBus32"><img src="https://images.creasol.it/creDomBus32_200.webp" alt="DomBus32 domotic module with 3 relay outputs" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Versatile module with 230V inputs and outputs, and 5 low voltage I/Os.
* 3x relays SPST 5A
* 3x 115/230Vac optoisolated inputs
* Single common for relays and AC inputs
* 5x general purpose I/O, each one configurable as analog/digital inputs, pushbutton, counter, temperature and distance sensor.
<br clear="all"/>

### DomBus33 - Module to domotize a light system using step relays
<a href="https://store.creasol.it/DomBus33"><img src="https://images.creasol.it/creDomBus32_200.webp" alt="DomBus33 domotic module with 3 relay outputs that can control 3 lights" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Module designed to **control 3 lights already existing and actually controlled by 230V pushbuttons and step-by-step relays**. In this way each light can be activated by existing pushbuttons, and by the domotic controller.
* 3x relays SPST 5A
* 3x 115/230Vac optoisolated inputs
* Single common for relays and AC inputs
* 5x general purpose I/O, each one configurable as analog/digital inputs, pushbutton, counter, temperature and distance sensor.

Each relay can toggle the existing step-relay, switching the light On/Off. The optoisolator monitors the light status. The 5 I/Os can be connected to pushbuttons to activate or deactivate one or all lights.
<br clear="all"/>

### DomBus36 - Domotic module with 12 relays
<a href="https://store.creasol.it/DomBus36"><img src="https://images.creasol.it/creDomBus36_400.webp" alt="DomBus36 domotic module with 12 relay outputs" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
DIN rail module, low profile, with **12 relays outputs and very low power consumption**.
* 12x relays SPST 5A
* Relays are grouped in 3 blocks, with a single common per block, for easier wiring
* Only 12mW power consumption with all relays OFF
* Only 750mW power consumption with all 12 relays ON !!
<br clear="all"/>

### DomBus37 - 12 inputs, 3 115/230Vac inputs, 3 relay outputs
<a href="https://store.creasol.it/DomBus37"><img src="https://images.creasol.it/creDomBus37_400.webp" alt="DomBus37 domotic module with 12 inputs, 3 AC inputs, 3 relay outputs" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Module designed to **interface alarm sensors (magnetc contact sensors, PIRs, tampers): it's able to monitor mains power supply (power outage / blackout) and also have 3 relays outputs.**
* 12x low voltage inputs (analog/digital inputs, buttons, alarm sensors, **balanced double/triple biased alarm sensors**,  counters, meters, temperature and distance sensors, ...)
* 3x 115/230Vac optoisolated inputs
* 2x relays SPST 5A
* 1x relay SPST 10A
<br clear="all"/>

### DomBus38 - 12 inputs, 1 100-250Vac input, 6 relay outputs
<a href="https://store.creasol.it/DomBus38"><img src="https://images.creasol.it/creDomBus38_400.webp" alt="DomBus38 smart home module with 12 inputs, 1 AC input, 6 SPDT relay outputs + 2 SPDT relay outputs 10A" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Module designed to **interface alarm sensors (magnetc contact sensors, PIRs, tampers), lights and appliances outputs, ...**
* 12x low voltage inputs (analog/digital inputs, buttons, alarm sensors, **balanced double/triple biased alarm sensors**, counters, meters, temperature and distance sensors, ...)
* 1x 115/230Vac optoisolated input to detect power outage and for zero-crossing detection (to switch relays minimizing the in-rush current)
* 4x relays SPDT 10A (with Normally Open and Normally Closed contacts)
* 2x relays SPST 10A (with only Normally Open contacts)
<br clear="all"/>

### DomBusTracker - Dual axis sun tracker controller working with Domoticz, Home Assistant, Node-RED, Modbus, ... and also working in standalone with no external controllers
<a href="https://store.creasol.it/DomBusTracker"><img src="https://images.creasol.it/creDomBusTracker_sun_400.webp" alt="DomBusTracker smart home module that controls 2 linear actuators in a solar tracking system" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Module that **check a deep-hole sun sensor to detect the direction of maximal sun radiation, working also in case of cloudy weather.**
* Controls two external actuators/motors (linear or not) to move motors to reach the best tilt / elevation and azimuth position to optimize photovoltaic production.
* **Check current through the motors to detect internal limit switch** (useful for linear actuators) and find where the tracker reach the final/initial position.
* **Works autonomously** (stand-alone), without any home automation system controller, but **also can be connected to a home automation system using Domoticz, Home Assistant, NodeRED, OpenHAB,** and other systems by using the DomBusGateway software (that converts DomBus protocol to MQTT AutoDiscovery), or with other systems by using DomBusTracker with Modbus firmware.
* Wire connection (RS485) to the domotic controller for the best reliability.
<br clear="all"/>

### DomRelay2 - 2x relays board
<a href="https://store.creasol.it/DomRelay2"><img src="https://images.creasol.it/creDomRelay22_200.png" alt="Relay board with 2 relays, to be used with DomBus domotic modules" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
Simple module with 2 relays, to be used with DomBus modules (like <a href="https://store.creasol.it/DomBusTH">DomBusTH</a> and <a href="https://store.creasol.it/DomBus12">DomBus12</a>) or other electronic boards with open-collector or open-drain outputs
* **2x SPST relays 5A** (Normally Open contact)
* Overvoltage protection (for inductive loads, like motors)
* Overcurrent protection (for capacitive laods, like AC/DC power supply, LED bulbs, ...)
<br clear="all"/>

### DomESP1 / DomESP2 - Board with relays and more for ESP8266 NodeMCU WiFi module
<a href="https://store.creasol.it/DomESP1"><img src="https://images.creasol.it/creDomESP2_400.webp" alt="Relay board for ESP8266 NodeMCU module" style="float: left; margin-right: 2em; vertical-align: middle;" align="left" /></a>
**IoT board designed for NodeMCU v3 board using ESP8266 WiFi microcontroller**
* 9÷24V power supply input, with high efficiency DC/DC regulator with 5V output
* **4x SPST relays 5A with overvoltage protection** (varistor)
* **2x mosfet outputs** (max 30V, 10A) for LED dimming or other DC loads
* 1x I²C interface for sensors, extended I/Os and more)
* 1x OneWire interface (DS18B20 or other 1wire sensors/devices)
<br clear="all"/>

