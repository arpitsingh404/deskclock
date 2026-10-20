# DeskClock extras - weather + AQI | network speed | VPS status
# Usage: powershell -File extras.ps1 -Type weather|net|vps

param(
    [ValidateSet('weather', 'net', 'vps')]
    [string]$Type = 'weather'
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# single instance per widget type - duplicate windows can never happen
# (hosted mode mein host khud manage karta hai, isliye mutex skip)
if ($env:DESKCLOCK_HOSTED -ne '1') {
    $script:instanceMutex = New-Object System.Threading.Mutex($false, "DeskClock_Widget_$Type")
    $script:hasMutex = $false
    try { $script:hasMutex = $script:instanceMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $script:hasMutex = $true }
    if (-not $script:hasMutex) { exit }
}

$stateFile = Join-Path $env:APPDATA "DeskClock_$Type.json"
$locFile = Join-Path $env:APPDATA 'DeskClock_location.json'
$cfg = @{ x = -1; y = -1 }
if (Test-Path $stateFile) {
    try {
        $l = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $l.x) { $cfg.x = [double]$l.x }
        if ($null -ne $l.y) { $cfg.y = [double]$l.y }
    } catch { }
}

# ---------------------------------------------------------------- location
function Get-LocationForWidget {
    if (Test-Path $locFile) {
        try {
            $j = Get-Content $locFile -Raw | ConvertFrom-Json
            if ($j.lat) { return @{ lat = [double]$j.lat; lon = [double]$j.lon; city = $j.city; country = $j.country } }
        } catch { }
    }
    try {
        $r = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,lat,lon,city,country' -TimeoutSec 10
        if ($r.status -eq 'success') { return @{ lat = [double]$r.lat; lon = [double]$r.lon; city = $r.city; country = $r.country } }
    } catch { }
    return @{ lat = 28.6139; lon = 77.2090; city = 'New Delhi'; country = 'India' }
}

function Get-WeatherText([int]$code) {
    switch ($code) {
        0 { return @('Clear', 0x2600) }
        1 { return @('Mostly clear', 0x1F324) }
        2 { return @('Partly cloudy', 0x26C5) }
        3 { return @('Overcast', 0x2601) }
        45 { return @('Fog', 0x1F32B) }
        48 { return @('Rime fog', 0x1F32B) }
        51 { return @('Light drizzle', 0x1F326) }
        53 { return @('Drizzle', 0x1F326) }
        55 { return @('Dense drizzle', 0x1F326) }
        61 { return @('Light rain', 0x1F327) }
        63 { return @('Rain', 0x1F327) }
        65 { return @('Heavy rain', 0x1F327) }
        66 { return @('Freezing rain', 0x1F327) }
        67 { return @('Freezing rain', 0x1F327) }
        71 { return @('Light snow', 0x1F328) }
        73 { return @('Snow', 0x1F328) }
        75 { return @('Heavy snow', 0x1F328) }
        77 { return @('Snow grains', 0x1F328) }
        80 { return @('Showers', 0x1F326) }
        81 { return @('Showers', 0x1F326) }
        82 { return @('Heavy showers', 0x26C8) }
        85 { return @('Snow showers', 0x1F328) }
        86 { return @('Snow showers', 0x1F328) }
        95 { return @('Thunderstorm', 0x26C8) }
        96 { return @('Thunder + hail', 0x26C8) }
        99 { return @('Thunder + hail', 0x26C8) }
        default { return @('-', 0x1F321) }
    }
}
function Get-AqiInfo([double]$aqi) {
    if ($aqi -le 0) { return @('', '#8A8A9A') }
    if ($aqi -le 50) { return @('Good', '#22C55E') }
    if ($aqi -le 100) { return @('Moderate', '#EAB308') }
    if ($aqi -le 150) { return @('Unhealthy (sensitive)', '#F97316') }
    if ($aqi -le 200) { return @('Unhealthy', '#EF4444') }
    if ($aqi -le 300) { return @('Very unhealthy', '#A855F7') }
    return @('Hazardous', '#7F1D1D')
}

function Get-WeatherCat([int]$code) {
    if ($code -le 1) { return 'sun' }
    if ($code -eq 2 -or $code -eq 3 -or $code -eq 45 -or $code -eq 48) { return 'cloud' }
    if ($code -ge 71 -and $code -le 77) { return 'snow' }
    if ($code -eq 85 -or $code -eq 86) { return 'snow' }
    if ($code -ge 51) { return 'rain' }
    return 'cloud'
}

