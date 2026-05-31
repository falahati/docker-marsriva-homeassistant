#!/usr/bin/env python3
"""
marsriva_poller.py - Marsriva MR-SPF6.5K-LP1-TL20E one-shot JSON poller

Reads one complete broadcast cycle from the inverter's RS232 diagnostic port
(Modbus RTU, 9600 8N1, broadcast-only — no querying) and prints a single JSON
object to stdout, then exits.  Designed to be called by mqtt-push.sh the same
way the old inverter_poller -1 was called.

Usage:
    python3 marsriva_poller.py [--port /dev/ttyUSB0] [--baud 9600] [--timeout 12]
    python3 marsriva_poller.py --file /tmp/capture.bin   # replay a capture

Environment overrides:
    MARSRIVA_PORT, MARSRIVA_BAUD
"""

import argparse
import json
import os
import sys
import time

try:
    import serial
except ImportError:
    serial = None

SERIAL_FRAME_LEN = 22   # length-22 payload = serial-number ASCII, marks cycle boundary
BMS_SENTINEL = 32767    # 0x7FFF: BMS reports this when battery is disconnected


# ---------------------------------------------------------------------------
# Register map: (frame_len, reg_index, json_key, scale, signed)
#   scale  = divisor (raw / scale = published value)
#   signed = True means treat raw as a signed int16
#
# Only confirmed (✓) and high-value plausible fields are included.
# Plausible fields are noted in comments.
# ---------------------------------------------------------------------------
REGISTER_MAP = [
    # --- Frame 38: BMS Status (battery's reported view via CAN BUS) ---
    (38,  3, "bms_battery_voltage",      10,   False),  # ✓ ÷10 V
    (38,  4, "bms_battery_current",      10,   True),   # ✓ ÷10 A, +charge/-discharge
    (38,  5, "bms_battery_temp",         10,   False),  # ✓ ÷10 °C
    (38,  6, "bms_soc",                   1,   False),  # ✓ %
    (38, 11, "bms_max_charge_current",    1,   False),  # ✓ A

    # --- Frame 104: Battery — inverter's own measurement + charge management ---
    (104,  4, "battery_remaining_kwh",  1000,  False),  # plausible ÷1000 kWh
    (104,  5, "battery_voltage",          10,  False),  # ✓ ÷10 V (inverter-measured)
    (104,  6, "battery_current",          10,  True),   # ✓ ÷10 A, signed
    (104, 38, "charging_active",           1,  False),  # ✓ 0=not charging, 2=charging

    # --- Frame 108: AC OUT1 Measurement (real-time, terminal-block) ---
    (108, 10, "ac_out_voltage",           10,  False),  # ✓ ÷10 V
    (108, 11, "ac_out_frequency",        100,  False),  # ✓ ÷100 Hz
    (108, 12, "ac_out_current",          100,  False),  # ✓ ÷100 A
    (108, 13, "ac_out_power_factor",     100,  True),   # plausible ÷100, signed

    # --- Frame 142: Inverter output (alternate measurement point) ---
    (142, 12, "inverter_output_power",     1,  False),  # plausible W
    (142, 13, "inverter_output_va",        1,  False),  # plausible VA
    (142, 18, "inverter_energy_counter",   1,  False),  # plausible ≈kWh×100

    # --- Frame 166: Grid measurement (confirmed accurate, 0 when grid off) ---
    (166,  0, "grid_voltage",            10,   False),  # ✓ ÷10 V
    (166,  1, "grid_power",               1,   False),  # ✓ W
    (166,  2, "grid_frequency",         100,   False),  # ✓ ÷100 Hz
    (166, 16, "grid_energy_counter",      1,   False),  # plausible ≈kWh×100
]

# Build a lookup: (frame_len, reg_index) → (json_key, scale, signed)
_REG_LOOKUP = {(fl, ri): (key, scale, sgn) for fl, ri, key, scale, sgn in REGISTER_MAP}

# The set of frame lengths we need to see at least once for a complete reading.
TARGET_FRAME_LENS = {fl for fl, _, _, _, _ in REGISTER_MAP}


# ---------------------------------------------------------------------------
# Modbus RTU helpers  (from POC, unchanged)
# ---------------------------------------------------------------------------

def modbus_crc(data):
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def decode_frame(length, payload):
    """
    Decode one validated Modbus frame.
    Returns {'__serial': str} for the serial-number frame, or
    {(length, reg_index): raw_uint16, ...} for data frames.
    """
    if length == SERIAL_FRAME_LEN:
        sn = bytes(payload[:14]).rstrip(b'\x00').decode('ascii', errors='replace')
        return {'__serial': sn}

    result = {}
    n_regs = length // 2
    for r in range(n_regs):
        raw = (payload[r * 2] << 8) | payload[r * 2 + 1]
        result[(length, r)] = raw
    return result


