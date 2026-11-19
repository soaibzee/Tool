@echo off
rem Step 1 - safe check. Changes nothing, only shows which lines would be edited.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-h3-prompt-limit.ps1"
echo.
pause
