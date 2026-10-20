# DeskClock widgets v2 - transparent analog clock + circular system rings + live map
# Usage: powershell -File widget.ps1 -Type clock|stats|map

param(
    [ValidateSet('clock', 'stats', 'map', 'battery', 'tunebtn')]
    [string]$Type = 'clock'
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
$mapFile = Join-Path $env:TEMP 'deskclock_map.png'
$cfg = @{ x = -1; y = -1 }
if (Test-Path $stateFile) {
    try {
        $l = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $l.x) { $cfg.x = [double]$l.x }
        if ($null -ne $l.y) { $cfg.y = [double]$l.y }
    } catch { }
}

# ------------------------------------------------------------------ map helpers
function Get-TileNumber([double]$lat, [double]$lon, [int]$z) {
    $n = [Math]::Pow(2, $z)
    $latRad = $lat * [Math]::PI / 180.0
    $xt = [Math]::Floor(($lon + 180.0) / 360.0 * $n)
    $yt = [Math]::Floor((1.0 - [Math]::Log([Math]::Tan($latRad) + 1.0 / [Math]::Cos($latRad)) / [Math]::PI) / 2.0 * $n)
    return @{ x = [int]$xt; y = [int]$yt; n = [int]$n }
}

function New-MapImage([double]$lat, [double]$lon, [int]$zoom, [int]$outW, [int]$outH, [string]$path) {
    $t = Get-TileNumber $lat $lon $zoom
    $ts = 256
    $canvas = New-Object System.Drawing.Bitmap ($ts * 3), ($ts * 3)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.Color]::FromArgb(24, 24, 30))
    for ($dx = -1; $dx -le 1; $dx++) {
        for ($dy = -1; $dy -le 1; $dy++) {
            $tx = $t.x + $dx; $ty = $t.y + $dy
            if ($tx -lt 0 -or $ty -lt 0 -or $tx -ge $t.n -or $ty -ge $t.n) { continue }
            try {
                $req = [System.Net.HttpWebRequest]::Create("https://tile.openstreetmap.org/$zoom/$tx/$ty.png")
                $req.UserAgent = 'DeskClockWidget/1.0 (personal desktop widget)'
                $req.Timeout = 8000
                $resp = $req.GetResponse()
                $img = [System.Drawing.Image]::FromStream($resp.GetResponseStream())
                $g.DrawImage($img, (($dx + 1) * $ts), (($dy + 1) * $ts), $ts, $ts)
                $img.Dispose(); $resp.Close()
            } catch { }
        }
    }
    $g.Dispose()
    $cx = [int](($ts * 3 - $outW) / 2); $cy = [int](($ts * 3 - $outH) / 2)
    $crop = New-Object System.Drawing.Bitmap $outW, $outH
    $g2 = [System.Drawing.Graphics]::FromImage($crop)
    $g2.DrawImage($canvas, (New-Object System.Drawing.Rectangle 0, 0, $outW, $outH), (New-Object System.Drawing.Rectangle $cx, $cy, $outW, $outH), 'Pixel')
    $g2.SmoothingMode = 'AntiAlias'
    $mx = [int]($outW / 2); $my = [int]($outH / 2)
    $g2.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(45, 124, 92, 255))), ($mx - 14), ($my - 14), 28, 28)
    $g2.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)), ($mx - 6), ($my - 6), 12, 12)
    $g2.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 124, 92, 255))), ($mx - 4), ($my - 4), 8, 8)
    $g2.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 10, 10, 16))), 0, 0, $outW, $outH)
    $g2.Dispose()
    $crop.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose(); $crop.Dispose()
}

function Get-LocationInfo {
    try {
        $r = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,countryCode,country,regionName,city,lat,lon' -TimeoutSec 10
        if ($r.status -eq 'success') {
            return @{ lat = [double]$r.lat; lon = [double]$r.lon; city = $r.city; region = $r.regionName; country = $r.country; cc = $r.countryCode }
        }
    } catch { }
    return $null
}

