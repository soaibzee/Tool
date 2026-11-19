# 4-cleanup-now.cmd
@echo off
rem Optional - delete old PNGs from outputs\ right now (older than 24 h).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-cleanup-outputs.ps1"
echo.
pause
