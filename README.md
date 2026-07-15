# Codex 用量悬浮窗（Windows）

一个置顶、可拖动的轻量悬浮窗，自动读取本机 Codex 会话日志中的官方用量数据。不读取浏览器 Cookie，不上传任何数据，也不需要 API Key 或额外安装软件。

## 运行

双击 `start.bat`。默认使用 Windows 自带 PowerShell/WPF；也可以在命令行运行：

```powershell
powershell -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText('.\usage_float.ps1')))"
```

首次运行若显示 `--%`，先在 Codex 中发送一条消息，再右键悬浮窗选择“立即刷新”。

## 自动启动（推荐）

先完整解压压缩包（不要直接在压缩包预览窗口内运行），再双击 `install_autostart.bat`。安装程序会把运行文件复制到稳定目录 `%LOCALAPPDATA%\CodexUsageFloat`，以后登录 Windows 后会启动一个不可见的轻量监控：

- 切换到 Codex：自动显示用量
- 切换到其他应用、最小化或关闭 Codex：自动完全隐藏
- 再次打开 Codex：自动恢复显示

不再需要每次手动运行。若不再需要，双击 `uninstall_autostart.bat`。

每次下载新版后，请重新双击一次 `install_autostart.bat`，它会覆盖固定目录中的旧版本并保留你的外观设置。

## 操作

- 拖动：按住悬浮窗移动
- Codex 窗口最小化或关闭时，悬浮窗同步隐藏；恢复 Codex 后自动出现
- 双击：切换普通/紧凑模式
- 右键：刷新、切换深色/浅色/蓝色/半透明外观，或关闭“跟随 Codex 显示”
- 颜色：绿色 > 40%，黄色 20–40%，红色 ≤ 20%

位置、显示模式、主题和跟随设置会保存在 `%APPDATA%\CodexUsageFloat\config.json`。

`app.py` 是相同功能的 Python/Tkinter 版本，适合已有完整 Python 环境时二次开发；日常使用请直接运行 `start.bat`。

## 数据口径

界面显示 `100 - used_percent`。数据来自 `%USERPROFILE%\.codex\sessions` 最近一次 `token_count` 事件中的 `rate_limits.primary`，并显示该窗口的重置倒计时。它反映 Codex 当前返回的用量窗口，不代表 API 账单余额，也不能读取 ChatGPT 网页中未暴露给 Codex 的其他额度。
