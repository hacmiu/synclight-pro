import Foundation

/// High-level driver for one Robobloq light (USB HID transport).
/// Uses the HID protocol from the original app (modules 60895 / 51545):
/// plain "RB" action frames with NO MAC embedded.
final class LightDriver {

    struct DeviceMeta {
        var id: String = ""            // bytes[5..<8] hex
        var uuid: String = ""          // bytes[12..<20] hex
        var firmware: String = ""      // bytes[21].[22].[23]
        var lampsAmount: Int = 0       // byte[11]
        var displaySize: Int = 0       // byte[8]
        var version: String = ""       // alias of firmware
    }

    private let transport: HIDTransport
    private(set) var meta = DeviceMeta()
    private(set) var isConnected = false

    /// Last static color sent, so brightness changes can re-send it (the USB
    /// light only applies brightness together with a fresh color frame — see
    /// sendBrightness in the original app).
    private var lastColor: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
    /// True while an effect or screen-sync stream is running; in that state the
    /// original app skips the color re-send after a brightness change.
    private(set) var isEffectOrSyncActive = false

    init(transport: HIDTransport) {
        self.transport = transport
    }

    /// Best-effort stable identity for persistence: the device's own uuid once
    /// it has reported it, otherwise empty (caller falls back to locationID).
    var identityKey: String {
        !meta.uuid.isEmpty ? "uuid:\(meta.uuid)" : ""
    }

    /// Connect assuming the transport has ALREADY opened a specific device
    /// (used for multi-light, where HIDTransport.openSpecific ran first).
    /// Reads device info + sends setOpenUrl(0), exactly like `connect()`.
    @discardableResult
    func connectOnOpenedTransport() -> Bool {
        return finishConnect()
    }

    @discardableResult
    func connect() -> Bool {
        guard transport.openFirstLight() else { return false }
        return finishConnect()
    }

    /// Shared tail of connect(): read info, then setOpenUrl(0).
    private func finishConnect() -> Bool {
        // Read device info (needed for lamps / uuid / firmware).
        transport.write(RobobloqProtocol.readDeviceInfo(seq: transport.nextSeq()))
        Thread.sleep(forTimeInterval: 0.4)
        let resp = transport.latestResponse()
        if resp.count >= 24 { parseDeviceInfo(resp) }

        // Fallback: some firmwares don't answer in time; a known-good default
        // keeps colour control working (original app uses 112-lamp payloads).
        if meta.lampsAmount <= 0 { meta.lampsAmount = 112 }

        // Original app sends setOpenUrl(0) right after reading info.
        transport.write(RobobloqProtocol.setOpenUrl(seq: transport.nextSeq(), value: 0))

        isConnected = true
        return true
    }

    private func parseDeviceInfo(_ b: [UInt8]) {
        func sliceHex(_ range: Range<Int>) -> String {
            range.compactMap { idx -> String? in
                guard idx < b.count else { return nil }
                return String(format: "%02x", b[idx])
            }.joined()
        }
        meta.id = sliceHex(5..<8)
        meta.displaySize = Int(b[8])
        meta.lampsAmount = Int(b[11])
        meta.uuid = sliceHex(12..<20)
        if b.count >= 24 {
            meta.firmware = "\(b[21]).\(b[22]).\(b[23])"
        }
        meta.version = meta.firmware
    }

    func disconnect() {
        transport.close()
        isConnected = false
    }

    // MARK: - Commands

    /// Static color for the whole strip.
    func setColor(r: UInt8, g: UInt8, b: UInt8) {
        lastColor = (r, g, b)
        let frame = RobobloqProtocol.setSectionColor(seq: transport.nextSeq(), r: r, g: g, b: b, lamps: meta.lampsAmount)
        transport.write(frame)
    }

    func turnOff() {
        lastColor = (0, 0, 0)
        let frame = RobobloqProtocol.turnOff(seq: transport.nextSeq(), lamps: meta.lampsAmount)
        transport.write(frame)
    }

