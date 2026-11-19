# h3-pc-tools

Small, **admin-free** helper scripts for a self-hosted **MiniMax-H3-Image** server on
Windows (the machine that runs `C:\AI\minimax-h3-image-server`).

Nothing here installs anything, changes Windows settings, edits the registry or
touches services. The scripts only rewrite two text files inside the server
folder you already own, plus one optional per-user scheduled task.

## What each file does

| File | Purpose |
|---|---|
| `patch-h3-prompt-limit.ps1` | Raises the server's prompt character cap from **8000 → 16000** in `app\main.py` and `queue\poller.py`. Dry run by default, keeps `*.bak-<timestamp>` copies, verifies the result. |
| `pc-cleanup-outputs.ps1` | Deletes PNGs older than N hours from the server's `outputs\` folder. Can register a daily 06:00 per-user task. |
| `render-guard.ps1` | **Trace wiper.** Deletes generated media + transient job files and empties the worker log, so the PC keeps no images and no prompt text. Can run every 1–2 minutes. |
| `1-check-patch.cmd` | Double-click: shows exactly which lines would change. Writes nothing. |
| `2-apply-patch.cmd` | Double-click: applies the patch (after `1` looks right). |
| `3-cleanup-task.cmd` | Double-click: registers the daily cleanup task. |
| `4-cleanup-now.cmd` | Double-click: runs the cleanup once. |
| `5-render-guard-install.cmd` | Double-click: wipes PC traces every 2 minutes from now on. |
| `6-render-guard-now.cmd` | Double-click: wipes PC traces once, right now. |

## Why the patch

The stock server truncates prompts at 8000 characters:

* request validation in `app\main.py` (`max_length=8000`, or a `MAX_PROMPT_CHARS` constant)
* `prompt[:8000]` inside `queue\poller.py`

Long creative prompts are silently cut there, which loses instructions and hurts
image quality. The model itself accepts far more (tens of thousands of
characters), so raising the server-side cap removes the only real limit.

## Usage

1. Copy this folder to the server PC, e.g. `C:\AI\h3-tools`.
2. If Windows says *"not digitally signed"*, unblock the downloaded files once:
   ```powershell
   Get-ChildItem .\*.ps1 | Unblock-File
   ```
3. Close the model + worker windows.
4. Double-click **`1-check-patch.cmd`** → review the printed lines.
5. Double-click **`2-apply-patch.cmd`** → writes the change + backups.
6. Start `START.cmd` again, then check:
   ```powershell
   irm http://127.0.0.1:8633/api/health
   # {"status":"ok","loaded":true,...}
   # if loaded is false:  irm -Method Post http://127.0.0.1:8633/api/admin/load
   ```
7. Optional: `3-cleanup-task.cmd` for the daily `outputs\` cleanup.
8. Recommended: `5-render-guard-install.cmd` so the PC deletes its own traces
   every couple of minutes (see the next section).

Command line equivalents:

```powershell
powershell -ExecutionPolicy Bypass -File .\patch-h3-prompt-limit.ps1            # dry run
powershell -ExecutionPolicy Bypass -File .\patch-h3-prompt-limit.ps1 -Apply     # write
powershell -ExecutionPolicy Bypass -File .\patch-h3-prompt-limit.ps1 -Root "D:\other\install" -NewLimit 16000
powershell -ExecutionPolicy Bypass -File .\pc-cleanup-outputs.ps1 -Register
```

## Keeping the PC a pure render machine

```powershell
.\render-guard.ps1 -WhatIf        # show what would be deleted, change nothing
.\render-guard.ps1                # delete now
.\render-guard.ps1 -Register      # repeat every 2 minutes (default)
.\render-guard.ps1 -Register -EveryMinutes 1
.\render-guard.ps1 -Unregister    # stop and remove the task
```

What it removes (never `.py`, `.cmd`, `.exe`, model weights or `config.json`):

* generated media — `.png .jpg .jpeg .webp .bmp .tif .tiff` in `outputs\`,
  `refs\`, `uploads\`, `images\`, `temp\`, `tmp\`, `cache\`, and the
  `queue\refs|tmp|temp|work|downloads|uploads` folders
* transient job payloads — `.json` inside `queue\tmp|temp|work|downloads`
* the worker log — emptied, or trimmed to `-KeepLogLines N`

Files are removed with `-Force`, so nothing lands in the Recycle Bin. More
folders can be added with `-ExtraDirs "D:\somewhere\else"`.

A delete is not a forensic wipe: a recovery tool could still find fragments on an
unencrypted disk. If that matters, turn on BitLocker for the drive, or run the
server under a separate Windows user whose temp/profile gets wiped. Model
weights, the venv and `config.json` always stay — they are not customer data.

## Admin rights

None needed. The scripts run as the normal user and only need **write access to
the server folder**. Admin would only be required if the server lives in
`C:\Program Files` or is registered as a Windows service, or if the current
session is already elevated (close and reopen the window normally).

Changing the execution policy is not needed either — `-ExecutionPolicy Bypass`
applies to that single process only.

## Revert

Every patched file gets a copy next to it:

```powershell
Get-ChildItem -Recurse *.bak-* | Select-Object FullName
Copy-Item .\app\main.py.bak-20260101-120000 .\app\main.py -Force
```

Then restart the server.
