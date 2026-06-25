# Agent Runtime Workflow

This repo has a practical loop for agent-assisted CC:Tweaked work:

```text
Codex edits repo -> GitHub push -> in-game update -> webhook reports -> local inspection
```

Prefer structured reports over screenshots whenever possible. Use screenshots and key sending only to resolve UI/focus/terminal-state questions that reports cannot answer.

## Local Tools

Read the latest in-game report:

```powershell
.\tools\read_latest_report.ps1
```

The Docker stack serves a live human-readable report viewer at `http://127.0.0.1:8786`.

Serve the same viewer directly without Docker:

```powershell
uv run python tools\report_viewer.py
```

Send text to the background Minecraft window:

```powershell
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" "update"
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" "report run inventory_example status"
```

Post a mouse click to Minecraft:

```powershell
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" --click right
uv run python tools\minecraft_send.py --title "Minecraft NeoForge" --click left --x 960 --y 540
```

Mouse clicks are best-effort `PostMessage` events. Use them only after a screenshot confirms the window is in the expected state. If the ComputerCraft terminal is not open but the player is facing the computer, a right click may open it; if the crosshair is not on the computer, ask the player to align the view.

Capture the Minecraft window:

```powershell
uv run python tools\minecraft_screenshot.py --title "Minecraft NeoForge" --method screen --out inbox\minecraft-window.bmp
```

Capture only a smaller region to reduce image parsing cost:

```powershell
uv run python tools\minecraft_screenshot.py --title "Minecraft NeoForge" --method screen --crop 700,380,1850,1050 --out inbox\terminal-crop.bmp
```

Use `--method screen` for current visible pixels. Use `--method printwindow` only when the window is covered; it can return stale game frames.

Send one command and capture after a delay:

```powershell
.\tools\cc_send_and_capture.ps1 "ls" -AfterSeconds 2
```

`cc_send_and_capture.ps1` defaults to a terminal-sized crop for the current `2560x1441` Minecraft capture. Use `-Crop ""` for a full-window capture.

## Report-First Debugging

Use these before reading terminal screenshots:

```text
report
report run path_check
report run inventory_example status
report note <short observation>
```

For agent-only file/command inspection, temporarily enable quiet shell reporting:

```text
report_shell enable
ls
id
report_shell disable
```

Supported report-only aliases are `ls`, `list`, `dir`, and `id`. They create temporary wrapper files under `/report_aliases/`, send command output to the webhook, and restore the previous aliases when disabled.

Add more report-only wrappers only when a command is read-only and useful for agent inspection. Do not quietly wrap destructive or state-changing commands such as `delete`, `rm`, `move`, `copy`, `mkdir`, or `cd` unless there is a very specific tested reason.

## Program Reports

Programs should report structured errors through `src/base/lib/reporter.lua` when failures matter to agent debugging. Do this for long-running automation, peripheral integration, and machine-control code.

Good report contents:

- `kind`: stable report category, such as `inventory-error` or `machine-state`
- `computerId`, `label`, and timestamp
- peripheral name/type/method
- arguments or config values that matter
- `ok`, `error`, and compact structured output

Avoid relying on terminal text for program errors when the program can call the reporter directly. The terminal has limited space and screenshots are harder to parse than JSON reports.

## Git And Download Discipline

Use signed-off commits for repo changes:

```powershell
git commit -s --no-gpg-sign -m "Describe the change"
```

Use `-s` for the `Signed-off-by` trailer, but do not use GPG/SSH commit signing from the agent runtime. The local signing agent may not be available to Codex, and deployment should not be blocked on 1Password signing.

This repo is intended to be deployed through `origin/main`. After making a clean signed-off commit for a requested change, run `git push origin main` automatically unless the user explicitly asks not to.

Before pushing, inspect the staged diff and status. Do not push secrets, tokens, `.env`, private local reports, unrelated user work, or bulky generated artifacts that are not part of the requested change.

Before suggesting a raw GitHub `wget` command, make sure the referenced file is committed and pushed to the branch named in the URL. A local-only commit is not enough for `raw.githubusercontent.com` downloads.

Updater layout:

- Put shared programs, configs, and libraries in `src/base/`.
- Put optional project programs in `src/projects/<project>/`.
- Do not edit `update.lua` just to add files under an existing base/project folder; it discovers files from GitHub.
- Bare `update` installs only `src/base/`.
- Use `update <project>` for one project, `update all` for every project, and `update --list` to inspect project names.

## Webhook Stack

The current endpoint is an HTTP webhook receiver, not a websocket:

```text
https://cc-webhook.transcenders.online/report
```

Check health:

```powershell
curl.exe https://cc-webhook.transcenders.online/health
```

Start or rebuild the local receiver/proxy/DDNS stack:

```powershell
docker compose -f docker-compose.webhook-proxy.yml up -d --build
```

Inspect problems:

```powershell
docker ps
docker logs cc-webhook
docker logs cc-proxy
docker logs cc-cloudflare-ddns
```

Reports are written to:

```text
inbox/latest-report.json
```

## Human-In-The-Loop Boundary

Use the player for physical setup work:

- placing, rotating, or removing blocks
- attaching or activating wired modems
- opening GUIs, filters, redstone link frequency slots, or Create goggles views
- aligning the crosshair before mouse-click automation
- building temporary test rigs for inventories, redstone, Create machines, or monitors

Use agent tools for repo changes, deployment commands, screenshots, report reading, and non-destructive probes.

When a feature depends on block placement or mod behavior, ask for one controlled setup change at a time and then collect a report. Keep Lua probes read-only until the player approves an action test.

## Visual Debugging Rules

Use screenshots for:

- confirming the ComputerCraft terminal is open and focused
- reading short terminal errors not captured by the webhook
- seeing whether Minecraft is in chat, inventory, terminal, or world focus
- checking whether a GUI or block view is visible before a mouse click

Prefer cropped screenshots of the terminal or relevant UI region. Full-window screenshots are useful only when world context matters.

If a screenshot and report disagree, trust the structured report for program state and the screenshot for UI/focus state.
