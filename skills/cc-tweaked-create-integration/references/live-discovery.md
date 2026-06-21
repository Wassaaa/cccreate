# Live Discovery Workflow

Use this when documentation does not describe the installed pack, a method is missing, a peripheral name is unstable, or the machine depends on block orientation, placement, GUI state, filters, redstone link frequencies, or unloaded chunks.

## Discovery Ladder

Start with the least invasive source of truth and escalate only when needed.

1. Static docs and repo context:
   - Read the relevant skill reference file.
   - Read existing `src/` code and `docs/INGAME_DEBUGGING.md`.
2. Read-only live reports:
   - Ask the player to run `report`.
   - Ask the player to run `report run peripherals`.
   - Deploy and run a probe that only reads peripheral names, types, methods, redstone inputs, inventories, and selected getter methods.
3. Visual evidence:
   - Ask for screenshots of the machine, GUIs, filters, tooltips, Create goggles readouts, modem faces, redstone link frequencies, train station names, or display-link setup.
4. Controlled placement experiments:
   - Ask the player to place, rotate, attach, detach, power, or rename exactly one block at a time.
   - Collect the same probe report after each change.
5. Implementation:
   - Code against observed behavior, not expected docs.
   - Keep version-specific assumptions isolated behind config, adapters, or clear probe checks.

## Useful In-Game Commands

The current repo can capture shell commands with `report run <command>`.

- `report`: general system report.
- `report run peripherals`: list visible peripherals using the built-in CraftOS program.
- `report run id`: confirm computer ID and label.
- `report run ls`: confirm installed files.
- `report run main`: capture the current main program behavior.
- `report note <text>`: attach a player observation to the local report stream.

If a probe program is added to `src/` and `update.lua`, use:

- `update`
- `reboot`
- `report run probe`

## Probe Program Shape

A good probe must avoid changing the world. It should report enough structure to design the next iteration:

- Computer ID, label, current time, and whether it is a turtle.
- `peripheral.getNames()`.
- All values returned by `peripheral.getType(name)`.
- `peripheral.getMethods(name)`.
- Redstone input/output and analog input/output for every side.
- Wired modem remote names and remote methods when a wired modem is present.
- Inventory `size()`, sparse `list()`, and optionally `getItemDetail(slot)` for non-empty slots.
- Create getter methods that do not actuate machines, such as speed/stress reads, station names, train presence, and display sizes.
- Errors from `pcall` with peripheral name, method, and arguments.

Avoid calling methods that sound like actions unless the user explicitly approves the test, such as `setTargetSpeed`, `rotate`, `move`, `assemble`, `disassemble`, `makePackage`, `request`, `extend`, `retract`, `setForcedRed`, or `setOutput`.

## Screenshot Requests

Ask for screenshots when the code cannot infer physical state. Be specific and request only the views needed.

Useful screenshot targets:

- The computer and every attached modem face.
- The wired modem network path between computer and target block.
- The target block with visible orientation.
- The block GUI for filters, addresses, schedules, stock requests, or package settings.
- Create goggles readouts for speed, stress, fluid, item, or train data.
- Redstone Link frequency slots and send/receive state.
- Train Station name, Train Signal state, and track layout near the station.
- F3/H advanced item tooltip when exact item IDs or NBT-ish identity matter.

When asking the player, include the exact reason: for example, "I need the modem face and target block in one screenshot to verify whether the block is actually on the wired network."

## Controlled Placement Experiments

Use one-variable experiments when docs do not explain exposure rules.

Examples:

- Place a wired modem directly on the suspected peripheral block, right-click the modem to connect it, then run the same probe.
- Rotate the block once, reconnect the modem, and run the same probe.
- Move the computer adjacent to the block without a wired network and compare local names/methods.
- Toggle redstone power off/on and compare redstone events plus getter methods.
- Add or remove a Create Display Link, then compare whether a Source/Target/Display peripheral appears.
- Attach a chest or barrel directly to the inventory manager or generic inventory block, then compare inventory methods.
- Load the chunk or stand near the machine, then compare whether train/logistics peripherals and events appear.

Record each experiment as:

```text
Hypothesis:
Change made:
Command run:
Observed peripheral names/types/methods:
Observed output/error:
Conclusion:
```

## Player Questions

Ask short, concrete questions only when live probing cannot infer the answer. Good questions:

- "Which Minecraft version, loader, and modpack version is this world running?"
- "Is this machine in a loaded chunk while the computer runs?"
- "Is the modem on the target block right-click-connected and visibly active?"
- "Can you send one screenshot with the computer, modem, and target block visible?"
- "Can you place the modem directly on the block and run `report run peripherals` again?"
- "Can you open the block GUI and screenshot the filter/address/frequency settings?"

Avoid broad questions like "what integrations are installed?" when a probe can discover visible peripherals.

## Interpreting Results

- If `peripheral.getNames()` does not show the block, suspect placement, modem connection, chunk loading, config, or that the block is not a peripheral.
- If a block appears but methods differ from docs, code against `peripheral.getMethods(name)` and isolate version-specific calls.
- If methods throw Java exceptions, preserve the exact error string and build a minimal reproduction probe.
- If inventory tables are sparse, use `pairs`.
- If events never fire, verify the block has an event surface and that the program is not sleeping through the event.
- If redstone works manually but not by code, inspect side/orientation and analog strength.
- If a Create mechanism responds to redstone but has no CC methods, control it through a computer side, `redstone_relay`, redstone link, or bridge addon.
