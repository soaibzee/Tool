@echo off
rem Optional - keeps outputs\ empty: registers a daily 06:00 cleanup that deletes
rem PNG files older than 24 h. Runs as your own user, no admin rights needed.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-cleanup-outputs.ps1" -Register
echo.
pause
