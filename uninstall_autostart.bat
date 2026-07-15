@echo off
set "LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CodexUsageFloat.lnk"
if exist "%LINK%" del "%LINK%"
echo 已关闭自动启动。当前运行的悬浮窗可通过右键菜单退出。
echo 程序文件保留在 %LOCALAPPDATA%\CodexUsageFloat，方便以后重新启用。
pause
