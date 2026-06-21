param(
  [string]$WindowTitle = "Minecraft",
  [int]$WaitSeconds = 8
)

$ErrorActionPreference = "Stop"

python tools/minecraft_send.py --title $WindowTitle "update"
Start-Sleep -Seconds $WaitSeconds
python tools/minecraft_send.py --title $WindowTitle "report"
