param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Command,

  [string]$Title = "Minecraft NeoForge",
  [double]$AfterSeconds = 2,
  [string]$Out = "inbox/minecraft-window.bmp"
)

$ErrorActionPreference = "Stop"

python "$PSScriptRoot\minecraft_send.py" --title $Title --delay 0.02 $Command
Start-Sleep -Seconds $AfterSeconds
python "$PSScriptRoot\minecraft_screenshot.py" --title $Title --out $Out
