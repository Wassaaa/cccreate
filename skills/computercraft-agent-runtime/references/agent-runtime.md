# Agent Runtime Reference

Use this reference when agent-side operation matters: background Minecraft input, screenshots, report-only shell aliases, webhook receiver health, and player handoff for physical setup.

## Priority Order

Prefer structured reports over screenshots:

1. `.\tools\read_latest_report.ps1`
2. `report`, `report run <program>`, or program-specific structured reports through `src/lib/reporter.lua`
3. `report_shell enable` for temporary read-only shell aliases
4. Cropped screenshots for terminal/UI/focus questions
5. Background key/mouse sending only after screenshot confirms the target UI state
6. Human-in-the-loop setup changes for block placement, rotation, modem attachment, GUIs, filters, or crosshair alignment

## Python Tooling

This project uses `uv` for Python helpers. Prefer:

```powershell
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" "update"
```

over bare `python ...`. If dependencies are missing, run:

```powershell
uv sync
```

For optional schematic tools:

```powershell
uv sync --extra schematics
```

The repo's `tools/` directory is the canonical tool implementation. The skill documents how to use those tools; it should not carry duplicate copies unless portability becomes more important than avoiding drift.

## Webhook Reporting

Current endpoint in this repo:

```text
https://cc-webhook.transcenders.online/report
```

Health check:

```powershell
curl.exe https://cc-webhook.transcenders.online/health
```

Start/rebuild stack:

```powershell
docker compose -f docker-compose.webhook-proxy.yml up -d --build
```

Inspect stack:

```powershell
docker ps
docker logs cc-webhook
docker logs cc-proxy
docker logs cc-cloudflare-ddns
```

Reports land at:

```text
inbox/latest-report.json
```

This is an HTTP webhook workflow, not an actual websocket. Program code should call `src/lib/reporter.lua` for structured errors/state instead of relying on terminal screenshots.

## Report-Only Shell

Use for agent-only read-only inspection:

```text
report_shell enable
ls
id
report_shell disable
```

Supported aliases: `ls`, `list`, `dir`, `id`.

Rules:

- Do not enable from startup.
- Do not create root files named after shell commands.
- Do not quietly wrap destructive/state-changing commands such as `delete`, `rm`, `move`, `copy`, `mkdir`, or `cd` unless a specific tested task requires it.
- `report_shell` stores temporary wrapper files in `/report_aliases/` and restores prior aliases on disable.

## Screenshots

Full window:

```powershell
uv run python tools\minecraft_screenshot.py --title "Minecraft NeoForge" --method screen --out inbox\minecraft-window.bmp
```

Cropped terminal/UI region:

```powershell
uv run python tools\minecraft_screenshot.py --title "Minecraft NeoForge" --method screen --crop 600,300,1450,850 --out inbox\terminal-crop.bmp
```

Use `--method screen` for current visible pixels. Use `--method printwindow` only when the window is covered; it may return stale frames. Prefer cropped screenshots for token cost unless world context matters.

## Key And Mouse Sending

Send text:

```powershell
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" "update"
```

Right-click or left-click the window:

```powershell
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" --click right
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" --click left --x 960 --y 540
```

Send and capture:

```powershell
.\tools\cc_send_and_capture.ps1 "ls" -AfterSeconds 2 -Crop "600,300,1450,850"
```

Only use mouse actions after a screenshot confirms the expected world/GUI state. If the ComputerCraft terminal is not open but the player is facing the computer, a right-click may open it. If the crosshair or focus is uncertain, ask the player to align/open it.

## Human-In-The-Loop Boundary

Ask the player to do physical world setup:

- place, rotate, or remove blocks
- attach and activate wired modems
- open GUIs, filters, redstone link slots, Create goggles views, train station screens
- align the crosshair before mouse-click automation
- build temporary test rigs for inventories, redstone, Create machines, monitors, or peripherals

Change one world variable at a time, then collect the same report/probe output. Keep probes read-only until the player approves action tests.
