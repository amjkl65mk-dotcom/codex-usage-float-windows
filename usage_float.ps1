Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public static class CodexWindowState {
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    static bool IsCodexProcess(uint pid) {
        try {
            var name = Process.GetProcessById((int)pid).ProcessName;
            return name.Equals("Codex", StringComparison.OrdinalIgnoreCase)
                || name.Equals("ChatGPT", StringComparison.OrdinalIgnoreCase)
                || name.IndexOf("Codex", StringComparison.OrdinalIgnoreCase) >= 0;
        } catch { return false; }
    }
    public static int GetState() {
        uint foregroundPid;
        GetWindowThreadProcessId(GetForegroundWindow(), out foregroundPid);
        bool codexForeground = IsCodexProcess(foregroundPid);
        int state = 0;
        EnumWindows((h, _) => {
            if (!IsWindowVisible(h)) return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            try {
                if (IsCodexProcess(pid)) {
                    if (!IsIconic(h)) state = 2;
                    else if (state == 0) state = 1;
                }
            } catch { }
            return state != 2;
        }, IntPtr.Zero);
        if (state == 0) {
            foreach (var name in new[] { "Codex", "ChatGPT" }) {
                foreach (var p in Process.GetProcessesByName(name)) {
                    p.Refresh();
                    var h = p.MainWindowHandle;
                    if (h != IntPtr.Zero && IsWindowVisible(h)) {
                        state = IsIconic(h) ? 1 : 2;
                        if (state == 2) break;
                    }
                }
            }
        }
        return (state == 2 && codexForeground) ? 3 : state;
    }
}
'@

$script:CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$script:ConfigDir = Join-Path $env:APPDATA 'CodexUsageFloat'
$script:ConfigFile = Join-Path $script:ConfigDir 'config.json'
$script:Compact = $false
$script:Theme = 'dark'
$script:FollowCodex = $true
$script:CodexVisible = $true

function Get-LatestUsage {
    $folders = @((Join-Path $script:CodexHome 'sessions'), (Join-Path $script:CodexHome 'archived_sessions'))
    $files = foreach ($folder in $folders) {
        if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue }
    }
    foreach ($file in ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 40)) {
        $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -notmatch '"type":"token_count"' -or $lines[$i] -notmatch '"rate_limits"') { continue }
            try {
                $row = $lines[$i] | ConvertFrom-Json
                $limits = $row.payload.rate_limits
                if ($null -ne $limits.primary.used_percent) {
                    return [pscustomobject]@{
                        Remaining = [math]::Max(0, [math]::Min(100, 100 - [double]$limits.primary.used_percent))
                        ResetsAt = if ($limits.primary.resets_at) { [long]$limits.primary.resets_at } else { $null }
                        Plan = if ($limits.plan_type) { $limits.plan_type.ToString().ToUpper() } else { 'CHATGPT' }
                    }
                }
            } catch { }
        }
    }
    return $null
}

function Read-Config {
    if (Test-Path -LiteralPath $script:ConfigFile) {
        try { return Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ x = $null; y = 36; compact = $false; theme = 'dark'; followCodex = $true }
}

function Save-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null }
    @{ x = [int]$window.Left; y = [int]$window.Top; compact = $script:Compact; theme = $script:Theme; followCodex = $script:FollowCodex } | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigFile -Encoding UTF8
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight">
  <Border Name="Card" Background="#EE111827" CornerRadius="11" Padding="11,8" SnapsToDevicePixels="True" BorderThickness="1" BorderBrush="#263244">
    <StackPanel>
      <DockPanel Width="126">
        <TextBlock Name="TitleText" Text="CODEX" Foreground="#9CA3AF" FontFamily="Segoe UI" FontSize="9" FontWeight="SemiBold" VerticalAlignment="Center" />
        <TextBlock Name="ValueText" Text="--%" Foreground="#F9FAFB" FontFamily="Segoe UI" FontSize="22" FontWeight="Bold" HorizontalAlignment="Right" />
      </DockPanel>
      <Border Name="Track" Width="126" Height="4" Background="#263244" CornerRadius="2" HorizontalAlignment="Left" Margin="0,3,0,0">
        <Grid HorizontalAlignment="Left"><Border Name="Bar" Width="0" Height="4" Background="#34D399" CornerRadius="2" HorizontalAlignment="Left" /></Grid>
      </Border>
      <TextBlock Name="DetailText" Text="读取中…" Foreground="#9CA3AF" FontFamily="Segoe UI" FontSize="9" Margin="0,4,0,0" />
    </StackPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$card = $window.FindName('Card'); $titleText = $window.FindName('TitleText'); $valueText = $window.FindName('ValueText')
