# Keeps the render PC a pure render machine: no generated media, no job payloads,
# no prompt text left behind on its disk.
#
# Run once (default: delete everything it finds, empty the worker log):
#   powershell -ExecutionPolicy Bypass -File .\render-guard.ps1
#
# See what would go, without deleting:
#   powershell -ExecutionPolicy Bypass -File .\render-guard.ps1 -WhatIf
#
# Install a repeating cleanup (every 2 minutes, current user, no admin):
#   powershell -ExecutionPolicy Bypass -File .\render-guard.ps1 -Register
#   powershell -ExecutionPolicy Bypass -File .\render-guard.ps1 -Register -EveryMinutes 1
#
# Remove it:
#   powershell -ExecutionPolicy Bypass -File .\render-guard.ps1 -Unregister
#
# Notes
#  * Only media files (.png .jpg .jpeg .webp .bmp .tif .tiff) and transient job
#    files are touched - never .py, .cmd, .exe, .bat, model weights or config.json.
#  * Files are removed with -Force, so nothing goes to the Recycle Bin.
#  * Delete is not a forensic wipe: a recovery tool could still find fragments on
#    an unencrypted disk. For that level, put the server on a BitLocker volume or
#    run it as a separate Windows user with its own temp folder.

[CmdletBinding()]
param(
  [string]$Root = 'C:\AI\minimax-h3-image-server',
  [int]$OlderThanSeconds = 0,
  [int]$KeepLogLines = 0,
  [string[]]$ExtraDirs = @(),
  [switch]$Register,
  [int]$EveryMinutes = 2,
  [string]$TaskName = 'H3 render guard',
  [switch]$Unregister,
  [switch]$WhatIf,
  [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

function Say([string]$text, [string]$color = 'Gray') {
  if (-not $Quiet) { Write-Host $text -ForegroundColor $color }
}

# ---------- unregister ----------
if ($Unregister) {
  schtasks /Delete /TN $TaskName /F *> $null
  Say "Removed scheduled task: $TaskName" 'Yellow'
  return
}

# ---------- install ----------
if ($Register) {
  $here    = Split-Path -Parent $MyInvocation.MyCommand.Path
  $runner  = Join-Path $here 'render-guard-run.cmd'
  $content = @(
    '@echo off',
    "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$here\render-guard.ps1`" -Root `"$Root`" -OlderThanSeconds $OlderThanSeconds -KeepLogLines $KeepLogLines -Quiet"
  ) -join "`r`n"
  Set-Content -LiteralPath $runner -Value $content -Encoding ASCII

  schtasks /Create /SC MINUTE /MO $EveryMinutes /TN $TaskName /TR "`"$runner`"" /RL LIMITED /F *> $null
  if ($LASTEXITCODE -ne 0) { throw "schtasks failed with exit code $LASTEXITCODE" }
  Say "Installed '$TaskName': every $EveryMinutes min, runs as $env:USERNAME (no admin)." 'Green'
  Say "Runner: $runner"
  return
}

# ---------- cleanup ----------
if (-not (Test-Path -LiteralPath $Root)) {
  Say "Server folder not found: $Root" 'Yellow'
  Say 'Pass the real path with -Root "D:\...\minimax-h3-image-server".'
  exit 2
}

$cutoff = (Get-Date).AddSeconds(-[Math]::Max(0, $OlderThanSeconds))

# folders that may hold rendered output / downloaded references
$mediaDirs = @(
  'outputs', 'output', 'refs', 'references', 'uploads', 'images',
  'temp', 'tmp', 'cache',
  'queue\refs', 'queue\tmp', 'queue\temp', 'queue\work', 'queue\downloads', 'queue\uploads'
) | ForEach-Object { Join-Path $Root $_ }

$mediaDirs += $ExtraDirs | Where-Object { $_ }
$mediaDirs = $mediaDirs | Where-Object { Test-Path -LiteralPath $_ }

# folders that may hold job payloads (json) for the current job
$jobDirs = @('queue\tmp', 'queue\temp', 'queue\work', 'queue\downloads') |
  ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ }

$mediaExt = @('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tif', '.tiff')
$keepNames = @('config.json', 'package.json', 'tsconfig.json')

$deleted = 0
$freedBytes = [int64]0

foreach ($dir in $mediaDirs) {
  $files = Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue
  foreach ($f in $files) {
    if ($f.LastWriteTime -gt $cutoff) { continue }
    $isMedia = $mediaExt -contains $f.Extension.ToLower()
    $isJobFile = ($jobDirs -contains $dir) -and ($f.Extension.ToLower() -eq '.json') -and ($keepNames -notcontains $f.Name.ToLower())
    if (-not ($isMedia -or $isJobFile)) { continue }
    if ($keepNames -contains $f.Name.ToLower()) { continue }

    if ($WhatIf) {
      Say ("would delete {0}  ({1:N0} KB)" -f $f.FullName, [Math]::Ceiling($f.Length / 1KB)) 'DarkGray'
    } else {
      try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $deleted++
        $freedBytes += $f.Length
      } catch {
        Say ("could not delete {0}: {1}" -f $f.FullName, $_.Exception.Message) 'Yellow'
      }
    }
  }
}

# job rows may also be mirrored into a local sqlite file - only its WAL/journal is
# transient, never touch the database itself.

# ---------- worker log ----------
$logs = @()
foreach ($name in 'poller.log', 'worker.log', 'queue\poller.log') {
  $p = Join-Path $Root $name
  if (Test-Path -LiteralPath $p) { $logs += Get-Item -LiteralPath $p }
}

foreach ($log in $logs) {
  if ($log.LastWriteTime -gt $cutoff) { continue }
  if ($WhatIf) { Say ("would trim {0} to {1} line(s)" -f $log.FullName, $KeepLogLines) 'DarkGray'; continue }
  try {
    if ($KeepLogLines -gt 0) {
      $tail = Get-Content -LiteralPath $log.FullName -Tail $KeepLogLines -ErrorAction SilentlyContinue
      [IO.File]::WriteAllText($log.FullName, (($tail -join "`n") + "`n"))
    } else {
      try { [IO.File]::WriteAllText($log.FullName, '') }
      catch { Clear-Content -LiteralPath $log.FullName -Force -ErrorAction Stop }
    }
  } catch {
    Say ("log is locked (worker running): {0}" -f $log.Name) 'Yellow'
  }
}

if ($WhatIf) {
  Say 'Dry run - nothing was deleted.' 'Cyan'
} else {
  Say ("Cleaned {0} file(s), {1:N1} MB; log(s): {2}" -f $deleted, ($freedBytes / 1MB), $(if ($logs.Count) { 'trimmed' } else { 'none' })) 'Green'
}
