# SyncLight Pro

Native **SwiftUI** macOS app (Apple Silicon) to control **Robobloq SyncLight**
USB light bars over HID — an arm64-native, from-scratch replacement for the
original Electron app.

<p align="center"><em>Cyberpunk UI · screen ambilight · sound pickup · multi-monitor · multi-light · any strip length</em></p>

## Features
- Connect to the USB light over HID (`0x1A86:0xFE07`)
- **Multi-light** — drive several bars at once; each light has its **own**
  settings, effects, auto-off, **its own screen-sync toggle**, and **its own
  target monitor**. A dropdown in the header picks which light the pages edit,
  and an **"All lights"** switch applies a change to every connected light at
  once.
- Static color, custom picker, brightness
- Effects (rainbow / breathing / flow / comet / music …) with speed, sound sensitivity & brightness
- Real-time **screen sync** (ambilight) via ScreenCaptureKit, wrapping all four screen edges
- **Multi-monitor aware** — pick which display each strip mirrors
- **Adapts to any strip length / LED count** (sampling grid derived from the
  device's real lamp count and the display aspect, like the original app)
- **Sound-pickup** effects driven by live system audio
- **USB Power Optimization** (hue-preserving brightness scaling to stay within USB current)
- **Start on boot** (menu-bar only); per-light settings persisted across launches
- Bilingual UI (Tiếng Việt / English)

## Device support

This is a **reverse-engineered** replacement, verified against a Robobloq USB
**HID** light bar (`VID 0x1A86 / PID 0xFE07`, manufacturer string `ROBOBLOQ`).

| Works | Not supported (yet) |
|---|---|
| Robobloq **USB HID** light bars (any length / LED count) | BLE lights (`0xFFAA:0x5555`) |
| **Multiple** USB HID lights at once (one per monitor) | USB dongle (`0xFFAA:0x5656`) |
| Any monitor (assign a display to each light) | Serial/CDC (`0xFE0C`) |

The BLE/dongle paths use a different 20-byte MAC-based frame (see
[`PROTOCOL.md`](PROTOCOL.md)) that is **not** implemented here.

### Different LED counts / strip lengths
The sampling grid is computed from the device's reported LED count and the
display aspect ratio ([`Sources/SyncLightPro/GridLayout.swift`](Sources/SyncLightPro/GridLayout.swift),
ported from the original Electron `getColsAndRows`), so strips of different
lengths should sync correctly. If a model misbehaves, please open an issue with
the `id` / LED count shown in the app (Settings) and your monitor resolution.

## Build & run

Requires macOS 13+, Xcode Command Line Tools, and an Apple Silicon Mac.

```bash
git clone https://github.com/hacmiu/synclight-pro.git
cd synclight-pro
./build.sh release
open "build/SyncLight Pro.app"
```

Or with plain SwiftPM:

```bash
swift build -c release
```

Screen Sync needs **Screen Recording** permission (System Settings → Privacy &
Security → Screen Recording).

## Usage

1. Plug in one or more lights, open the app, click **Connect** (or **Connect all**).
   With 2+ lights, pick the active one from the **dropdown in the header**.
2. **Color** tab — pick a color / brightness (applies to the selected light).
3. **Effects** tab — choose a dynamic or sound-pickup effect for the selected light.
4. **Sync** tab — turn on screen-sync for the selected light (each light syncs
   its own monitor independently). Set FPS, then **assign a display to each light**
   and flip strip direction per card.
5. **Settings** — language, per-light auto-off, USB power optimization, start on boot.

> Picking a static colour or an effect automatically turns **screen-sync off for
> that light only** (the others keep mirroring).

## Project layout

```
.
├── Package.swift                # SwiftPM executable target "SyncLightPro"
├── build.sh                     # build arm64 .app bundle into build/ (+ icon)
├── make_icon.sh                 # PNG/SVG -> .icns icon pipeline
├── Resources/                   # Info.plist, app icon, menu-bar icon
├── Sources/SyncLightPro/        # app sources
│   ├── App.swift                # @main SwiftUI App, MenuBarExtra + window, AppDelegate
│   ├── AppModel.swift           # ObservableObject — multi-light state + actions
│   ├── LightDevice.swift        # one light = transport + driver + sampler + settings
│   ├── ContentView.swift        # window shell (cyberpunk)
│   ├── Pages.swift              # Color / Effects / Sync / Settings pages
│   ├── CyberpunkTheme.swift     # palette, neon modifiers, segmented + dropdown
│   ├── L10n.swift               # bilingual string table
│   ├── HIDTransport.swift       # native IOKit HID transport
│   ├── LightDriver.swift        # device commands + metadata parsing
│   ├── RobobloqProtocol.swift   # RB/SC frame builders
│   ├── GridLayout.swift         # adaptive sampling grid (getAspectRatio/getColsAndRows)
│   ├── ScreenColorSampler.swift # ScreenCaptureKit color sampler (ambilight)
│   ├── SystemAudioMeter.swift   # realtime audio level for sound-pickup
│   ├── HotPlugMonitor.swift     # USB plug/unplug detection
│   ├── ColorSwatchButton.swift  # ColorPicker wrapper
│   └── HueSlider.swift          # HueSlider + GradientSlider
├── PROTOCOL.md                  # reverse-engineered HID protocol notes
├── docs/                        # architecture, dev notes, session handoff
└── LICENSE                      # MIT
```

## Documentation
- [`CHANGELOG.md`](CHANGELOG.md) — version history (current: **v1.1**)
- [`docs/README.md`](docs/README.md) — architecture & data flow
- [`docs/SESSION_HANDOFF.md`](docs/SESSION_HANDOFF.md) — current state & roadmap
- [`docs/DEV_NOTES.md`](docs/DEV_NOTES.md) — HID transport gotchas & testing
- [`PROTOCOL.md`](PROTOCOL.md) — reverse-engineered HID protocol

## Status

**v1.1** — core control (connect, color, brightness, effects, off) and screen
ambilight are verified on hardware. The sampling grid adapts to the device's LED
count and the selected monitor. **Multiple USB HID lights** are supported (each
with its own settings/effects/auto-off, its own screen-sync toggle and its own
target display) plus an **apply-to-all** mode; the app now survives sleep/wake.
BLE / dongle / serial not supported yet. See
[`CHANGELOG.md`](CHANGELOG.md) and
[`docs/SESSION_HANDOFF.md`](docs/SESSION_HANDOFF.md) for details.

## Disclaimer

Independent interoperability project, **not affiliated with or endorsed by
Robobloq**. Protocol derived via analysis for interoperability. See
[LICENSE](LICENSE).