# draws a small vector weather icon (sun / cloud / rain / snow) inside a Canvas
function Set-WxIcon($canvas, [string]$kind) {
    $canvas.Children.Clear()
    $mid = 25.0
    $mk = { param($hex) New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex)) }

    if ($kind -eq 'sun') {
        foreach ($a in 0, 45, 90, 135, 180, 225, 270, 315) {
            $ray = New-Object System.Windows.Shapes.Rectangle
            $ray.Width = 2.6; $ray.Height = 6; $ray.RadiusX = 1.3; $ray.RadiusY = 1.3
            $ray.Fill = & $mk '#FBBF24'
            $ray.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
            $ray.RenderTransform = New-Object System.Windows.Media.RotateTransform $a
            $rad = ($a - 90) * [Math]::PI / 180
            [void]$canvas.Children.Add($ray)
            $ray.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($mid + 15 * [Math]::Cos($rad) - 1.3))
            $ray.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($mid + 15 * [Math]::Sin($rad) - 3))
        }
        $sun = New-Object System.Windows.Shapes.Ellipse
        $sun.Width = 20; $sun.Height = 20
        $sun.Fill = & $mk '#FBBF24'
        $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $glow.BlurRadius = 12; $glow.ShadowDepth = 0; $glow.Opacity = 0.6
        $glow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#FBBF24')
        $sun.Effect = $glow
        [void]$canvas.Children.Add($sun)
        $sun.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($mid - 10))
        $sun.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($mid - 10))
        return
    }

    $parts = @(
        @{ L = 8;  T = 17; W = 21; H = 21; R = $false },
        @{ L = 18; T = 12; W = 16; H = 16; R = $false },
        @{ L = 27; T = 18; W = 13; H = 13; R = $false },
        @{ L = 9;  T = 23; W = 30; H = 12; R = $true }
    )
    foreach ($p in $parts) {
        if ($p.R) {
            $shape = New-Object System.Windows.Shapes.Rectangle
            $shape.RadiusX = 6; $shape.RadiusY = 6
        } else {
            $shape = New-Object System.Windows.Shapes.Ellipse
        }
        $shape.Width = [double]$p.W; $shape.Height = [double]$p.H
        $shape.Fill = & $mk '#E6E8F4'
        [void]$canvas.Children.Add($shape)
        $shape.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]$p.L)
        $shape.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$p.T)
    }

    if ($kind -eq 'rain' -or $kind -eq 'snow') {
        $top = 35.0
        $fill = if ($kind -eq 'rain') { '#7DD3FC' } else { '#E6E8F4' }
        foreach ($x in 14, 23, 32) {
            if ($kind -eq 'rain') {
                $drop = New-Object System.Windows.Shapes.Rectangle
                $drop.Width = 2.4; $drop.Height = 7; $drop.RadiusX = 1.2; $drop.RadiusY = 1.2
                $drop.RenderTransform = New-Object System.Windows.Media.RotateTransform 14
                $top = 34.0
            } else {
                $drop = New-Object System.Windows.Shapes.Ellipse
                $drop.Width = 4; $drop.Height = 4
                $top = 35.0
            }
            $drop.Fill = & $mk $fill
            [void]$canvas.Children.Add($drop)
            $drop.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]$x)
            $drop.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$top)
        }
    }
}

