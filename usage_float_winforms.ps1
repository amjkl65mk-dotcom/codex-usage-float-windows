Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$script:MutexCreated = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, 'Local\CodexUsageFloat', [ref]$script:MutexCreated)
if (-not $script:MutexCreated) { exit 0 }

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class UsageForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { var p=base.CreateParams; p.ExStyle|=0x08000000; return p; } }
    protected override void OnResize(EventArgs e) { base.OnResize(e); using(var p=new GraphicsPath()){int r=Math.Min(14,Math.Min(Width,Height)/2);p.AddArc(0,0,r*2,r*2,180,90);p.AddArc(Width-r*2-1,0,r*2,r*2,270,90);p.AddArc(Width-r*2-1,Height-r*2-1,r*2,r*2,0,90);p.AddArc(0,Height-r*2-1,r*2,r*2,90,90);p.CloseFigure();Region=new Region(p);}}
    protected override void OnPaint(PaintEventArgs e) { base.OnPaint(e); e.Graphics.SmoothingMode=SmoothingMode.AntiAlias; using(var p=new Pen(Color.FromArgb(40,90,90,90))){e.Graphics.DrawRectangle(p,0,0,Width-1,Height-1);}}
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
$script:theme = 'light'; $script:follow = $true; $script:compact = $false; $script:visibleState = $true

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
$form.FormBorderStyle='None';$form.ShowInTaskbar=$false;$form.TopMost=$true;$form.Size=New-Object Drawing.Size(148,68);$form.StartPosition='Manual';$form.Padding=New-Object Windows.Forms.Padding(1)
$title=New-Object Windows.Forms.Label;$title.SetBounds(10,7,70,17);$title.Font=New-Object Drawing.Font('Segoe UI',7.5,[Drawing.FontStyle]::Bold);$title.Text='CODEX'
$value=New-Object Windows.Forms.Label;$value.SetBounds(75,3,63,25);$value.TextAlign='MiddleRight';$value.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold);$value.Text='--%'
$track=New-Object Windows.Forms.Panel;$track.SetBounds(11,31,126,4)
$bar=New-Object Windows.Forms.Panel;$bar.SetBounds(0,0,0,4);$track.Controls.Add($bar)
$detail=New-Object Windows.Forms.Label;$detail.SetBounds(10,40,130,20);$detail.Font=New-Object Drawing.Font('Segoe UI',7.5);$detail.Text='Reading...'
$form.Controls.AddRange(@($title,$value,$track,$detail))

function Set-Theme($name){$script:theme=$name;switch($name){'light'{$form.BackColor='#FAFAFA';$title.ForeColor='#86868B';$detail.ForeColor='#86868B';$track.BackColor='#E5E5EA'}'blue'{$form.BackColor='#EAF3FF';$title.ForeColor='#56708F';$detail.ForeColor='#56708F';$track.BackColor='#D1E5FF'}'glass'{$form.BackColor='#F5F5F7';$form.Opacity=.86;$title.ForeColor='#6E6E73';$detail.ForeColor='#6E6E73';$track.BackColor='#D2D2D7'}default{$form.BackColor='#1D1D1F';$form.Opacity=.96;$title.ForeColor='#A1A1A6';$detail.ForeColor='#A1A1A6';$track.BackColor='#3A3A3C'}};if($name -ne 'glass'){$form.Opacity=1};$form.Invalidate();Save-Config}
function Set-Compact([bool]$enabled){$script:compact=$enabled;if($enabled){$title.Visible=$false;$track.Visible=$false;$detail.Visible=$false;$form.Size=New-Object Drawing.Size(56,30);$value.SetBounds(3,1,50,27);$value.TextAlign='MiddleCenter';$value.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)}else{$form.Size=New-Object Drawing.Size(148,68);$title.Visible=$true;$track.Visible=$true;$detail.Visible=$true;$value.SetBounds(75,3,63,25);$value.TextAlign='MiddleRight';$value.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold)};$form.Invalidate();Save-Config}
function Update-Usage {$u=Get-LatestUsage;if($u){$n=[double]$u.Remaining;$color=if($n -gt 40){'#34D399'}elseif($n -gt 20){'#FBBF24'}else{'#F87171'};$value.Text=('{0:N0}%' -f $n);$value.ForeColor=$color;$bar.BackColor=$color;$bar.Width=[int](126*$n/100);$title.Text="CODEX $($u.Plan)";if($u.Reset){$reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$u.Reset).LocalDateTime;$span=$reset-[datetime]::Now;if($span.TotalSeconds -lt 0){$span=[timespan]::Zero};$detail.Text=if($span.Days -gt 0){"$($span.Days)d $($span.Hours)h until reset"}elseif($span.Hours -gt 0){"$($span.Hours)h $($span.Minutes)m until reset"}else{"$($span.Minutes)m until reset"}}}else{$value.Text='--%';$detail.Text='Send a Codex message first'}}
function Update-Visibility {$interaction=$form.ClientRectangle.Contains($form.PointToClient([Windows.Forms.Cursor]::Position)) -or $menu.Visible;$show=(-not $script:follow) -or (([CodexWindows]::HasVisibleWindow()) -and ([CodexWindows]::IsForeground())) -or $interaction;if($show -ne $script:visibleState){$script:visibleState=$show;if($show){$form.Opacity=if($script:theme -eq 'glass'){.78}else{1};$form.Enabled=$true;$form.TopMost=$false;$form.TopMost=$true}else{$form.Opacity=0;$form.Enabled=$false}}}

