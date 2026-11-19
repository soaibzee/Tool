@echo off
rem Makes the render PC wipe its own traces: every 2 minutes it deletes generated
rem PNG/WEBP files (outputs\, refs\, temp\) and empties the worker log, so the
rem machine only ever holds the image it is rendering right now.
rem Runs as your own user - no admin rights needed.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0render-guard.ps1" -Register
echo.
echo Installed. Check any time with:  schtasks /Query /TN "H3 render guard"
pause
