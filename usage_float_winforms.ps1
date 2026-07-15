Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$script:MutexCreated = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, 'Local\CodexUsageFloat', [ref]$script:MutexCreated)
if (-not $script:MutexCreated) { exit 0 }

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class UsageForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p=base.CreateParams; p.ExStyle|=0x08000000; return p; } }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); NativeStyle.Apply(Handle, 0x00D7D2D2); }
}
public static class NativeStyle {
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    public static void Apply(IntPtr h, int borderColor) { int corner=2; DwmSetWindowAttribute(h,33,ref corner,4); DwmSetWindowAttribute(h,34,ref borderColor,4); }
    public static void SetVisible(IntPtr h, bool visible) { ShowWindow(h, visible ? 4 : 0); }
    public static bool Visible(IntPtr h) { return IsWindowVisible(h); }
}
public static class CodexWindows {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l);
    static bool IsCodex(uint pid) { try { var n=Process.GetProcessById((int)pid).ProcessName; return n.Equals("ChatGPT",StringComparison.OrdinalIgnoreCase)||n.IndexOf("Codex",StringComparison.OrdinalIgnoreCase)>=0; } catch { return false; } }
    public static bool IsForeground() { uint p; GetWindowThreadProcessId(GetForegroundWindow(),out p); return IsCodex(p); }
    public static bool HasVisibleWindow() { bool yes=false; EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(IsCodex(p)&&IsWindowVisible(h)&&!IsIconic(h)){yes=true;return false;}return true;},IntPtr.Zero);return yes; }
}
'@

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$configDir = Join-Path $env:APPDATA 'CodexUsageFloat'; $configFile = Join-Path $configDir 'config.json'
$script:theme = 'light'; $script:follow = $true; $script:compact = $false; $script:visibleState = $true; $script:hideMisses = 0

function Get-LatestUsage {
    $newest=$null; $files=@()
    foreach($d in @((Join-Path $codexHome 'sessions'),(Join-Path $codexHome 'archived_sessions'))){if(Test-Path $d){$files+=Get-ChildItem $d -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue}}
    foreach($f in ($files|Sort-Object LastWriteTime -Descending|Select-Object -First 40)){
        $lines=Get-Content $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
        for($i=$lines.Count-1;$i-ge 0;$i--){
            if($lines[$i] -notmatch '"type":"token_count"' -or $lines[$i] -notmatch '"rate_limits"'){continue}
            try{$r=$lines[$i]|ConvertFrom-Json;$l=$r.payload.rate_limits;if($null -ne $l.primary.used_percent){$when=$f.LastWriteTimeUtc;if($r.timestamp){try{$when=[DateTimeOffset]::Parse($r.timestamp).UtcDateTime}catch{}};$c=[pscustomobject]@{Remaining=[math]::Max(0,[math]::Min(100,100-[double]$l.primary.used_percent));Reset=$l.primary.resets_at;Plan=if($l.plan_type){$l.plan_type.ToString().ToUpper()}else{'CHATGPT'};When=$when};if($null -eq $newest -or $c.When -gt $newest.When){$newest=$c};break}}catch{}
        }
    };return $newest
}
function Read-Config {try{return Get-Content $configFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{return [pscustomobject]@{x=302;y=30;theme='light';followCodex=$true;compact=$false}}}
function Save-Config {New-Item $configDir -ItemType Directory -Force|Out-Null;@{x=$form.Left;y=$form.Top;theme=$script:theme;followCodex=$script:follow;compact=$script:compact}|ConvertTo-Json|Set-Content $configFile -Encoding UTF8}

$form=New-Object UsageForm
$form.FormBorderStyle='None';$form.ShowInTaskbar=$false;$form.TopMost=$true;$form.Size=New-Object Drawing.Size(132,58);$form.StartPosition='Manual'
$title=New-Object Windows.Forms.Label;$title.SetBounds(10,6,68,16);$title.Font=New-Object Drawing.Font('Segoe UI Variable Text',7.2,[Drawing.FontStyle]::Bold);$title.Text='CODEX'
$value=New-Object Windows.Forms.Label;$value.SetBounds(76,3,47,22);$value.TextAlign='MiddleRight';$value.Font=New-Object Drawing.Font('Segoe UI Variable Display',13,[Drawing.FontStyle]::Bold);$value.Text='--%'
$track=New-Object Windows.Forms.Panel;$track.SetBounds(10,27,112,3)
$bar=New-Object Windows.Forms.Panel;$bar.SetBounds(0,0,0,3);$track.Controls.Add($bar)
$detail=New-Object Windows.Forms.Label;$detail.SetBounds(10,34,112,16);$detail.Font=New-Object Drawing.Font('Segoe UI Variable Text',7.2);$detail.Text='正在读取…'
$form.Controls.AddRange(@($title,$value,$track,$detail))

function Set-Theme($name){$script:theme=$name;switch($name){'light'{$form.BackColor='#F5F5F7';$title.ForeColor='#6E6E73';$detail.ForeColor='#6E6E73';$track.BackColor='#D2D2D7';[NativeStyle]::Apply($form.Handle,0x00D7D2D2)}'blue'{$form.BackColor='#EDF5FF';$title.ForeColor='#536A86';$detail.ForeColor='#536A86';$track.BackColor='#CADCF2';[NativeStyle]::Apply($form.Handle,0x00F2DCCA)}default{$form.BackColor='#1D1D1F';$title.ForeColor='#A1A1A6';$detail.ForeColor='#A1A1A6';$track.BackColor='#3A3A3C';[NativeStyle]::Apply($form.Handle,0x003C3A3A)}};$form.Opacity=1;$form.Invalidate();Save-Config}
function Set-Compact([bool]$enabled){$script:compact=$enabled;if($enabled){$title.Visible=$false;$track.Visible=$false;$detail.Visible=$false;$form.Size=New-Object Drawing.Size(58,30);$value.SetBounds(2,1,54,27);$value.TextAlign='MiddleCenter';$value.Font=New-Object Drawing.Font('Segoe UI Variable Display',11,[Drawing.FontStyle]::Bold)}else{$form.Size=New-Object Drawing.Size(132,58);$title.Visible=$true;$track.Visible=$true;$detail.Visible=$true;$value.SetBounds(76,3,47,22);$value.TextAlign='MiddleRight';$value.Font=New-Object Drawing.Font('Segoe UI Variable Display',13,[Drawing.FontStyle]::Bold)};$form.Invalidate();Save-Config}
function Update-Usage {$u=Get-LatestUsage;if($u){$n=[double]$u.Remaining;$color=if($n -gt 40){'#30A46C'}elseif($n -gt 20){'#E8930C'}else{'#D92D20'};$value.Text=('{0:N0}%' -f $n);$value.ForeColor=$color;$bar.BackColor=$color;$bar.Width=[int](112*$n/100);$title.Text="CODEX $($u.Plan)";if($u.Reset){$reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$u.Reset).LocalDateTime;$span=$reset-[datetime]::Now;if($span.TotalSeconds -lt 0){$span=[timespan]::Zero};$detail.Text=if($span.Days -gt 0){"$($span.Days)天 $($span.Hours)小时后重置"}elseif($span.Hours -gt 0){"$($span.Hours)小时 $($span.Minutes)分后重置"}else{"$($span.Minutes)分钟后重置"}}}else{$value.Text='--%';$detail.Text='请先在 Codex 发送消息'}}
function Update-Visibility {
    $interaction=$form.ClientRectangle.Contains($form.PointToClient([Windows.Forms.Cursor]::Position)) -or $menu.Visible
    $shouldShow=(-not $script:follow) -or (([CodexWindows]::HasVisibleWindow()) -and ([CodexWindows]::IsForeground())) -or $interaction
    if($shouldShow){
        $script:hideMisses=0;$script:visibleState=$true
        if(-not [NativeStyle]::Visible($form.Handle)){[NativeStyle]::SetVisible($form.Handle,$true)}
        $form.TopMost=$false;$form.TopMost=$true
    }else{
        $script:hideMisses++
        if($script:hideMisses -ge 3 -and [NativeStyle]::Visible($form.Handle)){$script:visibleState=$false;[NativeStyle]::SetVisible($form.Handle,$false)}
    }
}

