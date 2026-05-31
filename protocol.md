# Marsriva MR-SPF6.5K-LP1-TL20E — Final Register Map

**Protocol**: Modbus RTU, 9600 baud, 8N1, slave address 0x01, function 0x03 (Read Holding Registers).
**Mode**: Inverter broadcasts ~22 frames every 6 seconds (one full cycle ≈ 2s active + 4s idle). No querying needed.
**Cycle marker**: Frame length 22 (serial number ASCII) marks the start of each cycle.

## Frame Index

| Frame size | Role | Notes |
|---|---|---|
| **22** | Serial number "73250527000614" (ASCII) | Marks cycle boundary |
| **38** | **BMS Status** — battery's view via CAN | All values reflect what the battery reports; sentinels appear when battery disconnected |
| **68** | **Unknown** — possibly inverter's own SOC + multi-inverter parallel info | Confirmed NOT battery data (unchanged when battery disconnected) |
| **104** | **Battery — inverter's own measurement + charge management** | Includes charging-active flag and stage |
| **108** | **AC OUT1 Measurement** (real-time, terminal block) | Slightly more accurate than F142 |
| **128** | **Configuration mirror** — every LCD setting echoed | Stable map of user settings (excluded from monitor) |
| **142** | **Inverter Output (alternate point)** | Close to OUT1 but V differs by ~hundreds of mV, A is ~1A lower; W/VA may lag LCD |
| **166** | **Grid Measurement** | Goes to 0 when grid disconnected; confirmed perfect |
| **188** | **Aggregate / roll-up** of other frames + state flags | Has mode-state flags (excluded from monitor) |
| **10** | Battery currents (transient, alternates between 2 layouts) | Behavior unclear |
| 4, 6, 12, 16, 20, 24, 26, 32, 96 | Reserved / mostly zero | Likely for unused features |

---

## Frame 38 — BMS Status (battery's view via CAN)

When the battery is **disconnected**: V/I → 32767 (sentinel), temp & max-charge → 0.

| Reg | Scale | Field | Status | Notes |
|---|---|---|---|---|
| 0 | raw | `bms_protocol_id?` | plausible | Constant 4 — likely BMS CAN protocol type (Pylon/Voltronic/etc.) |
| 2 | raw | `bms_firmware_or_model?` | plausible | Constant 114 — BMS identity/firmware |
| 3 | ÷10 V | `bms_battery_V` | ✓ confirmed | Battery voltage as reported by BMS |
| 4 | ÷10 A signed | `bms_battery_I` | ✓ confirmed | +charge / −discharge |
| 5 | ÷10 °C | `bms_battery_temp_C` | ✓ confirmed | Matches BMS-reported 30.3-30.5°C |
| 6 | raw % | `bms_SOC_pct` | ✓ confirmed | BMS-reported SOC (was 95% during test) |
| 7 | raw | reserved | — | Constant 100 |
| 8, 9 | — | reserved | — | 0x7FFF "disabled" sentinels |
| 10 | ÷10 V | `bms_bulk_charge_V?` | plausible | 56.8V — BMS-requested bulk target |
| 11 | raw A | `bms_max_charge_I` | ✓ confirmed | BMS-controlled max charge current; surges during transitions |
| 12 | raw | reserved | — | Constant 1000 |
| 13 | raw | reserved | — | 0 |
| 14 | raw % | `bms_low_soc_shutdown_pct?` | plausible | 20% — mirrors config #22 |
| 15 | raw % | `bms_low_soc_to_grid_pct?` | plausible | 50% — mirrors config #24 |
| 16 | raw % | `bms_high_soc_to_battery_pct?` | plausible | 90% — mirrors config #23 |
| 17, 18 | — | reserved | — | 0 |

---

## Frame 68 — Unknown (NOT battery data)

Disconnecting the battery does NOT change these values. The block at regs 0-15 mirrors at regs 16-31 (possibly indicates the inverter supports two of *something*). User's best guess: inverter's own SOC tracking and/or multi-inverter parallel data.

