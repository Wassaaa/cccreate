# CC:Tweaked API Map

Use these links when implementing Lua against CC:Tweaked itself. Prefer the official CC:Tweaked docs, then confirm live behavior with `peripheral.getMethods`.

## Core Links

- Main docs: https://tweaked.cc/
- Peripheral API: https://tweaked.cc/module/peripheral.html
- Generic inventory peripheral: https://tweaked.cc/generic_peripheral/inventory.html
- Modem peripheral: https://tweaked.cc/peripheral/modem.html
- Redstone API: https://tweaked.cc/module/redstone.html
- Redstone event: https://tweaked.cc/event/redstone.html
- Redstone Relay peripheral: https://tweaked.cc/peripheral/redstone_relay.html
- HTTP API: https://tweaked.cc/module/http.html
- Text serialization: https://tweaked.cc/module/textutils.html
- OS events and timers: https://tweaked.cc/module/os.html
- Parallel API: https://tweaked.cc/module/parallel.html
- Turtle API: https://tweaked.cc/module/turtle.html
- Filesystem API: https://tweaked.cc/module/fs.html
- Shell API: https://tweaked.cc/module/shell.html
- Settings API: https://tweaked.cc/module/settings.html
- Command computer API: https://tweaked.cc/module/commands.html
- `/computercraft` server command: https://tweaked.cc/reference/computercraft_command.html
- Peripheral Java API: https://tweaked.cc/mc-1.20.x/javadoc/dan200/computercraft/api/peripheral/package-summary.html

## Peripheral Discovery

- Use `peripheral.getNames()` to list visible peripherals.
- Use `peripheral.getType(name)` and capture all returned values. CC:Tweaked supports peripherals with multiple types on modern versions.
- Use `peripheral.hasType(name, type)` when available for clearer checks.
- Use `peripheral.getMethods(name)` before calling version-sensitive methods.
- Use `peripheral.wrap(name)` when repeatedly calling one device, and `peripheral.call(name, method, ...)` for dynamic dispatch.
- Use `peripheral.find(type, filter)` for simple single-device programs, but reject ambiguity when multiple matching blocks exist.

## Wired Modem Networks

Wired modem networks are the normal way to centralize inventory and machine automation.

- Wired-only remote methods include `getNamesRemote`, `isPresentRemote`, `getTypeRemote`, `hasTypeRemote`, `getMethodsRemote`, `callRemote`, and `getNameLocal`.
- Check `isWireless()` before calling wired-only remote methods.
- Peripheral names shown by wired modems can change after rebuilding. Store names in config only after a probe confirms the layout.
- When a central computer should control many machines, prefer wired modems plus remote peripherals over many adjacent computers.

## Generic Inventory Peripheral

Generic inventories expose chests and many modded inventories through CC:Tweaked.

Common methods:

- `size()`: slot count.
- `list()`: sparse table of basic item data by slot.
- `getItemDetail(slot)`: full item detail for one slot.
- `getItemLimit(slot)`: max stack capacity for a slot.
- `pushItems(toName, fromSlot, limit, toSlot)`: move items to another inventory on the same wired network.
- `pullItems(fromName, fromSlot, limit, toSlot)`: move items from another inventory on the same wired network.

Rules:

- Loop inventory lists with `pairs`, not `ipairs`.
- Empty slots are `nil`.
- Basic item rows include `name`, `count`, and maybe `nbt`; use `getItemDetail` only when the extra data is needed.
- `pushItems` and `pullItems` require both inventories to be available as peripherals on the same wired modem network.
- Add defensive range checks before moving between slots.
- For high-volume item movement, snapshot with `list()`, build temporary indexes such as item name to slots, and reuse those indexes for a batch or timed refresh window instead of re-scanning large inventories before each move.
- Prefer whole-stack transfer attempts and use the returned moved count. Avoid one-item loops or repeated count-sized push/pull attempts when one stack attempt gives the same result.
- Cache zero-move, full, or incompatible target slots until the next target refresh so a tight loop does not keep retrying known bad destinations.
- Keep full-slot scans with `size()` plus `getItemDetail(slot)` opt-in for inventories that hide useful identities from `list()`.

## Redstone Control

Core redstone supports three control styles:

- Binary: `setOutput`/`getInput`.
- Analog: `setAnalogOutput`/`getAnalogInput`, values 0 through 15.
- Bundled: `setBundledOutput`/`getBundledInput`, 16 color channels when a bundled-cable mod supports it.

Use `os.pullEvent("redstone")` or a parallel event loop instead of constant polling when possible.

Use `redstone_relay` when one computer needs multiple remote six-sided redstone IO blocks over a wired modem network. It mirrors the computer redstone method surface and is useful for Create links, clutches, gearshifts, deployers, requesters, and safety cutoffs.

## HTTP, Reports, and Serialization

This repo already uses `http.post` and `textutils.serializeJSON` in `src/lib/reporter.lua`.

- HTTP must be enabled by server config for webhooks and downloads.
- Use `textutils.serialize` for human-readable Lua reports.
- Use `textutils.serializeJSON` for webhook payloads.
- Keep report objects shallow enough to inspect in `inbox/latest-report.json`.

## Event Loops

- `os.pullEvent(filter)` waits for one event.
- `os.startTimer(seconds)` queues a `timer` event with an ID.
- `parallel.waitForAny` and `parallel.waitForAll` let a UI, controller, and event listener share one computer cooperatively.
- Avoid long blocking machine calls in the same loop that must catch redstone, train, or stress events.

## Turtles

Use turtles when physical interaction is the point: placing, breaking, moving, sucking, dropping, farming, mining, or mobile inspection.

Use inventory peripherals when moving items between fixed inventories. They are clearer, faster to reason about, and less dependent on turtle orientation.

## Command Computers

The `commands` API is only available on command computers. Treat it as creative/admin tooling, not normal survival automation. If command computers are used for debugging, keep command use isolated and do not make survival programs depend on it.
