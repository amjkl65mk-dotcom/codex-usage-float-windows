@echo off
setlocal
set "LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CodexUsageFloat.lnk"
set "TARGET=%~dp0start.bat"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$w=New-Object -ComObject WScript.Shell; $s=$w.CreateShortcut('%LINK%'); $s.TargetPath='%TARGET%'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=7; $s.Description='Codex usage floating monitor'; $s.Save()"
if exist "%LINK%" (
  echo 已开启自动启动。以后登录 Windows 后会自动监控 Codex。
  call "%~dp0start.bat"
) else (
  echo 设置失败，请尝试右键“以管理员身份运行”。
)
pause
