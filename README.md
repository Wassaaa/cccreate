# ComputerCraft Project

A small CC:Tweaked/ComputerCraft Lua project that can be edited in VS Code, pushed to GitHub, updated in-game, and debugged through a webhook report loop.

## Current Workflow

Code update path:

```text
VS Code -> GitHub -> in-game update command
```

Debug report path:

```text
ComputerCraft report command -> https://cc-webhook.transcenders.online/report -> inbox/latest-report.json
```

For the in-game debugging workflow, see [docs/INGAME_DEBUGGING.md](docs/INGAME_DEBUGGING.md).

## Project Layout

```text
.
+-- src/
|   +-- base/
|   |   +-- startup.lua
|   |   +-- ccwrap.lua
|   |   +-- main.lua
|   |   +-- path_check.lua
|   |   +-- report.lua
|   |   +-- report_shell.lua
|   |   +-- reset_project.lua
|   |   +-- wrap_commands.lua
|   |   +-- configure_webhook.lua
|   |   +-- config/
|   |   |   +-- webhook.example.lua
|   |   +-- lib/
|   |       +-- diagnostics.lua
|   |       +-- inventory_tools.lua
|   |       +-- logger.lua
|   |       +-- reporter.lua
|   |       +-- tom_cc_term_font.lua
|   |       +-- tom_term_emu.lua
|   |       +-- tom_term_font.png
|   +-- projects/
|   |   +-- turtle_crafter/
|   |   |   +-- craft_2x2_stack.lua
|   |   |   +-- turtle_inventory_probe.lua
|   |   +-- processing_router/
|   |   |   +-- processing_router.lua
|   |   |   +-- config/
|   |   |       +-- processing_router.example.lua
|   |   +-- network_probe/
|   |   |   +-- network_inventory_probe.lua
|   |   +-- inventory_example/
|   |   |   +-- inventory_example.lua
|   |   +-- ap_inventory_manager_test/
|   |   |   +-- ap_inventory_manager_test.lua
|   |   +-- requester_test/
|   |   |   +-- requester_test.lua
|   |   +-- tom_terminal/
|   |       +-- tom_gpu_terminal.lua
|   |       +-- tom_keyboard_probe.lua
+-- docs/
|   +-- INGAME_DEBUGGING.md
+-- tools/
|   +-- read_latest_report.ps1
|   +-- cc_update_and_report.ps1
|   +-- cc_send_and_capture.ps1
|   +-- minecraft_send.py
|   +-- minecraft_screenshot.py
|   +-- report_viewer.py
|   +-- webhook_receiver.py
+-- Dockerfile.webhook
+-- docker-compose.webhook-proxy.yml
+-- pyproject.toml
+-- uv.lock
+-- update.lua
+-- repair.lua
+-- README.md
+-- .env.example
+-- .gitignore
```

- `src/base/` contains shared files that every update installs to the ComputerCraft root.
- `src/projects/<name>/` contains optional project files. Bare `update` installs only base; `update <name>` installs base plus that project, also to the ComputerCraft root.
- `update.lua` discovers files from GitHub, so adding a file under `src/base/` or an existing project directory does not require editing the updater.
- `report` sends in-game diagnostics to the webhook.
- `report run <command>` captures command output explicitly when debugging.
- `report_shell enable` can temporarily make simple commands such as `ls` report-only.
- `inventory_example` demonstrates reading and moving between the bottom and back inventories.
- `craft_2x2_stack` runs a wired crafting turtle that fills 2x2 or 3x3 recipes from one or more input inventories.
- `processing_router` runs simple filtered processing jobs: watch an input inventory, push required items to configured machine inventories, and return outputs to storage.
- `ap_inventory_manager_test` probes and tests Advanced Peripherals Inventory Manager player transfers.
- `requester_test` probes a Create Redstone Requester and can request sample items to address `out`.
- `tom_gpu_terminal` runs Tom's Peripherals terminal emulator on router-wrapped GPU monitors.
- `tools/webhook_receiver.py` receives reports and writes them into `inbox/`.
- `tools/report_viewer.py` serves a live human-readable report viewer for `inbox/`.
- `docker-compose.webhook-proxy.yml` runs the webhook, Nginx Proxy Manager, and Cloudflare DDNS.

## Python Tooling

This repo uses `uv` for local Python helper scripts.

Set up the base environment:

```powershell
uv sync
```

Run Python helpers through `uv run`:

