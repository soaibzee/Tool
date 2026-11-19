# Raises the H3 prompt character limit on the model PC (8000 -> 16000).
#
# Runs as a NORMAL user. No admin rights, no registry / policy / service change:
# it only reads and rewrites two text files inside the folder you already own.
#
#   Check what would change (default, writes nothing):
#     powershell -ExecutionPolicy Bypass -File .\patch-h3-prompt-limit.ps1
#
#   Apply (makes .bak-<timestamp> copies first):
#     powershell -ExecutionPolicy Bypass -File .\patch-h3-prompt-limit.ps1 -Apply
#
#   Different folder or limit:
#     ... -Root "D:\minimax-h3-image-server" -NewLimit 16000
#
# If Windows says "not digitally signed", unblock the downloaded file once:
#   Unblock-File .\patch-h3-prompt-limit.ps1
#
# After -Apply: close the old server/worker windows and run START.cmd again,
# then check http://127.0.0.1:8633/api/health and /api/admin/load.

[CmdletBinding()]
param(
  [string]$Root = 'C:\AI\minimax-h3-image-server',
  [int]$NewLimit = 16000,
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$targets = @(
  (Join-Path $Root 'app\main.py'),
  (Join-Path $Root 'queue\poller.py')
)

if (-not (Test-Path -LiteralPath $Root)) {
  Write-Host "Folder not found: $Root" -ForegroundColor Yellow
  Write-Host 'Pass the real path, e.g. -Root "D:\minimax-h3-image-server"'
  exit 2
}

$missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) {
  Write-Host "Missing file(s):" -ForegroundColor Yellow
  $missing | ForEach-Object { Write-Host "  $_" }
  Write-Host 'Check the install folder (it must contain app\main.py and queue\poller.py).'
  exit 2
}

Write-Host "Root      : $Root"
Write-Host "New limit : $NewLimit"
Write-Host "Mode      : $(if ($Apply) { 'APPLY' } else { 'DRY RUN (nothing is written)' })"
Write-Host ''

$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$totalHits  = 0
$warnings   = @()

foreach ($file in $targets) {
  $bytes = [IO.File]::ReadAllBytes($file)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $text  = [IO.File]::ReadAllText($file)
  $crlf  = $text.Contains("`r`n")
  $lines = $text -split "`r?`n"

  # candidate lines: mention 8000 and talk about the prompt limit
  $hits = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '(?<!\d)8000(?!\d)') { continue }
    if ($line -notmatch '(?i)prompt|max_length|max_chars|max_len') { continue }
    $hits += [pscustomobject]@{
      Number = $i + 1
      Before = $line
      After  = [regex]::Replace($line, '(?<!\d)8000(?!\d)', [string]$NewLimit)
      Count  = ([regex]::Matches($line, '(?<!\d)8000(?!\d)')).Count
    }
  }

  Write-Host "--- $file"

  if ($hits.Count -eq 0) {
    $already = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '(?i)prompt' -and $lines[$i] -match "(?<!\d)$NewLimit(?!\d)") {
        $already += ('    line {0,4}: {1}' -f ($i + 1), $lines[$i].Trim())
      }
    }
    if ($already.Count -gt 0) {
      Write-Host "    looks already patched ($NewLimit present):"
      $already | ForEach-Object { Write-Host $_ }
    } else {
      Write-Host '    no prompt-limit line containing 8000 found (declared differently?)'
      Write-Host '    search manually:  Select-String -Path app\main.py,queue\poller.py -Pattern "8000"'
    }
    Write-Host ''
    continue
  }

  foreach ($h in $hits) {
    Write-Host ('    line {0,4}: {1}' -f $h.Number, $h.Before.Trim())
    Write-Host ('            -> {0}' -f $h.After.Trim()) -ForegroundColor Green
    if ($h.Count -gt 1) {
      $warnings += "line $($h.Number) of $file had $($h.Count) x 8000 - check it after patching"
    }
  }
  $totalHits += $hits.Count

  if ($Apply) {
    $backup = "$file.bak-$stamp"
    Copy-Item -LiteralPath $file -Destination $backup -Force
    Write-Host "    backup: $backup"

    foreach ($h in $hits) { $lines[$h.Number - 1] = $h.After }

    $nl      = if ($crlf) { "`r`n" } else { "`n" }
    $newText = ($lines -join $nl)
    $enc     = New-Object System.Text.UTF8Encoding($hasBom)
    [IO.File]::WriteAllText($file, $newText, $enc)
    Write-Host '    patched' -ForegroundColor Green
  }
  Write-Host ''
}

if ($totalHits -eq 0) {
  Write-Host 'Nothing to patch.'
  if ($warnings.Count) { $warnings | ForEach-Object { Write-Host "warning: $_" -ForegroundColor Yellow } }
  exit 0
}

if (-not $Apply) {
  Write-Host "Dry run complete: $totalHits line(s) would change." -ForegroundColor Cyan
  Write-Host 'Re-run the same command with -Apply to write the changes.'
  if ($warnings.Count) { $warnings | ForEach-Object { Write-Host "warning: $_" -ForegroundColor Yellow } }
  exit 0
}

# ---- verify by re-reading what is now on disk ----
Write-Host 'Verifying...'
$stillOld = 0
foreach ($file in $targets) {
  foreach ($line in ([IO.File]::ReadAllText($file) -split "`r?`n")) {
    if ($line -match '(?i)prompt|max_length|max_chars|max_len') {
      if ($line -match '(?<!\d)8000(?!\d)') { $stillOld++; Write-Host "  still 8000: $line" -ForegroundColor Red }
      if ($line -match "(?<!\d)$NewLimit(?!\d)") { Write-Host "  ok: $line" -ForegroundColor Green }
    }
  }
}

Write-Host ''
if ($warnings.Count) { $warnings | ForEach-Object { Write-Host "warning: $_" -ForegroundColor Yellow } }

if ($stillOld -gt 0) {
  Write-Host "Done with $stillOld line(s) still at 8000 - review them manually." -ForegroundColor Yellow
} else {
  Write-Host "Done: $totalHits line(s) changed to $NewLimit. No prompt limit at 8000 left." -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next steps on this PC (no admin needed):'
Write-Host '  1. Close the model + worker windows (or reboot).'
Write-Host '  2. Run START.cmd again.'
Write-Host '  3. irm http://127.0.0.1:8633/api/health            -> status ok'
Write-Host '  4. if loaded:false ->  irm -Method Post http://127.0.0.1:8633/api/admin/load'