# ------------------------------------------------------------------ XAML
function Get-ClockXaml {
    # fully transparent background: only ring, ticks and hands remain
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-clock">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="284"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
      <!-- single bezel ring + soft dial face (perfect circles) -->
      <Ellipse Width="284" Height="284" Stroke="#22000000" StrokeThickness="1.2"/>
      <Ellipse Width="252" Height="252">
        <Ellipse.Fill>
          <RadialGradientBrush>
            <GradientStop Color="#FEFEFF" Offset="0"/>
            <GradientStop Color="#F0F0F6" Offset="1"/>
          </RadialGradientBrush>
        </Ellipse.Fill>
      </Ellipse>

      <Canvas x:Name="dial" Width="284" Height="284"/>
      <Canvas x:Name="hands" Width="284" Height="284">
        <Canvas.Effect>
          <DropShadowEffect BlurRadius="7" ShadowDepth="1" Direction="270" Opacity="0.22" Color="#000000"/>
        </Canvas.Effect>

        <Rectangle x:Name="hourHand" Width="6" Height="58" RadiusX="3" RadiusY="3" Fill="#16161C" RenderTransformOrigin="0.5,1">
          <Rectangle.RenderTransform><RotateTransform x:Name="hourRot"/></Rectangle.RenderTransform>
        </Rectangle>
        <Rectangle x:Name="minHand" Width="4.5" Height="76" RadiusX="2.25" RadiusY="2.25" Fill="#2A2A33" RenderTransformOrigin="0.5,1">
          <Rectangle.RenderTransform><RotateTransform x:Name="minRot"/></Rectangle.RenderTransform>
        </Rectangle>
        <Rectangle x:Name="secHand" Width="2" Height="86" RadiusX="1" RadiusY="1" RenderTransformOrigin="0.5,1">
          <Rectangle.RenderTransform><RotateTransform x:Name="secRot"/></Rectangle.RenderTransform>
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#F43F5E" Offset="0"/>
              <GradientStop Color="#BE123C" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>

        <!-- centre jewel -->
        <Ellipse x:Name="centerGlow" Width="26" Height="26" Fill="#33F43F5E"/>
        <Ellipse x:Name="centerDot" Width="12" Height="12" Fill="#E11D48"/>
        <Ellipse x:Name="centerPin" Width="5" Height="5" Fill="#FDFDFF"/>
      </Canvas>
    </Grid>

    <!-- date row -->
    <StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="0,2,0,0">
      <TextBlock x:Name="timeTxt" Text="" HorizontalAlignment="Center"
                 Foreground="#14141A" FontFamily="Segoe UI Light" FontSize="32">
        <TextBlock.Effect><DropShadowEffect BlurRadius="6" ShadowDepth="1" Direction="270" Opacity="0.10" Color="#000000"/></TextBlock.Effect>
      </TextBlock>
      <TextBlock x:Name="dateTxt" Text="" HorizontalAlignment="Center" Margin="0,2,0,0"
                 Foreground="#14141A" FontFamily="Segoe UI" FontWeight="Bold" FontSize="12.5">
        <TextBlock.Effect><DropShadowEffect BlurRadius="6" ShadowDepth="1" Direction="270" Opacity="0.10" Color="#000000"/></TextBlock.Effect>
      </TextBlock>
      <TextBlock x:Name="dayTxt" Text="" HorizontalAlignment="Center" Margin="0,1,0,0"
                 Foreground="#6B6B76" FontFamily="Segoe UI" FontWeight="SemiBold" FontSize="9.5"/>
    </StackPanel>
  </Grid>
</Window>
"@
}

function RingXaml($name, $c1, $c2, $label) {
    # ring 80x80 (+ 7px stroke => ~87px visual) so it fits inside the 89px column with padding
    @"
      <StackPanel HorizontalAlignment="Center">
        <Grid Width="80" Height="80">
          <Ellipse Stroke="#3AFFFFFF" StrokeThickness="7"/>
          <Ellipse x:Name="$name" StrokeThickness="7" StrokeDashCap="Round"
                   RenderTransformOrigin="0.5,0.5">
            <Ellipse.Stroke>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="$c1" Offset="0"/>
                <GradientStop Color="$c2" Offset="1"/>
              </LinearGradientBrush>
            </Ellipse.Stroke>
            <Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="0" Opacity="0.55" Color="$c1"/></Ellipse.Effect>
          </Ellipse>
          <TextBlock x:Name="${name}Txt" Text="0%" HorizontalAlignment="Center" VerticalAlignment="Center"
                     Foreground="#FFFFFF" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20">
            <TextBlock.Effect><DropShadowEffect BlurRadius="9" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
          </TextBlock>
        </Grid>
        <TextBlock Text="$label" HorizontalAlignment="Center" Foreground="#5C5C68" FontSize="11"
                   FontFamily="Segoe UI" FontWeight="Bold" Margin="0,7,0,2">
          <TextBlock.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
        <TextBlock x:Name="${name}Sub" Text="" HorizontalAlignment="Center" Foreground="#B8B8C8" FontSize="9.5"
                   FontFamily="Segoe UI" FontWeight="SemiBold">
          <TextBlock.Effect><DropShadowEffect BlurRadius="7" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
      </StackPanel>
"@
}

function Get-StatsXaml {
    $cpu = RingXaml 'cpuArc' '#8B5CF6' '#3B82F6' 'CPU'
    $ram = RingXaml 'ramArc' '#22C55E' '#7EE787' 'RAM'
    $dsk = RingXaml 'dskArc' '#F59E0B' '#FBBF24' 'STORAGE'
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-stats">
  <Grid Margin="0">
    <StackPanel>
      <Grid Margin="4,0,4,10">
        <TextBlock Text="SYSTEM" Foreground="#5C5C68" FontSize="10.5" FontFamily="Segoe UI" FontWeight="Bold">
          <TextBlock.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
        <TextBlock x:Name="uptimeTxt" Text="" HorizontalAlignment="Right" Foreground="#C0C0D0" FontSize="9.5" FontWeight="SemiBold">
          <TextBlock.Effect><DropShadowEffect BlurRadius="7" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
      </Grid>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid Grid.Column="0">$cpu</Grid>
        <Grid Grid.Column="1">$ram</Grid>
        <Grid Grid.Column="2">$dsk</Grid>
      </Grid>

      <Border Margin="4,10,4,0" Height="40" CornerRadius="8" Background="#10FFFFFF" ClipToBounds="True">
        <Canvas x:Name="sparkCanvas" Width="238" Height="40">
          <Polyline x:Name="cpuLine" Stroke="#8B5CF6" StrokeThickness="2.2" StrokeLineJoin="Round"/>
          <Polyline x:Name="ramLine" Stroke="#22C55E" StrokeThickness="2.2" StrokeLineJoin="Round"/>
        </Canvas>
      </Border>
    </StackPanel>
  </Grid>
</Window>
"@
}

