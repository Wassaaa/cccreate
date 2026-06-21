param(
  [string]$HostAddress = "0.0.0.0",
  [int]$Port = 8765,
  [string]$Token = ""
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$RunDir = Join-Path $Root ".webhook"
$PidFile = Join-Path $RunDir "webhook_receiver.pid"
$OutLog = Join-Path $Root "webhook_receiver.log"
$ErrLog = Join-Path $Root "webhook_receiver.err.log"

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

if (Test-Path $PidFile) {
  $ExistingPid = Get-Content $PidFile -ErrorAction SilentlyContinue
  if ($ExistingPid -and (Get-Process -Id $ExistingPid -ErrorAction SilentlyContinue)) {
    Write-Host "Webhook receiver is already running with PID $ExistingPid."
    exit 0
  }

  Remove-Item -Path $PidFile -Force
}

$env:CC_WEBHOOK_HOST = $HostAddress
$env:CC_WEBHOOK_PORT = [string]$Port
$env:CC_WEBHOOK_TOKEN = $Token

$Process = Start-Process `
  -WindowStyle Hidden `
  -FilePath python `
  -ArgumentList "tools/webhook_receiver.py" `
  -WorkingDirectory $Root `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog `
  -PassThru

Set-Content -Path $PidFile -Value $Process.Id

Write-Host "Started webhook receiver with PID $($Process.Id)."
Write-Host "Listening on http://$HostAddress`:$Port/report"
Write-Host "Logs: $OutLog"