# ---------------------------------------------------------------- XAML
function Get-WeatherXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-weather">
  <Border Background="Transparent" Padding="0">
    <StackPanel VerticalAlignment="Center">
      <Grid Margin="1,0,1,9">
        <TextBlock x:Name="cityTxt" Text="" Foreground="#E8E8F2" FontSize="11" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
        <TextBlock x:Name="updatedTxt" Text="" HorizontalAlignment="Right" Foreground="#B8B8C8" FontSize="9.5" FontFamily="Segoe UI" VerticalAlignment="Center"/>
      </Grid>

      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="60"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- icon badge -->
        <Border Grid.Column="0" Width="50" Height="50" CornerRadius="25" VerticalAlignment="Center"
                Background="#14FFFFFF" BorderBrush="#1CFFFFFF" BorderThickness="1">
          <Canvas x:Name="wxIcon" Width="50" Height="50"/>
        </Border>

        <!-- temp + condition -->
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="tempTxt" Text="" Foreground="#FFFFFF" FontSize="36" FontFamily="Segoe UI Light" Margin="0,-3,0,0"/>
            <TextBlock Text="&#176;" Foreground="#B8B8C8" FontSize="19" FontFamily="Segoe UI Light" VerticalAlignment="Top" Margin="1,1,0,0"/>
          </StackPanel>
          <TextBlock x:Name="condTxt" Text="" Foreground="#EDEDF4" FontSize="10.5" FontFamily="Segoe UI" FontWeight="SemiBold" Margin="0,2,0,0"/>
        </StackPanel>

        <!-- hi / lo / wind -->
        <StackPanel Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right" Margin="14,0,0,0">
          <TextBlock x:Name="maxTxt" Text="" Foreground="#D0D0DE" FontSize="10.5" FontFamily="Segoe UI" HorizontalAlignment="Right"/>
          <TextBlock x:Name="minTxt" Text="" Foreground="#D0D0DE" FontSize="10.5" FontFamily="Segoe UI" HorizontalAlignment="Right"/>
          <TextBlock x:Name="windTxt" Text="" Foreground="#B8B8C8" FontSize="10.5" FontFamily="Segoe UI" HorizontalAlignment="Right" Margin="0,3,0,0"/>
        </StackPanel>
      </Grid>

      <!-- AQI chip -->
      <Border Margin="0,10,0,0" Padding="9,6" CornerRadius="10" Background="#10FFFFFF">
        <Grid>
          <TextBlock Text="AQI" Foreground="#B8B8C8" FontSize="9.5" FontFamily="Segoe UI" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <TextBlock x:Name="aqiTxt" Text="" HorizontalAlignment="Right" Foreground="#E8E8F2" FontSize="10" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
        </Grid>
      </Border>

      <!-- 7-day forecast (runtime pe build hota hai) -->
      <Grid x:Name="forecastGrid" Margin="0,10,0,0"/>
    </StackPanel>
  </Border>
</Window>
"@
}

function Get-NetXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-net">
  <Border Background="Transparent" Padding="0">
    <StackPanel VerticalAlignment="Center">
      <Grid Margin="1,0,1,10">
        <TextBlock Text="NETWORK" Foreground="#5C5C68" FontSize="10.5" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
        <TextBlock x:Name="adapterTxt" Text="" HorizontalAlignment="Right" Foreground="#B8B8C8" FontSize="9" FontFamily="Segoe UI" VerticalAlignment="Center"/>
      </Grid>

      <Grid Margin="0,0,0,5">
        <TextBlock Text="Download" Foreground="#C9C9D6" FontSize="10" FontFamily="Segoe UI" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <TextBlock x:Name="downTxt" Text="0.00 Mbps" HorizontalAlignment="Right" Foreground="#7EE787" FontSize="19" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
      </Grid>
      <Border Height="6" CornerRadius="3" Background="#0EFFFFFF" Margin="0,0,0,14">
        <Border x:Name="downBar" HorizontalAlignment="Left" Width="0" CornerRadius="3">
          <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#22C55E" Offset="0"/><GradientStop Color="#7EE787" Offset="1"/></LinearGradientBrush></Border.Background>
        </Border>
      </Border>

      <Grid Margin="0,0,0,5">
        <TextBlock Text="Upload" Foreground="#C9C9D6" FontSize="10" FontFamily="Segoe UI" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <TextBlock x:Name="upTxt" Text="0.00 Mbps" HorizontalAlignment="Right" Foreground="#8B5CF6" FontSize="19" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
      </Grid>
      <Border Height="6" CornerRadius="3" Background="#0EFFFFFF" Margin="0,0,0,13">
        <Border x:Name="upBar" HorizontalAlignment="Left" Width="0" CornerRadius="3">
          <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#8B5CF6" Offset="0"/><GradientStop Color="#3B82F6" Offset="1"/></LinearGradientBrush></Border.Background>
        </Border>
      </Border>

      <Grid>
        <TextBlock Text="SESSION" Foreground="#5C5C68" FontSize="9" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <TextBlock Text="&#8595;" Foreground="#22C55E" FontSize="10" FontFamily="Segoe UI" Margin="0,0,4,0"/>
          <TextBlock x:Name="dlTotalTxt" Text="0 MB" Foreground="#2E2E38" FontSize="10" FontFamily="Segoe UI" Margin="0,0,12,0"/>
          <TextBlock Text="&#8593;" Foreground="#8B5CF6" FontSize="10" FontFamily="Segoe UI" Margin="0,0,4,0"/>
          <TextBlock x:Name="ulTotalTxt" Text="0 MB" Foreground="#2E2E38" FontSize="10" FontFamily="Segoe UI"/>
        </StackPanel>
      </Grid>
    </StackPanel>
  </Border>
