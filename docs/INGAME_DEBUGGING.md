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
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
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

The command report includes:

- computer ID and label
- whether it is a turtle
- fuel level if turtle APIs exist
- inventory if turtle APIs exist
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
