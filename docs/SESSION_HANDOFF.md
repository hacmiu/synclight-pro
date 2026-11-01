# Session Handoff — SyncLight Pro

> Read this first in a new session. It captures the state, the hard-won
> knowledge, and the concrete next tasks.

---

## TL;DR

The app is **feature-complete and usable**: connect + color + brightness +
effects + off + **screen ambilight** + **sound-pickup** all work on real
hardware, with a **cyberpunk UI**, **USB Power Optimization**, **Start on boot**,
a **bundled app icon**, an **adaptive LED grid** (any strip length),
**monitor selection**, and **multi-light control** (several lights, each bound to
its own display with its own settings/effects). Remaining work is BLE.

---

## What was done in the LATEST session (UI + features)

1. **Cyberpunk UI** (`CyberpunkTheme.swift`): dark indigo base, neon accents
   (cyan/magenta/purple/yellow), `.neonText` / `.cyberPanel` modifiers,
   `CyberButtonStyle`, `CyberSectionTitle`, plus custom `CyberSegmented` and
   `CyberDropdown` (effect-group switch, strip direction, language picker).
   `ContentView` = neon header/sidebar/footer shell; all four pages restyled.
2. **USB Power Optimization** (`AppModel.usbPowerOptimization`, default on):
   mirrors the original `isLightCompression` — scales any colour with
   `R+G+B > 255` down (hue-preserving) to stay within USB current. Applied to
   the static colour and **per-zone** in ambilight (`AppModel.compress`).
3. **Start on boot** (`AppModel.setStartOnBoot` via `SMAppService.mainApp`, macOS
   13+): when enabled, the app launches menu-bar-only (accessory, no window);
   toggle syncs from `SMAppService.mainApp.status` at launch.
4. **Ambilight wrap-around**: `ScreenColorSampler` yields per-zone colours over
   all four screen edges; `LightDriver.streamScreenZones` drives them.
   `installationMethod` flips direction.
5. **App icon pipeline**: `make_icon.sh` turns `Resources/SyncLight Pro.png`
   (preferred, transparent) or the `.svg` into `Contents/Resources/AppIcon.icns`
   and sets `CFBundleIconFile=AppIcon`. `build.sh` calls it when a source exists.
   (Tried transparent-padding and a rounded-plate variant — both made Finder's
   list-view backing more obvious, so **reverted** to the raw PNG.)

---

## What was done in the FIRST session

### 1. Reverse-engineered the HID protocol (see `PROTOCOL.md`)
The original app is Electron; its device code lives in
`app_extracted/.webpack/main/index.js`. The USB light uses **simple "RB"
frames**, NOT the 20-byte MAC-based template that the BLE path uses.

Frame: `"RB" | len | seq | action | payload… | checksum`
- `len` = total bytes
- `seq` = rolling 1..254
- `checksum` = sum(all bytes before) % 256

Key opcodes: `setSectionLED=134`, `setBrightness=135`, `setLedEffect=133`,
`setSyncScreen=128`, `readDeviceInfo=130`, `setOpenURL=147`, `setAutoOff=137`,
`setDynamicSpeed=138`, `setSoundSensitivity=139`.

### 2. Rewrote the three core files
- **`RobobloqProtocol.swift`** — frame builders matching the real HID protocol
  (removed the MAC/template approach).
- **`HIDTransport.swift`** — native IOKit transport (the hard part, see below).
- **`LightDriver.swift`** — connect() reads real metadata, then sends
  `setOpenUrl(0)`; all command methods use the new frames. Falls back to
  `lamps=112` if the info read times out.
- **`AppModel.swift`** — removed the non-existent `setSyncScreen(on:)` calls.

### 3. Solved the "device opens but does nothing" problem

This was the crux. Symptoms: `IOHIDDeviceSetReport` returned `kIOReturnSuccess`
but the lamp never changed; and input reports (device info) never arrived —
while the *same* thing worked in Node (`node-hid`/hidapi).

**Root causes & fixes (ALL are required)** — also in `DEV_NOTES.md`:

1. **Open the device from the IOService registry**, not from
   `IOHIDManagerCopyDevices`. Use `IOServiceGetMatchingServices(kIOHIDDeviceKey)`
   + `IOHIDDeviceCreate(kCFAllocatorDefault, entry)`. Pick the vendor interface
   `usagePage == 0xFF00 && usage == 1`.