function Get-MapXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-map">
  <Window.Resources>
    <DropShadowEffect x:Key="glow" BlurRadius="26" ShadowDepth="0" Opacity="0.55" Color="#000000"/>
  </Window.Resources>
  <Border Background="Transparent" Padding="0">
    <Grid>
      <Border Height="312" CornerRadius="14" ClipToBounds="True" BorderBrush="#18FFFFFF" BorderThickness="1">
        <Grid>
          <Border>
            <Border.Background>
              <ImageBrush x:Name="mapBrush" Stretch="UniformToFill"/>
            </Border.Background>
          </Border>
          <!-- soft tint so the bright map tiles do not glare -->
          <Border Background="#4D0A0E16"/>
          <Border VerticalAlignment="Bottom" HorizontalAlignment="Left" Margin="10" Background="#EFFFFFFF" Padding="9,5" CornerRadius="9" BorderBrush="#18000000" BorderThickness="1">
            <StackPanel Orientation="Horizontal">
              <Ellipse Width="6" Height="6" Fill="#059669" VerticalAlignment="Center" Margin="0,0,7,0"/>
              <TextBlock x:Name="mapLabel" Text="locating" Foreground="#2E2E38" FontSize="10.5" FontFamily="Segoe UI"/>
            </StackPanel>
          </Border>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
"@
}

function Get-BatteryXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-battery">
  <Border Background="Transparent" Padding="0">
    <StackPanel VerticalAlignment="Center">
      <Grid Margin="1,0,1,12">
        <TextBlock Text="BATTERY" Foreground="#5C5C68" FontSize="10.5" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center">
          <TextBlock.Effect><DropShadowEffect BlurRadius="8" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
        <TextBlock x:Name="battState" Text="" HorizontalAlignment="Right" Foreground="#7EE787" FontSize="9.5" FontFamily="Segoe UI" FontWeight="Bold" VerticalAlignment="Center">
          <TextBlock.Effect><DropShadowEffect BlurRadius="7" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
      </Grid>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="1,0,0,0">
        <TextBlock x:Name="battPct" Text="100" Foreground="#FFFFFF" FontSize="35" FontFamily="Segoe UI Light" Margin="0,-4,0,0">
          <TextBlock.Effect><DropShadowEffect BlurRadius="9" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
        </TextBlock>
        <TextBlock Text="%" Foreground="#B8B8C8" FontSize="17" FontFamily="Segoe UI Light" VerticalAlignment="Top" Margin="2,1,0,0"/>
        <Path x:Name="battBolt" Data="M 7,0 L 0,9 L 4,9 L 3,15 L 10,6 L 6,6 Z"
              Fill="#7EE787" Stretch="Uniform" Width="13" Height="19" VerticalAlignment="Center" Margin="14,0,0,0"/>
      </StackPanel>

      <Border Margin="0,13,0,0" Height="24" CornerRadius="8"
              Background="#16FFFFFF" BorderBrush="#26FFFFFF" BorderThickness="1" Padding="3">
        <Border x:Name="battFill" CornerRadius="6" HorizontalAlignment="Left" Width="0">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
              <GradientStop Color="#22C55E" Offset="0"/>
              <GradientStop Color="#7EE787" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>
      </Border>

      <TextBlock x:Name="battDetail" Text="" Foreground="#B8B8C8" FontSize="9.5" FontFamily="Segoe UI" Margin="0,11,0,0">
        <TextBlock.Effect><DropShadowEffect BlurRadius="7" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
      </TextBlock>

      <TextBlock x:Name="battHealth" Text="" Foreground="#5C5C68" FontSize="9" FontFamily="Segoe UI" Margin="1,6,0,0">
        <TextBlock.Effect><DropShadowEffect BlurRadius="7" ShadowDepth="0" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
      </TextBlock>
    </StackPanel>
  </Border>
</Window>
"@
}

function Get-TuneBtnXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="False"
        Width="300" SizeToContent="Height" WindowStartupLocation="Manual" Title="DeskClock-tunebtn">
  <Border Background="Transparent" Padding="0">
    <Border x:Name="tuneBtn" Height="58" CornerRadius="14" BorderThickness="1" Cursor="Hand">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#FDFDFF" Offset="0"/>
          <GradientStop Color="#F4F4F9" Offset="0.55"/>
          <GradientStop Color="#E9E9F1" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#E2E2EA" Offset="0"/>
          <GradientStop Color="#D6D6E0" Offset="0.5"/>
          <GradientStop Color="#C6C6D2" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>

      <Grid>
        <!-- glass sheen -->
        <Border CornerRadius="13,13,4,4" Height="27" VerticalAlignment="Top" Margin="1,1,1,0">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#26FFFFFF" Offset="0"/>
              <GradientStop Color="#00FFFFFF" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>

        <Grid Margin="12,0,12,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <!-- icon tile (enamelled) -->
          <Border Grid.Column="0" Width="36" Height="36" CornerRadius="12" BorderThickness="1">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#B9A0FF" Offset="0"/>
                <GradientStop Color="#7C3AED" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <Border.BorderBrush>
              <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="#B3FFFFFF" Offset="0"/>
                <GradientStop Color="#33000000" Offset="1"/>
              </LinearGradientBrush>
            </Border.BorderBrush>
            <Viewbox Width="18" Height="18">
              <Canvas Width="24" Height="24">
                <Path Data="M 3,12 L 8,12 L 10,6 L 14,18 L 16,12 L 21,12"
                      Stroke="#FDFDFF" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              </Canvas>
            </Viewbox>
          </Border>

          <!-- labels -->
          <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="PC Health" Foreground="#FFFFFF" FontSize="12.5" FontWeight="Bold">
              <TextBlock.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.9" Color="#000000"/></TextBlock.Effect>
            </TextBlock>
            <TextBlock x:Name="tuneSub" Text="WinTune &#183; cleanup &amp; startup" Foreground="#7A7A88" FontSize="9" Margin="0,3,0,0">
              <TextBlock.Effect><DropShadowEffect BlurRadius="3" ShadowDepth="1" Opacity="0.8" Color="#000000"/></TextBlock.Effect>
            </TextBlock>
          </StackPanel>

          <!-- chevron badge -->
          <Border Grid.Column="2" x:Name="tuneChev" Width="24" Height="24" CornerRadius="8"
                  Background="#12FFFFFF" BorderBrush="#22FFFFFF" BorderThickness="1" VerticalAlignment="Center">
            <TextBlock Text="&#8250;" Foreground="#C4B5FD" FontSize="15"
                       HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-2,0,0"/>
          </Border>
        </Grid>
      </Grid>
    </Border>
  </Border>