$menu=New-Object Windows.Forms.ContextMenuStrip
$refresh=$menu.Items.Add('立即刷新');$refresh.Add_Click({Update-Usage})
$compactItem=New-Object Windows.Forms.ToolStripMenuItem('简洁模式');$compactItem.CheckOnClick=$true;$compactItem.Add_Click({Set-Compact $compactItem.Checked});[void]$menu.Items.Add($compactItem)
$themes=New-Object Windows.Forms.ToolStripMenuItem('更换外观');foreach($pair in @(@('light','苹果浅色'),@('dark','深色'),@('blue','淡蓝'),@('glass','半透明'))){$item=New-Object Windows.Forms.ToolStripMenuItem($pair[1]);$name=$pair[0];$item.Add_Click([scriptblock]::Create("Set-Theme '$name'"));[void]$themes.DropDownItems.Add($item)};[void]$menu.Items.Add($themes)
$followItem=New-Object Windows.Forms.ToolStripMenuItem('跟随 Codex 显示');$followItem.CheckOnClick=$true;$followItem.Checked=$true;$followItem.Add_Click({$script:follow=$followItem.Checked;Save-Config});[void]$menu.Items.Add($followItem)
$exit=$menu.Items.Add('退出');$exit.Add_Click({$form.Close()});$form.ContextMenuStrip=$menu
$drag={$null=[CodexWindows]::ReleaseCapture();$null=[CodexWindows]::SendMessage($form.Handle,0xA1,[IntPtr]2,[IntPtr]0)};foreach($c in @($form,$title,$value,$detail,$track)){$c.Add_MouseDown($drag)}
$form.Add_DoubleClick({Set-Compact (-not $script:compact)});$value.Add_DoubleClick({Set-Compact (-not $script:compact)})
$form.Add_Move({Save-Config});$form.Add_FormClosed({Save-Config;if($script:MutexCreated){$script:AppMutex.ReleaseMutex()}})
$config=Read-Config;$form.Left=[int]$config.x;$form.Top=[int]$config.y;if($config.theme){$script:theme=$config.theme};if($null -ne $config.followCodex){$script:follow=[bool]$config.followCodex;$followItem.Checked=$script:follow};if($null -ne $config.compact){$script:compact=[bool]$config.compact};Set-Theme $script:theme;Set-Compact $script:compact;$compactItem.Checked=$script:compact;Update-Usage
$usageTimer=New-Object Windows.Forms.Timer;$usageTimer.Interval=30000;$usageTimer.Add_Tick({Update-Usage});$usageTimer.Start()
$visibilityTimer=New-Object Windows.Forms.Timer;$visibilityTimer.Interval=400;$visibilityTimer.Add_Tick({Update-Visibility});$visibilityTimer.Start()
[Windows.Forms.Application]::Run($form)