| Reg | Scale | Field | Status |
|---|---|---|---|
| 0, 16 | raw % | `inverter_SOC_pct?` | plausible — inverter's own SOC estimate (90-93 range) |
| 2, 17 | raw | `unknown_68_2?` | unknown — 11-20 range, NOT battery temp |
| 4, 18 | raw | `unknown_68_4?` | constant 1 |
| 6, 19 | raw | `unknown_68_6?` | constant 17 |
| 8, 22 | raw | `unknown_68_8?` | constant 14 |
| 12, 28 | raw | `unknown_68_12?` | constant 14 |
| others | — | reserved | 0 |

---

## Frame 104 — Battery (inverter's view + charge management)

| Reg | Scale | Field | Status | Notes |
|---|---|---|---|---|
| 0 | raw | reserved | — | Constant 3 |
| 2 | raw | reserved | — | Constant 95 |
| 4 | ÷1000 kWh | `battery_remaining_kWh?` | plausible | ~4.4 kWh on a 5.2 kWh pack (raw Wh, display as kWh) |
| 5 | ÷10 V | `battery_V_inv` | ✓ confirmed | Inverter's measured battery voltage |
| 6, 7 | ÷10 A signed | `battery_I_inv` (& dup) | ✓ confirmed | Inverter's measured battery current; +charge/−discharge |
| 8 | ÷10 V | reserved | — | Constant 600 — BMS-reported absolute max V (60.0V) |
| 9 | ÷10 V | reserved | — | Constant 480 — BMS-reported min discharge V (48.0V) |
| 12 | ÷10 V | reserved | — | Constant 480 (48.0V nominal) |
| 13 | signed | reserved | — | Constant −15 |
| 38 | raw | **`charging_active_flag`** | ✓ **confirmed** | **0 = not charging, 2 = charging** |
| 39 | ÷10 V | reserved | — | Constant 552 — float V (55.2V) |
| 40 | ÷10 V | reserved | — | Constant 544 — charge V mode (54.4V) |
| 41, 42 | raw | `charge_stage_indicator?` | plausible | 100 steady, 200 during charge-stage transitions |
| 46 | ÷10 V | reserved | — | Constant 560 — equalize V (56.0V) |
| 48 | raw | reserved | — | Constant 7200 |
| 49 | raw | reserved | — | Constant 720 |

---

## Frame 108 — AC OUT1 Measurement (real-time)

| Reg | Scale | Field | Status | Notes |
|---|---|---|---|---|
| 0 | ÷10 V | reserved | — | Constant 2300 — output voltage target (230.0V) |
| 1 | ÷100 Hz | reserved | — | Constant 5000 — frequency target (50.00 Hz) |
| 10 | ÷10 V | `out1_voltage_V` | ✓ confirmed | Slightly lower than F142.08 |
| 11 | ÷100 Hz | `out1_freq_Hz` | ✓ confirmed | Differs from F142.09 by small steps |
| 12 | ÷100 A | `out1_current_A` | ✓ confirmed | ~1A HIGHER than F142.10 |
| 13 | ÷100 signed | `out1_power_factor_x100?` | plausible | Range −0.10 to +0.80, suspected PF×100 |
| 21, 25 | raw | `unknown_108_21?` | unknown | 322-329, identical values |

---

## Frame 142 — Inverter Output (alternate measurement)

Voltage/Hz/A close to F108 but differs. Has W/VA which F108 doesn't. W/VA may lag LCD readings.

| Reg | Scale | Field | Status | Notes |
|---|---|---|---|---|
| 1 | raw | reserved | — | Constant 1 |
| 8 | ÷10 V | `inv_out_voltage_V?` | plausible | Slightly higher than F108.10 |
| 9 | ÷100 Hz | `inv_out_freq_Hz?` | plausible | |
| 10 | ÷100 A | `inv_out_current_A?` | plausible | ~1A lower than F108.12 |
| 12 | raw W | `inv_out_power_W?` | plausible | Doesn't update instantly with LCD |
| 13 | raw VA | `inv_out_VA?` | plausible | Doesn't update instantly with LCD |
| 16 | raw | `unknown_142_16?` | unknown | 67-97 |
| 18, 24 | raw | `energy_counter?` | unknown | Slow climb 5721-5821 — likely kWh×100 = 58.21 kWh total/daily |

