param(
  [int]$Port = 8765
)

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$PidFile = Join-Path $Root ".webhook\webhook_receiver.pid"

if (Test-Path $PidFile) {
  $PidValue = Get-Content $PidFile -ErrorAction SilentlyContinue
  $Process = Get-Process -Id $PidValue -ErrorAction SilentlyContinue

  if ($Process) {
    Write-Host "PID file: $PidValue running."
  } else {
    Write-Host "PID file exists, but process is not running: $PidValue"
  }
} else {
  Write-Host "No PID file found."
}

$Listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

if ($Listeners) {
  $Listeners | Select-Object LocalAddress,LocalPort,OwningProcess
} else {
  Write-Host "No listener found on port $Port."
}
