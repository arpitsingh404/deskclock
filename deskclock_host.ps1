# DeskClock host - runs all widgets inside ONE powershell process.
# Har widget apni STA thread + runspace pe chalta hai, lekin CLR aur WPF
# assemblies sirf ek baar load hoti hain -> RAM ~1.3 GB se ~350 MB.
#
# Usage: powershell -STA -File deskclock_host.ps1

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ek hi host chalna chahiye
$hostMutex = New-Object System.Threading.Mutex($false, 'DeskClock_Host')
$owned = $false
try { $owned = $hostMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit }

# runspaces ko pata ho ki woh hosted hain -> per-widget mutex skip hoga
$env:DESKCLOCK_HOSTED = '1'

$items = @(
    @{ Type = 'clock';   Script = 'widget.ps1' },
    @{ Type = 'stats';   Script = 'widget.ps1' },
    @{ Type = 'battery'; Script = 'widget.ps1' },
    @{ Type = 'map';     Script = 'widget.ps1' },
    @{ Type = 'tunebtn'; Script = 'widget.ps1' },
    @{ Type = 'weather'; Script = 'extras.ps1' },
    @{ Type = 'net';     Script = 'extras.ps1' }
)

function New-WidgetRunner([hashtable]$item) {
    # runspace ko apna execution policy chahiye warna widget script block ho jaata hai
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass

    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript("& '$root\$($item.Script)' -Type '$($item.Type)'")

    $handle = $ps.BeginInvoke()
    return [pscustomobject]@{
        Type     = $item.Type
        Script   = $item.Script
        PS       = $ps
        RS       = $rs
        Handle   = $handle
        LastTry  = Get-Date
        Restarts = 0
    }
}

$runners = New-Object System.Collections.ArrayList

# Pehle MAP chalao - woh GPS se location resolve karke cache karta hai,
# taaki weather/network bhi wahi city dikhayein.
[void]$runners.Add((New-WidgetRunner @{ Type = 'map'; Script = 'widget.ps1' }))

$locFile = Join-Path $env:APPDATA 'DeskClock_location.json'
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $locFile) { break }
    $mapWin = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'DeskClock-map' }
    if ($mapWin) { break }
    Start-Sleep -Milliseconds 400
}

# Ab baaki widgets
$rest = $items | Where-Object { $_.Type -ne 'map' }
foreach ($i in $rest) { [void]$runners.Add((New-WidgetRunner $i)) }

# Host zinda rahe. Agar koi runspace mar jaye to 15s cooldown ke baad restart.
while ($true) {
    Start-Sleep -Seconds 5
    for ($k = 0; $k -lt $runners.Count; $k++) {
        $r = $runners[$k]
        if (-not $r.Handle) { continue }
        if (-not $r.Handle.IsCompleted) { continue }
        if (((Get-Date) - $r.LastTry).TotalSeconds -lt 15) { continue }

        try { $r.PS.Dispose() } catch { }
        try { $r.RS.Dispose() } catch { }
        Start-Sleep -Milliseconds 500

        $new = New-WidgetRunner @{ Type = $r.Type; Script = $r.Script }
        $new.Restarts = $r.Restarts + 1
        $runners[$k] = $new
    }
}