</Window>
"@
}

# ---------------------------------------------------------------- location
$locFile = Join-Path $env:APPDATA 'DeskClock_location.json'

function Get-ManualLocation {
    if (Test-Path $locFile) {
        try {
            $j = Get-Content $locFile -Raw | ConvertFrom-Json
            if ($j.lat) {
                return @{ lat = [double]$j.lat; lon = [double]$j.lon; city = $j.city; region = $j.region; country = $j.country; cc = $j.cc; source = 'manual' }
            }
        } catch { }
    }
    return $null
}

function Get-WindowsLocation {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $null = [Windows.Devices.Geolocation.Geolocator, Windows.Devices.Geolocation, ContentType = WindowsRuntime]
        $geo = [Windows.Devices.Geolocation.Geolocator]::new()
        $geo.DesiredAccuracy = [Windows.Devices.Geolocation.PositionAccuracy]::High
        $op = $geo.GetGeopositionAsync([TimeSpan]::FromSeconds(15), [TimeSpan]::FromSeconds(10))
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]
        $task = $asTask.MakeGenericMethod([Windows.Devices.Geolocation.Geoposition]).Invoke($null, @($op))
        if (-not $task.Wait(12000)) { return $null }
        $pos = $task.Result
        return @{ lat = [double]$pos.Coordinate.Point.Position.Latitude; lon = [double]$pos.Coordinate.Point.Position.Longitude }
    } catch {
        return $null
    }
}

function Get-ReverseGeocode([double]$lat, [double]$lon) {
    try {
        $req = [System.Net.HttpWebRequest]::Create("https://nominatim.openstreetmap.org/reverse?format=json&zoom=10&addressdetails=1&lat=$lat&lon=$lon")
        $req.UserAgent = 'DeskClockWidget/1.0 (personal desktop widget)'
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $json = $sr.ReadToEnd() | ConvertFrom-Json
        $sr.Close(); $resp.Close()
        $a = $json.address
        $city = $a.city; if (-not $city) { $city = $a.town }; if (-not $city) { $city = $a.village }; if (-not $city) { $city = $a.county }
        return @{
            city = $city
            region = $a.state
            country = $a.country
            cc = $a.country_code.ToUpper()
        }
    } catch { return $null }
}

function Resolve-Location {
    $m = Get-ManualLocation
    if ($m) { return $m }

    $w = Get-WindowsLocation
    if ($w) {
        $r = Get-ReverseGeocode $w.lat $w.lon
        if ($r -and $r.city) {
            return @{ lat = $w.lat; lon = $w.lon; city = $r.city; region = $r.region; country = $r.country; cc = $r.cc; source = 'gps' }
        }
        return @{ lat = $w.lat; lon = $w.lon; city = 'Current location'; region = ''; country = $r.country; cc = $r.cc; source = 'gps' }
    }

    $ip = Get-LocationInfo
    if ($ip) { $ip.source = 'ip'; return $ip }
    return @{ lat = 28.6139; lon = 77.2090; city = 'New Delhi'; region = 'Delhi'; country = 'India'; cc = 'IN'; source = 'default' }
}

$loc = $null
if ($Type -eq 'map') {
    $loc = Resolve-Location
    $script:loc = $loc

    # GPS se mili location ko cache karo taaki weather/network bhi wahi city dikhayein
    if ($loc.source -eq 'gps') {
        try {
            @{
                lat = $loc.lat; lon = $loc.lon; city = $loc.city
                region = $loc.region; country = $loc.country; cc = $loc.cc; source = 'gps'
            } | ConvertTo-Json | Set-Content $locFile -Encoding UTF8
        } catch { }
    }

    if (-not (Test-Path $mapFile) -or ((Get-Item $mapFile).LastWriteTime -lt (Get-Date).AddMinutes(-60))) {
        New-MapImage $loc.lat $loc.lon 11 600 656 $mapFile
    }
}

$xamlText = switch ($Type) {
    'clock' { Get-ClockXaml }
    'stats' { Get-StatsXaml }
    'map' { Get-MapXaml }
    'battery' { Get-BatteryXaml }
    'tunebtn' { Get-TuneBtnXaml }
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
    'clock'   { @{ w = 400; h = 400 } }
    'stats'   { @{ w = 282; h = 230 } }
    'map'     { @{ w = 282; h = 348 } }
    'tunebtn' { @{ w = 282; h = 104 } }
    'weather' { @{ w = 282; h = 230 } }
    'net'     { @{ w = 400; h = 178 } }
    'battery' { @{ w = 282; h = 230 } }
    default   { @{ w = 300; h = 180 } }
}
$window.Width = $sz.w
$window.Height = $sz.h
$window.WindowStartupLocation = 'Manual'

