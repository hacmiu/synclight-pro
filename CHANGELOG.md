# Changelog

All notable changes to SyncLight Pro are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [1.1] — 2026

Multi-light release. This version turns the single-light app into a full
multi-light controller with per-light state, a header light selector, sleep/wake
resilience, and richer effect control.

### Added
- **Multi-light support** — connect and drive several light bars at once. Each
  light is an independent controller with its **own** settings (hue, saturation,
  brightness, dynamic speed, sound sensitivity, strip direction, auto-off, last
  effect) and its **own** target display. Per-light settings and display
  bindings are persisted (keyed by device UUID, falling back to USB location).
- **Header light dropdown** — when 2+ lights are connected, a dropdown in the
  window header selects which light the Color / Effects / Sync / Settings pages
  edit. Single-light behavior is unchanged (no dropdown shown).
- **Per-light screen sync** — each light has its own sync toggle that starts and
  stops just its own sampler toward its own monitor. The Sync page shows one
  card per light (name, LED count, its own sync switch, display dropdown, strip
  direction, disconnect).
- **Apply to all lights** — a global "All lights" switch (next to the header
  dropdown) makes colour / effect / brightness / speed / sensitivity / auto-off
  commands apply to every connected light at once. Sliders broadcast the
  selected light's value to all.
- **Brightness for effects** — new brightness slider on the **Effects** page.
  When an effect is running, a brightness change re-issues the effect frame so
  the USB light actually commits the new level (see `LightDriver.setBrightnessInEffect`).
- **Wake-from-sleep refresh** — the app observes system wake
  (`didWakeNotification` / `screensDidWakeNotification`) and:
  1. re-opens any HID handle IOKit invalidated during sleep (same registry
     location), dropping lights that are truly gone;
  2. restarts each light's screen sampler (ScreenCaptureKit streams do not
     survive sleep);
  3. re-applies each light's current colour/effect and re-creates the
     sound-pickup audio feed when needed.

### Changed
- Choosing a static colour or an effect now turns screen-sync **off for the
  selected light only** (previously the sync toggle was global). Other lights
  keep mirroring.
- The Color / Effects / Settings pages now show a small read-only "editing:
  <light>" caption instead of an interactive picker; selection lives in the
  header dropdown.
- Version bumped to **1.1** (Info.plist `CFBundleShortVersionString` /
  `CFBundleVersion`).
- License copyright updated to **2026**.

### Fixed
- HID handles and capture streams no longer appear frozen after the Mac wakes
  from sleep.
- Race guard (`handlingWake`) prevents hot-plug auto-reconnect from racing the
  wake refresh during USB re-enumeration.
- Sampler closures use a thread-safe frame counter and avoid redundant
  `guard let self` captures.

## [1.0.0] — 2025

Initial native release — a SwiftUI macOS app that controls Robobloq USB light
bars over native IOKit HID (reverse-engineered "RB" protocol).

### Added
- Native HID transport (`HIDTransport`) with the five hard-won requirements for
  reliable reads/writes (IORegistry open, custom run-loop mode, 64-byte input
  buffer, report-id-0 writes, colour payload with lamp count).
- Static colour, brightness, dynamic ("幻彩") and sound-pickup ("拾音") effects.
- Real-time **screen ambilight** that wraps all four screen edges, with monitor
  selection and strip direction.
- **USB Power Optimization** (colour compression to stay within USB current).
- **Start on boot** (login item, menu-bar only on macOS 13+).
- Adaptive LED grid (any strip length) via `GridLayout`.
- Cyberpunk UI (neon header/sidebar/footer, custom segmented + dropdown
  controls), bundled app icon.
