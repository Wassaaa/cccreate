param(
  [string]$WindowTitle = "Minecraft",
  [int]$WaitSeconds = 8
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
  uv run python tools\minecraft_send.py --title $WindowTitle "update"
  Start-Sleep -Seconds $WaitSeconds
  uv run python tools\minecraft_send.py --title $WindowTitle "report"
}
finally {
  Pop-Location
}