def scan_frames(buf):
    """
    Scan a bytes/bytearray for valid Modbus RTU frames.
    Yields (frame_length, payload_bytes, end_offset) for each valid frame.
    """
    i = 0
    while i < len(buf) - 5:
        if buf[i] == 0x01 and buf[i + 1] == 0x03:
            L = buf[i + 2]
            total = 3 + L + 2
            if i + total <= len(buf):
                frame = bytes(buf[i:i + total])
                expected_crc = modbus_crc(frame[:-2])
                actual_crc = (frame[-1] << 8) | frame[-2]
                if expected_crc == actual_crc:
                    yield L, frame[3:-2], i + total
                    i += total
                    continue
        i += 1


# ---------------------------------------------------------------------------
# Decode one cycle's raw register dict into the JSON output dict
# ---------------------------------------------------------------------------

def build_output(cycle_regs, serial_str):
    out = {}
    if serial_str:
        out['serial_number'] = serial_str

    for (fl, ri), raw in cycle_regs.items():
        entry = _REG_LOOKUP.get((fl, ri))
        if entry is None:
            continue
        key, scale, signed = entry

        if raw == BMS_SENTINEL:
            out[key] = None  # battery disconnected — push script will skip
            continue

        if signed and raw >= 32768:
            value = raw - 65536
        else:
            value = raw

        if scale == 1:
            out[key] = value
        else:
            out[key] = round(value / scale, 3 if scale >= 1000 else (2 if scale >= 100 else 1))

    return out


# ---------------------------------------------------------------------------
# Collection strategy
#
# The inverter broadcasts ~22 frames per ~6s cycle, with a length-22 serial
# frame somewhere in the middle marking the boundary. We do NOT rely on a
# single serial-to-serial cycle (the stream can contain short/runt cycles at
# capture boundaries, which would yield a partial reading). Instead we MERGE
# every register from every valid frame seen during the listening window —
# latest value wins — so as long as each frame type appears at least once we
# get a complete reading.
# ---------------------------------------------------------------------------

def have_complete_reading(regs):
    """True once we've collected at least one register from every target frame."""
    seen_lens = {fl for (fl, _ri) in regs}
    return TARGET_FRAME_LENS.issubset(seen_lens)


# ---------------------------------------------------------------------------
# File replay mode
# ---------------------------------------------------------------------------

def run_file(path):
    with open(path, 'rb') as f:
        data = f.read()

    regs = {}
    serial_str = None
    for L, payload, _ in scan_frames(data):
        decoded = decode_frame(L, payload)
        if '__serial' in decoded:
            serial_str = decoded['__serial']
        else:
            regs.update(decoded)

    if regs or serial_str:
        print(json.dumps(build_output(regs, serial_str)))


# ---------------------------------------------------------------------------
# Live serial mode (listen, merge all frames, emit once complete or on timeout)
# ---------------------------------------------------------------------------

def run_live(port, baud, timeout_s):
    if serial is None:
        sys.exit("pyserial is not installed. Run: pip3 install pyserial")

    try:
        s = serial.Serial(port, baud, timeout=0.2)
    except serial.SerialException as e:
        sys.exit(f"Cannot open {port}: {e}")

    s.reset_input_buffer()

    buf = bytearray()
    regs = {}
    serial_str = None
    deadline = time.monotonic() + timeout_s

    try:
        while time.monotonic() < deadline:
            data = s.read(2048)
            if data:
                buf.extend(data)

            last_valid = 0
            for L, payload, end in scan_frames(buf):
                decoded = decode_frame(L, payload)
                if '__serial' in decoded:
                    serial_str = decoded['__serial']
                else:
                    regs.update(decoded)
                last_valid = end
            buf = buf[last_valid:]

            # Stop early once we have the serial number plus every target frame.
            if serial_str is not None and have_complete_reading(regs):
                break
    finally:
        s.close()

    if regs or serial_str:
        print(json.dumps(build_output(regs, serial_str)))
    else:
        sys.exit("Timeout: no data received from inverter")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    default_port = os.environ.get('MARSRIVA_PORT', '/dev/ttyUSB0')
    default_baud = int(os.environ.get('MARSRIVA_BAUD', '9600'))

    parser = argparse.ArgumentParser(description='Marsriva one-shot JSON poller')
    parser.add_argument('--port',    default=default_port, help='Serial port (default: %(default)s)')
    parser.add_argument('--baud',    default=default_baud, type=int, help='Baud rate (default: %(default)s)')
    parser.add_argument('--timeout', default=10, type=int, help='Max live read time in seconds; exits earlier once a complete reading is collected (default: %(default)s)')
    parser.add_argument('--file',    help='Replay a binary capture file instead of reading live')
    args = parser.parse_args()

    if args.file:
        run_file(args.file)
    else:
        run_live(args.port, args.baud, args.timeout)


if __name__ == '__main__':
    main()
