# Aircraft Actuator Backends

The aircraft stabilizer selects its rotor mixer and write step by `actuator.type`. The legacy backend keeps the original redstone-power PD path; the rotation-speed backend uses native RPM values.

## Backends

`redstone_signal` is the default and keeps the current analog-transmission setup. The mixer power range is `0..absoluteSignalMax`; output is inverted as `brakeSignal - power`, then written with `setSignal` to the scanned `scalarActuator` role map.

`rotation_speed` uses a separate RPM-native mixer and writes it to scanned `speedActuator` roles. Create Rotation Speed Controllers expose `setTargetSpeed(speed)` and `getTargetSpeed()`, with target speed clamped by the block to the in-game `-256..256 RPM` range. The setter yields until the next server tick, so the backend throttles repeated writes with `writeInterval` and `writeDeadbandRpm`.

Default rotation-speed config:

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
    autoRoleSigns = true,
    roleSigns = nil,
    round = false,
    baseRpm = 0,
    throttleRpmPerPower = 16,
    axis1KpRpm = 0,
    axis1KdRpm = 0,
    axis2KpRpm = 0,
    axis2KdRpm = 0,
    axis1TrimRpm = 0,
    axis2TrimRpm = 0,
    maxCorrectionRpm = 0,
    minTargetRpm = 0,
    maxTargetRpm = 256,
    desaturateHeadroomRpm = nil,
    writeInterval = 0.1,
    writeDeadbandRpm = 0.5,
  },
}
```

For legacy power-to-RPM diagnostics, target RPM is still available as:

```text
idleRpm + sign * roleSign * powerRpm * clamp(power / maxPower, 0, 1)
```

The active stabilizer path for `rotation_speed` does not use `stabilize.basePower`, `stabilize.axis*Kp`, `stabilize.axis*Kd`, or `stabilize.maxCorrection`. It computes native local target RPM directly:

```text
baseRpm + controllerThrottle * throttleRpmPerPower +/- axis RPM corrections
```

Before local unsigned targets are clamped, rotation-speed mode now uses the same `stabilize.desaturate` shift/scale pass as the redstone backend. This matters during descent: if the requested correction would push one rotor below `minTargetRpm`, the mixer raises or scales the whole RPM set instead of silently throwing away one side of the stabilizer. `desaturateHeadroomRpm=nil` derives RPM headroom from `stabilize.desaturateHeadroom * throttleRpmPerPower`; set a number only when a rig needs a different minimum spinning margin.

The local unsigned target is then clamped to `minTargetRpm..maxTargetRpm`, multiplied by global `sign` and per-corner `roleSign`, and clamped to `minRpm..maxRpm` before writing. Fractional RPM is sent by default; set `round=true` only for a future block that rejects floats. `roleSign` defaults to scan-derived controller-to-rotor geometry when `autoRoleSigns=true`; use `aircraft config rotation-speed-signs 1 1 -1 -1` for an explicit override.

## Migration Flow

Keep the current craft on `redstone_signal` until four speed controllers are physically placed and connected.

One scan can contain both systems. The scanner maps analog transmission controls under
`scalarActuator` and Rotation Speed Controllers under `speedActuator`; the active backend is
selected by config.

When ready:

```text
aircraft config actuator-type rotation_speed
aircraft config rotation-speed-signs auto
aircraft config rotation-speed 256 0 1 0 -256 256
aircraft config rotation-speed-control <baseRpm> <maxCorrectionRpm> <axis1KpRpm> <axis1KdRpm> [axis2KpRpm] [axis2KdRpm] [throttleRpmPerPower]
aircraft config rotation-speed-writes 0.1 0.5
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

For one-off tuning without saving config:

```text
aircraft stabilize --seconds 1 --actuator-type rotation_speed --base-rpm 120 --kp-rpm 80 --kd-rpm 25 --max-correction-rpm 40
```

`aircraft stabilize`, `aircraft brake`, the HUD, displays, and reports use the selected actuator backend. `aircraft signal` intentionally remains a raw `setSignal` diagnostic for the legacy redstone/transmission hardware.

## Future Blocks

Future fine-control blocks should fit the same module by exposing:

- one scalar setter, configured as `actuator.rotationSpeed.setter`
- one getter for status, configured as `actuator.rotationSpeed.getter`
- a stable scanned category and four-corner role map

If a future block uses a different unit than RPM, keep the backend shape but add a new `actuator.type` rather than overloading `rotation_speed`.
