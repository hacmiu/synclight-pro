# SyncLight Pro — Native macOS App (Apple Silicon)

A native **SwiftUI** macOS app to control **Robobloq SyncLight** USB light bars
(HID, VID `0x1A86` / PID `0xFE07`). It is a from-scratch, arm64-native replacement
for the original Electron/Node app (which used a x64-only `quiklight.node`).

---

## ⚡ Quick start (for the next session)

```bash
# from the repo root
swift build -c release            # plain SwiftPM build
./build.sh release                # build + assemble .app bundle (+ icon, ad-hoc signed)
open "build/SyncLight Pro.app"    # run the app
```

- Requires macOS 13+, Xcode command line tools, Apple Silicon.
- **Screen Sync** needs *Screen Recording* permission (System Settings → Privacy).

---

## Project layout

```
.                                  # repo root
├── Package.swift                # SwiftPM, executable target "SyncLightPro"
├── build.sh                     # builds arm64 .app bundle into build/ (+ icon)
├── make_icon.sh                 # PNG/SVG -> .icns icon pipeline
├── README.md                    # top-level project readme (GitHub landing page)
├── Resources/
│   ├── Info.plist               # bundle Info.plist
│   ├── SyncLight Pro.png        # app icon source (transparent, preferred)
│   └── menu bar.png             # menu-bar icon
├── Sources/SyncLightPro/
│   ├── App.swift                # @main SwiftUI App, MenuBarExtra + window, AppDelegate
│   ├── AppModel.swift           # ObservableObject — state + actions (connect, apply*, sync, USB opt, boot)
│   ├── ContentView.swift        # window shell: header, sidebar tabs, footer (cyberpunk)
│   ├── Pages.swift              # ColorPage, EffectsPage, SyncPage, SettingsPage
│   ├── CyberpunkTheme.swift     # cyber palette, neon modifiers, CyberSegmented, CyberDropdown
│   ├── L10n.swift               # bilingual (vi/en) string table
│   ├── HIDTransport.swift       # native IOKit HID transport (see below)
│   ├── LightDriver.swift        # high-level device commands + meta parsing
│   ├── RobobloqProtocol.swift   # frame builders (RB/SC frames)
│   ├── GridLayout.swift         # sampling grid: port of original getAspectRatio + getColsAndRows
│   ├── ScreenColorSampler.swift # ScreenCaptureKit colour sampler (ambilight)
│   ├── SystemAudioMeter.swift   # realtime audio level for sound-pickup effects
│   ├── HotPlugMonitor.swift     # USB plug/unplug detection
│   ├── ColorSwatchButton.swift  # ColorPicker wrapper
│   └── HueSlider.swift          # HueSlider + GradientSlider
├── PROTOCOL.md                  # reverse-engineered HID protocol notes
└── docs/
    ├── README.md                # ← this file
    ├── SESSION_HANDOFF.md       # what was done / current state / next steps
    └── DEV_NOTES.md             # gotchas, debugging, how to test without the app
```

---

## App icon

The bundle icon (`.icns`) is generated automatically by `build.sh` →
`make_icon.sh`:

- Put a **transparent PNG** at `Resources/SyncLight Pro.png` (preferred — alpha
  preserved, no rendering step, so no white halo).
- A `Resources/SyncLight Pro.svg` is used as a fallback (rendered via
  `rsvg-convert` / `cairosvg` / `imagemagick` if installed, else `qlmanage`).
- The `.icns` is placed in `Contents/Resources/AppIcon.icns` and
  `CFBundleIconFile=AppIcon` is set on the Info.plist.

**Note:** Finder's *list view* may draw a faint backing behind any icon — that is
a Finder decoration, **not** part of the `.icns`. Adding transparent padding or a
rounded plate does **not** remove it (tried, then reverted). Keep the artwork
as-is. After a rebuild, refresh the cache with:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "build/SyncLight Pro.app" && killall Finder
```

---

## Architecture (data flow)

```
ContentView / Pages (SwiftUI, cyberpunk theme)
        │  user actions
        ▼