$native = @"
using System;
using System.Runtime.InteropServices;
public static class ZV {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static void ToBottom(IntPtr h) { SetWindowPos(h, (IntPtr)1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }
}
"@
Add-Type -TypeDefinition $native

$update = { }

# ---------------- clock ----------------
if ($Type -eq 'clock') {
    $dial = $window.FindName('dial')
    $hourHand = $window.FindName('hourHand'); $minHand = $window.FindName('minHand'); $secHand = $window.FindName('secHand')
    $hourRot = $window.FindName('hourRot'); $minRot = $window.FindName('minRot'); $secRot = $window.FindName('secRot')
    $centerDot = $window.FindName('centerDot'); $centerPin = $window.FindName('centerPin'); $centerGlow = $window.FindName('centerGlow')
    $dateTxt = $window.FindName('dateTxt'); $dayTxt = $window.FindName('dayTxt'); $timeTxt = $window.FindName('timeTxt')
    $c = 142.0

    for ($i = 0; $i -lt 60; $i++) {
        # 12/3/6/9 ki jagah numbers aate hain, wahan tick mat banao
        if ($i % 15 -eq 0) { continue }
        $isHour = ($i % 5 -eq 0)
        $len = if ($isHour) { 14 } else { 6 }
        $w = if ($isHour) { 2.2 } else { 1.1 }
        $op = if ($isHour) { 0.85 } else { 0.30 }
        $line = New-Object System.Windows.Shapes.Rectangle
        $line.Width = $w; $line.Height = $len; $line.RadiusX = 1; $line.RadiusY = 1
        $line.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb([int](255 * $op), 26, 26, 34))
        $angle = $i * 6
        $rad = ($angle - 90) * [Math]::PI / 180
        $r = $c - 12 - ($len / 2)
        $rot = New-Object System.Windows.Media.RotateTransform
        $rot.Angle = $angle
        $line.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
        $line.RenderTransform = $rot
        $line.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c + $r * [Math]::Cos($rad) - ($w / 2)))
        $line.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c + $r * [Math]::Sin($rad) - ($len / 2)))
        [void]$dial.Children.Add($line)
    }
    foreach ($n in @(12, 3, 6, 9)) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "$n"; $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI Semibold'; $tb.FontSize = 16
        $tb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(230, 20, 20, 28))
        $tb.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $tb.Effect.BlurRadius = 8; $tb.Effect.ShadowDepth = 0; $tb.Effect.Opacity = 0.8; $tb.Effect.Color = [System.Windows.Media.Colors]::Black
        $tb.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $sz = $tb.DesiredSize
        $angle = switch ($n) { 12 { 0 } 3 { 90 } 6 { 180 } 9 { 270 } }
        $rad = ($angle - 90) * [Math]::PI / 180
        $r = $c - 22
        $tb.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c + $r * [Math]::Cos($rad) - $sz.Width / 2))
        $tb.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c + $r * [Math]::Sin($rad) - $sz.Height / 2))
        [void]$dial.Children.Add($tb)
    }

    $hourHand.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 3))
    $hourHand.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 58))
    $minHand.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 2.25))
    $minHand.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 76))
    $secHand.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 1))
    $secHand.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 86))
    $centerGlow.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 13))
    $centerGlow.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 13))
    $centerDot.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 6))
    $centerDot.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 6))
    $centerPin.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]($c - 2.5))
    $centerPin.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($c - 2.5))

    $update = {
        $now = Get-Date
        $sec = $now.Second + $now.Millisecond / 1000.0
        $min = $now.Minute + $sec / 60.0
        $hr = ($now.Hour % 12) + $min / 60.0
        $script:secRot.Angle = $sec * 6
        $script:minRot.Angle = $min * 6
        $script:hourRot.Angle = $hr * 30
        $script:timeTxt.Text = $now.ToString('HH:mm')
        $script:dateTxt.Text = $now.ToString('dd MMMM yyyy')
        $script:dayTxt.Text = $now.ToString('dddd').ToUpper()
    }
}

# ---------------- stats (rings) ----------------
if ($Type -eq 'stats') {
    $cpuArc = $window.FindName('cpuArc'); $ramArc = $window.FindName('ramArc'); $dskArc = $window.FindName('dskArc')
    $cpuTxt = $window.FindName('cpuArcTxt'); $ramTxt = $window.FindName('ramArcTxt'); $dskTxt = $window.FindName('dskArcTxt')
    $cpuSub = $window.FindName('cpuArcSub'); $ramSub = $window.FindName('ramArcSub'); $dskSub = $window.FindName('dskArcSub')
    $uptimeTxt = $window.FindName('uptimeTxt')

    # sparkline: pichhle 60 samples (2s interval = ~2 min history)
    $cpuLine = $window.FindName('cpuLine')
    $ramLine = $window.FindName('ramLine')
    $script:cpuHist = New-Object System.Collections.ArrayList
    $script:ramHist = New-Object System.Collections.ArrayList
    $script:MAXPTS = 60

    function Set-Spark($line, $hist) {
        $pc = New-Object System.Windows.Media.PointCollection
        $n = $hist.Count
        if ($n -gt 1) {
            for ($i = 0; $i -lt $n; $i++) {
                $x = ($i / [Math]::Max(1, $n - 1)) * 238
                $v = [Math]::Max(0, [Math]::Min(100, [double]$hist[$i]))
                $y = 34 - ($v / 100.0) * 28
                $pc.Add((New-Object System.Windows.Point($x, $y)))
            }
        }
        $line.Points = $pc
    }

    $D = 73.0                 # dash circle diameter = grid 80 - stroke 7 (centre-line)
    $C = [Math]::PI * $D     # circumference
    $TH = 7.0                 # stroke thickness
    $UNITS = $C / $TH         # circumference in dash-array units

    function Set-Ring($arc, [double]$pct) {
        $f = [Math]::Max(0.0, [Math]::Min(1.0, $pct / 100.0))
        $on = $f * $UNITS
        $off = [Math]::Max(0.0001, $UNITS - $on)
        $arc.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection
        $arc.StrokeDashArray.Add($on)
        $arc.StrokeDashArray.Add($off)
        $arc.StrokeDashOffset = 0
    }

    $update = {
        try {
            $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
            $cpu = [double]$p.PercentProcessorTime
            Set-Ring $script:cpuArc $cpu
            $script:cpuTxt.Text = "{0:N0}%" -f $cpu
            $script:cpuSub.Text = "$env:NUMBER_OF_PROCESSORS cores"

            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $total = [double]$os.TotalVisibleMemorySize
            $free = [double]$os.FreePhysicalMemory
            $ramPct = (($total - $free) / $total) * 100
            Set-Ring $script:ramArc $ramPct
            $script:ramTxt.Text = "{0:N0}%" -f $ramPct
            $script:ramSub.Text = "{0:N0}/{1:N0} GB" -f (($total - $free) / 1MB), ($total / 1MB)

            [void]$script:cpuHist.Add($cpu)
            if ($script:cpuHist.Count -gt $script:MAXPTS) { $script:cpuHist.RemoveAt(0) }
            [void]$script:ramHist.Add($ramPct)
            if ($script:ramHist.Count -gt $script:MAXPTS) { $script:ramHist.RemoveAt(0) }
            Set-Spark $script:cpuLine $script:cpuHist
            Set-Spark $script:ramLine $script:ramHist

            $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
            $dPct = (($d.Size - $d.FreeSpace) / $d.Size) * 100
            Set-Ring $script:dskArc $dPct
            $script:dskTxt.Text = "{0:N0}%" -f $dPct
            $script:dskSub.Text = "{0:N0}/{1:N0} GB" -f (($d.Size - $d.FreeSpace) / 1GB), ($d.Size / 1GB)

            $up = (Get-Date) - $os.LastBootUpTime
            $script:uptimeTxt.Text = ("up {0}d {1}h" -f $up.Days, $up.Hours)
        } catch { }
    }
}

