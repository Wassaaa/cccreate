# Aircraft Agent Guide

This project installs with `update aircraft`. Its files land at the ComputerCraft root, so `src/projects/aircraft/aircraft.lua` becomes `/aircraft.lua` and `src/projects/aircraft/lib/aircraft/*` becomes `/lib/aircraft/*`.

## Context To Read

- Root `AGENTS.md`, `README.md`, `docs/AGENT_RUNTIME.md`, and `docs/INGAME_DEBUGGING.md`.
- `src/projects/aircraft/config/aircraft.example.lua` for the complete config surface.
- Existing aircraft modules before editing:
  - `scanner.lua`: peripheral-router scan, orientation, roles, sampled getters.
  - `classify.lua`: capability classification from method names.
  - `flight_control.lua`: stabilization loop, roll/pitch mixer, reports.
  - `controller.lua`: aircraft adapter over shared controller input backends.
  - `hud.lua`, `displays.lua`, `display_loop.lua`: monitor and Nixie/display output.
  - `report_tabs.lua`, `reporting.lua`: structured report presentation.
- Official Create Avionics docs are trusted for this module. Relevant pages used so far:
  - `https://solastrius.github.io/CreateAvionics/peripheral/propeller_bearing.html`
  - `https://solastrius.github.io/CreateAvionics/peripheral/gimbal_sensor.html`
  - `https://solastrius.github.io/CreateAvionics/peripheral/linked_typewriter.html`

## Operating Model

- `aircraft scan` uses a Relative Routing/Peripheral Router style block to wrap nearby peripherals by relative coordinates and writes `/aircraft_scan.txt`.
- `aircraft status` reads the cached scan without actuating the craft.
- `aircraft stabilize` needs a scan, a gimbal sensor, four mapped scalar actuator outputs, and optionally propeller bearings, displays, HUD, controller input, and kill switch.
- Commands that move or write outputs stay dry unless both `--apply` is used and `dryRun=false` in config.
- Reports should stay compact but structured. Aircraft commands save local report files and send webhook reports unless disabled.

## Coordinates And Roles

- Do not hard-code physical rotor positions. Use scan role mapping and config axes.
- `frontAxis` and `leftAxis` can override orientation. After changing axes, tell the user to run `aircraft scan` again.
- Role names are `front_left`, `front_right`, `rear_left`, and `rear_right`.
- Scan samples safe getters. Do not add setters to scan sampling.

## Parallelism Notes

- Use `parallel` for Create: Avionics calls that yield until a server tick, especially routed/network peripheral work and setters. Plain local reads usually do not need it.
- `aircraft scan` runs routed coordinate probes through a worker pool controlled by `scan.parallelism` / `aircraft config scan-parallelism <workers>`. Default is 32; flight testing found 24 was a good practical value on the current setup. Higher values can be useful for experiments, but expect diminishing returns once the router or server tick is saturated.
- The stabilization actuator writes already batch the four scalar `setSignal` calls with `parallel.waitForAll`. Keep this path batched; do not replace it with sequential writes.
- Nixie/display writes are already batched across role displays. If a single Nixie/display array is used later, prefer one text write for the whole array, then keep its refresh interval slower than the control loop.
- The `redstone_router` controller backend already samples configured key bindings in parallel. Future controller backends that read multiple routed peripherals should preserve that shape or use a bounded worker pool when the input count grows.

## Stabilization And Heading

- The gimbal provides pitch/roll angles from gravity. It does not provide absolute heading.
- Do not add yaw correction to the four vertical-rotor mixer. Testing showed diagonal rotor thrust and handedness changes do not create useful yaw in the current simulation.
- Yaw-rate damping is handled separately through gyroscopic propeller bearing `setManualTarget()` calls. Neutral manual targets stay on craft-local up; yaw damping adds only a local tangential tilt so roll/pitch disturbances do not become bearing tilt.
- Future commanded heading hold should use the navigation table heading/orientation on top of the yaw-rate damper.
- Propeller bearing handedness may still be read with `getThrustHandedness()` for diagnostics. Do not write `setThrustHandedness()` from this module unless a future actuator design has a proven need.
- The mixer may desaturate rotor powers before clipping, shifting/scaling the power set to preserve pitch/roll correction while leaving headroom near 0 or max redstone power.
- Tilt compensation is collective-only: it adds bounded base power for the requested pitch/roll target, not accidental measured tumble. It is not real altitude hold.

## Controller Inputs

- Controller support goes through the shared `/lib/control_input.lua` layer. Current backends are `redstone_router` and `keyboard`.
- The `redstone_router` backend reads Redstone Link receiver blocks by relative coordinate.
- Controller placement is config-driven, not scan-driven. Use:
  - `aircraft config controller-type <redstone_router|keyboard>`
  - `aircraft config controller-layout <shiftX> <shiftY> <shiftZ> [side]`
  - `aircraft config controller-bind <key> <x> <y> <z> [side]`
- `controller-layout` uses the bottom-left `shift` coordinate, then lays out `shift A S D space` to aircraft right and `W` one row toward aircraft front. It uses configured axes first, then scan axes, then defaults to `front=+Z` and `left=+X`.
- The `keyboard` backend consumes CraftOS `key` and `key_up` events from an onboard keyboard or Create: Avionics Linked Typewriter.
- Controller throttle defaults to hold mode. `space` raises the retained throttle offset, `shift` lowers it, and the value is bounded by `controller.throttlePower`.
- The controller `k` input is reserved for the aircraft kill switch. It must not be mixed into movement axes.
- Physical kill switches can use local computer-side redstone or a redstone-router relative coordinate via `aircraft config killswitch-router <x> <y> <z> [side] [activeHigh]`.
- Use `aircraft killswitch --seconds <n>` to probe the configured kill switch and controller `k` key without running stabilization.

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