AppModel (@MainActor ObservableObject)
        │  applyColor / applyBrightness / … / startSync
        ▼
LightDriver  ── builds frames via ──►  RobobloqProtocol
        │                                   │ [UInt8] "RB…"/"SC…"
        ▼                                   ▼
HIDTransport.write(frame)  ──IOHIDDeviceSetReport──►  device
HIDTransport.latestResponse() ◄── input-report callback ◄── device
        ▲
ScreenColorSampler (ScreenCaptureKit) ── onZones ──► AppModel ──► streamScreenZones()  (ambilight, 4 sides)
SystemAudioMeter (CoreAudio)          ── onLevel ──► AppModel ──► setExternalAudio()   (sound-pickup)
```

---

## Controls / features

| Tab      | What it does                                                        |
|----------|---------------------------------------------------------------------|
| Color    | Color swatch (ColorPicker), Hue + Saturation sliders, brightness    |
| Effects  | Dynamic "幻彩" group (type 2, speed) / sound-pickup "拾音" group (type 3, sensitivity); 7 effects each |
| Sync     | Real-time screen→light ambilight (wraps all 4 screen edges), **monitor picker** (when >1 display), FPS, strip direction, permission |
| Settings | Language (vi/en), auto-off timer, **USB Power Optimization**, **Start on boot (menu-bar only)** |

Device info read at connect: `id`, `uuid`, `firmware`, `lamps` (LED count),
`displaySize`. Shown in the footer.

### Notable behaviours

- **USB Power Optimization** (Settings, default **on**): mirrors the original
  app's `isLightCompression`. Any colour whose `R+G+B > 255` is scaled down
  (hue-preserving) to stay within the USB power budget — prevents flicker /
  over-current. Applied per-zone in ambilight mode. Toggle off to allow full
  brightness.
- **Start on boot** (Settings): registers the app as a login item
  (`SMAppService.mainApp`). When enabled the app launches **menu-bar-only**
  (accessory activation policy, no Dock icon, no window); open the controls from
  the menu bar. When disabled (default), the window opens normally on launch.
- **Ambilight** sends per-zone colours sampled from the whole screen; the
  strip (mounted vertically) maps to all four screen edges. `installationMethod`
  flips the direction (left→right / right→left).
- **Adaptive grid** (`GridLayout.swift`): the number of sampling cells is derived
  from the device's real `lampsAmount` and the target display's aspect ratio,
  ported from the original Electron `getAspectRatio` + `getColsAndRows`. This
  makes strips of any length sync correctly (not just the 112-lamp bar on 21:9).
- **Monitor selection** (Sync tab, shown when >1 display): choose which screen
  the strip mirrors. Persisted in `UserDefaults`; changing it while syncing
  restarts capture automatically (`AppModel.restartSync`).

---

## Status (end of this session)

- ✅ **Connect + color + brightness + effects + off work on real hardware.**
  Meta read back `id=000503, uuid=cdab74531abc5bbb, fw=1.7.3, lamps=112,
  display=34`.
- ✅ Native HID transport working on arm64 (see `docs/DEV_NOTES.md`).
- ✅ **Screen Sync / ambilight** works (ScreenCaptureKit, all-4-side wrap).
- ✅ **Sound-pickup effects** work via `SystemAudioMeter`.
- ✅ **USB Power Optimization** + **Start on boot** added.
- ✅ **Cyberpunk UI** across all tabs (theme in `CyberpunkTheme.swift`).
- ✅ **App icon** pipeline (PNG/SVG → `.icns` in `build.sh`).
- ✅ **Adaptive LED grid** for any strip length (`GridLayout.swift`) and
  **monitor selection** (Sync tab).
- ⚠️ Effects mapping is a best-effort table in `Pages.swift`; fine-tune if a
  device disagrees.
- ⚠️ **Single light only**; BLE/dongle/serial not supported (see repo README).

See **`docs/SESSION_HANDOFF.md`** for details and remaining polish.