# ---------------- map ----------------
if ($Type -eq 'map') {
    $mapBrush = $window.FindName('mapBrush'); $mapLabel = $window.FindName('mapLabel')
    if (Test-Path $mapFile) { $script:mapBrush.ImageSource = New-Object System.Windows.Media.Imaging.BitmapImage ([Uri]$mapFile) }
    $script:mapLabel.Text = "$($loc.city), $($loc.country)  |  $([Math]::Round($loc.lat,2)), $([Math]::Round($loc.lon,2))"
}

# ---------------- battery ----------------
if ($Type -eq 'battery') {
    Add-Type -AssemblyName System.Windows.Forms
    $battPct = $window.FindName('battPct')
    $battFill = $window.FindName('battFill')
    $battBolt = $window.FindName('battBolt')
    $battState = $window.FindName('battState')
    $battDetail = $window.FindName('battDetail')
    $battHealth = $window.FindName('battHealth')

    $script:BAR = 175.0

    # static battery info (design capacity + cycles) - yeh change nahi hota
    $script:battHealthText = ''
    try {
        $static = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1
        $cap = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
        $cyc = Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1
        $parts = @()
        if ($static -and $cap -and [double]$static.DesignedCapacity -gt 0) {
            $h = [int][Math]::Round([double]$cap.FullChargedCapacity / [double]$static.DesignedCapacity * 100)
            $parts += ("health $h%")
        }
        if ($cyc -and $cyc.CycleCount -gt 0) { $parts += ("$($cyc.CycleCount) cycles") }
        if ($cap -and $cap.FullChargedCapacity -gt 0) { $parts += ("{0:N1} Wh" -f ([double]$cap.FullChargedCapacity / 1000)) }
        $script:battHealthText = ($parts -join '   ·   ')
    } catch { }

    function Format-Remain([int]$sec) {
        $ts = [TimeSpan]::FromSeconds([Math]::Max(0, $sec))
        if ($ts.TotalHours -ge 1) {
            return ("{0}h {1:D2}m" -f [int][Math]::Floor($ts.TotalHours), $ts.Minutes)
        }
        return ("{0} min" -f [Math]::Max(1, $ts.Minutes))
    }

    $update = {
        try {
            # bar inner width - measured once the window has laid out
            $parent = $script:battFill.Parent
            if ($parent -and $parent.ActualWidth -gt 10) {
                $script:BAR = [Math]::Max(40.0, $parent.ActualWidth - 6.0)
            }

            # --- real battery data ---
            # ASUS jaise laptops Win32_Battery mein galat BatteryStatus dete hain
            # (2 = "not charging" jabki actually charge ho raha hota hai).
            # Isliye root\wmi BatteryStatus primary source hai.
            $wb  = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            $wbs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
            $wbf = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
            $ps  = [System.Windows.Forms.SystemInformation]::PowerStatus

            $noBatt   = $false
            $charging = $false
            $online   = $false
            $life     = 0
            $pct      = 0
            $watts    = 0

            if ($wb) { $pct = [int]$wb.EstimatedChargeRemaining }

            if ($wbs) {
                $online = [bool]$wbs.PowerOnline
                $charging = [bool]$wbs.Charging
                $dischg = [bool]$wbs.Discharging
                $rate   = [double]$wbs.ChargeRate
                $drate  = [double]$wbs.DischargeRate
                $remain = [double]$wbs.RemainingCapacity
                $full   = if ($wbf) { [double]$wbf.FullChargedCapacity } else { 0 }

                if ($pct -le 0 -and $full -gt 0 -and $remain -gt 0) {
                    $pct = [int][Math]::Round(($remain / $full) * 100)
                }

                if ($charging -and $rate -gt 0 -and $full -gt $remain) {
                    $life = [int](($full - $remain) / $rate * 3600)
                } elseif ($dischg -and $drate -gt 0 -and $remain -gt 0) {
                    $life = [int]($remain / $drate * 3600)
                }

                if ($charging -and $rate -gt 0) { $watts = $rate / 1000 }
                elseif ($dischg -and $drate -gt 0) { $watts = $drate / 1000 }
            } else {
                $flags    = [int]$ps.BatteryChargeStatus
                $noBatt   = ($flags -eq 255)
                $pct      = [int][Math]::Round($ps.BatteryChargePercent)
                $charging = (($flags -band 4) -ne 0)
                $online   = ($ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
                $life     = [int]$ps.BatteryLifeRemaining
            }

            if ($ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online) { $online = $true }

            if ($pct -lt 0)   { $pct = 0 }
            if ($pct -gt 100) { $pct = 100 }
            if ($life -lt 0)  { $life = 0 }

            $script:battPct.Text = "$pct"
            $script:battFill.Width = [Math]::Round($script:BAR * $pct / 100.0, 1)
            if ($script:battHealth) { $script:battHealth.Text = $script:battHealthText }

            # colour by charge level (theme aware)
            $c1 = if ($pct -ge 50) { $script:T.ok } elseif ($pct -ge 20) { $script:T.warn } else { '#F87171' }
            $c2 = if ($pct -ge 50) { $script:T.okSoft } elseif ($pct -ge 20) { $script:T.warnSoft } else { '#EF4444' }
            $g = New-Object System.Windows.Media.LinearGradientBrush
            $g.StartPoint = New-Object System.Windows.Point(0, 0)
            $g.EndPoint = New-Object System.Windows.Point(1, 0)
            [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($c1)), 0))
            [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($c2)), 1))
            $script:battFill.Background = $g

            $accent = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($c1))
            $script:battBolt.Fill = $accent
            $script:battState.Foreground = $accent

            if ($noBatt) {
                $script:battState.Text = 'NO BATTERY'
                $script:battBolt.Visibility = [System.Windows.Visibility]::Collapsed
                $script:battDetail.Text = 'Running on AC power'
            }
            elseif ($charging) {
                $script:battState.Text = 'CHARGING'
                $script:battBolt.Visibility = [System.Windows.Visibility]::Visible
                if ($watts -gt 0 -and $life -gt 0) {
                    $script:battDetail.Text = ("{0:N1} W  |  {1} to full" -f $watts, (Format-Remain $life))
                } elseif ($watts -gt 0) {
                    $script:battDetail.Text = ("{0:N1} W  |  charging" -f $watts)
                } elseif ($life -gt 0) {
                    $script:battDetail.Text = (Format-Remain $life) + ' to full'
                } else {
                    $script:battDetail.Text = 'Charging on AC'
                }
            }
            elseif (-not $online) {
                $script:battState.Text = 'ON BATTERY'
                $script:battBolt.Visibility = [System.Windows.Visibility]::Collapsed
                if ($watts -gt 0 -and $life -gt 0) {
                    $script:battDetail.Text = ("{0:N1} W  |  {1} left" -f $watts, (Format-Remain $life))
                } elseif ($life -gt 0) {
                    $script:battDetail.Text = (Format-Remain $life) + ' remaining'
                } else {
                    $script:battDetail.Text = 'Discharging'
                }
            }
            else {
                if ($pct -ge 99) {
                    $script:battState.Text = 'FULL'
                    $script:battDetail.Text = 'Fully charged  |  AC connected'
                } else {
                    $script:battState.Text = 'PLUGGED IN'
                    $script:battDetail.Text = 'AC connected  |  not charging'
                }
                $script:battBolt.Visibility = [System.Windows.Visibility]::Collapsed
            }
        } catch {
            $script:battDetail.Text = 'battery info unavailable'
        }
    }

    # re-measure the bar as soon as the window has a real layout
    $window.Add_Loaded({ & $script:update })
}

