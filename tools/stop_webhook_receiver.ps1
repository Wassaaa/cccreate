$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PidFile = Join-Path $Root ".webhook\webhook_receiver.pid"

if (-not (Test-Path $PidFile)) {
  Write-Host "No webhook PID file found."
  exit 0
}

$PidValue = Get-Content $PidFile -ErrorAction SilentlyContinue
$Process = $null

if ($PidValue) {
  $Process = Get-Process -Id $PidValue -ErrorAction SilentlyContinue
}

if (-not $Process) {
  Write-Host "Webhook receiver is not running. Removing stale PID file."
  Remove-Item -Path $PidFile -Force
  exit 0
}

$CommandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $PidValue").CommandLine

if ($CommandLine -notlike "*webhook_receiver.py*") {
  Write-Host "PID $PidValue does not look like the webhook receiver. Refusing to stop it."
  exit 1
}

Stop-Process -Id $PidValue
Remove-Item -Path $PidFile -Force

Write-Host "Stopped webhook receiver with PID $PidValue."
