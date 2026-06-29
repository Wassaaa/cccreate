# Agent Guide

This is a CC:Tweaked/ComputerCraft repository for Minecraft automation. Code changes are not useful to the player until they are on `origin/main`, because `update.lua` hard-codes the GitHub `main` branch and the in-game computer downloads from raw GitHub.

## Start Here

- Read `README.md`, `docs/AGENT_RUNTIME.md`, and `docs/INGAME_DEBUGGING.md` before changing runtime behavior.
- For inventory movers, read `docs/INVENTORY_MOVEMENT.md`.
- For package crafting, read `docs/PACKAGE_CRAFTER.md`.
- If local research docs such as `docs/CREATE_PROPULSION_CC.md` or `docs/redstone-bus-layout.html` are present, read them when working on propulsion, aircraft, or redstone bus behavior.
- Read existing Lua under `src/base/` and the relevant `src/projects/<project>/` directory before adding patterns.

## Deployment Reality

- The in-game update path is `Codex edits -> commit -> push origin main -> in-game update`.
- Do not tell the user to switch Git branches when the goal is to update a Minecraft computer. Branches are invisible to the updater until merged to `main`.
- Use `update <project>` for one project, `update all` for every project, and bare `update` for base files only.
- `update.lua` discovers files under `src/base/` and `src/projects/<project>/`; adding files there does not require listing them manually.
- `AGENTS.md` files are repo metadata and are intentionally skipped by the updater.

## Git Discipline

- Check `git status --short --branch` before staging.
- Stage only files required for the requested change. Do not include unrelated user edits, local reports, secrets, `.env`, or generated bulk artifacts.
- Use signed-off commits: `git commit -s --no-gpg-sign -m "Message"`.
- For user-testable runtime changes, push `origin main` after a clean commit unless the user explicitly asks not to.
- If you also create a feature branch or PR, state clearly that in-game `update` will not see it until `main` contains it.

## Runtime Loop

- Prefer structured reports over screenshots: ask for or run `report`, `report run <command>`, then read `.\tools\read_latest_report.ps1`.
- Use `report_shell enable` only for temporary read-only commands such as `ls`, `list`, `dir`, and `id`, then disable it.
- Use screenshots and `tools/minecraft_send.py` only for terminal focus, GUI, or world-state questions that reports cannot answer.
- The player handles physical Minecraft actions: placing/rotating blocks, connecting modems, configuring GUIs, setting Redstone Link frequencies, and aligning the view for clicks.

## Lua And Integration Rules

- Target CC:Tweaked/CraftOS Lua compatibility. Avoid assumptions from desktop Lua versions unless verified.
- Wrap machine/peripheral IO in `pcall` when failures matter, and report method names, args, and error text.
- Prefer live discovery (`peripheral.getNames`, `peripheral.getType`, `peripheral.getMethods`) over remembered mod APIs when docs and the installed pack may differ.
- Use sparse inventory tables with `pairs`, not `ipairs`.
- Keep machine policy separate from peripheral IO where practical so control math can be reasoned about without the live world.
- For safety-sensitive machine code, keep dry-run or preview modes unless the user explicitly approves action tests.
