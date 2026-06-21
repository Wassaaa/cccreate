# In-Game Debugging Workflow

This project uses a one-way webhook from CC:Tweaked to this workspace.

Current public endpoint:

```text
https://cc-webhook.transcenders.online/report
```

Reports are saved on this PC:

```text
inbox/latest-report.json
```

## Recommended Loop

1. Codex edits Lua code in `src/`.
2. Codex commits and pushes to GitHub.
3. In-game computer runs:

```text
update
```

4. In-game computer sends state back:

```text
report
```

5. Codex reads:

```powershell
.\tools\read_latest_report.ps1
```

6. For command-specific debugging, run:

```text
report run ls
report run main
report run id
report run inventory_example status
```

## Useful In-Game Commands

Send a general system report:

```text
report
```

Send a note:

```text
report note testing after update
```

Run a command and send its captured output:

```text
report run main
```

Check the bottom and back inventories:

```text
report run inventory_example status
```

Move one stack from the bottom inventory to the back chest:

```text
report run inventory_example move
```

Move one stack from the back chest back to the bottom inventory:

```text
report run inventory_example return
```

The command report includes:

- computer ID and label
- whether it is a turtle
- fuel level if turtle APIs exist
- inventory if turtle APIs exist
- attached peripherals and inventory sizes
- file list
- command output
- command error when captured

## Webhook Health Checks

From this PC:

```powershell
curl.exe https://cc-webhook.transcenders.online/health
```

Expected response:

```text
ok
```

The health check only proves the public proxy and receiver are reachable. It does not test the report token.

To test the token, send a real report from in-game:

```text
report note token test
```

## Troubleshooting

If in-game `report` fails with `401`, the token in `config/webhook.lua` does not match `CC_WEBHOOK_TOKEN` in `.env`. Recreate the Docker stack after changing `.env`:

```powershell
docker compose -f docker-compose.webhook-proxy.yml up -d --build --force-recreate
```

If `report` times out, check that the stack is running:

```powershell
docker ps
docker logs cc-proxy
docker logs cc-webhook
docker logs cc-cloudflare-ddns
```

If DNS points at an old IP, check DDNS:

```powershell
docker logs cc-cloudflare-ddns
```

If GitHub updates do not appear in-game, refresh the updater first:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
update
```

Normally `update` self-updates. Use the `wget` command only if the local updater file is missing or broken.

If `wget` says the file already exists, refresh through a temporary file:

```text
delete updater_new
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua updater_new
delete update
move updater_new update
update
```

## Optional Minecraft Key Sender

The `tools/minecraft_send.py` helper can send commands to the Minecraft window from Windows.

List visible windows:

```powershell
python tools/minecraft_send.py --list
```

Send `update`:

```powershell
python tools/minecraft_send.py --title "Minecraft" update
```

Send a report command:

```powershell
python tools/minecraft_send.py --title "Minecraft" "report run inventory_example status"
```

Run update and then report:

```powershell
.\tools\cc_update_and_report.ps1
```

This uses Windows `PostMessage` and is intended to work in the background.

Send one command and capture the terminal shortly after:

```powershell
.\tools\cc_send_and_capture.ps1 "ls"
```

## Minecraft Screenshot Capture

Capture the Minecraft window when command sending or report output does not explain enough:

```powershell
python tools/minecraft_screenshot.py --title "Minecraft NeoForge" --method screen
```

Output:

```text
inbox/minecraft-window.bmp
```

If the Minecraft window is covered, try `PrintWindow` mode:

```powershell
python tools/minecraft_screenshot.py --title "Minecraft NeoForge" --method printwindow
```

## Terminal Output Capture

`report run <command>` already captures output from commands that write through the ComputerCraft terminal API while they run under the report wrapper.

Example:

```text
report run list
```

Interactive commands such as `edit` should be run directly in-game, not through `report run`.

To check what the shell will resolve:

```text
report run path_check
```

If the in-game computer gets into a bad state, hold `Ctrl+T` to terminate the current program and run:

```text
reset_project
```

Then reinstall with:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
update
reboot
```