$menu=New-Object Windows.Forms.ContextMenuStrip
$refresh=$menu.Items.Add('立即刷新');$refresh.Add_Click({Update-Usage})
$compactItem=New-Object Windows.Forms.ToolStripMenuItem('简洁模式');$compactItem.CheckOnClick=$true;$compactItem.Add_Click({Set-Compact $compactItem.Checked});[void]$menu.Items.Add($compactItem)
$themes=New-Object Windows.Forms.ToolStripMenuItem('更换外观');foreach($pair in @(@('light','苹果浅色'),@('dark','深色'),@('blue','淡蓝'))){$item=New-Object Windows.Forms.ToolStripMenuItem($pair[1]);$name=$pair[0];$item.Add_Click([scriptblock]::Create("Set-Theme '$name'"));[void]$themes.DropDownItems.Add($item)};[void]$menu.Items.Add($themes)
$followItem=New-Object Windows.Forms.ToolStripMenuItem('跟随 Codex 显示');$followItem.CheckOnClick=$true;$followItem.Checked=$true;$followItem.Add_Click({$script:follow=$followItem.Checked;Save-Config});[void]$menu.Items.Add($followItem)
$exit=$menu.Items.Add('退出');$exit.Add_Click({$form.Close()});$form.ContextMenuStrip=$menu
$drag={$null=[CodexWindows]::ReleaseCapture();$null=[CodexWindows]::SendMessage($form.Handle,0xA1,[IntPtr]2,[IntPtr]0)};foreach($c in @($form,$title,$value,$detail,$track)){$c.Add_MouseDown($drag)}
$form.Add_DoubleClick({Set-Compact (-not $script:compact)});$value.Add_DoubleClick({Set-Compact (-not $script:compact)})
$form.Add_Move({Save-Config});$form.Add_FormClosed({Save-Config;if($script:MutexCreated){$script:AppMutex.ReleaseMutex()}})
$config=Read-Config;$form.Left=[int]$config.x;$form.Top=[int]$config.y;if($config.theme){$script:theme=$config.theme};if($null -ne $config.followCodex){$script:follow=[bool]$config.followCodex;$followItem.Checked=$script:follow};if($null -ne $config.compact){$script:compact=[bool]$config.compact};Set-Theme $script:theme;Set-Compact $script:compact;$compactItem.Checked=$script:compact;Update-Usage
$usageTimer=New-Object Windows.Forms.Timer;$usageTimer.Interval=30000;$usageTimer.Add_Tick({Update-Usage});$usageTimer.Start()
$visibilityTimer=New-Object Windows.Forms.Timer;$visibilityTimer.Interval=400;$visibilityTimer.Add_Tick({Update-Visibility});$visibilityTimer.Start()
[Windows.Forms.Application]::Run($form)