# ---------------- winTune launcher button ----------------
if ($Type -eq 'tunebtn') {
    $update = { }

    $btn  = $window.FindName('tuneBtn')
    $chev = $window.FindName('tuneChev')

    function New-BtnBg([string]$c1, [string]$c2, [string]$c3) {
        $g = New-Object System.Windows.Media.LinearGradientBrush
        $g.StartPoint = New-Object System.Windows.Point(0, 0)
        $g.EndPoint = New-Object System.Windows.Point(0, 1)
        [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($c1)), 0))
        [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($c2)), 0.55))
        [void]$g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($c3)), 1))
        return $g
    }

    function Set-BtnLook([string]$c1, [string]$c2, [string]$c3, [string]$border, [string]$chevBg) {
        $btn.Background  = New-BtnBg $c1 $c2 $c3
        $btn.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($border))
        if ($chev) {
            $chev.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($chevBg))
        }
    }

    if ($btn) {
        $btn.Add_MouseEnter({ Set-BtnLook '#FDFDFF' '#F7F7FC' '#EFEFF6' '#7C3AED' '#EDE9FE' })
        $btn.Add_MouseLeave({ Set-BtnLook '#FDFDFF' '#F4F4F9' '#E9E9F1' '#D6D6E0' '#E6E6EE' })
        $btn.Add_MouseLeftButtonDown({ Set-BtnLook '#ECECF3' '#E6E6EE' '#DEDEE8' '#7C3AED' '#DDD6FE' })
        $btn.Add_MouseLeftButtonUp({
            Set-BtnLook '#FDFDFF' '#F7F7FC' '#EFEFF6' '#7C3AED' '#EDE9FE'
            $wt = Join-Path $PSScriptRoot 'wintune.ps1'
            if (Test-Path $wt) {
                Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $wt
                ) -WindowStyle Hidden
            }
        })
    }
}

