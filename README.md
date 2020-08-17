## Domoticz lua scripts, by Creasol https://www.creasol.it
In this repository you can find several LUA scripts and config files for Domoticz, the easy and powerful open-source home automation system controller.

More information, scripts, application notes, examples are available at https://www.creasol.it/support/domotics-home-automation-and-diy

Description of some products made by our company (DomBus1, DomBusTH, ...) are available at https://www.creasol.it/products/domotics and https://store.creasol.it/en/11-domotics

All scripts are provided freely, with absolute no warranty. Use them at your own risk.


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