$track = $window.FindName('Track'); $bar = $window.FindName('Bar'); $detailText = $window.FindName('DetailText')

function Update-Usage {
    $usage = Get-LatestUsage
    if ($usage) {
        $remaining = [double]$usage.Remaining
        $color = if ($remaining -gt 40) { '#34D399' } elseif ($remaining -gt 20) { '#FBBF24' } else { '#F87171' }
        $valueText.Text = '{0:N0}%' -f $remaining
        $valueText.Foreground = $color
        $bar.Background = $color
        $bar.Width = 126 * $remaining / 100
        $titleText.Text = "CODEX $($usage.Plan)"
        if ($usage.ResetsAt) {
            $reset = [DateTimeOffset]::FromUnixTimeSeconds($usage.ResetsAt).LocalDateTime
            $span = $reset - [datetime]::Now
            if ($span.TotalSeconds -lt 0) { $span = [timespan]::Zero }
            $countdown = if ($span.Days -gt 0) { "$($span.Days)天 $($span.Hours)小时" } elseif ($span.Hours -gt 0) { "$($span.Hours)小时 $($span.Minutes)分" } else { "$($span.Minutes)分钟" }
            $detailText.Text = "$countdown 后重置"
        } else { $detailText.Text = '重置时间未知' }
    } else {
        $valueText.Text = '--%'; $valueText.Foreground = '#9CA3AF'; $bar.Width = 0
        $detailText.Text = '暂无数据 · 在 Codex 中发送一条消息后刷新'
    }
}

function Toggle-Compact {
    $script:Compact = -not $script:Compact
    if ($script:Compact) {
        $titleText.Visibility = 'Collapsed'; $track.Visibility = 'Collapsed'; $detailText.Visibility = 'Collapsed'
        $valueText.FontSize = 16; $valueText.Margin = '0'; $card.Padding = '9,4'
    } else {
        $titleText.Visibility = 'Visible'; $track.Visibility = 'Visible'; $detailText.Visibility = 'Visible'
        $valueText.FontSize = 22; $valueText.Margin = '0'; $card.Padding = '11,8'
    }
    Save-Config
}

function Set-Theme([string]$name) {
    $script:Theme = $name
    switch ($name) {
        'light' { $card.Background = '#F2FFFFFF'; $card.BorderBrush = '#CBD5E1'; $titleText.Foreground = '#64748B'; $detailText.Foreground = '#64748B'; $track.Background = '#E2E8F0' }
        'blue' { $card.Background = '#F20B2559'; $card.BorderBrush = '#315A9E'; $titleText.Foreground = '#93C5FD'; $detailText.Foreground = '#BFDBFE'; $track.Background = '#1E3A6D' }
        'glass' { $card.Background = '#AA111827'; $card.BorderBrush = '#66FFFFFF'; $titleText.Foreground = '#D1D5DB'; $detailText.Foreground = '#D1D5DB'; $track.Background = '#66374251' }
        default { $card.Background = '#EE111827'; $card.BorderBrush = '#263244'; $titleText.Foreground = '#9CA3AF'; $detailText.Foreground = '#9CA3AF'; $track.Background = '#263244' }
    }
    Save-Config
}

