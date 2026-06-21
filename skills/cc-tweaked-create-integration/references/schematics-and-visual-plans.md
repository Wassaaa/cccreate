# Schematics and Visual Plans

Use this when a Create/CC:Tweaked idea needs a visual handoff: machine layout, modem placement, redstone link routing, inventories, train stations, display boards, or physical block orientation.

## Source Links

- Shulkr schematic viewer: https://www.shulkr.com/
- Shulkr Create viewer page: https://www.shulkr.com/minecraft-create-schematic-viewer
- Create wiki, loading a schematic: https://github.com/Creators-of-Create/Create/wiki/Loading-a-Schematic
- Create wiki, printing a schematic: https://github.com/Creators-of-Create/Create/wiki/Printing-a-Schematic
- Create Schematic and Quill page: https://create.fandom.com/wiki/Schematic_And_Quill
- CreateMod.com schematic repository: https://createmod.com/

## Supported Planning Formats

Use the format that matches the handoff:

- `.nbt`: preferred Create Schematic and Quill / Schematicannon format.
- `.schem`: common Sponge/WorldEdit schematic format, good for external tooling.
- `.litematic`: useful for Litematica planning and survival placement.
- `.mcstructure`: Bedrock-style structure format when relevant.

Shulkr can open these formats in-browser. For Create-heavy builds, prefer Shulkr over generic schematic viewers because Create blocks have important facing, casing, belt, pipe, shaft, and addon geometry.

## NBT Tooling

Use a real NBT library for generated schematic files. Do not hand-roll binary NBT unless there is no alternative.

Recommended Python path for this repo:

- Use `amulet-nbt` for `.nbt` generation and validation.
- Pin the dependency in a requirements file when a generator script is committed.
- Generate namespaced block IDs and blockstate properties as data, so modded IDs such as `create:*`, `computercraft:*`, or addon block IDs can be substituted once known.
- Load the generated file back with the same library before delivery and assert size, palette count, block count, and key palette entries.

For generated files, keep the source generator next to the repo tooling. A generated `.nbt` is hard to review; a compact generator script plus `plan.md` makes later iteration practical.

## Repo Conventions

When adding schematic artifacts to this repo, use a predictable structure:

```text
schematics/
  <machine-name>/
    <machine-name>.nbt
    plan.md
    probe-report.txt
```

Use `plan.md` for human placement notes, not general documentation. Keep it short and tied to the artifact:

- Purpose of the machine.
- Minecraft/Create/modpack version if known.
- Required mods and optional add-ons.
- Anchor block and intended facing.
- Required adjacent computer, modem, inventory, redstone, display, or train station positions.
- Side labels: computer sides, relay sides, redstone links, belt directions, shaft directions.
- What to screenshot after placement.
- Which `report run <program>` command validates the build.

Do not assume a schematic alone communicates CC wiring. Create/CC systems need side labels and peripheral names.

## Viewer-First Iteration

Expect the first generated schematic to need a visual pass. Shulkr/player feedback is part of the workflow, not a failure.

Start conservative:

- Prefer solid full blocks for the first pass when shape matters more than polish.
- Use full glass blocks before panes if the viewer or importer might mishandle connection state.
- Avoid stair-heavy roofs until facing, half, shape, waterlogged, and neighbor-state behavior has been checked.
- Prefer stepped full-block roofs for early drafts, then refine into stairs/slabs once the massing is correct.
- Place chimneys, pipes, modems, relays, signs, and other visible details after broad roof/wall fills so they do not get overwritten.
- Include real support blocks under flowers, redstone, tracks, and other fragile blocks.
- Build gable/wall support explicitly; do not rely on roof blocks to hide gaps.

Then iterate:

1. Generate the schematic.
2. Round-trip load it with the NBT library.
3. Open it in Shulkr.
4. Inspect outside, inside, roof edges, block directions, and slice layers.
5. Ask the player what looks wrong if they report holes, bad facings, floating blocks, or ugly massing.
6. Revise the generator, regenerate, and update `plan.md` material counts.

## Shulkr Handoff

Use Shulkr as the visual explanation surface for the player.

Options:

- Local: ask the player to open https://www.shulkr.com/viewer and choose the schematic file.
- Public URL: if the schematic is hosted at a direct public URL ending in `.nbt`, `.schem`, `.litematic`, or `.mcstructure`, use:

```text
https://www.shulkr.com/viewer?url=<direct-public-schematic-url>
```

Use public URL imports only for artifacts that are safe to expose. Otherwise keep the file local.

Ask the player to use:

- Orbit mode for overall layout.
- Free-fly mode for interiors, wiring, and machine routing.
- Slicer mode for layer-by-layer placement.
- Block inspection for exact IDs, coordinates, and blockstate properties.

## Creating Schematics

Preferred in-game Create workflow:

1. Build or prototype the machine in a creative/test world.
2. Use Schematic and Quill to select the machine bounds.
3. Save the schematic to an `.nbt` file.
4. Put the file under `schematics/<machine-name>/`.
5. Add a short `plan.md` with anchor, facing, IO, and validation commands.
6. Open it in Shulkr and inspect layer/sides before telling the player to build it.

For existing `.schem` or `.litematic` files, do not assume renaming to `.nbt` makes them Create-compatible. Convert in a test world when the final artifact must be used by Create's Schematic Table/Schematicannon.

## Designing From Code

When generating a schematic-like plan from CC requirements, start with a structured block map before producing a file:

```text
Origin: computer front face at x=0,y=0,z=0
Facing: north
Blocks:
  0,0,0 cc:tweaked:computer_normal label=controller
  0,0,-1 computercraft:wired_modem side=front connected=true
  1,0,-1 create:rotation_speed_controller peripheral=kinetic_input
  -1,0,-1 create:redstone_link mode=receiver frequency=[minecraft:redstone, create:cogwheel]
Signals:
  controller right analog 0..15 -> clutch enable
  relay top binary -> emergency stop
Validation:
  report run probe
```

Then either:

- Ask the player to build from the plan and send screenshots.
- Build it in a creative world and export an `.nbt`.
- Convert the block map into `.schem`/`.litematic` with a dedicated tool only after block IDs/states are known.

When code-generating, prefer a small builder abstraction with:

- `set_block(x, y, z, id, properties)`.
- `fill(x1, y1, z1, x2, y2, z2, id, properties)`.
- Palette de-duplication.
- Material count extraction from the generated palette.
- Validation that generated dimensions and block counts match expectations.

## Material and Placement Notes

For survival builds, schematic files are not enough. Include:

- Material list source: Shulkr material breakdown, Schematicannon material book, or manual count.
- Blocks the Schematicannon will not safely replace.
- Whether the Schematicannon target area must stay chunk-loaded.
- Gunpowder and adjacent inventory requirements.
- Any blocks that must be placed manually after printing, such as computers, configured filters, named train stations, linked redstone frequencies, bound memory cards, or private/security-sensitive config.

## Validation With CC Reports

After a player builds from a schematic:

1. Ask for a screenshot from the Shulkr angle that matches the in-game placement if orientation is suspect.
2. Ask for `report run peripherals`.
3. Ask for `report run probe` if the probe exists.
4. Compare expected side labels and peripheral names against the report.
5. Update `plan.md` if the real placement differs from the schematic.

Treat schematic visualization and CC probes as a pair: Shulkr explains the physical build, while `report` proves the computer can see and control it.
