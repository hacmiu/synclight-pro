import Foundation

/// Robobloq HID protocol frame builder — mirrors the original app's HID driver
/// (webpack modules 60895 protocol + 51545 driver). These frames are used by the
/// USB HID "light" product (PID 0xFE07). No MAC is embedded; the device address
/// is implicit in the frames themselves.
///
/// Frame layout:  "RB" (0x52 0x42) | len | seq | action | payload... | checksum
/// Checksum = sum(all bytes) % 256.
enum RobobloqProtocol {

    enum DeviceID {
        static let lightVID: UInt16 = 0x1A86
        static let lightPID: UInt16 = 0xFE07

        static let keyboardVID: UInt16 = 0x145F
        static let keyboardPID: UInt16 = 0x0339

        static let mouseVID: UInt16 = 0x145F
        static let mousePID: UInt16 = 0x0377

        static let bleVID: UInt16 = 0xFFAA
        static let blePID: UInt16 = 0x5555

        static let dongleVID: UInt16 = 0xFFAA
        static let donglePID: UInt16 = 0x5656

        static let cdcPID: UInt16 = 0xFE0C
    }

    /// Action opcodes for the HID protocol.
    enum Action: UInt8 {
        case setSyncScreen        = 128
        case writeDeviceInfo      = 129
        case readDeviceInfo       = 130
        case readDeviceUUID       = 131
        case setLedEffect         = 133
        case setSectionLED        = 134
        case setBrightness        = 135
        case setAutoOff           = 137
        case setDynamicSpeed      = 138
        case setSoundSensitivity  = 139
        case setExternalAudio     = 145
        case setOpenURL           = 147
        case setLampsAmount       = 149
        case setWhiteBright       = 150
        case turnOffLight         = 151
        case setComputerRhythm    = 152
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        var sum = 0
        for b in bytes { sum += Int(b) }
        return UInt8(sum % 256)
    }

    // MARK: - Generic frame helper

    /// Build `RB len seq action payload... sum`, where len = 5 + payload.count + 1.
    private static func frame(seq: UInt8, action: UInt8, payload: [UInt8]) -> [UInt8] {
        let len = 5 + payload.count + 1
        var b = [UInt8](repeating: 0, count: len)
        b[0] = 0x52; b[1] = 0x42
        b[2] = UInt8(len & 0xFF)
        b[3] = seq
        b[4] = action
        for (i, v) in payload.enumerated() { b[5 + i] = v }
        b[len - 1] = checksum(Array(b[0..<(len - 1)]))
        return b
    }

    // MARK: - Queries

    /// Read full device info. Parsed by caller:
    ///   id          = bytes[5..<8]
    ///   displaySize = byte[8]
    ///   version     = bytes[21].[22].[23]
    ///   lamps       = byte[11]
    ///   uuid        = bytes[12..<20]
    static func readDeviceInfo(seq: UInt8) -> [UInt8] {
        frame(seq: seq, action: Action.readDeviceInfo.rawValue, payload: [])
    }

    // MARK: - Setters

    /// Static section color. Builds the "on" payload used by the original app:
    ///   [1, r, g, b, 254]                           when lamps is unknown/0
    ///   [1, r, g, b, lamps, lamps+1, 0, 0, 0, 254]  when lamps in 1..253
    /// (The payload is a sequence of 5-byte groups `[start, r, g, b, end]`.)
    static func setSectionColor(seq: UInt8, r: UInt8, g: UInt8, b: UInt8, lamps: Int) -> [UInt8] {
        var payload: [UInt8] = [1, r, g, b, 254]
        if lamps > 0 && lamps < 254 {
            payload = [1, r, g, b,
                       UInt8(lamps & 0xFF), UInt8((lamps + 1) & 0xFF),
                       0, 0, 0, 254]
        }
        return frame(seq: seq, action: Action.setSectionLED.rawValue, payload: payload)
    }

    /// Multi-section LED frame (action 134) from 5-byte groups
    /// `[start, r, g, b, end]`. Used for screen sync where each frame paints a
    /// set of lamp ranges. Keep `zones.count` <= 55 so the frame fits one HID
    /// report (5 header + 55 data + 1 sum = 61 bytes).
    static func setSections(seq: UInt8, zones: [UInt8]) -> [UInt8] {
        frame(seq: seq, action: Action.setSectionLED.rawValue, payload: zones)
    }

    /// Turn the strip off (black, same "on" payload shape to release any lock).
    static func turnOff(seq: UInt8, lamps: Int) -> [UInt8] {
        var payload: [UInt8] = [1, 0, 0, 0, 254]
        if lamps > 0 && lamps < 254 {
            payload = [1, 0, 0, 0,
                       UInt8(lamps & 0xFF), UInt8((lamps + 1) & 0xFF),
                       0, 0, 0, 254]
        }
        return frame(seq: seq, action: Action.setSectionLED.rawValue, payload: payload)
    }

