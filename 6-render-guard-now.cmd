@echo off
rem Runs the trace cleanup once, right now. Use it after a batch finishes.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0render-guard.ps1"
echo.
pause
