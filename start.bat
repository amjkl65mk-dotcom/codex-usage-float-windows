@echo off
cd /d "%~dp0"
start "CodexUsageFloat" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText('%~dp0usage_float_winforms.ps1')))"