</Window>
"@
}

function Get-VpsXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-vps">
  <Border Background="Transparent" Padding="0">
    <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="0" Opacity="0.9" Color="#000000"/></Border.Effect>
    <StackPanel>
      <Grid Margin="0,0,0,10">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="statusDot" Width="8" Height="8" Fill="#8A8A9A" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <TextBlock Text="VCLOUD.TECH" Foreground="#E8E8F2" FontSize="10.5" FontFamily="Segoe UI" FontWeight="Bold"/>
        </StackPanel>
        <TextBlock x:Name="vpsMeta" Text="" HorizontalAlignment="Right" Foreground="#B8B8C8" FontSize="8.5"/>
      </Grid>

      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
          <TextBlock x:Name="vCpu" Text="" Foreground="#FFFFFF" FontSize="17" FontFamily="Segoe UI" FontWeight="Bold" HorizontalAlignment="Center"/>
          <TextBlock Text="CPU" Foreground="#D0D0DE" FontSize="9" FontFamily="Segoe UI Semibold" HorizontalAlignment="Center" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
          <TextBlock x:Name="vRam" Text="" Foreground="#FFFFFF" FontSize="17" FontFamily="Segoe UI" FontWeight="Bold" HorizontalAlignment="Center"/>
          <TextBlock Text="RAM" Foreground="#D0D0DE" FontSize="9" FontFamily="Segoe UI Semibold" HorizontalAlignment="Center" Margin="0,2,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
          <TextBlock x:Name="vDsk" Text="" Foreground="#FFFFFF" FontSize="17" FontFamily="Segoe UI" FontWeight="Bold" HorizontalAlignment="Center"/>
          <TextBlock Text="DISK" Foreground="#D0D0DE" FontSize="9" FontFamily="Segoe UI Semibold" HorizontalAlignment="Center" Margin="0,2,0,0"/>
        </StackPanel>
      </Grid>

      <Border Margin="0,12,0,0" Padding="2,4,2,4">
        <Grid>
          <TextBlock x:Name="svcTxt" Text="connecting" Foreground="#B8B8C8" FontSize="9" FontFamily="Segoe UI"/>
          <TextBlock x:Name="upTxt" Text="" HorizontalAlignment="Right" Foreground="#B8B8C8" FontSize="8.5"/>
        </Grid>
      </Border>
    </StackPanel>
  </Border>
</Window>
"@
}

# ---------------------------------------------------------------- build
$xamlText = switch ($Type) {
    'weather' { Get-WeatherXaml }
    'net' { Get-NetXaml }
    'vps' { Get-VpsXaml }
}


# ---------------------------------------------------------------- theme
$themeFile = Join-Path $PSScriptRoot 'theme.json'
$T = @{
    accent = '#A78BFA'; accent2 = '#60A5FA'; ok = '#34D399'; okSoft = '#6EE7B7'
    warn = '#FBBF24'; warnSoft = '#FDE68A'; text = '#F8FAFC'; muted = '#CBD5E1'; dim = '#94A3B8'
}
if (Test-Path $themeFile) {
    try {
        $tj = Get-Content $themeFile -Raw | ConvertFrom-Json
        foreach ($k in @('accent', 'accent2', 'ok', 'okSoft', 'warn', 'warnSoft', 'text', 'muted', 'dim')) {
            if ($tj.$k) { $T[$k] = $tj.$k }
        }
    } catch { }
}
$xamlText = $xamlText.Replace('#8B5CF6', $T.accent).Replace('#7C5CFF', $T.accent).Replace('#3B82F6', $T.accent2)
$xamlText = $xamlText.Replace('#22C55E', $T.ok).Replace('#7EE787', $T.okSoft)
$xamlText = $xamlText.Replace('#FBBF24', $T.warnSoft).Replace('#F59E0B', $T.warn)
$xamlText = $xamlText.Replace('#F2F2F8', $T.text).Replace('#EDEDF4', $T.text).Replace('#E8E8F2', $T.text)
$xamlText = $xamlText.Replace('#D8D8E4', $T.muted).Replace('#C9C9D6', $T.muted).Replace('#D0D0DE', $T.muted).Replace('#B8B8C8', $T.muted)
$xamlText = $xamlText.Replace('#FFFFFF', $T.text)
$xamlText = $xamlText.Replace('#C0C0D0', $T.muted).Replace('#9A9AB0', $T.dim)
$xamlText = $xamlText.Replace('#C4B5FD', $T.accent).Replace('#6EE7B7', $T.okSoft)
# light-on-dark tracks -> dark-on-light tracks
$xamlText = $xamlText.Replace('#22FFFFFF', '#18000000').Replace('#26FFFFFF', '#1E000000').Replace('#18FFFFFF', '#14000000')
$xamlText = $xamlText.Replace('#16FFFFFF', '#14000000').Replace('#14FFFFFF', '#12000000').Replace('#12FFFFFF', '#10000000')
$xamlText = $xamlText.Replace('#10FFFFFF', '#0C000000').Replace('#0EFFFFFF', '#0C000000').Replace('#0CFFFFFF', '#0A000000')
$xamlText = $xamlText.Replace('#8A8A9A', $T.dim).Replace('#6E6E80', $T.dim).Replace('#5E5E70', $T.dim)

