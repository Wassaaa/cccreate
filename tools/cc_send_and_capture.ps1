param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Command,

  [string]$Title = "Minecraft NeoForge",
  [double]$AfterSeconds = 2,
  [string]$Out = "inbox/minecraft-window.bmp",
  [ValidateSet("screen", "printwindow")]
  [string]$Method = "screen",
  [string]$Crop
)

$ErrorActionPreference = "Stop"

python "$PSScriptRoot\minecraft_send.py" --title $Title --delay 0.02 $Command
Start-Sleep -Seconds $AfterSeconds
$screenshotArgs = @("$PSScriptRoot\minecraft_screenshot.py", "--title", $Title, "--method", $Method, "--out", $Out)
if ($Crop) {
  $screenshotArgs += @("--crop", $Crop)
}
python @screenshotArgs
