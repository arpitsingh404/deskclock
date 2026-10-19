# DeskClock theme switcher
# Usage: powershell -File themes.ps1 -Set aurora|emerald|sunset|mono|ice
#        powershell -File themes.ps1 -List

param(
    [string]$Set = '',
    [switch]$List
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$themeFile = Join-Path $root 'theme.json'

$presets = [ordered]@{
    aurora = @{
        name = 'Aurora'; accent = '#A78BFA'; accent2 = '#60A5FA'
        ok = '#34D399'; okSoft = '#6EE7B7'; warn = '#FBBF24'; warnSoft = '#FDE68A'
        text = '#F8FAFC'; muted = '#CBD5E1'; dim = '#94A3B8'
    }
    emerald = @{
        name = 'Emerald'; accent = '#34D399'; accent2 = '#10B981'
        ok = '#4ADE80'; okSoft = '#86EFAC'; warn = '#FCD34D'; warnSoft = '#FDE68A'
        text = '#F0FDF4'; muted = '#BBF7D0'; dim = '#86EFAC'
    }
    sunset = @{
        name = 'Sunset'; accent = '#FB7185'; accent2 = '#F59E0B'
        ok = '#FBBF24'; okSoft = '#FCD34D'; warn = '#F97316'; warnSoft = '#FDBA74'
        text = '#FFF7ED'; muted = '#FED7AA'; dim = '#FDBA74'
    }
    ice = @{
        name = 'Ice'; accent = '#67E8F9'; accent2 = '#38BDF8'
        ok = '#5EEAD4'; okSoft = '#99F6E4'; warn = '#FDE047'; warnSoft = '#FEF08A'
        text = '#F0F9FF'; muted = '#BAE6FD'; dim = '#7DD3FC'
    }
    mono = @{
        name = 'Mono'; accent = '#E5E7EB'; accent2 = '#9CA3AF'
        ok = '#D1D5DB'; okSoft = '#E5E7EB'; warn = '#9CA3AF'; warnSoft = '#D1D5DB'
        text = '#FAFAFA'; muted = '#D4D4D8'; dim = '#A1A1AA'
    }
}

if ($List -or -not $Set) {
    "available themes:"
    foreach ($k in $presets.Keys) { "  - " + $k + "  (" + $presets[$k].name + ")" }
    if (-not $Set) { "`nusage: powershell -File themes.ps1 -Set aurora" }
    return
}

$key = $Set.ToLower()
if (-not $presets.Contains($key)) {
    "unknown theme: $Set"
    "available: " + ($presets.Keys -join ', ')
    return
}

$presets[$key] | ConvertTo-Json | Set-Content $themeFile -Encoding UTF8
"theme set to: " + $presets[$key].name

# restart all widgets so they pick the new palette
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'deskclock.ps1') -Action stop | Out-Null
Start-Sleep -Seconds 3
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'deskclock.ps1') -Action start