[xml]$xaml = $xamlText
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ---------------------------------------------------------------- v2 glass panel
$frame = New-Object System.Windows.Controls.Border
$frame.CornerRadius = New-Object System.Windows.CornerRadius 22
$frame.BorderThickness = New-Object System.Windows.Thickness 1
$frame.Padding = New-Object System.Windows.Thickness 0
# translucent white glass (all widgets) - higher opacity for crisp text
$frame.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x14, 0, 0, 0))
$glassBg = New-Object System.Windows.Media.LinearGradientBrush
$glassBg.StartPoint = New-Object System.Windows.Point(0, 0)
$glassBg.EndPoint = New-Object System.Windows.Point(0, 1)
[void]$glassBg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0xF0, 252, 252, 254), 0)))
[void]$glassBg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0xFA, 245, 245, 250), 1)))
$frame.Background = $glassBg

# soft depth
$sh = New-Object System.Windows.Media.Effects.DropShadowEffect
$sh.BlurRadius = 42
$sh.ShadowDepth = 8
$sh.Direction = 270
$sh.Opacity = 0.55
$sh.Color = [System.Windows.Media.Colors]::Black
$frame.Effect = $sh

$inner = $window.Content
if ($inner -is [System.Windows.UIElement]) { $inner.Effect = $null }
$window.Content = $null

$panel = New-Object System.Windows.Controls.Border
$panel.Padding = New-Object System.Windows.Thickness 18
$panel.CornerRadius = New-Object System.Windows.CornerRadius 21
$panel.Child = $inner

# top sheen (glass reflection)
$sheen = New-Object System.Windows.Controls.Border
$sheen.CornerRadius = New-Object System.Windows.CornerRadius 21
$sheen.IsHitTestVisible = $false
$sg = New-Object System.Windows.Media.LinearGradientBrush
$sg.StartPoint = New-Object System.Windows.Point(0, 0)
$sg.EndPoint = New-Object System.Windows.Point(0, 1)
[void]$sg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0x12, 255, 255, 255), 0)))
[void]$sg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0x04, 255, 255, 255), 0.38)))
[void]$sg.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0x00, 255, 255, 255), 0.55)))
$sheen.Background = $sg

$shell = New-Object System.Windows.Controls.Grid
[void]$shell.Children.Add($panel)
[void]$shell.Children.Add($sheen)
$frame.Child = $shell

$window.Content = $frame
if ($inner -is [System.Windows.FrameworkElement]) {
    $inner.VerticalAlignment = 'Center'
    $inner.HorizontalAlignment = 'Stretch'
}

# fixed box sizes -> the two-column grid lines up exactly
$window.SizeToContent = [System.Windows.SizeToContent]::Manual
$sz = switch ($Type) {
    'clock'   { @{ w = 300; h = 316 } }
    'stats'   { @{ w = 300; h = 190 } }
    'map'     { @{ w = 300; h = 176 } }
    'weather' { @{ w = 282; h = 230 } }
    'net'     { @{ w = 400; h = 178 } }
    default   { @{ w = 300; h = 180 } }
}
$window.Width = $sz.w
$window.Height = $sz.h
$window.WindowStartupLocation = 'Manual'