---

## Frame 166 — Grid Measurement ✓ confirmed accurate

| Reg | Scale | Field | Status | Notes |
|---|---|---|---|---|
| 0 | ÷10 V | `grid_voltage_V` | ✓ confirmed | 0 when grid disconnected |
| 1 | raw W | `grid_power_W` | ✓ confirmed | 0 when disconnected |
| 2 | ÷100 Hz | `grid_freq_Hz` | ✓ confirmed | 0 when disconnected |
| 16, 22 | raw | `grid_energy_counter_1?` (& dup) | unknown | 7009-7125, suspected kWh×100 = 71.21 kWh imported |

---

## Frame 128 — Configuration Mirror (excluded from monitor, for reference)

Every LCD config setting is echoed here. Useful for building a writeable settings interface later.

| Reg | Value | Setting (config #) | Match |
|---|---|---|---|
| 5 | 20 | #6 Max grid charge | 20A ✓ |
| 7 | 3 | #3 Output source priority (grid first) | ✓ |
| 8 | 480 | #10 Battery low | 48.0V ✓ |
| 9 | 448 | #11 Battery shutdown | 44.8V ✓ |
| 10 | 552 | #12 CV mode voltage | 55.2V ✓ |
| 11 | 544 | #13 Charge V mode | 54.4V ✓ |
| 12 | 496 | #8 Back to grid V | 49.6V ✓ |
| 13 | 532 | #9 Back to battery V | 53.2V ✓ |
| 14 | 185 | #14 Grid low | 185V ✓ |
| 15 | 264 | #15 Grid high | 264V ✓ |
| 19 | 560 | #16 Equalization V | 56V ✓ |
| 21 | 120 | #17 Eq. delay | 120 min ✓ |
| 22 | 30 | #18 Eq. interval | 30 days ✓ |
| 24 | 480 | #20 OUT2 disable V | 48V ✓ |
| 28 | 60 | #19 Max grid-tie | 6.0 kW (×10) ✓ |
| 32 | 20 | #22 Low SOC shutdown | 20% ✓ |
| 33 | 90 | #23 High SOC → battery | 90% ✓ |
| 34 | 50 | #24 Low SOC → grid | 50% ✓ |

---

## Frame 188 — Aggregate (excluded from monitor, for reference)

Mostly duplicates of other frames, plus **operating-mode state flags**:

| `mode_state_main` (F188.03) | `mode_state_secondary` (F188.04) | State |
|---|---|---|
| 7234 (0x1C42) | 35 | Grid passthrough, idle |
| 2882 (0x0B42) | 768 | On battery (grid disconnected) |
| 576 / 578 | 258 / 768 | Transitioning |

Also has signed grid power F188.19 (−1412 to 0, where negative = importing from grid).

---

## Remaining unknowns to investigate

| Where | Best guess | How to confirm |
|---|---|---|
| F38.10 (568) | BMS-requested bulk charge V | Should match value the BMS asks for during bulk charging |
| F38.14/15/16 | BMS SOC limits vs inverter config mirror | Change config on LCD, see if these change too — they shouldn't if they're BMS-reported |
| F68 entire frame | Multi-inverter parallel? | Add a second inverter, or change config #45 (BMS ID) |
| F104.04 | Remaining Wh | Watch during long discharge — should drop linearly |
| F108.13 | Power factor | Add a known inductive load (motor) and check value |
| F142.18 / F166.16 counters | Daily or total kWh | Watch over hours; check if they reset at midnight |
| F104.41/42 charging stages | Bulk / absorb / float / equalize | Watch during full charge cycle |
