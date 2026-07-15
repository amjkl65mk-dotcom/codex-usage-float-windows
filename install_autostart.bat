@echo off
cd /d "%~dp0"
set "SCRIPT=%~dp0install_autostart.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText('%SCRIPT%')))"
if errorlevel 1 echo Installation failed. Extract all files first and try again.
pause
