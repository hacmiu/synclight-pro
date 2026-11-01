import Foundation
import SwiftUI
import AppKit
import ServiceManagement

/// Observable app state bridging UI and device/screen subsystems.
///
/// Multi-light (Part C): the app now holds `[LightDevice]`. Each light has its
/// own settings + its own screen sampler bound to one display. The Color /
/// Effects / Settings pages act on the *selected* light; the sync toggle is
/// global and drives every light's sampler toward that light's display.
@MainActor
final class AppModel: ObservableObject {

    // MARK: - Persistence keys

    private enum PrefKey {
        static let language = "pref.language"
        static let syncFPS = "pref.syncFPS"
        static let usbPowerOptimization = "pref.usbPowerOptimization"
        static let hasUsedLight = "pref.hasUsedLight"            // enables auto-connect
        static let selectedDisplayID = "pref.selectedDisplayID"  // legacy single-light
        /// Per-light settings map: persistenceKey -> encoded LightSettings.
        static let perLight = "pref.perLightSettings"
    }

    @Published var language: AppLanguage = .vi { didSet { save(PrefKey.language, language.rawValue) } }
    @Published var statusText = ""

    // Global settings (app-wide)
    @Published var syncFPS: Double = 30 { didSet { save(PrefKey.syncFPS, syncFPS) } }
    @Published var syncEnabled = false
    @Published var usbPowerOptimization = true { didSet { save(PrefKey.usbPowerOptimization, usbPowerOptimization) } }
    @Published var startOnBoot = false

    // MARK: - Multi-light state

    /// All known lights (connected or not). Persisted display bindings and
    /// settings are re-applied on connect.
    @Published var devices: [LightDevice] = []

    /// Id of the light the Color/Effects/Settings pages currently edit.
    @Published var selectedLightID: UUID?

    /// The selected light, if any (falls back to the first light).
    var selectedDevice: LightDevice? {
        if let id = selectedLightID, let d = devices.first(where: { $0.id == id }) { return d }
        return devices.first
    }

    /// True when at least one light is connected (drives header badge/menu).
    var isConnected: Bool { devices.contains { $0.isConnected } }

    /// Convenience for the footer: firmware + LED count of the selected light.
    var firmware: String { selectedDevice?.firmware ?? "-" }
    var ledCount: Int { selectedDevice?.ledCount ?? 0 }

    private var audioMeters: [UUID: SystemAudioMeter] = [:]
    private var hotPlug: HotPlugMonitor?
    /// Guard so hot-plug callbacks (which also fire on wake re-enumeration)
    /// don't race with handleWake()'s own reopen logic.
    private var handlingWake = false

    var l10n: L10n { L10n(lang: language) }

    // MARK: - Init / persistence

    init() {
        restoreSettings()
        setupHotPlug()
        setupWakeObserver()
    }

    /// Observe system wake so we can refresh HID handles + restart samplers,
    /// which otherwise die across sleep and make the app look frozen.
    private var wakeObservers: [NSObjectProtocol] = []

