# DeskClock

A lightweight, glass-styled desktop widget suite for Windows 11. Six live widgets render as transparent WPF panels on your desktop — always behind your windows, never in the way.

![DeskClock preview](docs/preview.png)

---

## ✨ Features

### 6 live widgets

| Widget | What it shows |
|---|---|
| 🕐 **Clock** | Analog dial with smooth hands, full date and weekday |
| 📊 **System** | CPU / RAM / Storage rings, live CPU+RAM sparkline, uptime |
| 🔋 **Battery** | Charge %, level bar, charging wattage, time to full, battery health, cycle count |
| 🌤 **Weather** | Current temp, condition, high/low, wind, AQI, **7-day forecast** |
| 🌐 **Network** | Live download/upload speed, adapter name, session totals |
| 🗺 **Map** | GPS-based map of your current location with reverse-geocoded city |

### Real data only — nothing is faked

| Value | Source |
|---|---|
| CPU / RAM | `Win32_PerfFormattedData_PerfOS_Processor`, `Win32_OperatingSystem` |
| Storage | `Win32_LogicalDisk` |
| Battery charge / rate | `root\wmi` → `BatteryStatus`, `BatteryFullChargedCapacity`, `BatteryCycleCount` |
| Battery health | `BatteryFullChargedCapacity` ÷ `BatteryStaticData.DesignedCapacity` |
| Weather | [Open-Meteo](https://open-meteo.com/) forecast API |
| Air quality | Open-Meteo Air Quality API (US AQI) |
| Network speed | `Get-NetAdapterStatistics` |
| Map tiles | OpenStreetMap |
| City name | Nominatim reverse geocoding |
| Location | Windows Geolocation API (`Windows.Devices.Geolocation`) |

If a source is unavailable, the widget says so (`AQI n/a`, `offline`) instead of inventing a number.

### Built for reliability

- **Single-process architecture** — all 6 widgets run inside one PowerShell host via STA runspaces. Shared CLR + WPF assemblies keep RAM around **300 MB** instead of ~1.3 GB with separate processes.
- **Self-healing watchdog** — the tray process checks every 15 s. If the host dies it is restarted; if windows vanish the host is recycled.
- **Single-instance locks** — a mutex per widget type means duplicate windows can never appear.
- **Verify-and-retry launcher** — waits for each window to actually appear, retries up to 4 times.
- **Autostart with Windows** — optional Startup shortcut starts everything at login.
- **Glass UI** — vertical gradient, 20 px radius, 16 px padding, 1 px hairline border, soft drop shadow.

### WinTune — PC health & cleanup (built in)

Open it from the tray menu → **PC Health & Cleanup**.

| Tab | What it does |
|---|---|
| **Dashboard** | CPU / RAM / C: usage, uptime, top 12 processes by RAM |
| **Cleanup** | Scans User/Windows Temp, Windows Update cache, Chrome/Brave/Edge caches, npm cache and the Recycle Bin; shows reclaimable size; cleans the selected targets |
| **Startup** | Lists `HKCU\...\Run` entries and Startup-folder items; disables HKCU entries with an automatic JSON backup |
| **Battery** | Charge %, charging wattage, time to full, battery health, design vs full capacity, cycle count |

Everything is read from real sources — no placeholder numbers.

---

## 📦 Requirements

- Windows 10 / 11
- Windows PowerShell 5.1 (built in)
- Internet connection for weather, air quality and map tiles

No installation, no dependencies, no admin rights required.

---

## 🚀 Quick start

```powershell
# start all widgets
powershell -ExecutionPolicy Bypass -File D:\DeskClock\deskclock.ps1 -Action start

# make it start automatically at login
powershell -ExecutionPolicy Bypass -File D:\DeskClock\deskclock.ps1 -Action autostart -State on
```

---

## 🎛 Commands

| Command | What it does |
|---|---|
| `-Action start` | Start the host (all 6 widgets) and the tray |
| `-Action stop` | Stop all widgets |
| `-Action status` | Show what is running |
| `-Action reset` | Kill everything, clear saved positions, restart with the default layout |
| `-Action heal` | Start only what is missing |
| `-Action tray` | Start the tray icon only |
| `-Action autostart -State on\|off\|status` | Manage the Windows login shortcut |

### Tray menu

Right-click (or left-click) the tray icon:

- Show all widgets / Hide all widgets
- Restart + reset layout
- Auto-repair widgets (toggle)
- Start with Windows (toggle)
- Exit tray icon

---

## ⚙️ Configuration

### Theme

Edit `theme.json` to change the palette:

```json
{
  "name": "Aurora",
  "accent": "#A78BFA",
  "accent2": "#60A5FA",
  "text": "#F8FAFC",
  "muted": "#CBD5E1",
  "dim": "#94A3B8",
  "ok": "#34D399",
  "okSoft": "#6EE7B7",
  "warn": "#FBBF24",
  "warnSoft": "#FDE68A"
}
```

Restart the widgets after editing.

### Location

The map widget resolves your location with the Windows Geolocation API, reverse-geocodes it, and caches the result so the weather widget shows the same city:

```
%APPDATA%\DeskClock_location.json
```

You can also set it manually:

```json
{
  "lat": 27.0573,
  "lon": 78.6841,
  "city": "Shikohabad",
  "region": "Uttar Pradesh",
  "country": "India",
  "cc": "IN"
}
```

### Widget positions

Window positions are stored per widget in `%APPDATA%\DeskClock_<type>.json`. Drag a widget where you want it, or run `-Action reset` to restore the default two-column layout.

---

## 🧱 Architecture

```
deskclock.ps1          launcher: start / stop / status / reset / heal / tray / autostart
deskclock_host.ps1     single PowerShell process, one STA runspace per widget
widget.ps1             clock, stats, map, battery
extras.ps1             weather, network
wintune.ps1            PC health & cleanup panel (opened from the tray)
tray.ps1               system-tray icon + auto-repair watchdog
themes.ps1             theme helper
theme.json             colour palette
```

```
Desktop
└── Left column            Right column
    clock    (316 px)      weather  (190 px)
    stats    (220 px)      network  (164 px)
    battery  (190 px)      map      (372 px)
```

Both columns are bottom-aligned at the same coordinate.

---

## 📈 Performance

| Metric | Value |
|---|---|
| Processes | 2 (host + tray) |
| RAM (working set) | ~300 MB host + ~100 MB tray |
| CPU (idle) | < 1 % |
| Widget refresh | clock 100 ms · stats 2 s · network 1 s · battery 15 s · weather 10 min · map 30 s |

---

## 🩺 Troubleshooting

| Symptom | Fix |
|---|---|
| No widgets appear | `deskclock.ps1 -Action status`, then `-Action heal` |
| Widgets disappeared after a while | The tray watchdog restores them within ~45 s. Make sure the tray is running (`-Action tray`). |
| Weather shows a different city | Windows Location Services may be off. Set `%APPDATA%\DeskClock_location.json` manually. |
| Battery says "not charging" while plugged in | Some laptops (e.g. ASUS) report a wrong `Win32_Battery.BatteryStatus`. This project reads `root\wmi` directly, which is reliable. |
| Console window flashes at login | The Startup shortcut uses `-WindowStyle Hidden`; check that the shortcut still points at `deskclock.ps1`. |

---

## 📄 License

MIT © 2026 Arpit Singh