# ------------------------------------------------------------------ position + behaviour
$wa = [System.Windows.SystemParameters]::WorkArea
function Default-Pos {
    $w = $script:window.Width
    switch ($script:Type) {
        'clock' { $script:window.Left = $wa.Right - 18 - 282 - 14 - 282 - 14 - 400; $script:window.Top = 18 }
        'stats' { $script:window.Left = $wa.Right - 18 - 282; $script:window.Top = 18 }
        'battery' { $script:window.Left = $wa.Right - 18 - 282 - 14 - 282; $script:window.Top = 262 }
        'map' { $script:window.Left = $wa.Right - 18 - 282; $script:window.Top = 262 }
        'tunebtn' { $script:window.Left = $wa.Right - 18 - 282 - 14 - 282; $script:window.Top = 506 }
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

if ($Type -eq 'map') {
    $miSetLoc = New-Object System.Windows.Controls.MenuItem
    $miSetLoc.Header = 'Set location'
    $miSetLoc.Add_Click({
        Add-Type -AssemblyName Microsoft.VisualBasic
        $resp = [Microsoft.VisualBasic.Interaction]::InputBox(
            "City name ya 'lat, lon' likho (e.g. `"Dehradun`" ya `"30.3165, 78.0322`")",
            'Set location',
            "$($script:loc.lat), $($script:loc.lon)")
        if (-not $resp) { return }
        try {
            $lat = $null; $lon = $null; $city = $null
            if ($resp -match '^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*$') {
                $lat = [double]$Matches[1]; $lon = [double]$Matches[3]
                $rev = Get-ReverseGeocode $lat $lon
                if ($rev) { $city = $rev.city } else { $city = 'Pinned location' }
            } else {
                $q = [uri]::EscapeDataString($resp)
                $req = [System.Net.HttpWebRequest]::Create("https://nominatim.openstreetmap.org/search?format=json&limit=1&q=$q")
                $req.UserAgent = 'DeskClockWidget/1.0 (personal desktop widget)'
                $req.Timeout = 10000
                $r = $req.GetResponse()
                $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
                $arr = $sr.ReadToEnd() | ConvertFrom-Json
                $sr.Close(); $r.Close()
                if (-not $arr -or $arr.Count -eq 0) { throw "Jagah nahi mili: $resp" }
                $lat = [double]$arr[0].lat; $lon = [double]$arr[0].lon
                $city = ($arr[0].display_name -split ',')[0]
            }
            $rev = Get-ReverseGeocode $lat $lon
            $entry = @{
                lat     = $lat
                lon     = $lon
                city    = if ($rev -and $rev.city) { $rev.city } else { $city }
                region  = if ($rev) { $rev.region } else { '' }
                country = if ($rev) { $rev.country } else { '' }
                cc      = if ($rev) { $rev.cc } else { '' }
            }
            $entry | ConvertTo-Json | Set-Content $script:locFile -Encoding UTF8

            New-MapImage $entry.lat $entry.lon 12 300 184 $script:mapFile
            $script:mapBrush.ImageSource = New-Object System.Windows.Media.Imaging.BitmapImage ([Uri]$script:mapFile)
            $script:mapLabel.Text = "$($entry.city), $($entry.country)  |  $([Math]::Round($entry.lat,4)), $([Math]::Round($entry.lon,4))"
            $script:loc = $entry
        } catch {
            [System.Windows.MessageBox]::Show("Location set nahi ho payi:`n$($_.Exception.Message)", 'DeskClock')
        }
    })
    [void]$menu.Items.Add($miSetLoc)
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
}

$miReset = New-Object System.Windows.Controls.MenuItem
$miReset.Header = 'Reset position'
$miReset.Add_Click({
    $w = $script:window.Width
    $wa2 = [System.Windows.SystemParameters]::WorkArea
    switch ($script:Type) {
        'clock' { $script:window.Left = $wa2.Right - 18 - 282 - 14 - 282 - 14 - 400; $script:window.Top = 18 }
        'stats' { $script:window.Left = $wa2.Right - 18 - 282; $script:window.Top = 18 }
        'battery' { $script:window.Left = $wa2.Right - 18 - 282 - 14 - 282; $script:window.Top = 262 }
        'map' { $script:window.Left = $wa2.Right - 18 - 282; $script:window.Top = 262 }
        'tunebtn' { $script:window.Left = $wa2.Right - 18 - 282 - 14 - 282; $script:window.Top = 506 }
    }
})
$miDesktop = New-Object System.Windows.Controls.MenuItem
$miDesktop.Header = 'Send to desktop'
$miDesktop.Add_Click({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
    [ZV]::ToBottom($h)
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
    [ZV]::ToBottom($h)
})
$window.Add_Activated({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
    [ZV]::ToBottom($h)
})
$window.Add_StateChanged({
    if ($script:window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $script:window.WindowState = [System.Windows.WindowState]::Normal
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
        [ZV]::ToBottom($h)
    }
})
$window.Add_Closed({
    try { @{ x = $window.Left; y = $window.Top } | ConvertTo-Json | Set-Content $script:stateFile -Encoding UTF8 } catch { }
})

$mainTimer = New-Object System.Windows.Threading.DispatcherTimer
$mainTimer.Interval = if ($Type -eq 'clock') { [TimeSpan]::FromMilliseconds(100) }
    elseif ($Type -eq 'stats') { [TimeSpan]::FromSeconds(2) }
    elseif ($Type -eq 'battery') { [TimeSpan]::FromSeconds(15) }
    else { [TimeSpan]::FromSeconds(30) }
$mainTimer.Add_Tick($update)
$mainTimer.Start()

$zTimer = New-Object System.Windows.Threading.DispatcherTimer
$zTimer.Interval = [TimeSpan]::FromSeconds(3)
$zTimer.Add_Tick({
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
        [ZV]::ToBottom($h)
    } catch { }
})
$zTimer.Start()

& $update
$null = $window.ShowDialog()












