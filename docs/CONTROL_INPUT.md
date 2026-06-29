# Generic Control Input

Shared controller input lives in `/lib/control_input.lua` and backend modules under
`/lib/control_input/`. Programs should consume normalized logical inputs instead
of binding themselves to one physical controller layout.

Current logical inputs:

```text
w a s d space shift
```

Current backends:

- `redstone_router`: samples a redstone router with per-key coordinates. This is
  the original aircraft controller path.
- `keyboard`: consumes normal CraftOS `key` and `key_up` events. This works with
  a local keyboard or Create: Avionics Linked Typewriter.
- `modem`: receives key state over rednet from another computer running
  `/control_remote`.

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

Use a pocket or portable computer remote:

```text
aircraft config controller-type modem
aircraft config controller-modem cc_control any 0.75
```

On the remote computer:

```text
control_remote cc_control <aircraftComputerId>
```

If no target ID is passed, `control_remote` broadcasts on the configured
protocol.

## Modem Safety

The modem backend accepts both one-key updates and periodic full-state updates.
`control_remote` sends both, and the receiver clears all held remote keys if no
state arrives before `controller.timeout`.

This timeout is deliberate. It prevents a stuck movement key if the remote
computer unloads, loses modem contact, or exits without sending key-up events.

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
