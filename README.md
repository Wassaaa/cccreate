# ComputerCraft Project

A small CC:Tweaked/ComputerCraft Lua project that you can edit in VS Code, push to GitHub, and update in-game with one command.

## Project Layout

```text
.
+-- src/
|   +-- startup.lua
|   +-- main.lua
|   +-- report.lua
|   +-- config/
|   |   +-- webhook.example.lua
|   +-- lib/
|       +-- diagnostics.lua
|       +-- logger.lua
|       +-- reporter.lua
+-- update.lua
+-- tools/
|   +-- webhook_receiver.py
+-- README.md
+-- .gitignore
```

- `src/startup.lua` runs automatically when the ComputerCraft computer boots.
- `src/main.lua` is the main program.
- `src/lib/` is for small helper modules.
- `src/report.lua` sends diagnostics from the in-game computer to your webhook receiver.
- `update.lua` runs inside CC:Tweaked and downloads the latest files from GitHub.

## First Setup

Create a new GitHub repository, then edit the variables at the top of `update.lua`:

```lua
local githubUser = "<USER>"
local githubRepo = "<REPO>"
local branch = "main"
```

This project is configured for `Wassaaa/cccreate`.

## Push Updates From VS Code

After editing files in VS Code:

```powershell
git add .
git commit -m "Update ComputerCraft project"
git branch -M main
git remote add origin git@github.com:Wassaaa/cccreate.git
git push -u origin main
```

For later updates, you usually only need:

```powershell
git add .
git commit -m "Update code"
git push
```

## Install Or Update In-Game

On the ComputerCraft computer, download the updater:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
```

Then run:

```text
update
reboot
```

After that, your ComputerCraft computer will have the latest files from the `src/` folder.

## Fetch The Latest Code Later

Whenever you push new changes to GitHub, update the in-game computer with:

```text
update
reboot
```

If you change `update.lua` itself, download it again with `wget` first.

## Webhook Reports

The project includes a small Python webhook receiver. It saves incoming reports into `inbox/latest-report.json`.

Start it on your PC:

```powershell
python tools/webhook_receiver.py
```

By default it listens here:

```text
http://0.0.0.0:8765/report
```

For a first local test, use your computer's local LAN IP rather than your external IP if Minecraft is running on the same network.

On the ComputerCraft computer, copy the example config:

```text
copy config/webhook.example.lua config/webhook.lua
```

Then edit `config/webhook.lua` and set the URL:

```lua
return {
  url = "http://YOUR_IP:8765/report",
  token = "",
}
```

Run a report in-game:

```text
report
```

To run an in-game shell command and send the captured output:

```text
report run id
report run ls
report run main
```

If you expose this outside your LAN, set a token on both sides.

Start the Python server with a token:

```powershell
$env:CC_WEBHOOK_TOKEN="change-me"
python tools/webhook_receiver.py
```

Then use the same token in `config/webhook.lua`:

```lua
return {
  url = "http://YOUR_IP_OR_DOMAIN:8765/report",
  token = "change-me",
}
```
