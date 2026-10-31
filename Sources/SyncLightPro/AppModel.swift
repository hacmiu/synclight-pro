import Foundation
import SwiftUI
import ServiceManagement

/// Observable app state bridging UI and device/screen subsystems.
@MainActor
final class AppModel: ObservableObject {

    // MARK: - Persistence keys

    private enum PrefKey {
        static let language = "pref.language"
        static let hue = "pref.hue"
        static let saturation = "pref.saturation"
        static let brightness = "pref.brightness"
        static let dynamicSpeed = "pref.dynamicSpeed"
        static let soundSensitivity = "pref.soundSensitivity"
        static let syncFPS = "pref.syncFPS"
        static let installationMethod = "pref.installationMethod"
        static let autoOffEnabled = "pref.autoOffEnabled"
        static let autoOffMinutes = "pref.autoOffMinutes"
        static let usbPowerOptimization = "pref.usbPowerOptimization"
        static let lastEffectType = "pref.lastEffectType"   // 2/3 = effect group, absent = none
        static let lastEffectIndex = "pref.lastEffectIndex" // 0..6
        static let hasUsedLight = "pref.hasUsedLight"       // enables auto-connect
        static let selectedDisplayID = "pref.selectedDisplayID"
    }

    @Published var language: AppLanguage = .vi { didSet { save(PrefKey.language, language.rawValue) } }
    @Published var isConnected = false
    @Published var statusText = ""

    // Live controls
    @Published var hue: Double = 0.667 { didSet { save(PrefKey.hue, hue) } }          // 0..1 (matches Apple Color .blue)
    @Published var saturation: Double = 1.0 { didSet { save(PrefKey.saturation, saturation) } } // 0..1 (0 = white/grey, 1 = full colour)
    @Published var brightness: Double = 80 { didSet { save(PrefKey.brightness, brightness) } }  // 0..100

    /// Swift Color for the current hue + saturation (full value).
    var color: Color { Color(hue: hue, saturation: saturation, brightness: 1) }
    @Published var dynamicSpeed: Double = 50 { didSet { save(PrefKey.dynamicSpeed, dynamicSpeed) } }     // 5..100
    @Published var soundSensitivity: Double = 50 { didSet { save(PrefKey.soundSensitivity, soundSensitivity) } } // 5..100

    // Sync
    @Published var syncEnabled = false
    @Published var syncFPS: Double = 30 { didSet { save(PrefKey.syncFPS, syncFPS) } }

    /// Which display the strip should mirror (CGDirectDisplayID). `nil` = main
    /// display. Persisted so a chosen monitor survives relaunch.
    @Published var selectedDisplayID: UInt32? = nil {
        didSet {
            if let id = selectedDisplayID {
                save(PrefKey.selectedDisplayID, Int(id))
            } else {
                UserDefaults.standard.removeObject(forKey: PrefKey.selectedDisplayID)
            }
            // Restart capture live if sync is running so it follows the change.
            if syncEnabled { restartSync() }
        }
    }
    /// Strip direction as seen by the viewer facing the screen:
    /// 0 = the strip runs/animates left→right, 1 = right→left. The light bar is
    /// always mounted along the vertical axis, so this only chooses which end
    /// of the bar corresponds to the top or bottom of the screen.
    @Published var installationMethod = 0 {
        didSet {
            mirrorBox.value = installationMethod == 1
            save(PrefKey.installationMethod, installationMethod)
        }
    }

    /// Thread-safe mirror flag read from the sampler's capture queue.
    private let mirrorBox = AtomicBool(false)

    // Auto off
    @Published var autoOffEnabled = false { didSet { save(PrefKey.autoOffEnabled, autoOffEnabled) } }
    @Published var autoOffMinutes: Double = 30 { didSet { save(PrefKey.autoOffMinutes, autoOffMinutes) } }

    // USB Power Optimization (mirrors the original `isLightCompression`).
    // When on, any colour whose R+G+B exceeds 255 is scaled down to keep total
    // current within the USB power budget (prevents flicker/over-current).
    @Published var usbPowerOptimization = true { didSet { save(PrefKey.usbPowerOptimization, usbPowerOptimization) } }

