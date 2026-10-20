# DeskClock tray controller
# System-tray icon se saare widgets show / hide / restart karne ke liye.
# Usage: powershell -File tray.ps1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$sig = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class TRW {
    public delegate bool E(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(E cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);

    static List<IntPtr> All() {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => {
            var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
            if (sb.ToString().StartsWith("DeskClock-")) list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list;
    }
    public static int Count() { return All().Count; }
    public static List<string> Titles() {
        var list = new List<string>();
        EnumWindows((h, l) => {
            var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
            string t = sb.ToString();
            if (t.StartsWith("DeskClock-")) list.Add(t);
            return true;
        }, IntPtr.Zero);
        return list;
    }
    public static int VisibleCount() {
        int n = 0;
        foreach (var h in All()) if (IsWindowVisible(h)) n++;
        return n;
    }
    public static void ShowAll() {
        foreach (var h in All()) {
            ShowWindow(h, 9);                                       // SW_RESTORE
            SetWindowPos(h, (IntPtr)1, 0, 0, 0, 0, 0x0001 | 0x0002); // HWND_BOTTOM, no move/resize
        }
    }
    public static void HideAll() {
        foreach (var h in All()) ShowWindow(h, 0);                   // SW_HIDE
    }
}
"@
if (-not ('TRW' -as [type])) { Add-Type -TypeDefinition $sig }

# ---------------- single instance ----------------
$mutex = New-Object System.Threading.Mutex($false, 'DeskClockTrayMutex')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch { $owned = $false }
if (-not $owned) { exit }

# ---------------- helpers ----------------
function Get-StartupShortcut {
    $startup = [Environment]::GetFolderPath('Startup')
    Join-Path $startup 'DeskClock Widgets.lnk'
}
function Test-Autostart { Test-Path (Get-StartupShortcut) }

function Invoke-Launcher([string]$action, [string]$state = '') {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                 '-File', (Join-Path $root 'deskclock.ps1'), '-Action', $action)
    if ($state) { $argList += @('-State', $state) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden
}

# ---------------- host watchdog ----------------
# Saare widgets ek hi host process mein chalte hain. Host mar jaye to 15s mein wapas.
# Agar host zinda hai par windows gayab/hidden hain, to ~45s baad host restart ho jata hai.
$script:lastHostTry = [datetime]::MinValue
$script:badTicks = 0
$script:userHidden = $false

function Repair-Host {
    try {
        $hostProc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'deskclock_host\.ps1' }

        if (-not $hostProc) {
            $now = Get-Date
            if (($now - $script:lastHostTry).TotalSeconds -lt 20) { return }
            $script:lastHostTry = $now
            $hp = Join-Path $root 'deskclock_host.ps1'
            if (Test-Path $hp) {
                Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                    '-File', $hp
                ) -WindowStyle Hidden | Out-Null
            }
            $script:badTicks = 0
            return
        }

        # user ne khud hide kiya hai to visibility check mat karo
        if ($script:userHidden) { $script:badTicks = 0; return }

        $titles  = [TRW]::Titles()
        $visible = [TRW]::VisibleCount()
        if ($titles.Count -lt 7 -or $visible -lt 7) {
            $script:badTicks++
            if ($script:badTicks -ge 3) {
                $script:badTicks = 0
                foreach ($hp2 in @($hostProc)) {
                    Stop-Process -Id $hp2.ProcessId -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Milliseconds 800
                $script:lastHostTry = [datetime]::MinValue
                Repair-Host
            }
        } else {
            $script:badTicks = 0
        }
    } catch { }
}

$script:watchdog = New-Object System.Windows.Forms.Timer
$script:watchdog.Interval = 15000
$script:watchdog.Add_Tick({ Repair-Host })
$script:watchdog.Start()

# ---------------- tray icon (custom drawn clock) ----------------
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = New-Object System.Drawing.RectangleF(1.0, 1.0, 30.0, 30.0)
    $d = 9.0
    [void]$path.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    [void]$path.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    [void]$path.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    [void]$path.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $c1 = [System.Drawing.Color]::FromArgb(255, 24, 24, 36)
    $c2 = [System.Drawing.Color]::FromArgb(255, 9, 9, 15)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, 32, 32)), $c1, $c2, 90)
    $g.FillPath($bg, $path)

    $pen1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 167, 139, 250), 2.6)
    $pen1.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen1.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen1, 16.0, 16.0, 16.0, 8.5)

    $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 110, 231, 183), 2.0)
    $pen2.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen2.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen2, 16.0, 16.0, 22.5, 19.5)

    $dot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 248, 250, 252))
    $g.FillEllipse($dot, 14.6, 14.6, 2.8, 2.8)

    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
    $bmp.Dispose()
    return $icon
}

# ---------------- menu ----------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.ShowImageMargin = $false

$miShow = $menu.Items.Add('Show all widgets')
$miShow.Add_Click({ $script:userHidden = $false; [TRW]::ShowAll() })

$miHide = $menu.Items.Add('Hide all widgets')
$miHide.Add_Click({ $script:userHidden = $true; [TRW]::HideAll() })

$miReset = $menu.Items.Add('Restart + reset layout')
$miReset.Add_Click({ Invoke-Launcher 'reset' })

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miTune = $menu.Items.Add('PC Health & Cleanup')
$miTune.Add_Click({
    $wt = Join-Path $root 'wintune.ps1'
    if (Test-Path $wt) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $wt
        ) -WindowStyle Hidden
    }
})

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miWatch = $menu.Items.Add('Auto-repair widgets')
$miWatch.CheckOnClick = $true
$miWatch.Checked = $true
$miWatch.Add_Click({
    if ($miWatch.Checked) { $script:watchdog.Start() } else { $script:watchdog.Stop() }
})

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miStart = $menu.Items.Add('Start with Windows')
$miStart.CheckOnClick = $true
$miStart.Add_Click({
    $wantOn = $miStart.Checked
    # autostart action is fast -> run it in-process so the menu state stays truthful
    try {
        & (Join-Path $root 'deskclock.ps1') -Action autostart -State $(if ($wantOn) { 'on' } else { 'off' }) | Out-Null
    } catch {
        $miStart.Checked = -not $wantOn
    }
})
$menu.Add_Opening({ $miStart.Checked = Test-Autostart })

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$miExit = $menu.Items.Add('Exit tray icon')
$miExit.Add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

# ---------------- notify icon ----------------
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = New-TrayIcon
$notify.Text = 'DeskClock widgets'
$notify.Visible = $true
$notify.ContextMenuStrip = $menu

$notify.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $menu.Show([System.Windows.Forms.Cursor]::Position)
    }
})

$notify.Add_BalloonTipClicked({ [TRW]::ShowAll() })

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run()