2. **Schedule the device on a CUSTOM `CFRunLoopMode`** (e.g.
   `SYNCLIGHT_HID_<ptr>`), *not* `defaultMode`, and pump it with
   `CFRunLoopRunInMode(mode, …)` on a dedicated background thread. This is exactly
   what hidapi does (`HIDAPI_<ptr>`). `defaultMode` did **not** deliver reports.
3. **Input-report buffer = 64 bytes** (matches `MaxInputReportSize`); keep the
   pointer alive for the lifetime of the device.
4. **Write the raw frame WITHOUT a leading report-id byte.** hidapi's
   `set_report` strips `data[0]` when report id is 0, so it sends the frame bytes
   as-is with `reportID=0`. So call
   `IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, frame, frame.count)`.
5. **Color payload must include `lamps`:**
   `[1, r, g, b, lamps, lamps+1, 0, 0, 0, 254]` (action 134). The short form
   `[1,r,g,b,254]` does **not** light the strip.

After all five: metadata reads back correctly and colors change.

### 4. Verified working
- `swiftc` end-to-end driver test: RED→GREEN→BLUE→WHITE→OFF all lit.
- Meta: `id=000503, uuid=cdab74531abc5bbb, fw=1.7.3, lamps=112, display=34`.
- `.app` bundle builds via `./build.sh release`.

---

## Known-good debugging helpers (already verified)

A C reference that works (hidapi, from node_modules) was used to prove the
protocol; the Swift transport now matches it byte-for-byte. If something
regresses, compare against a Node script:

```js
// /tmp/nhid style
const HID = require('node-hid');
const dev = new HID.HID(HID.devices().filter(x=>x.manufacturer==='ROBOBLOQ')[0].path);
function ck(b){return b.reduce((a,x)=>a+x,0)%256;}
function setSectionLED(payload){ /* RB,len,seq,134,payload,ck */ }
dev.write(Buffer.concat([Buffer.from([0]), setSectionLED([1,255,0,0,112,113,0,0,0,254])]));
```

If Node lights the lamp but Swift doesn't → re-check the 5 requirements above.

---

## DONE (previously listed as next tasks)

- ✅ **Screen Sync / ambilight** validated on hardware; now wraps all four edges
  via per-zone sampling (`ScreenColorSampler` + `LightDriver.streamScreenZones`).
- ✅ **Sound-pickup effects** driven by `SystemAudioMeter`.
- ✅ **USB Power Optimization** (colour compression) added.
- ✅ **Start on boot** (menu-bar only) added.
- ✅ **Cyberpunk UI** applied to every tab.
- ✅ **App icon** bundled via `make_icon.sh`.
- ✅ **Adaptive LED grid** — `GridLayout.swift` ports the original Electron
  `getAspectRatio` + `getColsAndRows`; `AppModel.gridDims(forDisplay:driver:)`
  uses the real `id`/`lampsAmount` from `LightDriver.meta` + display pixel size,
  so any strip length works (no longer hard-coded 16×9 for 112 lamps).
- ✅ **Monitor selection** — `ScreenColorSampler.displayID` targets the chosen
  display; `AppModel.selectedDisplayID` (persisted) + SyncPage dropdown +
  `restartSync()` on change. (`availableDisplays()` lists screens, main first.)
- ✅ **Multi-light control (Part C)** — see the section below.
- ✅ **Wake-from-sleep refresh** — HID reopen + sampler/audio restart on wake.

## Multi-light control (Part C) — DONE

`AppModel` now holds `[LightDevice]` (new `LightDevice.swift`) instead of a
single `driver` + `sampler`. Each `LightDevice` owns its own `HIDTransport`,
`LightDriver`, `ScreenColorSampler`, `displayID`, **its own per-light
screen-sync toggle (`syncEnabled`)**, and its **own** settings (hue,
saturation, brightness, speed, sensitivity, direction, auto-off, last effect).
Highlights:

- **`HIDTransport`** — added `enumerateEntries()` (each device + its live
  registry entry), `openSpecific(_:)` (open one specific entry, consuming the
  handle) and `releaseEntry(for:)`. `openFirstLight()` is now a thin wrapper.
  The five hard DEV_NOTES requirements are unchanged (IORegistry open, custom
  `SYNCLIGHT_HID_<ptr>` run-loop mode, 64-byte input buffer, report-id-0 write).
  `DeviceInfo` gained `locationID` (`kIOHIDLocationIDKey`) as an identity key.
