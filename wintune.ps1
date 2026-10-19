# DeskClock WinTune - PC health & cleanup panel
# Tray menu se khulta hai: "PC Health & Cleanup"
# Usage: powershell -File wintune.ps1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# single instance
$mtx = New-Object System.Threading.Mutex($false, 'DeskClock_WinTune')
$owned = $false
try { $owned = $mtx.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { exit }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="True" Topmost="False"
        Width="940" Height="660" WindowStartupLocation="CenterScreen"
        Title="DeskClock-WinTune">
  <Window.Resources>
    <Style TargetType="GridViewColumnHeader">
      <Setter Property="Background" Value="#10FFFFFF"/>
      <Setter Property="Foreground" Value="#9A9AB0"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="ListViewItem">
      <Setter Property="Foreground" Value="#D8D8E4"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="FontSize" Value="11"/>
    </Style>
    <Style x:Key="NavBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#A8A8BC"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="14,11"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#10FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ActBtn" TargetType="Button">
      <Setter Property="Background" Value="#2A8B5CF6"/>
      <Setter Property="Foreground" Value="#F2F2F8"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#3D8B5CF6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#0CFFFFFF"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="14"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
    </Style>
  </Window.Resources>

  <Border Background="#F212121B" CornerRadius="16" BorderThickness="1" BorderBrush="#26FFFFFF">
    <Border.Effect><DropShadowEffect BlurRadius="34" ShadowDepth="0" Opacity="0.6" Color="#000000"/></Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="54"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="26"/>
      </Grid.RowDefinitions>

      <!-- title bar -->
      <Grid x:Name="header" Grid.Row="0" Margin="22,0,14,0" Background="Transparent">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="WinTune" Foreground="#F2F2F8" FontSize="15" FontWeight="Bold"/>
          <Border Background="#1F8B5CF6" CornerRadius="6" Padding="7,2" Margin="10,1,0,0" VerticalAlignment="Center">
            <TextBlock Text="PC HEALTH" Foreground="#C4B5FD" FontSize="9" FontWeight="Bold"/>
          </Border>
        </StackPanel>
        <Button x:Name="btnClose" Content="&#x2715;" HorizontalAlignment="Right" VerticalAlignment="Center"
                Width="34" Height="28" Background="Transparent" Foreground="#9A9AB0" BorderThickness="0"
                FontSize="12" Cursor="Hand"/>
      </Grid>

      <!-- body -->
      <Grid Grid.Row="1" Margin="14,0,14,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="172"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- nav -->
        <StackPanel Grid.Column="0" Margin="0,0,10,10">
          <Button x:Name="navDash"  Content="Dashboard" Style="{StaticResource NavBtn}"/>
          <Button x:Name="navClean" Content="Cleanup"   Style="{StaticResource NavBtn}"/>
          <Button x:Name="navStart" Content="Startup"   Style="{StaticResource NavBtn}"/>
          <Button x:Name="navBatt"  Content="Battery"   Style="{StaticResource NavBtn}"/>
        </StackPanel>

        <!-- pages -->
        <Grid Grid.Column="1" Margin="0,0,0,4">

          <!-- DASHBOARD -->
          <Grid x:Name="pageDash">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Orientation="Horizontal">
              <Border Style="{StaticResource Card}" Width="200">
                <StackPanel>
                  <TextBlock Text="CPU" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold"/>
                  <TextBlock x:Name="dashCpu" Text="--" Foreground="#C4B5FD" FontSize="30" FontFamily="Segoe UI Light"/>
                  <TextBlock x:Name="dashCpuSub" Text="" Foreground="#8A8A9A" FontSize="10"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="200">
                <StackPanel>
                  <TextBlock Text="RAM" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold"/>
                  <TextBlock x:Name="dashRam" Text="--" Foreground="#6EE7B7" FontSize="30" FontFamily="Segoe UI Light"/>
                  <TextBlock x:Name="dashRamSub" Text="" Foreground="#8A8A9A" FontSize="10"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="200">
                <StackPanel>
                  <TextBlock Text="C: DRIVE" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold"/>
                  <TextBlock x:Name="dashDisk" Text="--" Foreground="#FBBF24" FontSize="30" FontFamily="Segoe UI Light"/>
                  <TextBlock x:Name="dashDiskSub" Text="" Foreground="#8A8A9A" FontSize="10"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Width="150">
                <StackPanel>
                  <TextBlock Text="UPTIME" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold"/>
                  <TextBlock x:Name="dashUp" Text="--" Foreground="#F2F2F8" FontSize="22" FontFamily="Segoe UI Light" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
            </StackPanel>

            <TextBlock Grid.Row="1" Text="TOP PROCESSES" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold" Margin="2,18,0,8"/>

            <ListView x:Name="procList" Grid.Row="2" Background="Transparent" BorderThickness="0" Foreground="#D8D8E4">
              <ListView.View>
                <GridView>
                  <GridViewColumn Header="Process" Width="260" DisplayMemberBinding="{Binding Name}"/>
                  <GridViewColumn Header="RAM" Width="120" DisplayMemberBinding="{Binding Mem}"/>
                  <GridViewColumn Header="PID" Width="100" DisplayMemberBinding="{Binding Pid}"/>
                </GridView>
              </ListView.View>
            </ListView>
          </Grid>

          <!-- CLEANUP -->
          <Grid x:Name="pageClean" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,0,10">
              <Button x:Name="btnScan" Content="Scan" Style="{StaticResource ActBtn}"/>
              <Button x:Name="btnClean" Content="Clean selected" Style="{StaticResource ActBtn}" Margin="10,0,0,0" Background="#2A22C55E"/>
              <TextBlock x:Name="cleanStatus" Text="" Foreground="#8A8A9A" FontSize="11" VerticalAlignment="Center" Margin="14,0,0,0"/>
            </StackPanel>

            <ListView x:Name="cleanList" Grid.Row="1" Background="Transparent" BorderThickness="0" Foreground="#D8D8E4">
              <ListView.View>
                <GridView>
                  <GridViewColumn Width="34">
                    <GridViewColumn.CellTemplate>
                      <DataTemplate><CheckBox IsChecked="{Binding Checked}" HorizontalAlignment="Center"/></DataTemplate>
                    </GridViewColumn.CellTemplate>
                  </GridViewColumn>
                  <GridViewColumn Header="Target" Width="220" DisplayMemberBinding="{Binding Name}"/>
                  <GridViewColumn Header="Size" Width="110" DisplayMemberBinding="{Binding SizeText}"/>
                  <GridViewColumn Header="Path" Width="330" DisplayMemberBinding="{Binding Path}"/>
                </GridView>
              </ListView.View>
            </ListView>

            <TextBlock Grid.Row="2" x:Name="cleanHint" Foreground="#6E6E80" FontSize="10" Margin="2,10,0,0"
                       Text="Sirf temp/cache files delete hoti hain. Locked files skip ho jaati hain. Recycle Bin alag se clear hota hai."/>
          </Grid>

          <!-- STARTUP -->
          <Grid x:Name="pageStart" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,0,10">
              <Button x:Name="btnStartRefresh" Content="Refresh" Style="{StaticResource ActBtn}"/>
              <Button x:Name="btnDisable" Content="Disable selected (HKCU)" Style="{StaticResource ActBtn}" Margin="10,0,0,0" Background="#2AEF4444"/>
              <TextBlock x:Name="startStatus" Text="" Foreground="#8A8A9A" FontSize="11" VerticalAlignment="Center" Margin="14,0,0,0"/>
            </StackPanel>
            <ListView x:Name="startList" Grid.Row="1" Background="Transparent" BorderThickness="0" Foreground="#D8D8E4">
              <ListView.View>
                <GridView>
                  <GridViewColumn Header="Name" Width="200" DisplayMemberBinding="{Binding Name}"/>
                  <GridViewColumn Header="Scope" Width="90" DisplayMemberBinding="{Binding Scope}"/>
                  <GridViewColumn Header="Command" Width="420" DisplayMemberBinding="{Binding Command}"/>
                </GridView>
              </ListView.View>
            </ListView>
          </Grid>

          <!-- BATTERY -->
          <Grid x:Name="pageBatt" Visibility="Collapsed">
            <StackPanel Margin="2,0,0,0">
              <Border Style="{StaticResource Card}" HorizontalAlignment="Left" Width="330">
                <StackPanel>
                  <TextBlock Text="BATTERY" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold"/>
                  <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                    <TextBlock x:Name="battPct" Text="--" Foreground="#F2F2F8" FontSize="42" FontFamily="Segoe UI Light"/>
                    <TextBlock Text="%" Foreground="#9A9AB0" FontSize="18" VerticalAlignment="Top" Margin="2,8,0,0"/>
                    <TextBlock x:Name="battState" Text="" Foreground="#FBBF24" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="16,0,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="battDetail" Text="" Foreground="#B8B8C8" FontSize="11" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>

              <Border Style="{StaticResource Card}" HorizontalAlignment="Left" Width="560" Margin="0,12,0,0">
                <StackPanel>
                  <TextBlock Text="BATTERY HEALTH" Foreground="#9A9AB0" FontSize="10" FontWeight="Bold" Margin="0,0,0,8"/>
                  <TextBlock x:Name="battHealth" Text="--" Foreground="#D8D8E4" FontSize="12"/>
                  <TextBlock x:Name="battCap" Text="" Foreground="#8A8A9A" FontSize="11" Margin="0,4,0,0"/>
                  <TextBlock x:Name="battCycles" Text="" Foreground="#8A8A9A" FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>

        </Grid>
      </Grid>

      <TextBlock Grid.Row="2" x:Name="footTxt" Text="DeskClock WinTune \u00b7 real data only"
                 Foreground="#5E5E70" FontSize="10" Margin="22,0,0,8"/>
    </Grid>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

# ---------------------------------------------------------------- helpers
function Fmt-Size([double]$b) {
    if ($b -ge 1GB) { return "{0:N2} GB" -f ($b / 1GB) }
    if ($b -ge 1MB) { return "{0:N1} MB" -f ($b / 1MB) }
    if ($b -ge 1KB) { return "{0:N0} KB" -f ($b / 1KB) }
    return "{0:N0} B" -f $b
}

function Get-FolderSize([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    try {
        return [double](Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
    } catch { return 0 }
}

$window.FindName('header').Add_MouseLeftButtonDown({ $window.DragMove() })
$window.FindName('btnClose').Add_Click({ $window.Close() })

# ---------------------------------------------------------------- navigation
$pages = @{
    dash  = $window.FindName('pageDash')
    clean = $window.FindName('pageClean')
    start = $window.FindName('pageStart')
    batt  = $window.FindName('pageBatt')
}
$navs = @{
    dash  = $window.FindName('navDash')
    clean = $window.FindName('navClean')
    start = $window.FindName('navStart')
    batt  = $window.FindName('navBatt')
}

function Show-Page([string]$name) {
    foreach ($k in $pages.Keys) {
        if ($k -eq $name) { $pages[$k].Visibility = 'Visible' } else { $pages[$k].Visibility = 'Collapsed' }
        if ($k -eq $name) {
            $navs[$k].Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1F8B5CF6'))
            $navs[$k].Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F2F2F8'))
        } else {
            $navs[$k].Background = [System.Windows.Media.Brushes]::Transparent
            $navs[$k].Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#A8A8BC'))
        }
    }
}

$navs.dash.Add_Click({ Show-Page 'dash' })
$navs.clean.Add_Click({ Show-Page 'clean' })
$navs.start.Add_Click({ Show-Page 'start' })
$navs.batt.Add_Click({ Show-Page 'batt' })

# ---------------------------------------------------------------- dashboard
function Update-Dashboard {
    try {
        $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        $cpu = if ($p) { [double]$p.PercentProcessorTime } else { 0 }
        $window.FindName('dashCpu').Text = "{0:N0}%" -f $cpu
        $window.FindName('dashCpuSub').Text = "$env:NUMBER_OF_PROCESSORS cores"

        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $total = [double]$os.TotalVisibleMemorySize
        $free = [double]$os.FreePhysicalMemory
        $ramPct = if ($total -gt 0) { (($total - $free) / $total) * 100 } else { 0 }
        $window.FindName('dashRam').Text = "{0:N0}%" -f $ramPct
        $window.FindName('dashRamSub').Text = ("{0:N0} / {1:N0} GB used" -f (($total - $free) / 1MB), ($total / 1MB))

        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($d) {
            $pct = (($d.Size - $d.FreeSpace) / $d.Size) * 100
            $window.FindName('dashDisk').Text = "{0:N0}%" -f $pct
            $window.FindName('dashDiskSub').Text = ("{0:N1} GB free" -f ($d.FreeSpace / 1GB))
        }

        $up = (Get-Date) - $os.LastBootUpTime
        $window.FindName('dashUp').Text = ("{0}d {1}h" -f $up.Days, $up.Hours)

        $rows = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending | Select-Object -First 12 |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.ProcessName
                    Mem  = Fmt-Size $_.WorkingSet64
                    Pid  = $_.Id
                }
            }
        $window.FindName('procList').ItemsSource = $rows
    } catch { }
}

# ---------------------------------------------------------------- cleanup
$script:cleanTargets = @(
    @{ Name = 'User Temp';        Path = $env:TEMP;                                                          Kind = 'contents' },
    @{ Name = 'Windows Temp';     Path = 'C:\Windows\Temp';                                                  Kind = 'contents' },
    @{ Name = 'Windows Update';   Path = 'C:\Windows\SoftwareDistribution\Download';                         Kind = 'contents' },
    @{ Name = 'Chrome Cache';     Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache";          Kind = 'contents' },
    @{ Name = 'Brave Cache';      Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"; Kind = 'contents' },
    @{ Name = 'Edge Cache';       Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache";         Kind = 'contents' },
    @{ Name = 'npm cache';        Path = "$env:LOCALAPPDATA\npm-cache";                                      Kind = 'contents' },
    @{ Name = 'Recycle Bin';      Path = 'Recycle Bin';                                                      Kind = 'recycle' }
)

$script:scanJob = $null
$script:scanRows = @()

function Start-CleanupScan {
    $window.FindName('cleanStatus').Text = 'Scanning...'
    $window.FindName('btnScan').IsEnabled = $false
    $script:scanJob = Start-Job -ScriptBlock {
        param($targets)
        $res = @()
        foreach ($t in $targets) {
            $size = 0
            try {
                if ($t.Kind -eq 'recycle') {
                    $shell = New-Object -ComObject Shell.Application
                    $rb = $shell.Namespace(10)
                    foreach ($i in $rb.Items()) { $size += $i.Size }
                } elseif (Test-Path $t.Path) {
                    $size = [double](Get-ChildItem $t.Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                        Measure-Object Length -Sum).Sum
                }
            } catch { }
            $res += [pscustomobject]@{ Name = $t.Name; Path = $t.Path; Kind = $t.Kind; Bytes = $size }
        }
        return $res
    } -ArgumentList (,$script:cleanTargets)
}

$script:scanTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:scanTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$script:scanTimer.Add_Tick({
    if (-not $script:scanJob) { return }
    if ($script:scanJob.State -ne 'Completed') { return }
    $script:scanTimer.Stop()
    $res = Receive-Job $script:scanJob -ErrorAction SilentlyContinue
    Remove-Job $script:scanJob -Force -ErrorAction SilentlyContinue
    $script:scanJob = $null

    $rows = @()
    foreach ($r in $res) {
        $rows += [pscustomobject]@{
            Checked  = ($r.Bytes -gt 0)
            Name     = $r.Name
            SizeText = Fmt-Size $r.Bytes
            Path     = $r.Path
            Bytes    = $r.Bytes
            Kind     = $r.Kind
        }
    }
    $script:scanRows = $rows
    $window.FindName('cleanList').ItemsSource = $rows
    $total = ($rows | Measure-Object Bytes -Sum).Sum
    $window.FindName('cleanStatus').Text = ("Done - {0} reclaimable" -f (Fmt-Size $total))
    $window.FindName('btnScan').IsEnabled = $true
})

$window.FindName('btnScan').Add_Click({ Start-CleanupScan; $script:scanTimer.Start() })

$window.FindName('btnClean').Add_Click({
    $sel = @($script:scanRows | Where-Object { $_.Checked -and $_.Bytes -gt 0 })
    if ($sel.Count -eq 0) { $window.FindName('cleanStatus').Text = 'Kuch select nahi hai'; return }

    $window.FindName('cleanStatus').Text = 'Cleaning...'
    $freed = 0.0
    foreach ($r in $sel) {
        try {
            if ($r.Kind -eq 'recycle') {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                $freed += $r.Bytes
            } else {
                Get-ChildItem -LiteralPath $r.Path -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $freed += $r.Bytes
            }
        } catch { }
    }
    $window.FindName('cleanStatus').Text = ("Freed ~{0}" -f (Fmt-Size $freed))
    Start-CleanupScan
    $script:scanTimer.Start()
})

# ---------------------------------------------------------------- startup
function Load-Startup {
    $rows = @()
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $props = (Get-ItemProperty $runKey -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' }
    foreach ($p in $props) {
        $rows += [pscustomobject]@{ Name = $p.Name; Scope = 'HKCU'; Command = [string]$p.Value }
    }
    $startupDir = [Environment]::GetFolderPath('Startup')
    Get-ChildItem $startupDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rows += [pscustomobject]@{ Name = $_.BaseName; Scope = 'Startup'; Command = $_.Name }
    }
    $window.FindName('startList').ItemsSource = $rows
    $window.FindName('startStatus').Text = ("{0} entries" -f $rows.Count)
}

$window.FindName('btnStartRefresh').Add_Click({ Load-Startup })

$window.FindName('btnDisable').Add_Click({
    $sel = $window.FindName('startList').SelectedItem
    if (-not $sel) { $window.FindName('startStatus').Text = 'Select an entry first'; return }
    if ($sel.Scope -ne 'HKCU') { $window.FindName('startStatus').Text = 'Sirf HKCU entries disable ho sakti hain'; return }
    $backup = Join-Path $env:APPDATA 'DeskClock_startup_backup.json'
    try {
        $cur = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run').PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { @{ Name = $_.Name; Value = [string]$_.Value } }
        @{ saved = (Get-Date).ToString('o'); entries = $cur } | ConvertTo-Json -Depth 5 |
            Set-Content $backup -Encoding UTF8
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $sel.Name -ErrorAction Stop
        $window.FindName('startStatus').Text = ("Disabled: {0} (backup: {1})" -f $sel.Name, $backup)
        Load-Startup
    } catch {
        $window.FindName('startStatus').Text = 'Error: ' + $_.Exception.Message
    }
})

# ---------------------------------------------------------------- battery
function Update-Battery {
    try {
        $wb  = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        $wbs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
        $wbf = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
        $static = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1
        $cyc = Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1

        $pct = if ($wb) { [int]$wb.EstimatedChargeRemaining } else { 0 }
        $window.FindName('battPct').Text = "$pct"

        if ($wbs) {
            $charging = [bool]$wbs.Charging
            $online = [bool]$wbs.PowerOnline
            $rate = [double]$wbs.ChargeRate
            $drate = [double]$wbs.DischargeRate
            $remain = [double]$wbs.RemainingCapacity
            $full = if ($wbf) { [double]$wbf.FullChargedCapacity } else { 0 }

            if ($charging) {
                $window.FindName('battState').Text = 'CHARGING'
                $w = $rate / 1000
                if ($full -gt $remain -and $rate -gt 0) {
                    $mins = [int](($full - $remain) / $rate * 60)
                    $window.FindName('battDetail').Text = ("{0:N1} W  |  {1} min to full" -f $w, $mins)
                } else {
                    $window.FindName('battDetail').Text = ("{0:N1} W  |  charging" -f $w)
                }
            } elseif (-not $online) {
                $window.FindName('battState').Text = 'ON BATTERY'
                $w = $drate / 1000
                if ($drate -gt 0 -and $remain -gt 0) {
                    $mins = [int]($remain / $drate * 60)
                    $window.FindName('battDetail').Text = ("{0:N1} W  |  {1} min left" -f $w, $mins)
                } else {
                    $window.FindName('battDetail').Text = 'Discharging'
                }
            } else {
                $window.FindName('battState').Text = if ($pct -ge 99) { 'FULL' } else { 'PLUGGED IN' }
                $window.FindName('battDetail').Text = 'AC connected'
            }

            if ($static -and $full -gt 0 -and [double]$static.DesignedCapacity -gt 0) {
                $h = [int][Math]::Round($full / [double]$static.DesignedCapacity * 100)
                $window.FindName('battHealth').Text = ("Health: {0}%" -f $h)
                $window.FindName('battCap').Text = ("Full charge: {0:N1} Wh   |   Design: {1:N1} Wh" -f ($full / 1000), ([double]$static.DesignedCapacity / 1000))
            } else {
                $window.FindName('battHealth').Text = 'Health: n/a (driver ne design capacity nahi di)'
            }
            if ($cyc) { $window.FindName('battCycles').Text = ("Cycle count: {0}" -f $cyc.CycleCount) }
        }
    } catch { }
}

# ---------------------------------------------------------------- go
Show-Page 'dash'
Update-Dashboard
Load-Startup
Update-Battery

$dashTimer = New-Object System.Windows.Threading.DispatcherTimer
$dashTimer.Interval = [TimeSpan]::FromSeconds(3)
$dashTimer.Add_Tick({ Update-Dashboard })
$dashTimer.Start()

$window.Add_Closed({ $dashTimer.Stop() })
$window.ShowDialog() | Out-Null
