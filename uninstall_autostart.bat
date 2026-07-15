@echo off
set "LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CodexUsageFloat.lnk"
if exist "%LINK%" del "%LINK%"
echo Autostart has been disabled.
pause
