@echo off
rem Step 2 - apply the patch (8000 -> 16000). Keeps .bak-<timestamp> copies.
rem Close the model/worker windows first, then run START.cmd again afterwards.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-h3-prompt-limit.ps1" -Apply
echo.
echo Next: start START.cmd, then open http://127.0.0.1:8633/api/health
pause
