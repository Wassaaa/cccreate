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
|   +-- start_webhook_receiver.ps1
|   +-- stop_webhook_receiver.ps1
|   +-- status_webhook_receiver.ps1
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
.\tools\start_webhook_receiver.ps1
```

By default it listens here:

```text
http://0.0.0.0:8765/report
```

Check whether it is running:

```powershell
.\tools\status_webhook_receiver.ps1
```

Stop it when you are done:

```powershell
.\tools\stop_webhook_receiver.ps1
```

The scripts keep a PID file in `.webhook/` so the receiver is not left running randomly.

## Multiplayer Server Networking

If you are playing on a multiplayer server, the HTTP request comes from the Minecraft server, not from your Minecraft client. That means the server must be able to reach your PC over the internet.

This project is currently configured to try:

```text
http://84.231.9.21:8765/report
```

For that to work:

- your router must forward TCP port `8765` to this PC
- Windows Firewall must allow inbound TCP `8765`
- the server's CC:Tweaked config must allow outbound HTTP requests to your IP and port

If port `8765` does not work, use a port you already expose, such as `80`, and start the receiver on that port:

```powershell
.\tools\start_webhook_receiver.ps1 -Port 80
```

Then use this in `config/webhook.lua`:

```lua
return {
  url = "http://84.231.9.21/report",
  token = "change-me",
}
```

Port `443` usually needs a real HTTPS reverse proxy or tunnel in front of the Python script. The Python receiver itself speaks plain HTTP.

## Domain / Reverse Proxy Setup

If you already have a domain and Nginx Proxy Manager, this is usually better than exposing port `8765` directly.

Run the webhook receiver with Docker:

```powershell
$env:CC_WEBHOOK_TOKEN="change-me"
docker compose -f docker-compose.webhook.yml up -d --build
```

If you run it from WSL instead, use the same command from the project folder in WSL.

In Nginx Proxy Manager, create a proxy host:

```text
Domain: cc-webhook.your-domain.example
Scheme: http
Forward Hostname/IP: cc-webhook
Forward Port: 8765
```

That direct container name only works if the webhook container is on the same Docker network as Nginx Proxy Manager. If it is not, either add the webhook container to the NPM network or forward to the host IP and exposed port `8765`.

Then use HTTPS in `config/webhook.lua`:

```lua
return {
  url = "https://cc-webhook.your-domain.example/report",
  token = "change-me",
}
```

Check the container:

```powershell
docker logs cc-webhook
docker compose -f docker-compose.webhook.yml ps
```

Stop it:

```powershell
docker compose -f docker-compose.webhook.yml down
```

On the ComputerCraft computer, copy the example config:

```text
copy config/webhook.example.lua config/webhook.lua
```

Then edit `config/webhook.lua` and set the URL:

```lua
return {
  url = "http://84.231.9.21:8765/report",
  token = "change-me",
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
.\tools\start_webhook_receiver.ps1 -Token "change-me"
```

Then use the same token in `config/webhook.lua`:

```lua
return {
  url = "http://YOUR_IP_OR_DOMAIN:8765/report",
  token = "change-me",
}
```
