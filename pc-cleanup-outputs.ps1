# Keeps the model PC's outputs\ folder empty-ish (laptop holds the real copies).
#
#   Dry run (shows what would be deleted):
#     powershell -ExecutionPolicy Bypass -File .\pc-cleanup-outputs.ps1
#
#   Delete now:
#     powershell -ExecutionPolicy Bypass -File .\pc-cleanup-outputs.ps1 -Hours 0
#
#   Register a daily 06:00 scheduled task (no admin needed, runs as you):
#     powershell -ExecutionPolicy Bypass -File .\pc-cleanup-outputs.ps1 -Register
#
#   Remove the task again:
#     powershell -ExecutionPolicy Bypass -File .\pc-cleanup-outputs.ps1 -Unregister

[CmdletBinding()]
param(
  [string]$Outputs = 'C:\AI\minimax-h3-image-server\outputs',
  [int]$Hours = 24,
  [string]$TaskName = 'H3 outputs cleanup',
  [string]$TaskTime = '06:00',
  [switch]$Register,
  [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

if ($Unregister) {
  schtasks /Delete /TN $TaskName /F | Out-Null
  Write-Host "Removed scheduled task: $TaskName"
  return
}

if (-not (Test-Path -LiteralPath $Outputs)) {
  Write-Host "Outputs folder not found: $Outputs"
  Write-Host 'Pass the real path with -Outputs "C:\AI\...\outputs".'
  exit 2
}

$cutoff = (Get-Date).AddHours(-$Hours)
$stale = @(Get-ChildItem -LiteralPath $Outputs -Filter *.png -File | Where-Object { $_.LastWriteTime -lt $cutoff })
$totalMb = if ($stale.Count) { [math]::Round((($stale | Measure-Object Length -Sum).Sum / 1MB), 1) } else { 0 }

Write-Host "Folder   : $Outputs"
Write-Host "Cutoff   : older than $Hours h ($($cutoff.ToString('yyyy-MM-dd HH:mm')))"
Write-Host "Files    : $($stale.Count) PNG, $totalMb MB"
foreach ($f in $stale | Select-Object -First 10) {
  Write-Host ("   {0}  {1}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $f.Name)
}
if ($stale.Count -gt 10) { Write-Host "   ... and $($stale.Count - 10) more" }

if ($Register) {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  $runner = Join-Path $here 'pc-cleanup-outputs-run.cmd'
  $cmd = @(
    '@echo off',
    "powershell -NoProfile -ExecutionPolicy Bypass -File `"$here\pc-cleanup-outputs.ps1`" -Outputs `"$Outputs`" -Hours $Hours"
  ) -join "`r`n"
  Set-Content -LiteralPath $runner -Value $cmd -Encoding ASCII

  schtasks /Create /SC DAILY /TN $TaskName /TR "`"$runner`"" /ST $TaskTime /F | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "schtasks failed with exit code $LASTEXITCODE" }
  Write-Host ''
  Write-Host "Registered daily task '$TaskName' at $TaskTime using $runner"
  return
}

if ($stale.Count -eq 0) {
  Write-Host ''
  Write-Host 'Nothing to delete right now.'
  return
}

foreach ($f in $stale) { Remove-Item -LiteralPath $f.FullName -Force }
Write-Host ''
Write-Host "Deleted $($stale.Count) file(s), freed $totalMb MB."
