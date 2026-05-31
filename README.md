# Marsriva MR-SPF6.5K-LP1-TL20E → Home Assistant via MQTT

A Docker container that reads live data from a **Marsriva MR-SPF6.5K-LP1-TL20E**
hybrid inverter and publishes it to **Home Assistant** via MQTT auto-discovery.

---

## How it works

The inverter continuously broadcasts Modbus RTU frames (9600 8N1) on its RS232
diagnostic port — no commands need to be sent. The container listens on that
serial port, decodes one complete broadcast cycle (~6 s), and pushes the parsed
values to your MQTT broker every 30 seconds. Home Assistant picks up the sensors
automatically through MQTT discovery.

```
Marsriva RS232 port
   │  (USB dongle, /dev/ttyUSB0)
   ▼
marsriva_poller.py  ──►  JSON on stdout
   │
mqtt-push.sh ──►  mosquitto_pub  ──►  MQTT broker  ──►  Home Assistant
```

---

## Prerequisites

- Docker + Docker Compose
- A running MQTT broker accessible from the container (e.g. Mosquitto add-on in HA)
- MQTT integration enabled in Home Assistant (with auto-discovery on)
- The inverter connected via an RS232→USB dongle (typically `/dev/ttyUSB0`)

---

## Setup

### 1. Configure MQTT

Edit `config/mqtt.json`:

```json
{
    "server": "192.168.1.10",
    "port": "1883",
    "topic": "homeassistant",
    "devicename": "marsriva",
    "username": "mqtt_user",
    "password": "mqtt_pass",
    "clientid": "marsriva_a3f7c1d9e4b2085f",
    "influx": {
        "enabled": "false",
        ...
    }
}
```

Set `server` to your MQTT broker's IP and fill in credentials if required.

### 2. Check the USB device path

The default serial port is `/dev/ttyUSB0`. If your dongle appears on a different
path, update the `devices` section in `docker-compose.yml` and pass `--port` to the
poller (edit `mqtt-push.sh` line with `marsriva_poller.py`).

### 3. Start the container

```bash
docker compose up -d
```

Sensors will appear in Home Assistant under `sensor.marsriva_*` within a minute.

---

## Published sensors

All sensor names follow the pattern `sensor.marsriva_<field>`.

### Confirmed accurate (✓)

| Sensor | Unit | Description |
|---|---|---|
| `bms_battery_voltage` | V | Battery voltage (BMS view) |
| `bms_battery_current` | A | Battery current, + charge / − discharge (BMS view) |
| `bms_battery_temp` | °C | Battery temperature (BMS reported) |
| `bms_soc` | % | State of charge (BMS reported) |
| `bms_max_charge_current` | A | Max charge current requested by BMS |
| `battery_voltage` | V | Battery voltage (inverter measured) |
| `battery_current` | A | Battery current (inverter measured, signed) |
| `charging_active` | — | 0 = not charging, 2 = charging |
| `ac_out_voltage` | V | AC output voltage |
| `ac_out_frequency` | Hz | AC output frequency |
| `ac_out_current` | A | AC output current |
| `grid_voltage` | V | Grid voltage (0 when grid disconnected) |
| `grid_power` | W | Grid power (0 when grid disconnected) |
| `grid_frequency` | Hz | Grid frequency (0 when grid disconnected) |
| `serial_number` | — | Inverter serial number |

### Plausible — best effort (meaning not fully confirmed)

| Sensor | Unit | Notes |
|---|---|---|
| `battery_remaining_kwh` | kWh | Estimated remaining capacity |
| `ac_out_power_factor` | — | Suspected power factor ÷100 |
| `inverter_output_power` | W | Output power (may lag LCD slightly) |
| `inverter_output_va` | VA | Apparent power (may lag LCD slightly) |
| `inverter_energy_counter` | — | Slow-climbing counter, approx kWh×100 |
| `grid_energy_counter` | — | Slow-climbing counter, approx kWh×100 |

---

## InfluxDB (optional)

Set `influx.enabled` to `"true"` in `config/mqtt.json` and fill in the
`host`, `username`, `password`, and `database` fields. Each field will be written
to the configured measurement using the name in `namingMap`. Rename the values in
`namingMap` to match your InfluxDB schema if needed.

---

## Testing without hardware

The poller includes a file-replay mode for offline testing:

```bash
# Record a capture on the Pi:
cat /dev/ttyUSB0 > /tmp/inverter_capture.bin  # Ctrl-C after a few seconds

# Replay on any machine with Python 3:
python3 sources/marsriva-cli/marsriva_poller.py --file /tmp/inverter_capture.bin
```

This prints the same JSON that `mqtt-push.sh` would receive in production.

---

## Troubleshooting

**No sensors in HA** — Check that the MQTT broker address is correct in `mqtt.json`
and that HA has MQTT auto-discovery enabled (`discovery: true` in the MQTT
integration settings).

**Timeout / no data** — Verify the USB dongle is mapped to `/dev/ttyUSB0` inside
the container (`docker exec marsriva-mqtt ls /dev/ttyUSB0`) and that `privileged:
true` is set in `docker-compose.yml`.

**Wrong values** — Some "plausible" fields may read incorrectly until the inverter's
register map is fully validated against your specific firmware. Confirmed fields
(see table above) are reliable.

---

## Protocol notes

The Marsriva MR-SPF6.5K-LP1-TL20E broadcasts Modbus RTU frames at 9600 baud on
slave address `0x01` with function code `0x03`. It does **not** respond to queries —
it broadcasts unprompted. A full cycle of ~22 frames repeats every ~6 seconds. The
22-byte payload frame carries the serial number (ASCII) and marks the start of each
new cycle.

Full register map with decoded field meanings is documented in the source code:
[`sources/marsriva-cli/marsriva_poller.py`](sources/marsriva-cli/marsriva_poller.py)