$native = @"
using System;
using System.Runtime.InteropServices;
public static class ZX {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void ToBottom(IntPtr h) { SetWindowPos(h, (IntPtr)1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }
}
"@
Add-Type -TypeDefinition $native

$update = { }
$interval = [TimeSpan]::FromSeconds(30)

# ---------------- weather ----------------
if ($Type -eq 'weather') {
    $cityTxt = $window.FindName('cityTxt'); $updatedTxt = $window.FindName('updatedTxt')
    $wxIcon = $window.FindName('wxIcon'); $tempTxt = $window.FindName('tempTxt'); $condTxt = $window.FindName('condTxt')
    $maxTxt = $window.FindName('maxTxt'); $minTxt = $window.FindName('minTxt'); $windTxt = $window.FindName('windTxt')
    $aqiTxt = $window.FindName('aqiTxt')

    # 7-day forecast columns (runtime pe build)
    $fg = $window.FindName('forecastGrid')
    $script:fcDay = @(); $script:fcHi = @(); $script:fcLo = @()
    for ($i = 0; $i -lt 7; $i++) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$fg.ColumnDefinitions.Add($col)

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($sp, $i)

        $d = New-Object System.Windows.Controls.TextBlock
        $d.Text = '--'; $d.FontSize = 8.5
        $d.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $d.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#5C5C68'))
        $d.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        $hi = New-Object System.Windows.Controls.TextBlock
        $hi.Text = '--'; $hi.FontSize = 10
        $hi.FontWeight = [System.Windows.FontWeights]::SemiBold
        $hi.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $hi.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B0B10'))
        $hi.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $hi.Margin = New-Object System.Windows.Thickness(0,2,0,0)

        $lo = New-Object System.Windows.Controls.TextBlock
        $lo.Text = '--'; $lo.FontSize = 9
        $lo.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
        $lo.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#5C5C68'))
        $lo.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        [void]$sp.Children.Add($d)
        [void]$sp.Children.Add($hi)
        [void]$sp.Children.Add($lo)
        [void]$fg.Children.Add($sp)

        $script:fcDay += $d
        $script:fcHi  += $hi
        $script:fcLo  += $lo
    }

    $loc = Get-LocationForWidget
    $script:cityTxt.Text = "$($loc.city)"
    Set-WxIcon $wxIcon 'sun'

    $update = {
        try {
            $lat = $script:loc.lat; $lon = $script:loc.lon
            $u = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7"
            $w = Invoke-RestMethod -Uri $u -TimeoutSec 15
            $code = [int]$w.current.weather_code
            $info = Get-WeatherText $code
            Set-WxIcon $script:wxIcon (Get-WeatherCat $code)
            $script:tempTxt.Text = "{0:N0}" -f [double]$w.current.temperature_2m
            $script:condTxt.Text = $info[0]
            $script:maxTxt.Text = "H {0:N0}" -f [double]$w.daily.temperature_2m_max[0]
            $script:minTxt.Text = "L {0:N0}" -f [double]$w.daily.temperature_2m_min[0]
            $script:windTxt.Text = "{0:N0} km/h" -f [double]$w.current.wind_speed_10m
            $script:updatedTxt.Text = (Get-Date).ToString('HH:mm')

            try {
                for ($i = 0; $i -lt 7; $i++) {
                    $t = [datetime]::Parse([string]$w.daily.time[$i])
                    $script:fcDay[$i].Text = $t.ToString('ddd').Substring(0,3).ToUpper()
                    $script:fcHi[$i].Text = ("{0:N0}" -f [double]$w.daily.temperature_2m_max[$i]) + [char]0xB0
                    $script:fcLo[$i].Text = ("{0:N0}" -f [double]$w.daily.temperature_2m_min[$i]) + [char]0xB0
                }
            } catch { }

            try {
                $a = Invoke-RestMethod -Uri "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=us_aqi" -TimeoutSec 12
                $aqi = [double]$a.current.us_aqi
                $ai = Get-AqiInfo $aqi
                $script:aqiTxt.Text = "{0:N0}  {1}" -f $aqi, $ai[0]
                $script:aqiTxt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($ai[1]))
            } catch { $script:aqiTxt.Text = 'AQI n/a' }
        } catch {
            $script:condTxt.Text = 'offline'
            $script:updatedTxt.Text = 'retry'
        }
    }
    $script:loc = $loc
    $interval = [TimeSpan]::FromMinutes(10)
}

