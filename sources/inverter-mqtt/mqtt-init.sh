#!/bin/bash
#
# Register MQTT auto-discovery topics for all Marsriva sensors.
# Runs once at startup and every 5 minutes so HA picks them back up after a restart.

MQTT_SERVER=`cat /etc/inverter/mqtt.json | jq '.server' -r`
MQTT_PORT=`cat /etc/inverter/mqtt.json | jq '.port' -r`
MQTT_TOPIC=`cat /etc/inverter/mqtt.json | jq '.topic' -r`
MQTT_DEVICENAME=`cat /etc/inverter/mqtt.json | jq '.devicename' -r`
MQTT_USERNAME=`cat /etc/inverter/mqtt.json | jq '.username' -r`
MQTT_PASSWORD=`cat /etc/inverter/mqtt.json | jq '.password' -r`
MQTT_MANUFACTURER=`cat /etc/inverter/mqtt.json | jq '.manufacturer' -r`
MQTT_MODEL=`cat /etc/inverter/mqtt.json | jq '.model' -r`
MQTT_SERIAL=`cat /etc/inverter/mqtt.json | jq '.serial' -r`
MQTT_VER=`cat /etc/inverter/mqtt.json | jq '.ver' -r`
# Use a distinct client id from the push loop so concurrent connections don't evict each other
MQTT_CLIENTID=`cat /etc/inverter/mqtt.json | jq '.clientid' -r`_init

registerTopic () {
    # $1=field_name  $2=unit  $3=mdi_icon
    mosquitto_pub \
        -h $MQTT_SERVER \
        -p $MQTT_PORT \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -i $MQTT_CLIENTID \
        -t "$MQTT_TOPIC/sensor/"$MQTT_DEVICENAME"_$1/config" \
        -m "{
            \"name\": \""$MQTT_DEVICENAME"_$1\",
            \"unique_id\": \""$MQTT_DEVICENAME"_$1\",
            \"unit_of_measurement\": \"$2\",
            \"state_topic\": \"$MQTT_TOPIC/sensor/"$MQTT_DEVICENAME"_$1\",
            \"icon\": \"mdi:$3\",
            \"device\": {
                \"identifiers\": [\""$MQTT_DEVICENAME"_"$MQTT_SERIAL"\"],
                \"manufacturer\": \"$MQTT_MANUFACTURER\",
                \"model\": \"$MQTT_MODEL\",
                \"name\": \"$MQTT_DEVICENAME\",
                \"sw_version\": \"$MQTT_VER\"
            }
        }"
}

# --- BMS Status (battery's reported view via CAN) ---
registerTopic "bms_battery_voltage"     "V"   "battery-outline"
registerTopic "bms_battery_current"     "A"   "current-dc"
registerTopic "bms_battery_temp"        "°C"  "thermometer"
registerTopic "bms_soc"                 "%"   "battery-outline"
registerTopic "bms_max_charge_current"  "A"   "current-dc"

# --- Battery: inverter's own measurement ---
registerTopic "battery_voltage"         "V"   "battery-outline"
registerTopic "battery_current"         "A"   "current-dc"
registerTopic "battery_remaining_kwh"   "kWh" "battery-charging-outline"
registerTopic "charging_active"         ""    "power"

# --- AC Output ---
registerTopic "ac_out_voltage"          "V"   "power-plug"
registerTopic "ac_out_frequency"        "Hz"  "sine-wave"
registerTopic "ac_out_current"          "A"   "current-ac"
registerTopic "ac_out_power_factor"     ""    "alpha-p-circle-outline"
registerTopic "inverter_output_power"   "W"   "flash"
registerTopic "inverter_output_va"      "VA"  "flash-outline"
registerTopic "inverter_energy_counter" ""    "counter"

# --- Grid ---
registerTopic "grid_voltage"            "V"   "power-plug"
registerTopic "grid_power"              "W"   "transmission-tower"
registerTopic "grid_frequency"          "Hz"  "sine-wave"
registerTopic "grid_energy_counter"     ""    "counter"

# --- Configuration mirror (read-only settings echoed by the inverter) ---
registerTopic "cfg_max_grid_charge_current"   "A"   "current-ac"
registerTopic "cfg_output_source_priority"    ""    "cog-outline"
registerTopic "cfg_battery_low_voltage"       "V"   "battery-outline"
registerTopic "cfg_battery_shutdown_voltage"  "V"   "battery-outline"
registerTopic "cfg_cv_charge_voltage"         "V"   "battery-charging"
registerTopic "cfg_charge_voltage"            "V"   "battery-charging"
registerTopic "cfg_back_to_grid_voltage"      "V"   "transmission-tower"
registerTopic "cfg_back_to_battery_voltage"   "V"   "battery-outline"
registerTopic "cfg_grid_low_voltage"          "V"   "transmission-tower"
registerTopic "cfg_grid_high_voltage"         "V"   "transmission-tower"
registerTopic "cfg_equalization_voltage"      "V"   "battery-charging"
registerTopic "cfg_equalization_delay"        "min" "timer-outline"
registerTopic "cfg_equalization_interval"     "d"   "calendar"
registerTopic "cfg_out2_disable_voltage"      "V"   "power-plug-outline"
registerTopic "cfg_max_grid_tie_power"        "kW"  "transmission-tower"
registerTopic "cfg_low_soc_shutdown"          "%"   "battery-outline"
registerTopic "cfg_high_soc_to_battery"       "%"   "battery-outline"
registerTopic "cfg_low_soc_to_grid"           "%"   "battery-outline"

# --- Identity ---
registerTopic "serial_number"           ""    "identifier"