    // Start on boot (login item), menu-bar only, no window popup.
    @Published var startOnBoot = false

    // Device meta
    @Published var firmware = "-"
    @Published var ledCount = 0

    private let transport = HIDTransport()
    private var driver: LightDriver?
    private var sampler: ScreenColorSampler?
    private var audioMeter: SystemAudioMeter?
    private var hotPlug: HotPlugMonitor?

    /// Last effect the user applied (type 2/3, index 0..6), if any.
    /// Persisted so it can be re-applied after an auto-connect on next launch.
    private var lastEffectType: UInt8?
    private var lastEffectIndex: UInt8?

    /// Current effect type in use (2 = dynamic, 3 = sound pickup, nil = none).
    @Published private(set) var activeEffectType: UInt8?

    var l10n: L10n { L10n(lang: language) }

    // MARK: - Init / persistence

    init() {
        restoreSettings()
        setupHotPlug()
    }

    // MARK: - UserDefaults helpers

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Load the last-used settings into the published properties. Called once
    /// from `init()` before the UI observes the object, so the default-value
    /// `didSet` writers won't clobber the stored values.
    private func restoreSettings() {
        let ud = UserDefaults.standard

        if let lang = ud.string(forKey: PrefKey.language), let l = AppLanguage(rawValue: lang) {
            language = l
        }
        if ud.object(forKey: PrefKey.hue) != nil { hue = clamp(ud.double(forKey: PrefKey.hue), 0, 1) }
        if ud.object(forKey: PrefKey.saturation) != nil { saturation = clamp(ud.double(forKey: PrefKey.saturation), 0, 1) }
        if ud.object(forKey: PrefKey.brightness) != nil { brightness = clamp(ud.double(forKey: PrefKey.brightness), 0, 100) }
        if ud.object(forKey: PrefKey.dynamicSpeed) != nil { dynamicSpeed = clamp(ud.double(forKey: PrefKey.dynamicSpeed), 5, 100) }
        if ud.object(forKey: PrefKey.soundSensitivity) != nil { soundSensitivity = clamp(ud.double(forKey: PrefKey.soundSensitivity), 5, 100) }
        if ud.object(forKey: PrefKey.syncFPS) != nil { syncFPS = clamp(ud.double(forKey: PrefKey.syncFPS), 5, 60) }
        installationMethod = ud.integer(forKey: PrefKey.installationMethod)
        autoOffEnabled = ud.bool(forKey: PrefKey.autoOffEnabled)
        if ud.object(forKey: PrefKey.autoOffMinutes) != nil { autoOffMinutes = clamp(ud.double(forKey: PrefKey.autoOffMinutes), 5, 120) }
        if ud.object(forKey: PrefKey.usbPowerOptimization) != nil {
            usbPowerOptimization = ud.bool(forKey: PrefKey.usbPowerOptimization)
        }
        if ud.object(forKey: PrefKey.lastEffectType) != nil {
            let t = ud.integer(forKey: PrefKey.lastEffectType)
            if t == 2 || t == 3 {
                lastEffectType = UInt8(t)
                lastEffectIndex = UInt8(clamping: ud.integer(forKey: PrefKey.lastEffectIndex))
            }
        }
        if ud.object(forKey: PrefKey.selectedDisplayID) != nil {
            selectedDisplayID = UInt32(ud.integer(forKey: PrefKey.selectedDisplayID))
        }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    /// Whether the light had been connected in a previous session.
    private var hasUsedLight: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.hasUsedLight)
    }

    // MARK: - Hot-plug

    /// Watch for the light being plugged in / unplugged. Keeps `isConnected`
    /// accurate and auto-reconnects when the light comes back.
    private func setupHotPlug() {
        let monitor = HotPlugMonitor()
        monitor.onChanged = { [weak self] present in
            guard let self = self else { return }
            Task { @MainActor in self.handleHotPlug(present: present) }
        }
        monitor.start()
        hotPlug = monitor
    }

    private func handleHotPlug(present: Bool) {
        if present {
            // Device (re)appeared — reconnect if we were using it and aren't now.
            if !isConnected && hasUsedLight {
                autoConnectLastLight()
            }
        } else if isConnected {
            // Unplugged — drop the stale handle.
            NSLog("[HotPlug] light removed")
            stopSync()
            driver?.disconnect()
            driver = nil
            isConnected = false
            statusText = l10n.noDevice
        }
    }

    // MARK: - Connect

    func connect() {
        let d = LightDriver(transport: transport)
        if d.connect() {
            driver = d
            isConnected = true
            statusText = l10n.connected
            firmware = d.meta.firmware.isEmpty ? "-" : d.meta.firmware
            ledCount = d.meta.lampsAmount
            // Remember the light so the next launch can auto-connect.
            save(PrefKey.hasUsedLight, true)
            // Re-apply the restored settings to the freshly connected light.
            reapplyRestoredSettings()
        } else {
            isConnected = false
            statusText = l10n.noDevice
        }
    }

    /// On launch, if the light was used before and is present, connect silently.
    func autoConnectLastLight() {
        guard !isConnected, hasUsedLight else { return }
        guard !HIDTransport.enumerate().isEmpty else {
            statusText = l10n.noDevice
            return
        }
        connect()
    }

    /// Push the restored (persisted) settings to a just-connected light:
    /// brightness (+ auto-off) first, then the last effect or the last colour.
    private func reapplyRestoredSettings() {
        applyBrightness()
        if autoOffEnabled { applyAutoOff() }
        if let type = lastEffectType, let index = lastEffectIndex {
            applyEffect(type: type, index: index)
        } else {
            applyColor()
        }
    }

    func disconnect() {
        stopSync()
        driver?.disconnect()
        driver = nil
        isConnected = false
        statusText = l10n.notConnected
    }

    // MARK: - Color

    func applyColor() {
        stopAudioFeed()
        activeEffectType = nil
        // A static colour replaces any effect; forget the stored effect so an
        // auto-connect on next launch restores this colour instead.
        lastEffectType = nil
        lastEffectIndex = nil
        UserDefaults.standard.removeObject(forKey: PrefKey.lastEffectType)
        driver?.endEffectOrSync()
        var rgb = color.toRGB()
        if usbPowerOptimization {
            rgb = AppModel.compress(rgb)
        }
        driver?.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    /// USB Power Optimization: scale a colour down so R+G+B <= 255, preserving
    /// hue (original `isLightCompression` in lowLight/lowLightForSync).
    static func compress(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> (r: UInt8, g: UInt8, b: UInt8) {
        let sum = Int(c.r) + Int(c.g) + Int(c.b)
        guard sum > 255 else { return c }
        let f = Double(sum) / 255.0
        func d(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, Int(Double(v) / f)))) }
        return (d(c.r), d(c.g), d(c.b))
    }

    /// Set hue/saturation from an arbitrary picked color (e.g. the ColorPicker),
    /// keeping the two sliders in sync, then push it to the device.
    func setColor(_ newColor: Color) {
        let hsb = newColor.toHSB()
        hue = hsb.h
        saturation = hsb.s
        applyColor()
    }

    func applyBrightness() {
        // 0..100 -> 0..255 (driver clamps minimum to 5, like the original app).
        driver?.setBrightness(UInt8(max(0, min(255, (brightness / 100.0 * 255.0).rounded()))))
    }

    func applySpeed() {
        // The original app inverts the slider value before sending:
        // deviceSpeed = 100 - slider (slider low = fast, high = slow visually,
        // but "speed" here reads as 0=slow..100=fast on our UI). We keep our
        // slider meaning "faster = higher" and invert to the device value.
        driver?.setDynamicSpeed(UInt8(100 - dynamicSpeed))
    }

    func applySoundSensitivity() {
        driver?.setSoundSensitivity(UInt8(soundSensitivity))
    }

    func applyEffect(type: UInt8, index: UInt8) {
        // Leaving screen-sync if it was running so the effect can take over.
        if syncEnabled { stopSync() }
        driver?.setSoundSensitivity(UInt8(soundSensitivity))
        // Dynamic speed only affects colour effects (type 2). Sound-pickup
        // effects (type 3) follow the audio, so speed is irrelevant for them
        // (the original app hides the speed slider in pickup mode).
        if type == 2 {
            driver?.setDynamicSpeed(UInt8(100 - dynamicSpeed))
        }
        driver?.setLedEffect(type: type, index: index)
        activeEffectType = type
        // Remember the effect so auto-connect can restore it on next launch.
        lastEffectType = type
        lastEffectIndex = index
        save(PrefKey.lastEffectType, Int(type))
        save(PrefKey.lastEffectIndex, Int(index))
        // Sound-pickup effects (type 3) need audio fed from the app; tell the
        // device to use "computer rhythm" (app-fed) and start capturing system
        // audio. For other effect types stop any audio feed.
        if type == 3 {
            driver?.setComputerRhythm(1)
            startAudioFeed()
        } else {
            stopAudioFeed()
        }
    }

    /// Feed system-audio level to the device so type-3 (sound pickup) effects
    /// react to the music actually playing on the Mac.
    private func startAudioFeed() {
        stopAudioFeed()
        let meter = SystemAudioMeter()
        let sens = max(5, min(100, soundSensitivity)) / 100.0
        meter.noiseFloor = Float(0.02 - 0.017 * sens)   // 0.02 (insensitive) .. 0.003 (very sensitive)
        meter.gain = Float(0.6 + 2.4 * sens)            // 0.6 .. 3.0
        meter.onLevel = { [weak self] level in
            guard let self = self, self.activeEffectType == 3 else { return }
            let scaled = UInt16(max(0, min(65535, level * 65535.0)))
            self.driver?.setExternalAudio(level: scaled)
        }
        audioMeter = meter
        Task { [weak self] in
            do {
                try await meter.start()
            } catch {
                await MainActor.run {
                    self?.activeEffectType = nil
                    self?.statusText = self?.l10n.screenPermission ?? ""
                }
            }
        }
    }

    private func stopAudioFeed() {
        let meter = audioMeter
        audioMeter = nil
        Task { await meter?.stop() }
    }

    func applyAutoOff() {
        driver?.setAutoOff(enable: autoOffEnabled, minutes: UInt8(autoOffMinutes))
    }

    // MARK: - Start on boot (login item)

    /// Reflect the current login-item registration state into `startOnBoot`.
    func refreshStartOnBoot() {
        if #available(macOS 13.0, *) {
            startOnBoot = SMAppService.mainApp.status == .enabled
        }
    }

    /// Register/unregister the app as a login item. When enabled the app is
    /// launched at login in menu-bar-only mode (see App.swift auto-open guard).
    func setStartOnBoot(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "startOnBoot")
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                startOnBoot = SMAppService.mainApp.status == .enabled
            } catch {
                NSLog("[StartOnBoot] \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
                startOnBoot = SMAppService.mainApp.status == .enabled
            }
        } else {
            startOnBoot = enabled
        }
    }

    // MARK: - Screen sync

    private var syncFrameCount = 0

    func startSync() {
        guard isConnected else { return }
        stopAudioFeed()
        activeEffectType = nil

        // Screen Recording permission is required for the ambilight capture.
        if !CGPreflightScreenCaptureAccess() {
            NSLog("[Sync] no screen-capture permission; requesting")
            _ = CGRequestScreenCaptureAccess()
        }

        Task { [weak self] in
                guard let self = self else { return }
            let s = ScreenColorSampler()
            s.fps = self.syncFPS
            // Target display: the user's choice, else the main display.
            let displayID = self.selectedDisplayID ?? CGMainDisplayID()
            s.displayID = displayID
            // Grid dimensions: port of the original getColsAndRows, which uses
            // the device id + actual lamp count + the display aspect ratio, so
            // any strip length / monitor works (not just 112 lamps on 21:9).
            let dims = AppModel.gridDims(forDisplay: displayID, driver: self.driver)
            s.cols = dims.cols
            s.rows = dims.rows
            s.mirrorProvider = { [weak self] in self?.mirrorBox.value ?? false }
            self.syncFrameCount = 0
            s.onZones = { [weak self] zones in
                DispatchQueue.main.async {
                    guard let self = self, self.syncEnabled else { return }
                    // Per-zone USB power optimization (lowLightForSync).
                    let packed: [(r: UInt8, g: UInt8, b: UInt8)] = zones.map { z in
                        let c = (r: z.r, g: z.g, b: z.b)
                        return self.usbPowerOptimization ? AppModel.compress(c) : c
                    }
                    if self.syncFrameCount % 30 == 0 {
                        let c = packed.first ?? (0, 0, 0)
                        NSLog("[Sync] frame \(self.syncFrameCount) zones=\(packed.count) first=(\(c.r),\(c.g),\(c.b))")
                    }
                    self.syncFrameCount += 1
                    self.driver?.streamScreenZones(packed)
                }
            }
            do {
                try await s.start()
                self.sampler = s
                self.syncEnabled = true
                self.driver?.endEffectOrSync()
                NSLog("[Sync] started, capture running")
            } catch {
                NSLog("[Sync] start failed: \(error.localizedDescription)")
                self.syncEnabled = false
                self.statusText = self.l10n.screenPermission
            }
        }
    }

    func stopSync() {
        Task {
            await sampler?.stop()
            sampler = nil
        }
        syncEnabled = false
        driver?.endEffectOrSync()
    }

    /// Restart capture (e.g. after the target display changed while syncing).
    private func restartSync() {
        guard syncEnabled else { return }
        stopSync()
        // Small delay so the old SCStream fully tears down before restarting.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { self?.startSync() }
        }
    }

    /// Compute the sampling grid via `GridLayout.colsAndRows` using the device
    /// id + lamp count from the connected driver and the target display size.
    static func gridDims(forDisplay displayID: UInt32, driver: LightDriver?) -> GridLayout.Dims {
        let lamps = driver?.meta.lampsAmount ?? 112
        let id = driver?.meta.id ?? ""
        let (w, h) = displayPixelSize(displayID)
        return GridLayout.colsAndRows(deviceId: id,
                                      lampsAmount: lamps,
                                      displayWidth: w,
                                      displayHeight: h)
    }

    /// Pixel width/height of a display (falls back to points, then 16:9).
    static func displayPixelSize(_ displayID: UInt32) -> (Int, Int) {
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            let pw = mode.pixelWidth, ph = mode.pixelHeight
            if pw > 0 && ph > 0 { return (pw, ph) }
        }
        if let screen = NSScreen.screens.first(where: { matches($0, displayID) }) {
            let s = screen.frame.size
            return (Int(s.width), Int(s.height))
        }
        return (1920, 1080)
    }

    /// Match an NSScreen to a CGDirectDisplayID via its device description.
    static func matches(_ screen: NSScreen, _ id: UInt32) -> Bool {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return num?.uint32Value == id
    }

    /// The displays available to mirror, as (displayID, label) — main first.
    static func availableDisplays() -> [(id: UInt32, name: String)] {
        let mainID = CGMainDisplayID()
        var out: [(UInt32, String)] = []
        for (i, screen) in NSScreen.screens.enumerated() {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                ?? 0
            let label: String
            if id == mainID {
                label = "Main Display"
            } else {
                label = "Display \(i + 1) (\(Int(screen.frame.width))×\(Int(screen.frame.height)))"
            }
            out.append((id, label))
        }
        // Ensure the main display is first.
        out.sort { a, b in
            if a.0 == mainID { return true }
            if b.0 == mainID { return false }
            return a.0 < b.0
        }
        return out
    }
}

// MARK: - Color helpers

/// Minimal thread-safe Bool (guarded by a lock) for cross-thread flags.
final class AtomicBool {
    private let lock = NSLock()
    private var storage: Bool
    init(_ v: Bool) { storage = v }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

extension Color {
    func toRGB() -> (r: UInt8, g: UInt8, b: UInt8) {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.blue
        return (UInt8(ns.redComponent * 255), UInt8(ns.greenComponent * 255), UInt8(ns.blueComponent * 255))
    }

    /// Hue (0..1) and saturation (0..1) of the color (brightness ignored).
    func toHSB() -> (h: Double, s: Double) {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.blue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s))
    }

    /// Uppercase "#RRGGBB" string for display.
    var hexString: String {
        let rgb = toRGB()
        return String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }
}


