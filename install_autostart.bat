@echo off
setlocal
set "INSTALL=%LOCALAPPDATA%\CodexUsageFloat"
set "LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CodexUsageFloat.lnk"
if not exist "%INSTALL%" mkdir "%INSTALL%"
copy /y "%~dp0usage_float.ps1" "%INSTALL%\usage_float.ps1" >nul
copy /y "%~dp0start.bat" "%INSTALL%\start.bat" >nul
copy /y "%~dp0uninstall_autostart.bat" "%INSTALL%\uninstall_autostart.bat" >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$w=New-Object -ComObject WScript.Shell; $s=$w.CreateShortcut('%LINK%'); $s.TargetPath='%INSTALL%\start.bat'; $s.WorkingDirectory='%INSTALL%'; $s.WindowStyle=7; $s.Description='Codex usage floating monitor'; $s.Save()"
if exist "%LINK%" (
  echo 已安装到固定目录并开启自动启动：%INSTALL%
  echo 以后登录 Windows 后会自动监控 Codex。
  call "%INSTALL%\start.bat"
) else (
  echo 设置失败，请尝试右键“以管理员身份运行”。
)
pause
