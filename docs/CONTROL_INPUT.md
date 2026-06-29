# Generic Control Input

Shared controller input lives in `/lib/control_input.lua` and backend modules under
`/lib/control_input/`. Programs should consume normalized logical inputs instead
of binding themselves to one physical controller layout.

Current logical inputs:

```text
w a s d space shift
k
```

Current backends:

- `redstone_router`: samples a redstone router with per-key coordinates. This is
  the original aircraft controller path.
- `keyboard`: consumes normal CraftOS `key` and `key_up` events. This works with
  a local keyboard or Create: Avionics Linked Typewriter.

## Aircraft Setup

Enable controller input:

```text
aircraft config controller true
```

Use the existing Redstone Link / redstone router controller:

```text
aircraft config controller-type redstone_router
aircraft config controller-layout <shiftX> <shiftY> <shiftZ> [side]
```

Use an onboard Linked Typewriter next to the aircraft computer:

```text
aircraft config controller-type keyboard
aircraft controller --seconds 10 --controller
```

## Kill Switch

Aircraft stabilization can stop from a physical redstone kill switch or from the
controller `K` key. The `K` key is enabled by default when `killSwitch.enabled`
is true and works with the `keyboard` controller backend.

Local computer-side redstone:

```text
aircraft config killswitch true front true
```

Redstone router relative coordinate:

```text
aircraft config killswitch-router <x> <y> <z> [side] [activeHigh true|false]
```

Example:

```text
aircraft config killswitch-router 4 0 -2 up true
```

Controller key:

```text
aircraft config killswitch-key true k
```

Probe the currently configured kill switch without running the flight loop:

```text
aircraft killswitch --seconds 10
```

The physical kill switch fails closed. If the configured local side or router
read cannot be checked during stabilization, the aircraft stops instead of
continuing without a verified kill switch.

## Program Integration

Event-based backends need an input pump running in parallel with the program's
main control loop:

```lua
local input = require("lib.control_input")
local context = input.open({
  enabled = true,
  type = "keyboard",
  inputs = { "w", "a", "s", "d", "space", "shift" },
})

parallel.waitForAny(
  function()
    input.pump(context)
  end,
  function()
    while true do
      local frame = input.sample(context)
      -- use frame.reads here
      sleep(0.1)
    end
  end
)
```

Sampled backends such as `redstone_router` do not need the pump.
