---
name: cc-tweaked-create-integration
description: "Plan, build, and debug CC:Tweaked Lua automation for Minecraft Create mod systems. Use when working in this repo on ComputerCraft/CC:Tweaked programs, peripherals, wired modem networks, generic inventories, redstone/analog/bundled signals, redstone relays, Create kinetic/train/logistics/display peripherals, Create schematics/blueprints, Create: Simulated/Aeronautics control, Advanced Peripherals, CC:C Bridge, or other mod-stack integration probes."
---

# CC:Tweaked Create Integration

## Operating Model

Use this skill to turn an in-game machine idea into repo Lua changes that can be deployed, probed, and iterated through the existing webhook loop.

Work from observed peripherals first. CC:Tweaked, Create, and add-ons vary by Minecraft/mod version, loader, and config, so prefer an in-game discovery report over remembered method names.

## Workflow

1. Read repo context first:
   - `README.md` for update and webhook flow.
   - `docs/INGAME_DEBUGGING.md` for `report`, `report run`, and local report-reading commands.
   - Existing files under `src/` before changing runtime behavior.
2. Choose the relevant reference:
   - Core CC:Tweaked peripherals, inventory movement, redstone, modems, events, HTTP, turtles: `references/cc-tweaked-apis.md`.
   - Native Create CC:Tweaked peripherals for kinetics, trains, logistics, displays: `references/create-native-peripherals.md`.
   - Advanced Peripherals blocks, turtle upgrades, storage bridges, world sensors, Create integration surfaces, item/fluid filters, cooldowns, and memory-card ownership: `references/advanced-peripherals.md`.
   - Other optional add-ons such as CC:C Bridge, redstone-link bridges, Create: Simulated/Aeronautics, Create: Avionics: `references/addon-integrations.md`.
   - Missing, stale, or incomplete docs; live probing; screenshot requests; player placement experiments: `references/live-discovery.md`.
   - Create schematic artifacts, blueprint handoff, Shulkr viewer links, material/placement notes: `references/schematics-and-visual-plans.md`.
3. Probe the live world when behavior depends on block placement or mod version. Add or run a small program that captures `peripheral.getNames()`, all `peripheral.getType(name)` values, `peripheral.getMethods(name)`, redstone inputs, inventory summaries, and any target-specific method return values.
4. Implement the smallest useful Lua program or library change under `src/`. If adding a new file that must install in-game, update `update.lua` so the updater downloads it.
5. Deploy with the repo update path, then collect a report:
   - In game: `update`, `reboot`, then `report` or `report run <program>`.
   - On this PC: `.\tools\read_latest_report.ps1`.
6. Iterate from the report. Treat missing peripherals, renamed network nodes, absent methods, nil returns, sparse inventory tables, and Java exceptions as expected integration facts to handle cleanly.

## Probe Pattern

When no reliable peripheral map exists, create a temporary `src/probe.lua` or add a command mode that serializes a snapshot like this:

```lua
local snapshot = {
  peripherals = {},
  redstone = {},
}

for _, name in ipairs(peripheral.getNames()) do
  local types = { peripheral.getType(name) }
  local methods = peripheral.getMethods(name) or {}
  table.sort(methods)

  snapshot.peripherals[name] = {
    types = types,
    methods = methods,
  }
end

for _, side in ipairs(redstone.getSides()) do
  snapshot.redstone[side] = {
    input = redstone.getInput(side),
    analog = redstone.getAnalogInput(side),
  }
end

print(textutils.serialize(snapshot))
```

For inventories, also call `list()` and loop with `pairs`, not `ipairs`, because inventory slot tables are sparse.

## Missing Docs Workflow

When docs are thin, stale, or inconsistent with the live pack, use `references/live-discovery.md` and escalate in this order:

1. Run non-invasive reports first: `report`, `report run peripherals`, and a probe that only reads names, types, methods, redstone inputs, and inventory summaries.
2. Ask the player for screenshots when physical context matters: block faces, modem attachment, Create goggles/tooltips, redstone link frequencies, inventory/filter GUIs, train station names, and surrounding wiring.
3. Ask the player to place or rotate blocks in controlled A/B tests only after the read-only report is insufficient. Change one variable at a time and collect a report after each change.
4. Treat the live computer as the source of truth. If docs and probes disagree, implement against the observed method names and record the mismatch in the task notes or reference file.

## Lua Integration Rules

- Prefer `peripheral.find(type)` for single devices and a config file or discovery map for named devices. Avoid hard-coded generated names such as `minecraft:chest_12` unless the report proves they are stable enough for the build.
- Wrap peripheral calls that touch machines in `pcall` and report the method name, peripheral name, arguments, and error text.
- Use events for reactive systems where available: `redstone`, Create `speed_change`, `stress_change`, train events, and add-on events. Use timers or `parallel` when a UI/control loop must keep listening while waiting.
- Treat `sleep` as a coarse delay, not an event-safe scheduler.
- Clamp or validate analog redstone and Create RPM inputs before calling the peripheral.
- Separate policy from IO: keep machine decisions in testable functions and isolate `peripheral`, `redstone`, `turtle`, and `http` calls at the edges.
- Keep report output compact but structured with `textutils.serialize` or `textutils.serializeJSON`.

## Design Priorities

- Inventory systems: prefer generic inventory peripherals and wired modem networks before turtle slot juggling. Track item names, counts, slot numbers, and NBT hashes when exact identity matters.
- Advanced Peripherals: treat peripherals and turtle upgrades as optional capability layers. Detect by live type/method list first, then read `references/advanced-peripherals.md` before using Inventory Manager, ME/RS Bridge, Player/Environment/Geo tools, Chat Box, Colony Integrator, or AP Create integrations.
- Redstone systems: prefer analog output for 0-15 control, `redstone_relay` for remote multi-side control, and Create Redstone Links for in-world wireless routing when direct peripheral control is not available.
- Create kinetics: use native Create peripherals such as rotational speed controllers, sequenced gearshifts, speedometers, and stressometers when present. Fall back to redstone control only when no direct peripheral exists.
- Create logistics: use Stock Ticker, Packager/Re-Packager, Redstone Requester, and Table Cloth docs when Create 6 logistics are in the pack; verify live methods because this surface is version-sensitive.
- Trains: use station/signal/observer events and schedule tables, then validate routes with `canTrainReach`/`distanceTo` before assuming a schedule can execute.
- Schematics: use Create `.nbt` schematics or neutral `.schem`/`.litematic` plans when a visual build handoff is clearer than prose. Pair every schematic with orientation, anchor, required adjacent peripherals, redstone side labels, material notes, and a Shulkr viewer path.
- Simulated/Aeronautics: verify exact installed add-ons and versions before designing tight control loops. Prefer direct CC peripherals from Create: Avionics or the relevant addon when installed; otherwise use redstone, display targets, and probes.

## Source Discipline

Use source links in the reference files as a starting map, then verify current behavior against the installed mod stack. If a docs page and in-game probe disagree, trust the probe for implementation and note the version mismatch in comments or follow-up docs.