# ---------------- network ----------------
if ($Type -eq 'net') {
    $downTxt = $window.FindName('downTxt'); $upTxt = $window.FindName('upTxt')
    $downBar = $window.FindName('downBar'); $upBar = $window.FindName('upBar')
    $dlTotalTxt = $window.FindName('dlTotalTxt'); $ulTotalTxt = $window.FindName('ulTotalTxt')
    $adapterTxt = $window.FindName('adapterTxt')

    $script:prevRx = $null; $script:prevTx = $null; $script:prevTime = $null
    $script:totalRx = 0.0; $script:totalTx = 0.0
    $BARW = 364.0

    $update = {
        try {
            $stats = Get-NetAdapterStatistics -ErrorAction Stop | Where-Object { $_.ReceivedBytes -gt 0 }
            $rx = ($stats | Measure-Object -Property ReceivedBytes -Sum).Sum
            $tx = ($stats | Measure-Object -Property SentBytes -Sum).Sum
            $now = Get-Date

            if ($null -ne $script:prevRx) {
                $dt = ($now - $script:prevTime).TotalSeconds
                if ($dt -gt 0) {
                    $dRx = [Math]::Max(0, ($rx - $script:prevRx))
                    $dTx = [Math]::Max(0, ($tx - $script:prevTx))
                    $script:totalRx += $dRx
                    $script:totalTx += $dTx
                    $mbpsDown = ($dRx * 8) / $dt / 1MB
                    $mbpsUp = ($dTx * 8) / $dt / 1MB
                    $script:downTxt.Text = "{0:N2} Mbps" -f $mbpsDown
                    $script:upTxt.Text = "{0:N2} Mbps" -f $mbpsUp
                    $script:downBar.Width = [Math]::Max(0, [Math]::Min($BARW, $BARW * [Math]::Min(1, $mbpsDown / 100)))
                    $script:upBar.Width = [Math]::Max(0, [Math]::Min($BARW, $BARW * [Math]::Min(1, $mbpsUp / 50)))
                    $script:dlTotalTxt.Text = ("{0:N1} MB" -f ($script:totalRx / 1MB))
                    $script:ulTotalTxt.Text = ("{0:N1} MB" -f ($script:totalTx / 1MB))
                }
            }
            $script:prevRx = $rx; $script:prevTx = $tx; $script:prevTime = $now
            $name = ($stats | Select-Object -First 1).Name
            if ($name) { $script:adapterTxt.Text = $name }
        } catch {
            $script:dlTotalTxt.Text = 'n/a'
            $script:ulTotalTxt.Text = 'n/a'
        }
    }
    $interval = [TimeSpan]::FromSeconds(1)
}

# ---------------- vps ----------------
if ($Type -eq 'vps') {
    $statusDot = $window.FindName('statusDot'); $vpsMeta = $window.FindName('vpsMeta')
    $vCpu = $window.FindName('vCpu'); $vRam = $window.FindName('vRam'); $vDsk = $window.FindName('vDsk')
    $svcTxt = $window.FindName('svcTxt'); $upTxt2 = $window.FindName('upTxt')

    $sshKey = Join-Path $env:USERPROFILE '.ssh\vps_vclub'
    $remote = @'
echo CPU=$(top -bn1 | awk '/Cpu\(s\)/{printf "%.0f", 100-$8}')
echo RAM=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
echo DSK=$(df / | awk 'NR==2{gsub("%","",$5); print $5}')
echo UP=$(uptime -p | sed 's/up //')
echo SVC=$(systemctl is-active nginx topupbot ssh | paste -sd, -)
'@
    $remoteB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))

    $update = {
        try {
            $script:cmd = "echo $($script:remoteB64) | base64 -d | bash"
            $out = & ssh -i $script:sshKey -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new root@94.156.99.114 $script:cmd 2>&1
            $text = ($out | Out-String)
            if ($text -match 'CPU=(\d+)') {
                $script:statusDot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(34, 197, 94))
                $script:vCpu.Text = $Matches[1] + '%'
                if ($text -match 'RAM=(\d+)') { $script:vRam.Text = $Matches[1] + '%' }
                if ($text -match 'DSK=(\d+)') { $script:vDsk.Text = $Matches[1] + '%' }
                if ($text -match 'UP=([^\r\n]+)') {
                    $u = $Matches[1].Trim()
                    $uw = if ($u -match '(\d+) week') { $Matches[1] + 'w ' } else { '' }
                    $ud = if ($u -match '(\d+) day') { $Matches[1] + 'd ' } else { '' }
                    $uh = if ($u -match '(\d+) hour') { $Matches[1] + 'h' } else { '' }
                    $script:uptimeShort = ($uw + $ud + $uh).Trim()
                    $script:upTxt2.Text = ''
                }
                if ($text -match 'SVC=([^\r\n]+)') {
                    $svc = $Matches[1].Trim()
                    $dots = ($svc -split ',') | ForEach-Object { if ($_ -eq 'active') { '' } else { '' } }
                    $script:svcTxt.Text = "nginx $($dots[0])    topupbot $($dots[1])    ssh $($dots[2])"
                }
                $script:vpsMeta.Text = if ($script:uptimeShort) { 'online - ' + $script:uptimeShort } else { 'online' }
            } else {
                throw 'no data'
            }
        } catch {
            $script:statusDot.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(239, 68, 68))
            $script:vpsMeta.Text = 'offline'
            $script:svcTxt.Text = 'SSH connect failed'
            $script:vCpu.Text = ''; $script:vRam.Text = ''; $script:vDsk.Text = ''
        }
    }
    $interval = [TimeSpan]::FromSeconds(30)
}