    /// Brightness 0..255. The USB light only applies a new brightness level when
    /// it is followed by a fresh color frame, so — like the original app's
    /// USB branch of sendBrightness — re-send the last color right after the
    /// 135 frame (unless an effect / sync stream is currently driving the LEDs).
    func setBrightness(_ value: UInt8) {
        let v = max(value, 5)   // original app clamps minimum to 5
        transport.write(RobobloqProtocol.setBrightness(seq: transport.nextSeq(), value: v))
        if isEffectOrSyncActive { return }
        Thread.sleep(forTimeInterval: 0.02)   // 20ms, as in the original app
        let (r, g, b) = lastColor
        transport.write(RobobloqProtocol.setSectionColor(seq: transport.nextSeq(), r: r, g: g, b: b, lamps: meta.lampsAmount))
    }

    func setLedEffect(type: UInt8, index: UInt8) {
        isEffectOrSyncActive = true
        // The original app primes the strip with the current colour
        // (setSectionLED) right before switching to an effect frame, so the
        // effect starts from the expected lit state.
        let (r, g, b) = lastColor
        transport.write(RobobloqProtocol.setSectionColor(seq: transport.nextSeq(), r: r, g: g, b: b, lamps: meta.lampsAmount))
        Thread.sleep(forTimeInterval: 0.03)
        transport.write(RobobloqProtocol.setLedEffect(seq: transport.nextSeq(), effectType: type, effectIndex: index))
    }

    func setDynamicSpeed(_ value: UInt8) {
        transport.write(RobobloqProtocol.setDynamicSpeed(seq: transport.nextSeq(), value: value))
    }

    func setSoundSensitivity(_ value: UInt8) {
        transport.write(RobobloqProtocol.setSoundSensitivity(seq: transport.nextSeq(), value: value))
    }

    /// Feed an audio level 0..65535 to sound-pickup effects (action 145).
    func setExternalAudio(level: UInt16) {
        isEffectOrSyncActive = true
        transport.write(RobobloqProtocol.setExternalAudio(seq: transport.nextSeq(), level: level))
    }

    /// Select rhythm source: 1 = computer (app-fed audio), 2 = controller.
    func setComputerRhythm(_ rhythmType: UInt8) {
        transport.write(RobobloqProtocol.setComputerRhythm(seq: transport.nextSeq(), rhythmType: rhythmType))
    }

    /// Real-time screen color sync (ambilight, wrap-around perimeter).
    ///
    /// `zoneColors` is the perimeter cell order produced by the sampler (grid
    /// perimeter in wrap order). We distribute the lamps across those cells
    /// exactly like the original `getOtherSideProto` (each cell → a consecutive
    /// `[start,r,g,b,end]` group) and send them in ONE "SC" frame — the device
    /// reassembles a frame split across multiple 64-byte HID reports.
    func streamScreenZones(_ zoneColors: [(r: UInt8, g: UInt8, b: UInt8)]) {
        isEffectOrSyncActive = true
        let lamps = meta.lampsAmount > 0 ? meta.lampsAmount : 112
        let zones = RobobloqProtocol.syncZones(lamps: lamps, zoneColors: zoneColors)
        transport.write(RobobloqProtocol.setSyncScreen(seq: transport.nextSeq(), zones: zones))
    }

    /// Single full-strip color sync (fallback / simple mode).
    func streamScreenColor(r: UInt8, g: UInt8, b: UInt8) {
        streamScreenZones([(r: r, g: g, b: b)])
    }

    /// Leave effect/sync mode so the next brightness change re-sends the color.
    func endEffectOrSync() {
        isEffectOrSyncActive = false
    }

    func setAutoOff(enable: Bool, minutes: UInt8) {
        transport.write(RobobloqProtocol.setAutoOff(seq: transport.nextSeq(), enable: enable ? 1 : 0, minutes: minutes))
    }
}


