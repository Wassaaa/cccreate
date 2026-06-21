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
|   +-- startup.lua
|   +-- ccwrap.lua
|   +-- main.lua
|   +-- inventory_example.lua
|   +-- report.lua
|   +-- report_shell.lua
|   +-- wrap_commands.lua
|   +-- path_check.lua
|   +-- reset_project.lua
|   +-- config/
|   |   +-- webhook.example.lua
|   +-- lib/
|       +-- diagnostics.lua
|       +-- inventory_tools.lua
|       +-- logger.lua
|       +-- reporter.lua
+-- docs/
|   +-- INGAME_DEBUGGING.md
+-- tools/
|   +-- read_latest_report.ps1
|   +-- cc_update_and_report.ps1
|   +-- cc_send_and_capture.ps1
|   +-- minecraft_send.py
|   +-- minecraft_screenshot.py
|   +-- webhook_receiver.py
+-- Dockerfile.webhook
+-- docker-compose.webhook-proxy.yml
+-- update.lua
+-- repair.lua
+-- README.md
+-- .env.example
+-- .gitignore
```

- `src/` contains files that are installed on the ComputerCraft computer.
- `update.lua` downloads the latest `src/` files from GitHub.
- `report` sends in-game diagnostics to the webhook.
- `report run <command>` captures command output explicitly when debugging.
- `report_shell enable` can temporarily make simple commands such as `ls` report-only.
- `inventory_example` demonstrates reading and moving between the bottom and back inventories.
- `tools/webhook_receiver.py` receives reports and writes them into `inbox/`.
- `docker-compose.webhook-proxy.yml` runs the webhook, Nginx Proxy Manager, and Cloudflare DDNS.

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
cc-webhook          Python report receiver
cc-proxy            Nginx Proxy Manager
cc-cloudflare-ddns  Cloudflare DNS updater
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

The first `wget` installs the updater. After that, running `update` is enough: it checks for a newer updater, replaces itself if needed, restarts once, and then downloads the current project files from `src/`.

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
git commit -m "Update ComputerCraft project"
git push
```

Then in-game:

```text
update
reboot
```

The updater self-updates, so you normally do not need to run `wget` again unless the local `update` file is deleted or broken.

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

Read the latest report on this PC:

```powershell
.\tools\read_latest_report.ps1
```

Optionally send commands to the Minecraft window from this PC:

```powershell
python tools/minecraft_send.py --title "Minecraft" update
python tools/minecraft_send.py --title "Minecraft" "report run inventory_example status"
```

Capture the Minecraft window:

```powershell
python tools/minecraft_screenshot.py --title "Minecraft NeoForge" --method screen
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