```powershell
uv run python tools/minecraft_send.py --title "Minecraft" update
uv run python tools/minecraft_screenshot.py --title "Minecraft NeoForge" --method screen
uv run python tools/report_viewer.py
uv run python tools/webhook_receiver.py
```

Install optional schematic tooling when generating or validating `.nbt` schematic files:

```powershell
uv sync --extra schematics
```

## Start The Webhook Stack

Create a local `.env` file:

```powershell
copy .env.example .env
notepad .env
```

Set:

```text
CC_WEBHOOK_TOKEN=your-report-token
CF_API_TOKEN=your-cloudflare-token
CF_DDNS_DOMAINS=cc-webhook.transcenders.online
CF_DDNS_PROXIED=true
```

Start the stack:

```powershell
docker compose -f docker-compose.webhook-proxy.yml up -d --build
```

The stack runs:

```text
cc-webhook         Python report receiver
cc-report-viewer   live local report viewer
cc-proxy           Nginx Proxy Manager
cc-cloudflare-ddns Cloudflare DNS updater
```

Open Nginx Proxy Manager:

```text
http://127.0.0.1:81
```

Proxy host:

```text
Domain: cc-webhook.transcenders.online
Scheme: http
Forward Hostname/IP: cc-webhook
Forward Port: 8765
Block Common Exploits: on
Websockets Support: off
```

Use Let's Encrypt SSL for the proxy host.

Health check:

```powershell
curl.exe https://cc-webhook.transcenders.online/health
```

Expected response:

```text
ok
```

Local report viewer:

```text
http://127.0.0.1:8786
```

Stop the stack:

```powershell
docker compose -f docker-compose.webhook-proxy.yml down
```

## Install Or Update In-Game

On the ComputerCraft computer:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
update
reboot
```

The first `wget` installs the updater. After that, running `update` checks for a newer updater, replaces itself if needed, restarts once, and installs the shared `src/base/` files.

Install project files with:

```text
update --list
update turtle_crafter
update all
```

`update <project>` installs base plus `src/projects/<project>/`. `update all` installs base plus every project.

Configure the webhook in-game:

```text
copy config/webhook.example.lua config/webhook.lua
edit config/webhook.lua
```

Set:

```lua
return {
  url = "https://cc-webhook.transcenders.online/report",
  token = "your-report-token",
}
```

## Push Updates From VS Code

After editing files:

```powershell
git add .
git commit -s -m "Update ComputerCraft project"
git push
```

For agent-made changes in this repo, a clean signed-off commit should normally be pushed to `origin/main` immediately so in-game `update` and raw GitHub `wget` commands can see it. Check the diff first and do not push secrets, `.env`, private local reports, or unrelated files.

Then in-game:

```text
update
reboot
```

The updater self-updates, so you normally do not need to run `wget` again unless the local `update` file is deleted or broken.

## Nether Brick Crafting Turtle

`craft_2x2_stack` expects a crafting turtle and at least two generic inventory peripherals on the same wired modem network. It only moves `minecraft:nether_brick`, fills the selected 2x2 or 3x3 turtle crafting grid to 64 items per slot, crafts a full stack batch, and pushes whatever item was crafted to the selected output inventory.

Item movement uses wired inventory `pushItems`/`pullItems`; the turtle uses `turtle.getItemDetail` only to validate its internal slots and `turtle.craft` to craft. The output slot is selected once at startup. Craft slots may contain partial `minecraft:nether_brick` stacks, but every non-craft slot must be empty at startup. During runtime, unexpected items outside the controlled craft slots or pending output slot stop the script instead of being routed into an input or output inventory.

Run it with no arguments to choose the grid size, input inventories, and output inventory. Inputs are selected in priority order; enter one number/name at a time, comma-separate several entries, or press Enter when done. If only one unselected inventory remains, it is used as output automatically.

To skip prompts, pass the optional grid size, then output inventory, then one or more input inventories. Input arguments may be comma-separated:

```text
craft_2x2_stack 3x3 minecraft:chest_output minecraft:chest_input_1,minecraft:chest_input_2
```

Direct install for just this program:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/src/projects/turtle_crafter/craft_2x2_stack.lua craft_2x2_stack
```

## Send Reports From In-Game

General diagnostics:

```text
report
```

Send a note:

```text
report note testing after update
```

Capture a command:

```text
report run main
report run ls
report run id
report run inventory_example status
```

Inventory example:

```text
inventory_example status
inventory_example move
inventory_example return
```

