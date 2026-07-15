@echo off
cd /d "%~dp0"
start "CodexUsageFloat" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText('%~dp0usage_float.ps1')))"
