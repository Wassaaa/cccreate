$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ReportPath = Join-Path $Root "inbox\latest-report.json"

if (-not (Test-Path $ReportPath)) {
  Write-Host "No latest report found at $ReportPath"
  exit 1
}

Get-Content $ReportPath -Raw
