# Aircraft Agent Guide

This project installs with `update aircraft`. Its files land at the ComputerCraft root, so `src/projects/aircraft/aircraft.lua` becomes `/aircraft.lua` and `src/projects/aircraft/lib/aircraft/*` becomes `/lib/aircraft/*`.

## Context To Read

- Root `AGENTS.md`, `README.md`, `docs/AGENT_RUNTIME.md`, and `docs/INGAME_DEBUGGING.md`.
- `src/projects/aircraft/config/aircraft.example.lua` for the complete config surface.
- Existing aircraft modules before editing:
  - `scanner.lua`: peripheral-router scan, orientation, roles, sampled getters.
  - `classify.lua`: capability classification from method names.
  - `flight_control.lua`: stabilization loop, mixer, rotor handedness, reports.
  - `controller.lua`: redstone-router controller input sampling.
  - `hud.lua`, `displays.lua`, `display_loop.lua`: monitor and Nixie/display output.
  - `report_tabs.lua`, `reporting.lua`: structured report presentation.
- Official Create Avionics docs are trusted for this module. Relevant pages used so far:
  - `https://solastrius.github.io/CreateAvionics/peripheral/propeller_bearing.html`
  - `https://solastrius.github.io/CreateAvionics/peripheral/gimbal_sensor.html`
  - `https://solastrius.github.io/CreateAvionics/peripheral/linked_typewriter.html`

## Operating Model

- `aircraft scan` uses a Relative Routing/Peripheral Router style block to wrap nearby peripherals by relative coordinates and writes `/aircraft_scan.txt`.
- `aircraft status` reads the cached scan without actuating the craft.
- `aircraft stabilize` needs a scan, a gimbal sensor, four mapped scalar actuator outputs, and optionally propeller bearings, displays, HUD, redstone-router controller, and kill switch.
- Commands that move or write outputs stay dry unless both `--apply` is used and `dryRun=false` in config.
- Reports should stay compact but structured. Aircraft commands save local report files and send webhook reports unless disabled.

## Coordinates And Roles

- Do not hard-code physical rotor positions. Use scan role mapping and config axes.
- `frontAxis` and `leftAxis` can override orientation. After changing axes, tell the user to run `aircraft scan` again.
- Role names are `front_left`, `front_right`, `rear_left`, and `rear_right`.
- Scan samples safe getters. Do not add setters to scan sampling.

## Stabilization And Yaw

- The gimbal provides pitch/roll angles from gravity. It does not provide absolute heading.
- Yaw damping uses angular rate `wy` from `getAngularRatesRad()`.
- Current yaw command path is direct Q/E input mixed into rotor diagonals. Future "fly to location / auto heading" work needs navigation/position data, not just the gimbal angle table.
- Mixer sign issues should usually be solved with config knobs (`yawSign`, negative `controller.yawPower`, trim/caps) before rewiring roles.

## Rotor Handedness

- Propeller bearing handedness is discovered with `getThrustHandedness()` during scan/status/control.
- The craft should be built with all rotors initially in the correct upward-thrust handedness. That scanned value is the baseline.
- Leave `rotors.handedness` empty unless the user explicitly wants an override.
- `aircraft rotor-handedness baseline` restores the scanned/configured baseline. `diagonal`, `all`, role-specific, and `toggle` modes are tools for tests, not the default model.
- Only call `setThrustHandedness()` from explicit rotor-handedness handling or the controlled baseline application path.

## Controller Inputs

- Existing controller support is through a `redstone_router` reading Redstone Link receiver blocks by relative coordinate.
- Controller placement is config-driven, not scan-driven. Use:
  - `aircraft config controller-layout <shiftX> <shiftY> <shiftZ> [side]`
  - `aircraft config controller-bind <key> <x> <y> <z> [side]`
- `controller-layout` uses the bottom-left `shift` coordinate, then lays out `shift A S D space` to aircraft right and `Q W E` one row toward aircraft front. It uses configured axes first, then scan axes, then defaults to `front=+Z` and `left=+X`.
- Missing Q/E in old configs are inferred from W/A/S/D.
- Q/E yaw math is `yaw = E - Q`; if in-game direction is backwards, tune `controller.yawPower` negative before swapping bindings.
- Linked Typewriter support is a future second controller backend. It should consume CraftOS `key` and `key_up` events without removing the current redstone controller path.

## Expected In-Game Flow

```text
update aircraft
aircraft scan
aircraft status
aircraft config show
aircraft controller
aircraft stabilize --controller --apply --seconds <n>
```

For debugging, prefer:

```text
report run aircraft status
report run aircraft config show
report run aircraft controller --seconds 5
```

Then read the local report on this PC with:

```powershell
.\tools\read_latest_report.ps1
```
