# Create Native CC:Tweaked Peripherals

Create has native CC:Tweaked integration for many blocks. The older Create GitHub wiki notes that listed peripherals do not require an addon; the newer Create wiki has expanded Create 6 pages.

Starting links:

- Overview from Create GitHub wiki: https://github.com/Creators-of-Create/Create/wiki/ComputerCraft-Integration
- Current Create CC:Tweaked wiki section, accessible through any page sidebar: https://wiki.createmod.net/users/cc-tweaked-integration/rotational-speed-controller

Always verify in game with `peripheral.getNames()`, `peripheral.getType(name)`, and `peripheral.getMethods(name)`.

## Kinetics and Motion

- Sequenced Gearshift: https://wiki.createmod.net/users/cc-tweaked-integration/sequenced-gearshift
  - Methods: `rotate(angle, modifier)`, `move(distance, modifier)`, `isRunning()`.
  - Use for precise shaft rotation and piston/pulley/gantry movement. Validate positive distances/angles and use negative modifiers for reverse movement.
- Rotational Speed Controller: https://wiki.createmod.net/users/cc-tweaked-integration/rotational-speed-controller
  - Methods: `setTargetSpeed(speed)`, `getTargetSpeed()`.
  - RPM target is clamped by Create docs to `-256..256`.
- Creative Motor: https://wiki.createmod.net/users/cc-tweaked-integration/creative-motor
  - Methods: `setGeneratedSpeed(speed)`, `getGeneratedSpeed()`.
  - Creative-only, but useful for testing control loops.
- Speedometer: https://wiki.createmod.net/users/cc-tweaked-integration/speedometer
  - Method: `getSpeed()`.
  - Event: `speed_change`.
- Stressometer: https://wiki.createmod.net/users/cc-tweaked-integration/stressometer
  - Methods: `getStress()`, `getStressCapacity()`.
  - Events: `overstressed`, `stress_change`.
- Sticker: https://wiki.createmod.net/users/cc-tweaked-integration/sticker
  - Methods: `isExtended()`, `isAttachedToBlock()`, `extend()`, `retract()`, `toggle()`.

## Displays

- Display Link: https://wiki.createmod.net/users/cc-tweaked-integration/display-link
  - Terminal-like methods include `setCursorPos`, `getCursorPos`, `getSize`, `isColor`, `write`, `writeBytes`, `clearLine`, `clear`, `update`.
  - Writes go to an internal buffer. Call `update()` to push to the display target.
- Nixie Tube: https://wiki.createmod.net/users/cc-tweaked-integration/nixie-tube
  - Methods include `setText`, `setTextColour`/`setTextColor`, and `setSignal`.
  - Useful for status, counters, alarms, and compact dashboards.

## Trains

- Train Station: https://wiki.createmod.net/users/cc-tweaked-integration/train/train-station
  - Methods include `assemble`, `disassemble`, assembly mode, station name, train presence, train name, schedules, `canTrainReach`, and `distanceTo`.
  - Events include `train_imminent`, `train_arrival`, and `train_departure`.
  - Validate station connectivity and route availability before changing schedules.
- Train Signal: https://wiki.createmod.net/users/cc-tweaked-integration/train/train-signal
  - Methods include `getState`, `isForcedRed`, `setForcedRed`, `getSignalType`, `cycleSignalType`, `listBlockingTrainNames`.
  - Event: `train_signal_state_change`.
- Train Observer: https://wiki.createmod.net/users/cc-tweaked-integration/train/train-observer
  - Use for route and train event sensing when present. Probe methods in game because behavior depends heavily on placement.
- Train Schedule Lua format: https://wiki.createmod.net/users/cc-tweaked-integration/train/train-schedule
  - Schedules are Lua tables with `cyclic`, `entries`, one instruction per entry, and nested OR/AND conditions.
  - Build schedule tables explicitly and report them before applying.
- Libraries for train schedules: https://wiki.createmod.net/users/cc-tweaked-integration/train/libraries

## Logistics

Create 6 logistics are powerful and version-sensitive. Probe live methods before writing irreversible automation.

- Packager: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/packager
  - Common surface includes package content inspection, `makePackage()`, `setAddress(address)`, and package events.
- Re-Packager: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/repackager
  - Similar to Packager, but note documented limitations around encoded packages.
- Stock Ticker: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/stock-ticker
  - Provides complex filtered requests. Keep filters small and test with harmless item counts first.
- Redstone Requester: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/redstone-requester
  - Supports request configuration, item requests, crafting requests, and programmatic request execution.
- Table Cloth: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/table-cloth
  - Store/shop behavior can become a peripheral only under documented conditions. Probe before depending on it.
- Package Frogport: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/package-frogport
- Postbox: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/postbox
- Package Object: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/package-object
- Order Data Object: https://wiki.createmod.net/users/cc-tweaked-integration/logistics/order-data-object

## Create Redstone Blocks

These are in-world Create mechanisms, not necessarily CC peripherals. Use CC redstone output, redstone relays, or bridge add-ons to control them.

- Redstone Link community wiki: https://create.fandom.com/wiki/Redstone_Link
  - Sends/receives redstone by two-item frequency, preserves signal strength, has a configurable range, and can be part of train schedule conditions.
- Redstone Additions community wiki: https://create.fandom.com/wiki/Redstone_Additions
- Pulse Repeater community wiki: https://create.fandom.com/wiki/Pulse_Repeater
- Gearshift community wiki: https://create.fandom.com/wiki/Gearshift

For precise control, prefer direct Create peripherals where available. Use redstone links for routing and physical compatibility with existing contraptions.

## Implementation Patterns

- For kinetic control, build a closed loop with Speedometer/Stressometer inputs and Speed Controller/Gearshift outputs.
- For safety, listen for `overstressed` and set a controller speed to zero or disable a clutch/link.
- For displays, batch writes and call `update()` once per frame.
- For trains, subscribe to train events and use route checks before schedule mutation.
- For logistics, write a dry-run/probe mode that prints intended requests before calling request/make methods.
