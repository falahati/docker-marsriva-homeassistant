#!/bin/bash
INFLUX_ENABLED=`cat /etc/inverter/mqtt.json | jq '.influx.enabled' -r`

pushMQTTData () {
    MQTT_SERVER=`cat /etc/inverter/mqtt.json | jq '.server' -r`
    MQTT_PORT=`cat /etc/inverter/mqtt.json | jq '.port' -r`
    MQTT_TOPIC=`cat /etc/inverter/mqtt.json | jq '.topic' -r`
    MQTT_DEVICENAME=`cat /etc/inverter/mqtt.json | jq '.devicename' -r`
    MQTT_USERNAME=`cat /etc/inverter/mqtt.json | jq '.username' -r`
    MQTT_PASSWORD=`cat /etc/inverter/mqtt.json | jq '.password' -r`
    # Use a distinct client id from the init loop so concurrent connections don't evict each other
    MQTT_CLIENTID=`cat /etc/inverter/mqtt.json | jq '.clientid' -r`_push

    mosquitto_pub \
        -h $MQTT_SERVER \
        -p $MQTT_PORT \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -i $MQTT_CLIENTID \
        -t "$MQTT_TOPIC/sensor/"$MQTT_DEVICENAME"_$1" \
        -m "$2"

    if [[ $INFLUX_ENABLED == "true" ]] ; then
        pushInfluxData $1 $2
    fi
}

pushInfluxData () {
    INFLUX_HOST=`cat /etc/inverter/mqtt.json | jq '.influx.host' -r`
    INFLUX_USERNAME=`cat /etc/inverter/mqtt.json | jq '.influx.username' -r`
    INFLUX_PASSWORD=`cat /etc/inverter/mqtt.json | jq '.influx.password' -r`
    INFLUX_DEVICE=`cat /etc/inverter/mqtt.json | jq '.influx.device' -r`
    INFLUX_PREFIX=`cat /etc/inverter/mqtt.json | jq '.influx.prefix' -r`
    INFLUX_DATABASE=`cat /etc/inverter/mqtt.json | jq '.influx.database' -r`
    INFLUX_MEASUREMENT_NAME=`cat /etc/inverter/mqtt.json | jq '.influx.namingMap.'$1'' -r`

    curl -i -XPOST "$INFLUX_HOST/write?db=$INFLUX_DATABASE&precision=s" -u "$INFLUX_USERNAME:$INFLUX_PASSWORD" --data-binary "$INFLUX_PREFIX,device=$INFLUX_DEVICE $INFLUX_MEASUREMENT_NAME=$2"
}

#####################################################################################

INVERTER_DATA=`timeout 15 python3 /opt/marsriva-cli/marsriva_poller.py`

push () {
    # Skip empty values and JSON null (null = BMS sentinel / missing register)
    local val=`echo $INVERTER_DATA | jq ".$1" -r`
    [ -n "$val" ] && [ "$val" != "null" ] && pushMQTTData "$1" "$val"
}

# --- BMS Status ---
push "bms_battery_voltage"
push "bms_battery_current"
push "bms_battery_temp"
push "bms_soc"
push "bms_max_charge_current"

# --- Battery: inverter's own measurement ---
push "battery_voltage"
push "battery_current"
push "battery_remaining_kwh"
push "charging_active"

# --- AC Output ---
push "ac_out_voltage"
push "ac_out_frequency"
push "ac_out_current"
push "ac_out_power_factor"
push "inverter_output_power"
push "inverter_output_va"
push "inverter_energy_counter"

# --- Grid ---
push "grid_voltage"
push "grid_power"
push "grid_frequency"
push "grid_energy_counter"

# --- Operating state ---
push "mode_state"
push "mode_state_secondary"

# --- Configuration mirror (read-only settings) ---
push "cfg_max_grid_charge_current"
push "cfg_output_source_priority"
push "cfg_battery_low_voltage"
push "cfg_battery_shutdown_voltage"
push "cfg_cv_charge_voltage"
push "cfg_charge_voltage"
push "cfg_back_to_grid_voltage"
push "cfg_back_to_battery_voltage"
push "cfg_grid_low_voltage"
push "cfg_grid_high_voltage"
push "cfg_equalization_voltage"
push "cfg_equalization_delay"
push "cfg_equalization_interval"
push "cfg_out2_disable_voltage"
push "cfg_max_grid_tie_power"
push "cfg_low_soc_shutdown"
push "cfg_high_soc_to_battery"
push "cfg_low_soc_to_grid"

# --- Identity ---
push "serial_number"
