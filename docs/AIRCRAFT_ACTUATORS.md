# Aircraft Actuator Backends

The aircraft stabilizer computes four per-rotor power demands from the same PD mixer regardless of how the drivetrain is controlled. The final write step is selected by `actuator.type`.

## Backends

`redstone_signal` is the default and keeps the current analog-transmission setup. The mixer power range is `0..absoluteSignalMax`; output is inverted as `brakeSignal - power`, then written with `setSignal` to the scanned `scalarActuator` role map.

`rotation_speed` maps that same mixer power range to target RPM and writes it to scanned `speedActuator` roles. Create Rotation Speed Controllers expose `setTargetSpeed(speed)` and `getTargetSpeed()`, with target speed clamped by the block to the in-game `-256..256 RPM` range.

Default mapping:

```lua
actuator = {
  type = "redstone_signal",
  rotationSpeed = {
    roleFamily = "speedActuator",
    setter = "setTargetSpeed",
    getter = "getTargetSpeed",
    idleRpm = 0,
    powerRpm = 256,
    brakeRpm = 0,
    minRpm = -256,
    maxRpm = 256,
    sign = 1,
    round = true,
  },
}
```

For rotation speed control, target RPM is:

```text
idleRpm + sign * powerRpm * clamp(power / maxPower, 0, 1)
```

The result is clamped to `minRpm..maxRpm` and rounded by default because the Create controller API expects integer RPM.

## Migration Flow

Keep the current craft on `redstone_signal` until four speed controllers are physically placed and connected.

One scan can contain both systems. The scanner maps analog transmission controls under
`scalarActuator` and Rotation Speed Controllers under `speedActuator`; the active backend is
selected by config.

When ready:

```text
aircraft config actuator-type rotation_speed
aircraft config rotation-speed 256 0 1 0 -256 256
aircraft scan
aircraft status
aircraft stabilize --seconds 1
```

Only use `--apply` after `aircraft status` shows four mapped `speedActuator` roles and dry-run stabilize reports plausible RPM outputs.

For A/B testing on a practice rig:

```text
aircraft stabilize --seconds 1 --actuator-type redstone_signal
aircraft stabilize --seconds 1 --actuator-type rotation_speed
```

`aircraft stabilize`, `aircraft brake`, the HUD, displays, and reports use the selected actuator backend. `aircraft signal` intentionally remains a raw `setSignal` diagnostic for the legacy redstone/transmission hardware.

## Future Blocks

Future fine-control blocks should fit the same module by exposing:

- one scalar setter, configured as `actuator.rotationSpeed.setter`
- one getter for status, configured as `actuator.rotationSpeed.getter`
- a stable scanned category and four-corner role map

If a future block uses a different unit than RPM, keep the backend shape but add a new `actuator.type` rather than overloading `rotation_speed`.