function Update-CodexVisibility {
    if (-not $script:FollowCodex) {
        if (-not $script:CodexVisible) {
            $window.Opacity = 1; $window.IsHitTestVisible = $true; $script:CodexVisible = $true
        }
        return
    }
    $state = [CodexWindowState]::GetState()
    $userInteracting = $window.IsMouseOver -or ($null -ne $card.ContextMenu -and $card.ContextMenu.IsOpen)
    if ($state -eq 3 -or $userInteracting) {
        if (-not $script:CodexVisible) {
            $window.Opacity = 1
            $window.IsHitTestVisible = $true
            $window.Topmost = $false; $window.Topmost = $true
            $script:CodexVisible = $true
        }
    }
    elseif ($script:CodexVisible) {
        $window.Opacity = 0
        $window.IsHitTestVisible = $false
        $script:CodexVisible = $false
    }
}

$menu = New-Object System.Windows.Controls.ContextMenu
$refreshItem = New-Object System.Windows.Controls.MenuItem; $refreshItem.Header = '立即刷新'; $refreshItem.Add_Click({ Update-Usage }); [void]$menu.Items.Add($refreshItem)
$compactItem = New-Object System.Windows.Controls.MenuItem; $compactItem.Header = '切换紧凑模式'; $compactItem.Add_Click({ Toggle-Compact }); [void]$menu.Items.Add($compactItem)
$themeMenu = New-Object System.Windows.Controls.MenuItem; $themeMenu.Header = '更换外观'
foreach ($theme in @(@('dark','深色'), @('light','浅色'), @('blue','蓝色'), @('glass','半透明'))) {
    $item = New-Object System.Windows.Controls.MenuItem; $item.Header = $theme[1]; $themeName = $theme[0]
    $item.Add_Click([scriptblock]::Create("Set-Theme '$themeName'")); [void]$themeMenu.Items.Add($item)
}
[void]$menu.Items.Add($themeMenu)
$followItem = New-Object System.Windows.Controls.MenuItem; $followItem.Header = '跟随 Codex 显示'; $followItem.IsCheckable = $true; $followItem.IsChecked = $true
$followItem.Add_Click({ $script:FollowCodex = $followItem.IsChecked; Save-Config; Update-CodexVisibility }); [void]$menu.Items.Add($followItem)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
$exitItem = New-Object System.Windows.Controls.MenuItem; $exitItem.Header = '退出'; $exitItem.Add_Click({ Save-Config; $window.Close() }); [void]$menu.Items.Add($exitItem)
$card.ContextMenu = $menu

$window.Add_MouseLeftButtonDown({ if ($_.ClickCount -eq 2) { Toggle-Compact } else { $window.DragMove() } })
$window.Add_MouseLeftButtonUp({ Save-Config })
$window.Add_Closing({ Save-Config })

$config = Read-Config
$window.Add_Loaded({
    if ($null -ne $config.x) { $window.Left = [double]$config.x } else { $window.Left = [SystemParameters]::WorkArea.Right - $window.ActualWidth - 24 }
    $window.Top = if ($null -ne $config.y) { [double]$config.y } else { 36 }
    if ($config.PSObject.Properties.Name -contains 'theme') { Set-Theme $config.theme }
    if ($config.PSObject.Properties.Name -contains 'followCodex') { $script:FollowCodex = [bool]$config.followCodex; $followItem.IsChecked = $script:FollowCodex }
    if ($config.compact -eq $true) { Toggle-Compact }
    Update-Usage
    Update-CodexVisibility
})
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [timespan]::FromSeconds(30); $timer.Add_Tick({ Update-Usage }); $timer.Start()
$visibilityTimer = New-Object System.Windows.Threading.DispatcherTimer
$visibilityTimer.Interval = [timespan]::FromMilliseconds(500); $visibilityTimer.Add_Tick({ Update-CodexVisibility }); $visibilityTimer.Start()
[void]$window.ShowDialog()
