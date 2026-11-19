# Tool

Admin-free helper scripts for a self-hosted **MiniMax-H3-Image** server on Windows
(the PC that runs `C:\AI\minimax-h3-image-server`).

Nothing here installs software, changes Windows settings, edits the registry or
touches services. The scripts only rewrite two `.py` files inside the server
folder you already own, plus one optional per-user scheduled task.

## Files

| File | What it does |
|---|---|
| `patch-h3-prompt-limit.ps1` | Raises the prompt cap **8000 → 16000** in `app\main.py` and `queue\poller.py`. Dry run by default, keeps `*.bak-<timestamp>` copies, verifies the result. |
| `render-guard.ps1` | Deletes generated media + transient job files and empties the worker log, so the PC keeps no images and no prompt text. Can repeat every 1–2 minutes. |
| `1-check-patch.cmd` | Show which lines the patch would change. Writes nothing. |
| `2-apply-patch.cmd` | Apply the patch. |
| `3-render-guard-install.cmd` | Start the trace wiper (every 2 minutes, from now on). |
| `4-render-guard-now.cmd` | Run the trace wiper once, right now. |

No other files are needed on the PC. `README.md` is just this page.

## Usage

1. Put these files in `C:\AI\h3-tools` (any folder works).
2. If Windows says *"not digitally signed"*, unblock them once:
   ```powershell
   Get-ChildItem .\*.ps1 | Unblock-File
   ```
3. Close the model + worker windows.
4. Double-click **`1-check-patch.cmd`** → review the printed lines.
5. Double-click **`2-apply-patch.cmd`** → writes the change + backups + verifies `16000`.
6. Start `START.cmd` again, then check:
   ```powershell
   irm http://127.0.0.1:8633/api/health
   # {"status":"ok","loaded":true,...}
   # if loaded is false:  irm -Method Post http://127.0.0.1:8633/api/admin/load
   ```
7. Double-click **`3-render-guard-install.cmd`** → the PC now wipes its own traces.

Command line:

```powershell
.\patch-h3-prompt-limit.ps1                 # dry run
.\patch-h3-prompt-limit.ps1 -Apply          # write
.\patch-h3-prompt-limit.ps1 -Root "D:\other\install" -NewLimit 16000

.\render-guard.ps1 -WhatIf                  # show what would be deleted
.\render-guard.ps1                          # delete now
.\render-guard.ps1 -Register                # every 2 minutes
.\render-guard.ps1 -Register -EveryMinutes 1
.\render-guard.ps1 -Unregister              # stop and remove the task
.\render-guard.ps1 -ExtraDirs "D:\more\stuff"
```

## Why the patch

The stock server cuts prompts at 8000 characters — request validation in
`app\main.py` (`max_length=8000`, or a `MAX_PROMPT_CHARS` constant) and
`prompt[:8000]` in `queue\poller.py`. Long creative prompts are silently
truncated there, which loses instructions and hurts image quality. The model
itself accepts far more, so raising the server-side cap removes the only real
limit.

## What the trace wiper removes

* generated media — `.png .jpg .jpeg .webp .bmp .tif .tiff` in `outputs\`,
  `refs\`, `uploads\`, `images\`, `temp\`, `tmp\`, `cache\`, and in
  `queue\refs|tmp|temp|work|downloads|uploads`
* transient job payloads — `.json` inside `queue\tmp|temp|work|downloads`
* the worker log — emptied, or trimmed to `-KeepLogLines N`

It never touches `.py`, `.cmd`, `.exe`, `.bat`, model weights, the venv or
`config.json`. Files go with `-Force`, so nothing lands in the Recycle Bin.

A delete is not a forensic wipe: a recovery tool could still find fragments on an
unencrypted disk. If that matters, enable BitLocker for the drive, or run the
server under a separate Windows user whose profile/temp is wiped. Also avoid
opening `outputs\` in Explorer or the web UI while a batch runs — thumbnails and
browser cache can keep small previews.

## Admin rights

None needed. The scripts run as the normal user and only need write access to the
server folder. Admin would only be required if the server lives under
`C:\Program Files`, is registered as a Windows **service**, or the folder belongs
to another user. Start `START.cmd` normally — not "Run as administrator".

`-ExecutionPolicy Bypass` applies to that single process only; it does not change
any Windows setting.

## Revert

Every patched file gets a copy next to it:

```powershell
Get-ChildItem -Recurse *.bak-* | Select-Object FullName
Copy-Item .\app\main.py.bak-20260101-120000 .\app\main.py -Force
```

Then restart the server. To stop the trace wiper: `.\render-guard.ps1 -Unregister`.