    /// Brightness 0..255 (device clamps internally).
    static func setBrightness(seq: UInt8, value: UInt8) -> [UInt8] {
        frame(seq: seq, action: Action.setBrightness.rawValue, payload: [value])
    }

    /// LED effect: action 133, payload [effectType, effectIndex].
    static func setLedEffect(seq: UInt8, effectType: UInt8, effectIndex: UInt8) -> [UInt8] {
        frame(seq: seq, action: Action.setLedEffect.rawValue, payload: [effectType, effectIndex])
    }

    /// Dynamic speed 5..100.
    static func setDynamicSpeed(seq: UInt8, value: UInt8) -> [UInt8] {
        let v = min(max(value, 5), 100)
        return frame(seq: seq, action: Action.setDynamicSpeed.rawValue, payload: [v])
    }

    /// Sound sensitivity 5..100.
    static func setSoundSensitivity(seq: UInt8, value: UInt8) -> [UInt8] {
        let v = min(max(value, 5), 100)
        return frame(seq: seq, action: Action.setSoundSensitivity.rawValue, payload: [v])
    }

    /// External audio level (action 145, 8-byte frame: UInt16BE at [5..6]).
    static func setExternalAudio(seq: UInt8, level: UInt16) -> [UInt8] {
        let hi = UInt8((level >> 8) & 0xFF)
        let lo = UInt8(level & 0xFF)
        return frame(seq: seq, action: Action.setExternalAudio.rawValue, payload: [hi, lo])
    }

    /// Rhythm source (action 152): 1 = computer (app feeds audio), 2 = controller.
    static func setComputerRhythm(seq: UInt8, rhythmType: UInt8) -> [UInt8] {
        frame(seq: seq, action: Action.setComputerRhythm.rawValue, payload: [rhythmType])
    }

    /// Open URL / mode flag used right after info read (action 147).
    static func setOpenUrl(seq: UInt8, value: UInt8 = 0) -> [UInt8] {
        frame(seq: seq, action: Action.setOpenURL.rawValue, payload: [value])
    }

    /// Auto off: action 137, payload [enable, minutes].
    static func setAutoOff(seq: UInt8, enable: UInt8, minutes: UInt8) -> [UInt8] {
        frame(seq: seq, action: Action.setAutoOff.rawValue, payload: [enable, minutes])
    }

    /// Real-time sync-screen stream — "SC" header frame.
    ///
    /// Each lamp zone is encoded as a 5-byte group `[startLamp, R, G, B, endLamp]`
    /// (this is exactly what the original app's `getOtherSideProto` produces and
    /// what `setSyncScreen` copies verbatim). `zones` is the flattened list of
    /// those 5-byte groups, so `zones.count` must be a multiple of 5.
    ///
    /// Frame:  "SC" | UInt16BE(len) | seq | action(128) | <zone groups...> | sum
    static func setSyncScreen(seq: UInt8, zones: [UInt8]) -> [UInt8] {
        var data = zones
        while data.count % 5 != 0 { data.append(0) }
        let len = 7 + data.count
        var b = [UInt8](repeating: 0, count: len)
        b[0] = 0x53; b[1] = 0x43            // 'S','C'
        b[2] = UInt8((len >> 8) & 0xFF)     // UInt16BE length
        b[3] = UInt8(len & 0xFF)
        b[4] = seq
        b[5] = Action.setSyncScreen.rawValue
        for (i, v) in data.enumerated() { b[6 + i] = v }
        b[len - 1] = checksum(Array(b[0..<(len - 1)]))
        return b
    }

    /// Convenience: build zone groups for `count` evenly-split zones across
    /// `lamps` lamps, given a per-zone colour lookup. Lamp indices in the
    /// protocol are 1-based (1..lamps), matching setSectionColor.
    static func syncZones(lamps: Int, zoneColors: [(r: UInt8, g: UInt8, b: UInt8)]) -> [UInt8] {
        let n = max(1, lamps)
        let z = max(1, zoneColors.count)
        var out: [UInt8] = []
        out.reserveCapacity(z * 5)
        for i in 0..<z {
            let start = n * i / z + 1                       // 1-based
            let end = min(n, n * (i + 1) / z)               // 1-based inclusive
            let c = zoneColors[i]
            out.append(UInt8(max(1, min(255, start))))
            out.append(c.r)
            out.append(c.g)
            out.append(c.b)
            out.append(UInt8(max(1, min(255, end))))
        }
        return out
    }
}
