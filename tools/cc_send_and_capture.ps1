param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Command,

  [string]$Title = "Minecraft NeoForge",
  [double]$AfterSeconds = 2,
  [string]$Out = "inbox/minecraft-window.bmp",
  [ValidateSet("screen", "printwindow")]
  [string]$Method = "screen",
  [string]$Crop = "700,380,1850,1050"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
  uv run python tools\minecraft_send.py --title $Title --delay 0.02 $Command
  Start-Sleep -Seconds $AfterSeconds

  $screenshotArgs = @("python", "tools\minecraft_screenshot.py", "--title", $Title, "--method", $Method, "--out", $Out)
  if ($Crop) {
    $screenshotArgs += @("--crop", $Crop)
  }
  uv run @screenshotArgs
}
finally {
  Pop-Location
}
