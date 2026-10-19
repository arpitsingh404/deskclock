# DeskClock launcher - single-process host ke saath start / stop / status / heal
# Usage: powershell -File deskclock.ps1 -Action start|stop|status|reset|heal|tray|autostart [-State on|off|status]
#
# Saare widgets ek hi powershell process (deskclock_host.ps1) ke andar chalte hain,
# isliye RAM 7 processes ke bajaye 1 process jitni hi lagti hai.

param(
    [ValidateSet('start', 'stop', 'status', 'reset', 'heal', 'tray', 'autostart')]
    [string]$Action = 'start',
    [ValidateSet('on', 'off', 'status')]
    [string]$State = 'on'
)

$ErrorActionPreference = 'Continue'

$sig = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class DW {
    public delegate bool E(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(E cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public static Dictionary<string, uint> FindAll() {
        var map = new Dictionary<string, uint>();
        EnumWindows((h, l) => {
            var sb = new StringBuilder(256); GetWindowText(h, sb, 256);
            string t = sb.ToString();
            if (t.StartsWith("DeskClock-")) {
                uint pid; GetWindowThreadProcessId(h, out pid);
                if (!map.ContainsKey(t)) map[t] = pid;
            }
            return true;
        }, IntPtr.Zero);
        return map;
    }
}
"@
if (-not ('DW' -as [type])) { Add-Type -TypeDefinition $sig }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$hostScript = Join-Path $root 'deskclock_host.ps1'

$items = @(
    @{ Type = 'clock';   Script = 'widget.ps1' },
    @{ Type = 'stats';   Script = 'widget.ps1' },
    @{ Type = 'battery'; Script = 'widget.ps1' },
    @{ Type = 'map';     Script = 'widget.ps1' },
    @{ Type = 'weather'; Script = 'extras.ps1' },
    @{ Type = 'net';     Script = 'extras.ps1' }
)

function Get-HostProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'deskclock_host\.ps1' }
}

function Test-Host { return [bool](Get-HostProcess) }

function Start-Host {
    if (Test-Host) { return $false }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $hostScript
    ) -WindowStyle Hidden | Out-Null
    return $true
}

function Get-AncestorPids {
    # apne aap ko (aur parents ko) kabhi kill mat karo
    $set = @()
    $cur = $PID
    for ($i = 0; $i -lt 6; $i++) {
        $set += $cur
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
        if (-not $p) { break }
        $cur = [int]$p.ParentProcessId
        if ($cur -le 4) { break }
    }
    return $set
}

function Stop-Everything {
    $safe = Get-AncestorPids
    foreach ($h in @(Get-HostProcess)) {
        if ($safe -contains $h.ProcessId) { continue }
        try { Stop-Process -Id $h.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
    # purani per-process widgets bhi clear kar do
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $safe -notcontains $_.ProcessId -and $_.CommandLine -match 'DeskClock\\(widget|extras)\.ps1' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }

    for ($i = 0; $i -lt 50; $i++) {
        if (([DW]::FindAll()).Count -eq 0 -and -not (Test-Host)) { return }
        Start-Sleep -Milliseconds 200
    }
}

function Count-Found([hashtable]$live) {
    $up = 0
    foreach ($i in $items) { if ($live.ContainsKey("DeskClock-$($i.Type)")) { $up++ } }
    return $up
}

function Wait-AllWindows([int]$timeoutSec = 60) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $up = Count-Found ([DW]::FindAll())
        if ($up -ge $items.Count) { return $up }
        Start-Sleep -Milliseconds 500
    }
    return (Count-Found ([DW]::FindAll()))
}

function Report-All {
    $live = [DW]::FindAll()
    foreach ($i in $items) {
        $t = "DeskClock-$($i.Type)"
        if ($live.ContainsKey($t)) { "  {0,-10} UP" -f $i.Type }
        else { "  {0,-10} FAILED" -f $i.Type }
    }
    "  ----"
    "  {0}/{1} widgets up" -f (Count-Found $live), $items.Count
}

function Start-Tray {
    $tray = Join-Path $root 'tray.ps1'
    if (-not (Test-Path $tray)) { return }
    $already = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'DeskClock\\tray\.ps1' }
    if ($already) { return }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $tray
    ) -WindowStyle Hidden | Out-Null
}

switch ($Action) {
    'start' {
        "DeskClock start"
        if (Start-Host) { "  host started (single process)" }
        else { "  host already running" }
        "  waiting for widgets..."
        Wait-AllWindows 60 | Out-Null
        Report-All
        Start-Tray
    }
    'heal' {
        "DeskClock heal"
        if (Start-Host) { "  host restarted" }
        else { "  host already running - waiting for any missing widget" }
        Wait-AllWindows 60 | Out-Null
        Report-All
        Start-Tray
    }
    'reset' {
        "DeskClock reset"
        Stop-Everything
        Get-ChildItem (Join-Path $env:APPDATA 'DeskClock_*.json') -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'DeskClock_location.json' } |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 500
        Start-Host | Out-Null
        "  waiting for widgets..."
        Wait-AllWindows 60 | Out-Null
        Report-All
        Start-Tray
    }
    'stop' {
        Stop-Everything
        "  all widgets stopped"
    }
    'status' {
        $hp = @(Get-HostProcess)
        if ($hp.Count -gt 0) { "  {0,-10} RUNNING (pid {1})" -f 'host', $hp[0].ProcessId }
        else { "  {0,-10} stopped" -f 'host' }

        $live = [DW]::FindAll()
        foreach ($i in $items) {
            $t = "DeskClock-$($i.Type)"
            if ($live.ContainsKey($t)) { "  {0,-10} RUNNING (pid {1})" -f $i.Type, $live[$t] }
            else { "  {0,-10} stopped" -f $i.Type }
        }
        $tray = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'DeskClock\\tray\.ps1' }
        if ($tray) { "  {0,-10} RUNNING (pid {1})" -f 'tray', @($tray)[0].ProcessId }
        else { "  {0,-10} stopped" -f 'tray' }
    }
    'tray' {
        Start-Tray
        "  tray icon running"
    }
    'autostart' {
        $lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'DeskClock Widgets.lnk'
        switch ($State) {
            'on' {
                $shell = New-Object -ComObject WScript.Shell
                $lnk = $shell.CreateShortcut($lnkPath)
                $lnk.TargetPath = 'powershell.exe'
                $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $root 'deskclock.ps1') + '" -Action start'
                $lnk.WorkingDirectory = $root
                $lnk.WindowStyle = 7
                $lnk.Description = 'Start DeskClock desktop widgets'
                $lnk.Save()
                "  autostart ON"
            }
            'off' {
                Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue
                "  autostart OFF"
            }
            'status' {
                if (Test-Path $lnkPath) { "  autostart ON" } else { "  autostart OFF" }
            }
        }
    }
}
