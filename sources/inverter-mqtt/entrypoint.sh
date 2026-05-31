#!/bin/bash
export TERM=xterm

# Re-register MQTT auto-discovery topics every 5 minutes so HA picks them up after a restart
watch -n 300 /opt/inverter-mqtt/mqtt-init.sh > /dev/null 2>&1 &

# Poll the inverter and push values to MQTT every 30 seconds
watch -n 30 /opt/inverter-mqtt/mqtt-push.sh > /dev/null 2>&1