Processing router:

```text
copy config/processing_router.example.lua config/processing_router.lua
edit config/processing_router.lua
processing_router status
processing_router once
processing_router watch
```

Each job has an `input`, `output`, and `items` list. An item entry uses `name`, `count`, and `to`:

```lua
{
  name = "iron_press",
  input = { x = 0, y = 0, z = 1, label = "iron input" },
  output = { x = 0, y = 0, z = 2, label = "iron output" },
  items = {
    {
      name = "minecraft:iron_ingot",
      count = 1,
      to = { x = 1, y = 0, z = 0, label = "press input" },
    },
  },
}
```

Use `storage` globally or per job to choose where outputs are returned. Locations can be side/peripheral names such as `"back"`, Peripheral Router coordinates such as `{ x = 5, y = 1, z = 2 }`, or already-wrapped router objects from the config file.

Advanced Peripherals Inventory Manager test:

```text
ap_inventory_manager_test status
ap_inventory_manager_test find minecraft:iron_ingot
ap_inventory_manager_test plan-give north 1 1
ap_inventory_manager_test plan-take north 1 1
```

Redstone Requester test:

```text
requester_test status
requester_test preview out 1 3 bottom
requester_test request out 1 3 bottom
requester_test craft-preview crafter 1 minecraft:oak_planks minecraft:oak_planks - minecraft:oak_planks minecraft:oak_planks
requester_test craft crafter 1 minecraft:oak_planks minecraft:oak_planks - minecraft:oak_planks minecraft:oak_planks
```

Tom's Peripherals GPU terminal:

```text
tom_keyboard_probe prefixed 20
tom_gpu_terminal demo
tom_gpu_terminal multishell
tom_gpu_terminal run requester_test status
```

Defaults are router GPU coordinates `-1 1 0`, router keyboard coordinates `-3 0 -2`, monitor block resolution `64`, and Tom's bitmap terminal font at scale `1`. A 2x2 bitmap monitor is about `128x128` pixels, which gives roughly a `21x14` character terminal, so this is mostly parked until more monitors are available. With a router-wrapped keyboard, Tom's keyboard events report from the router side, such as `back`; the terminal runner detects that side automatically.

Read the latest report on this PC:

```powershell
.\tools\read_latest_report.ps1
```

Open a live human-readable report viewer from the Docker stack:

```text
http://127.0.0.1:8786
```

You can also run the viewer directly without Docker:

```powershell
uv run python tools/report_viewer.py
```

Optionally send commands to the Minecraft window from this PC:

```powershell
uv run python tools/minecraft_send.py --title "Minecraft" update
uv run python tools/minecraft_send.py --title "Minecraft" "report run inventory_example status"
```

Capture the Minecraft window:

```powershell
uv run python tools/minecraft_screenshot.py --title "Minecraft NeoForge" --method screen
```

Send one command and immediately capture the result:

```powershell
.\tools\cc_send_and_capture.ps1 "ls"
```

Use `report run <command>` when you want command output sent to the webhook.

For a temporary report-only shell, run:

```text
update
report_shell enable
ls
report_shell disable
```

In that mode, supported commands send their output to the webhook instead of printing the command output in the terminal.
Running `update` clears active report-only aliases, so re-run `report_shell enable` after updating.
The temporary wrapper files live in `/report_aliases/` and are removed by `report_shell disable` or `update`.
When disabled, aliases are restored to whatever they were before `report_shell enable`.
If report-only aliases were not active, `update` leaves normal shell aliases alone.

Reports are saved to:

```text
inbox/latest-report.json
```

## Troubleshooting

If reports return `401`, the token in `config/webhook.lua` does not match `CC_WEBHOOK_TOKEN` in `.env`. Recreate the stack after changing `.env`:

```powershell
docker compose -f docker-compose.webhook-proxy.yml up -d --build --force-recreate
```

If reports time out:

```powershell
docker ps
docker logs cc-proxy
docker logs cc-webhook
docker logs cc-cloudflare-ddns
```

If DNS points at an old IP, check:

```powershell
docker logs cc-cloudflare-ddns
```

If the ComputerCraft install gets confusing, remove this project from the in-game computer:

```text
reset_project
```

If startup is running and you cannot type, hold `Ctrl+T` in the ComputerCraft terminal to terminate the running program, then run the reset command.

If old command wrappers broke normal commands, run the one-time repair script:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/repair.lua repair_once
repair_once
reboot
```
