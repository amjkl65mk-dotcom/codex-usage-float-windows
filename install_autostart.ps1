$ErrorActionPreference = 'Stop'
$source = (Get-Location).Path
$install = Join-Path $env:LOCALAPPDATA 'CodexUsageFloat'
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$link = Join-Path $startup 'CodexUsageFloat.lnk'

New-Item -ItemType Directory -Path $install -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'usage_float.ps1') -Destination $install -Force
Copy-Item -LiteralPath (Join-Path $source 'start.bat') -Destination $install -Force
Copy-Item -LiteralPath (Join-Path $source 'uninstall_autostart.bat') -Destination $install -Force

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($link)
$shortcut.TargetPath = Join-Path $install 'start.bat'
$shortcut.WorkingDirectory = $install
$shortcut.WindowStyle = 7
$shortcut.Description = 'Codex usage floating monitor'
$shortcut.Save()

if (-not (Test-Path -LiteralPath $link)) { throw 'Startup shortcut was not created.' }
Start-Process -FilePath (Join-Path $install 'start.bat') -WindowStyle Hidden
Write-Host "Installed successfully: $install"
Write-Host 'The monitor will start automatically after Windows sign-in.'