# ---------------------------------------------------------------- position
$wa = [System.Windows.SystemParameters]::WorkArea
function Default-Pos {
    $w = $script:window.Width
    switch ($script:Type) {
        'weather' { $script:window.Left = $wa.Right - 18 - 282 - 14 - 282; $script:window.Top = 18 }
        'net' { $script:window.Left = $wa.Right - 18 - 282 - 14 - 282 - 14 - 400; $script:window.Top = 432 }
        'vps' { $script:window.Left = 18; $script:window.Top = 14 + 176 + 8 + 140 + 8 }
    }
}
if ($cfg.x -lt 0 -or $cfg.y -lt 0) { Default-Pos } else { $window.Left = $cfg.x; $window.Top = $cfg.y }

$script:dragging = $false
$script:startPt = $null
$window.Add_MouseLeftButtonDown({
    $script:dragging = $true
    $script:startPt = [System.Windows.Input.Mouse]::GetPosition($script:window)
})
$window.Add_MouseMove({
    if ($script:dragging) {
        $p = [System.Windows.Input.Mouse]::GetPosition($script:window)
        $script:window.Left += ($p.X - $script:startPt.X)
        $script:window.Top += ($p.Y - $script:startPt.Y)
    }
})
$window.Add_MouseLeftButtonUp({ $script:dragging = $false })

$menu = New-Object System.Windows.Controls.ContextMenu
$miReset = New-Object System.Windows.Controls.MenuItem
$miReset.Header = 'Reset position'
$miReset.Add_Click({
    $wa2 = [System.Windows.SystemParameters]::WorkArea
    switch ($script:Type) {
        'weather' { $script:window.Left = $wa2.Right - 18 - 282 - 14 - 282; $script:window.Top = 18 }
        'net' { $script:window.Left = $wa2.Right - 18 - 282 - 14 - 282 - 14 - 400; $script:window.Top = 432 }
        'vps' { $script:window.Left = $wa2.Right - 375 - 18; $script:window.Top = 14 }
    }
})
$miDesktop = New-Object System.Windows.Controls.MenuItem
$miDesktop.Header = 'Send to desktop'
$miDesktop.Add_Click({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
    [ZX]::ToBottom($h)
})
$miClose = New-Object System.Windows.Controls.MenuItem
$miClose.Header = 'Close'
$miClose.Add_Click({ $script:window.Close() })
[void]$menu.Items.Add($miReset)
[void]$menu.Items.Add($miDesktop)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miClose)
$window.ContextMenu = $menu

$window.Add_Loaded({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
    [ZX]::ToBottom($h)
})
$window.Add_Activated({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
    [ZX]::ToBottom($h)
})
$window.Add_StateChanged({
    if ($script:window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $script:window.WindowState = [System.Windows.WindowState]::Normal
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
        [ZX]::ToBottom($h)
    }
})
$window.Add_Closed({
    try { @{ x = $window.Left; y = $window.Top } | ConvertTo-Json | Set-Content $script:stateFile -Encoding UTF8 } catch { }
})

$mainTimer = New-Object System.Windows.Threading.DispatcherTimer
$mainTimer.Interval = $interval
$mainTimer.Add_Tick($update)
$mainTimer.Start()

$zTimer = New-Object System.Windows.Threading.DispatcherTimer
$zTimer.Interval = [TimeSpan]::FromSeconds(3)
$zTimer.Add_Tick({
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
        [ZX]::ToBottom($h)
    } catch { }
})
$zTimer.Start()

& $update
$null = $window.ShowDialog()