    private func setupWakeObserver() {
        let center = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            // Hop to the main actor; don't touch self on the notifier thread.
            Task { @MainActor [weak self] in self?.handleWake() }
        }
        wakeObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                 object: nil, queue: .main, using: handler))
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                 object: nil, queue: .main, using: handler))
    }

    // NOTE: no deinit — AppModel lives for the whole app lifetime and its
    // block observers keep only a weak reference to self, so this is not a leak.

    // MARK: - UserDefaults helpers

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func restoreSettings() {
        let ud = UserDefaults.standard
        if let lang = ud.string(forKey: PrefKey.language), let l = AppLanguage(rawValue: lang) {
            language = l
        }
        if ud.object(forKey: PrefKey.syncFPS) != nil { syncFPS = clamp(ud.double(forKey: PrefKey.syncFPS), 5, 60) }
        if ud.object(forKey: PrefKey.usbPowerOptimization) != nil {
            usbPowerOptimization = ud.bool(forKey: PrefKey.usbPowerOptimization)
        }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    private var hasUsedLight: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.hasUsedLight)
    }

    // MARK: - Per-light settings persistence

    /// Codable snapshot of one light's settings.
    private struct LightSettings: Codable {
        var displayID: UInt32?
        var hue: Double
        var saturation: Double
        var brightness: Double
        var dynamicSpeed: Double
        var soundSensitivity: Double
        var installationMethod: Int
        var autoOffEnabled: Bool
        var autoOffMinutes: Double
        var lastEffectType: UInt8?
        var lastEffectIndex: UInt8?
    }

    private func loadPerLightMap() -> [String: LightSettings] {
        guard let data = UserDefaults.standard.data(forKey: PrefKey.perLight),
              let map = try? JSONDecoder().decode([String: LightSettings].self, from: data) else {
            return [:]
        }
        return map
    }

    private func storePerLightMap(_ map: [String: LightSettings]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: PrefKey.perLight)
        }
    }

    /// Persist one light's current settings under its identity key.
    func persist(_ device: LightDevice) {
        var map = loadPerLightMap()
        map[device.persistenceKey] = LightSettings(
            displayID: device.displayID,
            hue: device.hue,
            saturation: device.saturation,
            brightness: device.brightness,
            dynamicSpeed: device.dynamicSpeed,
            soundSensitivity: device.soundSensitivity,
            installationMethod: device.installationMethod,
            autoOffEnabled: device.autoOffEnabled,
            autoOffMinutes: device.autoOffMinutes,
            lastEffectType: device.lastEffectType,
            lastEffectIndex: device.lastEffectIndex
        )
        storePerLightMap(map)
    }

    /// Apply persisted settings (if any) onto a freshly-connected light. Falls
    /// back to the legacy single-light display selection on first run.
    private func restoreSettings(for device: LightDevice) {
        let map = loadPerLightMap()
        if let s = map[device.persistenceKey] {
            device.hue = s.hue
            device.saturation = s.saturation
            device.brightness = s.brightness
            device.dynamicSpeed = s.dynamicSpeed
            device.soundSensitivity = s.soundSensitivity
            device.installationMethod = s.installationMethod
            device.autoOffEnabled = s.autoOffEnabled
            device.autoOffMinutes = s.autoOffMinutes
            device.lastEffectType = s.lastEffectType
            device.lastEffectIndex = s.lastEffectIndex
            device.displayID = s.displayID
        } else if let legacy = UserDefaults.standard.object(forKey: PrefKey.selectedDisplayID) as? Int,
                  legacy != 0 {
            device.displayID = UInt32(legacy)
        }
        device.mirrorBox.value = device.installationMethod == 1
    }

    // MARK: - Hot-plug

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
            // Ignore add-events while a wake refresh is in flight — handleWake()
            // re-opens the same lights itself and reconnecting here would race.
            if handlingWake { return }
            if hasUsedLight { tryAutoReconnectMissing() }
        } else {
            pruneDisconnectedLights()
        }
    }

    private func pruneDisconnectedLights() {
        let presentLocations = Set(HIDTransport.enumerate().map { $0.locationID })
        var removedAny = false
        for device in devices where device.isConnected {
            if !presentLocations.contains(device.locationID) {
                teardownLight(device)
                removedAny = true
            }
        }
        if removedAny {
            if !devices.contains(where: { $0.isConnected }) {
                stopSync()
                statusText = l10n.noDevice
            }
            objectWillChange.send()
        }
    }

    // MARK: - Connect

    /// Connect the first available light not already open (single-light flow /
    /// header "Connect"). Adds it to `devices`.
    func connect() {
        let entries = HIDTransport.enumerateEntries()
        guard !entries.isEmpty else { statusText = l10n.noDevice; return }
        let openLocations = Set(devices.filter { $0.isConnected }.map { $0.locationID })
        let candidates = entries.filter { !openLocations.contains($0.info.locationID) }
        // Prefer a vendor interface entry; fall back to any, then the first.
        let chosen = candidates.first(where: { $0.info.usagePage == 0xFF00 && $0.info.usage == 1 })
            ?? candidates.first
            ?? entries.first(where: { $0.info.usagePage == 0xFF00 && $0.info.usage == 1 })
            ?? entries[0]
        for e in entries where e.entry != chosen.entry { HIDTransport.releaseEntry(for: e) }
        addLight(from: chosen)
    }

    /// Connect ALL enumerated lights not already open. Header "Connect all".
    func connectAll() {
        let entries = HIDTransport.enumerateEntries()
        guard !entries.isEmpty else { statusText = l10n.noDevice; return }
        let openLocations = Set(devices.filter { $0.isConnected }.map { $0.locationID })
        var byLocation: [Int: [HIDTransport.MatchedEntry]] = [:]
        for e in entries { byLocation[e.info.locationID, default: []].append(e) }

        for (loc, group) in byLocation {
            if openLocations.contains(loc) {
                for e in group { HIDTransport.releaseEntry(for: e) }
                continue
            }
            let chosen = group.first(where: { $0.info.usagePage == 0xFF00 && $0.info.usage == 1 }) ?? group[0]
            for e in group where e.entry != chosen.entry { HIDTransport.releaseEntry(for: e) }
            addLight(from: chosen)
        }
        if !devices.contains(where: { $0.isConnected }) { statusText = l10n.noDevice }
    }

    /// Build a LightDevice from a matched entry, open it, restore settings and
    /// (if used before) push them to the hardware.
    private func addLight(from entry: HIDTransport.MatchedEntry) {
        let transport = HIDTransport()
        guard transport.openSpecific(entry) else {
            statusText = l10n.noDevice
            return
        }
        let driver = LightDriver(transport: transport)
        guard driver.connectOnOpenedTransport() else {
            transport.close()
            statusText = l10n.noDevice
            return
        }
        let index = devices.count + 1
        let device = LightDevice(transport: transport, driver: driver,
                                 locationID: entry.info.locationID,
                                 displayName: "\(l10n.light) \(index)")
        device.isConnected = true
        restoreSettings(for: device)
        devices.append(device)
        if selectedLightID == nil { selectedLightID = device.id }
        save(PrefKey.hasUsedLight, true)
        statusText = l10n.connected
        objectWillChange.send()

        reapplyRestoredSettings(for: device)
        if syncEnabled { startSampler(for: device) }
    }

    /// On launch, auto-connect lights we've used before that are present.
    func autoConnectLastLight() {
        guard hasUsedLight else { return }
        guard !HIDTransport.enumerate().isEmpty else {
            statusText = l10n.noDevice
            return
        }
        connectAll()
    }

    private func tryAutoReconnectMissing() {
        guard !HIDTransport.enumerate().isEmpty else { return }
        connectAll()
    }

    private func reapplyRestoredSettings(for device: LightDevice) {
        device.driver.setBrightness(UInt8(max(0, min(255, (device.brightness / 100.0 * 255.0).rounded()))))
        if device.autoOffEnabled {
            device.driver.setAutoOff(enable: true, minutes: UInt8(device.autoOffMinutes))
        }
        if let type = device.lastEffectType, let index = device.lastEffectIndex {
            device.driver.setSoundSensitivity(UInt8(device.soundSensitivity))
            if type == 2 { device.driver.setDynamicSpeed(UInt8(100 - device.dynamicSpeed)) }
            let rgb = AppModel.compressIfNeeded(device.color.toRGB(), usbPowerOptimization)
            device.driver.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
            device.driver.setLedEffect(type: type, index: index)
            device.activeEffectType = type
            if type == 3 { device.driver.setComputerRhythm(1); startAudioFeed(for: device) }
        } else {
            let rgb = AppModel.compressIfNeeded(device.color.toRGB(), usbPowerOptimization)
            device.driver.endEffectOrSync()
            device.driver.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        stopSync()
        for device in devices { teardownLight(device) }
        devices.removeAll()
        selectedLightID = nil
        statusText = l10n.notConnected
        objectWillChange.send()
    }

    func disconnect(_ device: LightDevice) {
        removeSampler(for: device)
        teardownLight(device)
        devices.removeAll { $0 === device }
        if selectedLightID == device.id { selectedLightID = devices.first?.id }
        if !devices.contains(where: { $0.isConnected }) { statusText = l10n.notConnected }
        objectWillChange.send()
    }

    private func teardownLight(_ device: LightDevice) {
        device.sampler?.onZones = nil
        stopAudioFeed(for: device)
        device.driver.disconnect()
        device.isConnected = false
    }

    // MARK: - Selection

    func select(_ device: LightDevice) {
        selectedLightID = device.id
        objectWillChange.send()
    }

    // MARK: - Color / Brightness / settings (per selected light)

    func applyColor() {
        guard let device = selectedDevice else { return }
        stopAudioFeed(for: device)
        device.activeEffectType = nil
        device.lastEffectType = nil
        device.lastEffectIndex = nil
        device.driver.endEffectOrSync()
        var rgb = device.color.toRGB()
        if usbPowerOptimization { rgb = AppModel.compress(rgb) }
        device.driver.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
        persist(device)
        objectWillChange.send()
    }

    /// Set hue/saturation from a picked color on the selected light.
    func setColor(_ newColor: Color) {
        guard let device = selectedDevice else { return }
        let hsb = newColor.toHSB()
        device.hue = hsb.h
        device.saturation = hsb.s
        applyColor()
    }

    /// USB Power Optimization: scale a colour down so R+G+B <= 255.
    static func compress(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> (r: UInt8, g: UInt8, b: UInt8) {
        let sum = Int(c.r) + Int(c.g) + Int(c.b)
        guard sum > 255 else { return c }
        let f = Double(sum) / 255.0
        func d(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, Int(Double(v) / f)))) }
        return (d(c.r), d(c.g), d(c.b))
    }

    private static func compressIfNeeded(_ c: (r: UInt8, g: UInt8, b: UInt8), _ on: Bool) -> (r: UInt8, g: UInt8, b: UInt8) {
        on ? compress(c) : c
    }

    func applyBrightness() {
        guard let device = selectedDevice else { return }
        device.driver.setBrightness(UInt8(max(0, min(255, (device.brightness / 100.0 * 255.0).rounded()))))
        persist(device)
    }

    func applySpeed() {
        guard let device = selectedDevice else { return }
        device.driver.setDynamicSpeed(UInt8(100 - device.dynamicSpeed))
        persist(device)
    }

    func applySoundSensitivity() {
        guard let device = selectedDevice else { return }
        device.driver.setSoundSensitivity(UInt8(device.soundSensitivity))
        persist(device)
    }

    func applyEffect(type: UInt8, index: UInt8) {
        guard let device = selectedDevice else { return }
        if syncEnabled { stopSampler(for: device) }
        device.driver.setSoundSensitivity(UInt8(device.soundSensitivity))
        if type == 2 { device.driver.setDynamicSpeed(UInt8(100 - device.dynamicSpeed)) }
        device.driver.setLedEffect(type: type, index: index)
        device.activeEffectType = type
        device.lastEffectType = type
        device.lastEffectIndex = index
        if type == 3 {
            device.driver.setComputerRhythm(1)
            startAudioFeed(for: device)
        } else {
            stopAudioFeed(for: device)
        }
        persist(device)
        objectWillChange.send()
    }

    func applyAutoOff() {
        guard let device = selectedDevice else { return }
        device.driver.setAutoOff(enable: device.autoOffEnabled, minutes: UInt8(device.autoOffMinutes))
        persist(device)
    }

    /// Change which display the selected light mirrors (persisted per light).
    func setDisplay(_ displayID: UInt32?, for device: LightDevice) {
        device.displayID = displayID
        persist(device)
        if syncEnabled { restartSampler(for: device) }
        objectWillChange.send()
    }

    // MARK: - Audio feed (per light)

    private func startAudioFeed(for device: LightDevice) {
        stopAudioFeed(for: device)
        let meter = SystemAudioMeter()
        let sens = max(5, min(100, device.soundSensitivity)) / 100.0
        meter.noiseFloor = Float(0.02 - 0.017 * sens)
        meter.gain = Float(0.6 + 2.4 * sens)
        meter.onLevel = { [weak device] level in
            guard let device = device, device.activeEffectType == 3 else { return }
            let scaled = UInt16(max(0, min(65535, level * 65535.0)))
            device.driver.setExternalAudio(level: scaled)
        }
        audioMeters[device.id] = meter
        Task {
            do { try await meter.start() }
            catch {
                await MainActor.run {
                    device.activeEffectType = nil
                    self.statusText = self.l10n.screenPermission
                }
            }
        }
    }

    private func stopAudioFeed(for device: LightDevice) {
        let meter = audioMeters.removeValue(forKey: device.id)
        Task { await meter?.stop() }
    }

    // MARK: - Start on boot (login item)

    func refreshStartOnBoot() {
        if #available(macOS 13.0, *) {
            startOnBoot = SMAppService.mainApp.status == .enabled
        }
    }

    func setStartOnBoot(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "startOnBoot")
        if #available(macOS 13.0, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                startOnBoot = SMAppService.mainApp.status == .enabled
            } catch {
                NSLog("[StartOnBoot] \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
                startOnBoot = SMAppService.mainApp.status == .enabled
            }
        } else {
            startOnBoot = enabled
        }
    }

    // MARK: - Screen sync (per-light sampler)

    /// Start one sampler per connected light (each toward its own display).
    func startSync() {
        let connected = devices.filter { $0.isConnected }
        guard !connected.isEmpty else { return }
        for device in connected { stopAudioFeed(for: device); device.activeEffectType = nil }

        if !CGPreflightScreenCaptureAccess() {
            NSLog("[Sync] no screen-capture permission; requesting")
            _ = CGRequestScreenCaptureAccess()
        }

        for device in connected { startSampler(for: device) }
        syncEnabled = true
    }

    private func startSampler(for device: LightDevice) {
        let s = ScreenColorSampler()
        s.fps = syncFPS
        let displayID = device.displayID ?? CGMainDisplayID()
        s.displayID = displayID
        let dims = AppModel.gridDims(forDisplay: displayID, driver: device.driver)
        s.cols = dims.cols
        s.rows = dims.rows
        s.mirrorProvider = { [weak device] in device?.mirrorBox.value ?? false }

        let counter = FrameCounter()
        s.onZones = { [weak self, weak device] zones in
            DispatchQueue.main.async {
                guard let device = device else { return }
                let compress = self?.usbPowerOptimization ?? true
                guard self?.syncEnabled ?? false else { return }
                let packed: [(r: UInt8, g: UInt8, b: UInt8)] = zones.map { z in
                    let c = (r: z.r, g: z.g, b: z.b)
                    return compress ? AppModel.compress(c) : c
                }
                let n = counter.next()
                if n % 30 == 0 {
                    let c = packed.first ?? (0, 0, 0)
                    NSLog("[Sync] light=\(device.displayName) frame \(n) zones=\(packed.count) first=(\(c.r),\(c.g),\(c.b))")
                }
                device.driver.streamScreenZones(packed)
            }
        }
        Task { [weak self, weak device] in
            do {
                try await s.start()
                guard let device = device else { return }
                device.sampler = s
                device.driver.endEffectOrSync()
                NSLog("[Sync] started for \(device.displayName)")
            } catch {
                NSLog("[Sync] start failed for \(device?.displayName ?? "?"): \(error.localizedDescription)")
                self?.statusText = self?.l10n.screenPermission ?? ""
            }
        }
    }

    func stopSync() {
        for device in devices {
            if let s = device.sampler {
                s.onZones = nil
                Task { await s.stop() }
                device.sampler = nil
            }
            device.driver.endEffectOrSync()
        }
        syncEnabled = false
    }

    private func removeSampler(for device: LightDevice) {
        if let s = device.sampler {
            s.onZones = nil
            Task { await s.stop() }
            device.sampler = nil
        }
    }

    private func stopSampler(for device: LightDevice) {
        removeSampler(for: device)
        device.driver.endEffectOrSync()
    }

    private func restartSampler(for device: LightDevice) {
        removeSampler(for: device)
        Task { [weak self, weak device] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                guard let self = self, let device = device, self.syncEnabled else { return }
                self.startSampler(for: device)
            }
        }
    }

    // MARK: - Wake from sleep

    /// Called when the Mac wakes from sleep. After sleep the HID handles and
    /// ScreenCaptureKit streams can be dead (writes silently no-op, capture
    /// stops feeding frames) which made the app appear frozen. We:
    ///   1. re-open any HID device whose handle is no longer alive,
    ///   2. restart every sampler (SCStream does not survive sleep),
    ///   3. re-apply each light's current colour/effect so the strip is correct.
    /// Lights whose hardware truly went away are torn down.
    func handleWake() {
        guard !handlingWake else { return }
        handlingWake = true
        defer {
            // Brief grace period: let any in-flight hot-plug add-events that were
            // queued during wake settle before we re-enable auto-reconnect.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.handlingWake = false
            }
        }
        NSLog("[Wake] refreshing lights after sleep")
        let connected = devices.filter { $0.isConnected }
        guard !connected.isEmpty else { return }

        for device in connected {
            // 1) Re-open the HID handle if IOKit invalidated it during sleep.
            if !device.transport.isAlive {
                if device.transport.reopen() {
                    NSLog("[Wake] reopened HID for \(device.displayName)")
                } else {
                    NSLog("[Wake] HID gone for \(device.displayName); dropping it")
                    teardownLight(device)
                    continue
                }
            }
        }
        // Remove any lights we just dropped.
        devices.removeAll { !$0.isConnected }

        // 2) Restart samplers (SCStream dies across sleep) and 3) re-apply state.
        for device in devices where device.isConnected {
            if syncEnabled {
                // restartSampler delays a moment so ScreenCaptureKit is ready
                // after wake before we re-open capture.
                restartSampler(for: device)
            } else {
                removeSampler(for: device)
                reapplyCurrentState(for: device)
            }
        }
        objectWillChange.send()
    }

    /// Re-push the light's current colour/effect/brightness to the hardware
    /// (used after wake when not syncing, when no sampler drives it).
    private func reapplyCurrentState(for device: LightDevice) {
        if let type = device.activeEffectType {
            device.driver.setSoundSensitivity(UInt8(device.soundSensitivity))
            if type == 2 { device.driver.setDynamicSpeed(UInt8(100 - device.dynamicSpeed)) }
            let rgb = AppModel.compressIfNeeded(device.color.toRGB(), usbPowerOptimization)
            device.driver.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
            device.driver.setLedEffect(type: type, index: device.lastEffectIndex ?? 0)
            if type == 3 {
                // Sound-pickup: the audio meter (ScreenCaptureKit) also dies
                // across sleep, so re-create the feed.
                device.driver.setComputerRhythm(1)
                startAudioFeed(for: device)
            }
        } else {
            let rgb = AppModel.compressIfNeeded(device.color.toRGB(), usbPowerOptimization)
            device.driver.endEffectOrSync()
            device.driver.setColor(r: rgb.r, g: rgb.g, b: rgb.b)
        }
        device.driver.setBrightness(UInt8(max(0, min(255, (device.brightness / 100.0 * 255.0).rounded()))))
    }

    // MARK: - Grid helpers

    static func gridDims(forDisplay displayID: UInt32, driver: LightDriver?) -> GridLayout.Dims {
        let lamps = driver?.meta.lampsAmount ?? 112
        let id = driver?.meta.id ?? ""
        let (w, h) = displayPixelSize(displayID)
        return GridLayout.colsAndRows(deviceId: id,
                                      lampsAmount: lamps,
                                      displayWidth: w,
                                      displayHeight: h)
    }

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

    static func matches(_ screen: NSScreen, _ id: UInt32) -> Bool {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return num?.uint32Value == id
    }

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
        out.sort { a, b in
            if a.0 == mainID { return true }
            if b.0 == mainID { return false }
            return a.0 < b.0
        }
        return out
    }
}

// MARK: - Color helpers

/// Monotonic frame counter for the per-light sampler debug logging.
final class FrameCounter {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        defer { n += 1 }
        return n
    }
}

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

    func toHSB() -> (h: Double, s: Double) {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.blue
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s))
    }

    var hexString: String {
        let rgb = toRGB()
        return String(format: "#%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }
}
