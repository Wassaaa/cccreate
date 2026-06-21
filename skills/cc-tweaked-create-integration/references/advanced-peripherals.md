# Advanced Peripherals API Map

Use this when the pack includes Advanced Peripherals and the task involves AP blocks, turtle upgrades, storage bridges, player/world sensors, chat interaction, or AP's mod integration wrappers.

Main docs: https://docs.advanced-peripherals.de/latest/

Advanced Peripherals changes names and behavior across Minecraft/AP versions. Probe live names and methods before coding, especially on 1.21.1+ where many names moved from camelCase to snake_case.

## Before Implementing

1. Run a read-only probe first:
   - `report run peripherals`
   - a method probe using `peripheral.getNames()`, all `peripheral.getType(name)` returns, and `peripheral.getMethods(name)`.
2. Identify whether the target is:
   - a normal block peripheral adjacent to the computer or on a wired modem
   - a turtle upgrade on the left or right side of a turtle
   - an item-bound feature such as Memory Card ownership
   - a bridge that also requires another mod, such as AE2, Refined Storage, MineColonies, Create, Mekanism, Botania, Powah, or Storage Drawers
3. Read the exact docs page for the matching peripheral or turtle upgrade.
4. Wrap action calls in `pcall` and report the peripheral name, method, arguments, and error text.

## Docs To Read By Surface

Guides:

- Disabled peripherals: https://docs.advanced-peripherals.de/latest/guides/disabled_peripherals/
- Lua objects: https://docs.advanced-peripherals.de/latest/guides/lua_objects/
- Item and fluid filters: https://docs.advanced-peripherals.de/latest/guides/item_and_fluid_filters/
- Cooldowns and fuel consumption: https://docs.advanced-peripherals.de/latest/guides/cooldowns_and_fuel_consumption/
- Storage system functions: https://docs.advanced-peripherals.de/latest/guides/storage_system_functions/

Core peripherals:

- Chat Box: https://docs.advanced-peripherals.de/latest/peripherals/chat_box/
- Energy Detector: https://docs.advanced-peripherals.de/latest/peripherals/energy_detector/
- Environment Detector: https://docs.advanced-peripherals.de/latest/peripherals/environment_detector/
- Player Detector: https://docs.advanced-peripherals.de/latest/peripherals/player_detector/
- Inventory Manager: https://docs.advanced-peripherals.de/latest/peripherals/inventory_manager/
- NBT Storage: https://docs.advanced-peripherals.de/latest/peripherals/nbt_storage/
- Block Reader: https://docs.advanced-peripherals.de/latest/peripherals/block_reader/
- Geo Scanner: https://docs.advanced-peripherals.de/latest/peripherals/geo_scanner/
- Redstone Integrator: https://docs.advanced-peripherals.de/latest/peripherals/redstone_integrator/
- AR Controller: https://docs.advanced-peripherals.de/latest/peripherals/ar_controller/
- ME Bridge: https://docs.advanced-peripherals.de/latest/peripherals/me_bridge/
- RS Bridge: https://docs.advanced-peripherals.de/latest/peripherals/rs_bridge/
- Colony Integrator: https://docs.advanced-peripherals.de/latest/peripherals/colony_integrator/

Turtle upgrades:

- Chatty Turtle: https://docs.advanced-peripherals.de/latest/turtles/chatty_turtle/
- Chunky Turtle: https://docs.advanced-peripherals.de/latest/turtles/chunky_turtle/
- Environment Turtle: https://docs.advanced-peripherals.de/latest/turtles/environment_turtle/
- Player Turtle: https://docs.advanced-peripherals.de/latest/turtles/player_turtle/
- Geoscanning Turtle: https://docs.advanced-peripherals.de/latest/turtles/geoscanning_turtle/
- Weak Automata: https://docs.advanced-peripherals.de/latest/turtles/metaphysics/weak_automata/
- Husbandry Automata: https://docs.advanced-peripherals.de/latest/turtles/metaphysics/husbandry_automata/
- End Automata: https://docs.advanced-peripherals.de/latest/turtles/metaphysics/end_automata/
- Overpowered Automata: https://docs.advanced-peripherals.de/latest/turtles/metaphysics/overpowered_automata/

Create integration pages:

- Basin: https://docs.advanced-peripherals.de/latest/integrations/create/basin/
- Blaze Burner: https://docs.advanced-peripherals.de/latest/integrations/create/blaze_burner/
- Fluid Tank: https://docs.advanced-peripherals.de/latest/integrations/create/fluid_tank/
- Mechanical Mixer: https://docs.advanced-peripherals.de/latest/integrations/create/mechanical_mixer/
- Blocks with Scroll Behaviour: https://docs.advanced-peripherals.de/latest/integrations/create/blocks_with_scroll_behaviour/

Other mod integration pages are under https://docs.advanced-peripherals.de/latest/integrations/.

## Peripheral Name Patterns

Docs show both legacy and current names. Prefer capability detection over hard-coded names.

Common 1.21.1+ names:

- `inventory_manager`
- `player_detector`
- `environment_detector`
- `block_reader`
- `geo_scanner`
- `redstone_integrator`
- `me_bridge`
- `rs_bridge`

Common older names:

- `inventoryManager`
- `playerDetector`
- `environmentDetector`
- `blockReader`
- `geoScanner`
- `redstoneIntegrator`
- `meBridge`
- `rsBridge`

Use `peripheral.find(type, filter)` only when one matching peripheral is expected. If multiple AP blocks are present, require a config name or report the candidates and stop.

Prefer CC:Tweaked's built-in `redstone_relay` for new remote redstone IO when both `redstone_relay` and Advanced Peripherals `redstone_integrator` are available. Use AP Redstone Integrator when that is what the pack/build already exposes or when its documented behavior is specifically needed.

## Inventory Manager

Use for player inventory automation, not generic chest-to-chest movement.

Rules:

- Requires a Memory Card bound to a player and inserted into the manager.
- The adjacent inventory or tank belongs next to the Inventory Manager, not next to the computer.
- Use `getOwner()` before any player-inventory mutation.
- Use `getItems()`, `getArmor()`, `getItemInHand()`, and `getItemInOffHand()` for read-only state.
- Use `addItemToPlayer(direction, filter)` and `removeItemFromPlayer(direction, filter)` only after confirming direction, owner, and target storage.
- Filters may include `name`, `count`, `slot`, `fromSlot`, `toSlot`, tags, NBT, or fingerprint depending on the API surface. Read the item/filter guide before exact matching.

## ME Bridge And RS Bridge

Use these when the pack has Applied Energistics 2 or Refined Storage and the task is directly about network inventory, crafting, import, or export.

Rules:

- The inventory or tank used for import/export belongs next to the bridge, not next to the computer.
- Keep bridge use behind an adapter so base Create/inventory code does not require AE2 or Refined Storage.
- Prefer read-only calls first: network item listing, craftability, item lookup, energy/storage statistics, and crafting CPU/status where available.
- For crafting, check craftability and current crafting status before `craftItem`/`craftFluid`.
- Listen for bridge crafting events only after verifying the event fires in the installed version.
- Use item/fluid filters from the official guide rather than ad hoc string matching when exact identity matters.

## Sensors And World Data

- Player Detector: use for online players, positions, range/area checks, and player events such as joins/leaves/clicks. Treat multidimensional behavior as config-dependent.
- Environment Detector/Turtle: use for biome, dimension, light levels, weather, moon phase, and optional mod data such as Mekanism radiation.
- Block Reader: use to inspect the block in front, block states, and tile-entity data.
- Geo Scanner/Geoscanning Turtle: use to scan nearby blocks and analyze chunk ore counts. Check `cost(radius)` and scan cooldowns/fuel before scanning.
- Energy Detector: use for FE/RF-like energy state near compatible blocks.
- NBT Storage: use when scripts need durable structured data beyond plain files or when sharing data between AP workflows.

## Chat, AR, And Player-Facing IO

- Chat Box can emit or receive chat-style interactions. Treat public chat as user-facing output: keep messages compact, non-spammy, and configurable.
- AR Controller and AR Goggles are player-facing display surfaces. Confirm the target player has the needed item/equipment before depending on AR output.
- Computer Tool and AP Pocket Computer features can change how player-held computers interact with peripherals. Probe before building a workflow around them.

## Turtle Upgrades

AP turtle upgrades can turn turtles into sensors, chat interfaces, chunk loaders, or interaction actors.

Rules:

- Probe turtle side upgrades with `peripheral.getType("left")`, `peripheral.getType("right")`, and method lists before using them.
- Keep movement/fuel/path policy separate from AP sensor/action calls.
- For chunk-loading turtles, be explicit about when chunk loading is expected and how to turn it off.
- For metaphysics automata, treat entity interaction as high impact. Use read-only detection first and require explicit user approval before action tests.
- For geoscanning, check scan cost, max fuel/energy, radius limits, and cooldowns before repeated scans.

## Advanced Peripherals Create Integrations

AP adds peripheral wrappers for some Create blocks that are different from Create's native CC:Tweaked peripherals.

Use AP Create integrations when the target is one of AP's documented wrappers, such as Basin, Blaze Burner, Fluid Tank, Mechanical Mixer, or blocks with Scroll Behaviour. Use native Create docs for Stock Ticker, Packager, Redstone Requester, trains, displays, and kinetic peripherals unless a live probe shows AP exposing the target instead.

## Safety And Config Notes

- AP servers may disable individual peripherals. If a documented peripheral is missing, check the disabled-peripherals guide and live method probes before assuming placement is wrong.
- Some AP calls have cooldowns or fuel/FE costs. Use `cost`, `getMaxFuelLevel`, or documented cooldown calls where available before loops.
- Bridge, inventory, and player-facing APIs often depend on physical adjacency or bound items. Ask for a screenshot or controlled placement change when live probes cannot infer setup.
- Do not assume returned tables are dense arrays. Use `pairs` unless the docs explicitly promise list semantics.
- For NBT-sensitive item matching, prefer fingerprints/hashes or documented filter fields over display names.
