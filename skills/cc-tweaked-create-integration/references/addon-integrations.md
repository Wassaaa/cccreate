# Add-On Integration Map

Use this when the task involves mod-stack blocks beyond base CC:Tweaked and base Create. These integrations change quickly, so verify installed mod IDs and versions before implementing.

## Advanced Peripherals

Read `advanced-peripherals.md` for the dedicated API map. Advanced Peripherals is broad enough that it should not be handled from this add-on summary.

## CC:C Bridge

- Modrinth: https://modrinth.com/project/fXt291FO
- GitHub: https://github.com/tweaked-programs/cccbridge
- Docs site from project metadata: https://cccbridge.kleinbox.dev/

Use when the pack includes CC:C Bridge and the goal is tighter Create display/redstone integration than base Create offers.

Documented project capabilities include:

- Source and Target blocks for moving Create display-source data into/out of computers.
- Reading displayable Create values such as stress or tank readouts by routing them through display systems.
- RedRouter for redstone control through long cable-like networks.
- Extra Create-themed peripheral blocks.

Probe names and methods live. Older examples may use outdated peripheral names.

## Redstone Link Bridges

These add direct CC control of Create Redstone Link frequencies. They are useful when physical redstone links are already the machine's control bus.

- CC: Redstone Link Bridge on CurseForge: https://www.curseforge.com/minecraft/mc-mods/cc-redstone-link-bridge
- CC: Create Redstone Link on Modrinth: https://modrinth.com/project/zDWcAhSD

Use only if installed. If not installed, a CC computer can still drive a nearby Create Redstone Link through vanilla redstone output or a `redstone_relay`, but it cannot directly set arbitrary link frequency pairs without a bridge block.

## Create: Computing

- Modrinth: https://modrinth.com/project/GVyHe3IO

Provides extra Create/ComputerCraft bridge concepts such as computerized display sources/targets and computerized redstone links. Treat it as optional and probe before use.

## Create: Simulated and Create Aeronautics

Starting links:

- Create Aeronautics site: https://createsimulated.com/
- Create Aeronautics on Modrinth: https://modrinth.com/project/oWaK0Q19
- Simulated Project GitHub: https://github.com/Creators-of-Aeronautics/Simulated-Project
- CreateMod.com Simulated page: https://createmod.com/mods/simulated

Create: Simulated is the core physics/assembly layer for the Aeronautics project family. Aeronautics/Offroad/Liftoff style systems may expose redstone, display, and CC integrations that differ from base Create.

Implementation rules:

- Do not assume base Create peripheral names apply to Simulated/Aeronautics blocks.
- Probe CC peripheral methods on each instrument/control block.
- For precise vehicle control, prefer direct sensor/control peripherals when installed.
- For rough control, use redstone and analog signal conventions, then calibrate in game.

## Create: Avionics

- Modrinth: https://modrinth.com/project/h4nsLvjf
- GitHub: https://github.com/SolAstrius/CreateAvionics

This addon provides CC:Tweaked peripherals for Create: Simulated and Create: Aeronautics blocks, including flight sensors, controls, propulsion, links, and communications.

Use when building autopilot, stabilization, throttle, propeller, altitude, attitude, velocity, or bearing automation. Read the addon docs/API before writing tight control loops, then validate units and coordinate frames with a probe report.

## Create Aeronautics: Thrusters and Things

- CurseForge: https://www.curseforge.com/minecraft/mc-mods/create-aeronautics-thrusters-and-things

This addon publishes external ComputerCraft API docs for some Simulated/Aeronautics block entities. Use only after confirming the mod is installed and the target blocks are present.

## General Add-On Strategy

- Add optional adapters rather than making core programs require one addon.
- Detect by peripheral type and method list, not by mod name alone.
- Keep "capability reports" in webhook output so later iterations can compare installed behavior against docs.
- When a mod page says support is version-specific, record Minecraft version, loader, mod version, and CC:Tweaked version in the report.