- **`LightDriver`** — added `connectOnOpenedTransport()` (connect assuming the
  transport already opened a specific device) and `identityKey` (uuid-based).
- **`AppModel`** — `connect()` (first free light), `connectAll()` (every
  enumerated light), per-light `disconnect(_:)`; **all** pages operate on the
  **selected** light (`selectedDevice`, `select(_:)`). **Screen-sync is
  per-light**: `setSync(_:for:)` / `setSync(_:)` toggle `device.syncEnabled` and
  start/stop that light's own sampler toward its own display. Choosing a static
  colour (`applyColor`) or an effect (`applyEffect`) turns sync **off for that
  selected light only** (other lights unaffected). `setDisplay(_:for:)` restarts
  a single light's sampler live. Hot-plug prunes only the removed light by
  locationID. `syncActive` is a convenience for the menu icon.
- **Persistence** — per-light settings + display binding + `syncEnabled` are
  stored as a JSON map in `pref.perLightSettings`, keyed by `uuid:` (once
  reported) else `loc:<locationID>`. First-run adopts the legacy
  `pref.selectedDisplayID`.
- **UI** — the window **header** has a light **dropdown** (shown when ≥2 lights)
  that selects which light *all* pages edit. SyncPage shows a per-light sync
  toggle for the selected light, a sampling-FPS slider, and one **card per
  connected light** (name, LED count, its own sync switch, display dropdown,
  strip direction, disconnect). Color / Effects / Settings still show a small
  `LightPicker` caption (read-only) so you know which light you're editing, and
  their controls bind to the selected light. Header button is Connect /
  Disconnect all; footer shows the connected-light count when >1. Single-light
  behavior is unchanged.

## Wake-from-sleep refresh — DONE

After sleep, IOKit can silently invalidate the `IOHIDDevice` handle (writes
return success but do nothing, input reports stop) and ScreenCaptureKit streams
(`SCStream` for ambilight + the audio meter) die — which made the app look
frozen. Fix:

- **`AppModel`** observes `NSWorkspace.didWakeNotification` +
  `screensDidWakeNotification` (`setupWakeObserver`, `@Sendable` handler hops to
  the main actor) and calls **`handleWake()`**, which:
  1. re-opens any light whose `HIDTransport.isAlive` is false via
     `HIDTransport.reopen()` (same registry `locationID`); lights that are truly
     gone are torn down,
  2. restarts each light's sampler (via `restartSampler`, small delay so
     ScreenCaptureKit is ready) when syncing, else re-applies the current
     colour/effect (`reapplyCurrentState`) and re-creates the sound-pickup audio
     feed if a type-3 effect was active.
- **`HIDTransport`** gained `locationID` (set on open), `isAlive` (registry
  presence check for the same location) and `reopen()`.
- **Race guard:** `handlingWake` blocks hot-plug add-events for ~1.5 s so the
  wake refresh isn't raced by a `connectAll()` from the re-enumeration.

## REMAINING (roadmap)

1. **BLE / dongle / serial support** — needs the 20-byte MAC frame path
   (`PROTOCOL.md`, builder 62564). Not implemented.
2. **Fine-tune the effects table** in `Pages.swift`
   (`applyEffect(type:index:)` → `setLedEffect`, action 133). Confirm each entry
   maps to the intended on-device effect; adjust `type`/`index` if a device
   disagrees.
3. **Multi-light polish** — e.g. reorderable/renamable lights, an optional
   "apply to all lights" shortcut, per-light screen-sync FPS. Not started.
4. **Cleanup:** remove debug `probe*.swift` scripts once satisfied.
5. **Packaging:** proper `Info.plist` versioning, notarized release.

---

## Files you'll touch most

- `Sources/SyncLightPro/HIDTransport.swift` — transport (be careful, see DEV_NOTES)
- `Sources/SyncLightPro/RobobloqProtocol.swift` — frame formats
- `Sources/SyncLightPro/ScreenColorSampler.swift` — ambilight source
- `Sources/SyncLightPro/LightDevice.swift` — one light = driver + sampler + settings
- `Sources/SyncLightPro/Pages.swift` — pages per-light; effects table lives here
