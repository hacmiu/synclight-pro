import Foundation
import IOKit
import IOKit.hid

/// Native HID transport for Robobloq lights (arm64 native), replicating the
/// original app's node-hid/hidapi behaviour exactly:
///
///  * The IOHIDDevice is created directly from the IOService registry
///    (`IOHIDDeviceCreate`) — NOT via `IOHIDManagerCopyDevices`. This is required
///    for both writes and input reports to work.
///  * Input reports are registered with a 64-byte buffer and scheduled on a
///    dedicated **custom** CFRunLoopMode (hidapi's "HIDAPI_<ptr>" trick), pumped
///    on a background thread. defaultMode does not deliver reports reliably.
///  * Outputs are written with `IOHIDDeviceSetReport(type, reportID: 0, frame)`
///    where `frame` is the raw "RB..." bytes WITHOUT a leading report-id byte
///    (hidapi strips report id 0 before calling SetReport).
final class HIDTransport {

    struct DeviceInfo {
        var path: String
        var vendorID: Int
        var productID: Int
        var manufacturer: String
        var product: String
        var serial: String
        var usagePage: Int
        var usage: Int
        /// Registry location id (USB bus/port address). Stable across relaunches
        /// as long as the light stays in the same port; used as an identity
        /// fallback before the device has reported its own uuid.
        var locationID: Int
    }

    /// A matched registry entry paired with its device info. `openSpecific`
    /// uses `entry` to create the IOHIDDevice directly (see DEV_NOTES: devices
    /// MUST be opened from the IOService registry, not IOHIDManagerCopyDevices).
    struct MatchedEntry {
        var info: DeviceInfo
        var entry: io_service_t
    }

    enum TransportType: String {
        case hid, ble, dongle, serial
    }

    private static let roboMatch: [String: Any] = ["Manufacturer": "ROBOBLOQ"]

    // MARK: - Enumeration

    /// Enumerate every matched Robobloq device along with its live registry
    /// entry. The returned entry handles are owned by the caller: release the
    /// ones you do NOT open via `releaseEntry(for:)` (the one passed to
    /// `openSpecific` is consumed/released there).
    static func enumerateEntries() -> [MatchedEntry] {
        var iter: io_iterator_t = 0
        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        for (k, v) in roboMatch { matching[k] = v }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iter) }

        var out: [MatchedEntry] = []
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let dev = IOHIDDeviceCreate(kCFAllocatorDefault, entry) {
                out.append(MatchedEntry(info: info(of: dev), entry: entry))
            } else {
                IOObjectRelease(entry)
            }
            entry = IOIteratorNext(iter)
        }
        return out
    }

    /// Release a registry entry that will not be opened.
    static func releaseEntry(for m: MatchedEntry) {
        if m.entry != 0 { IOObjectRelease(m.entry) }
    }

    static func enumerate() -> [DeviceInfo] {
        let entries = enumerateEntries()
        let infos = entries.map { $0.info }
        for m in entries { releaseEntry(for: m) }
        return infos
    }

    private static func prop<T>(_ dev: IOHIDDevice, _ key: String, _ dflt: T) -> T {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? T) ?? dflt
    }

    private static func info(of dev: IOHIDDevice) -> DeviceInfo {
        DeviceInfo(
            path: prop(dev, kIOHIDTransportKey, ""),
            vendorID: prop(dev, kIOHIDVendorIDKey, 0),
            productID: prop(dev, kIOHIDProductIDKey, 0),
            manufacturer: prop(dev, kIOHIDManufacturerKey, ""),
            product: prop(dev, kIOHIDProductKey, ""),
            serial: prop(dev, kIOHIDSerialNumberKey, ""),
            usagePage: prop(dev, kIOHIDPrimaryUsagePageKey, 0),
            usage: prop(dev, kIOHIDPrimaryUsageKey, 0),
            locationID: prop(dev, kIOHIDLocationIDKey, 0)
        )
    }

    // MARK: - State

    private var device: IOHIDDevice?
    private let seqGen = SequenceGenerator()

    /// Registry location id of the currently-open device (0 if none). Lets us
    /// re-open the SAME physical light after sleep/wake instead of whatever
    /// happens to be first.
    private(set) var locationID: Int = 0

    private let lock = NSLock()
    private var lastResponse: [UInt8] = []
    private var readBuffer: [UInt8] = []
    private var responseReady = false

    private var runLoopThread: Thread?
    private var runLoopRef: CFRunLoop?
    private var runLoopMode: CFRunLoopMode = CFRunLoopMode.defaultMode
    private var shouldStop = false

    private static let inputReportSize = 64
    private static let outputReportSize = 64

    // MARK: - Open / close

    /// Open the first Robobloq HID device (preferring the vendor interface
    /// usagePage 0xFF00 / usage 1) directly from the IORegistry.
    @discardableResult
    func openFirstLight() -> Bool {
        let entries = Self.enumerateEntries()
        guard !entries.isEmpty else { return false }
        // Prefer a vendor interface entry; otherwise the first one.
        let chosen = entries.first(where: { $0.info.usagePage == 0xFF00 && $0.info.usage == 1 }) ?? entries[0]
        let opened = openSpecific(chosen)
        // Release every entry we didn't open (openSpecific consumes `chosen`).
        for e in entries where e.entry != chosen.entry { Self.releaseEntry(for: e) }
        return opened
    }

    /// Open one specific matched device (creates the IOHIDDevice from its
    /// registry entry). Consumes and releases the entry handle.
    @discardableResult
    func openSpecific(_ matched: MatchedEntry) -> Bool {
        defer { Self.releaseEntry(for: matched) }
        guard let dev = IOHIDDeviceCreate(kCFAllocatorDefault, matched.entry) else { return false }

        guard IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return false
        }
        device = dev
        locationID = matched.info.locationID
        shouldStop = false

        // Custom run-loop mode unique to this device (hidapi equivalent).
        let modeStr = "SYNCLIGHT_HID_\(Unmanaged.passUnretained(dev).toOpaque())"
        let mode = CFRunLoopMode(modeStr as CFString)
        runLoopMode = mode

        // Input-report callback with a persistent 64-byte buffer.
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputReportSize)
        buf.initialize(repeating: 0, count: Self.inputReportSize)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            dev, buf, Self.inputReportSize,
            { context, _, _, _, _, report, reportLength in
                guard let context = context else { return }
                let transport = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
                let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
                transport.handleIncoming(data)
            }, ctx)

        // Schedule + pump on a dedicated background thread.
        let readySem = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self = self, let d = self.device else { return }
            let rl: CFRunLoop = CFRunLoopGetCurrent() ?? CFRunLoopGetMain()
            self.runLoopRef = rl
            IOHIDDeviceScheduleWithRunLoop(d, rl, mode.rawValue)
            readySem.signal()
            while !self.shouldStop {
                CFRunLoopRunInMode(mode, 0.5, false)
            }
            IOHIDDeviceUnscheduleFromRunLoop(d, rl, mode.rawValue)
        }
        thread.name = "sync.hid.runloop"
        thread.stackSize = 512 * 1024
        thread.start()
        runLoopThread = thread
        _ = readySem.wait(timeout: .now() + 2.0)
        return true
    }

    func close() {
        shouldStop = true
        if let rl = runLoopRef {
            CFRunLoopStop(rl)
            CFRunLoopWakeUp(rl)
        }
        Thread.sleep(forTimeInterval: 0.1)
        if let d = device {
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        runLoopRef = nil
        runLoopThread = nil
    }

    /// Best-effort liveness probe for the currently-open device.
    ///
    /// After sleep/wake (or a USB reset) the IOHIDDevice handle can be silently
    /// invalidated by IOKit: writes return success but do nothing, and input
    /// reports stop. We detect that by (a) confirming a handle exists and (b)
    /// checking the device is still present in the live registry with the same
    /// location. A cheap 1-byte input-report query is not reliable across
    /// devices, so the registry check is the primary signal.
    var isAlive: Bool {
        guard device != nil else { return false }
        guard locationID != 0 else { return true } // can't verify; assume ok
        let present = Self.enumerate().contains { $0.locationID == locationID }
        return present
    }

    /// Close and re-open the SAME physical light (by registry location) after
    /// sleep/wake. Returns true on success. Falls back to false if the device
    /// is gone (caller then treats the light as disconnected).
    @discardableResult
    func reopen() -> Bool {
        let loc = locationID
        close()
        guard loc != 0 else { return false }
        let entries = Self.enumerateEntries()
        guard let match = entries.first(where: { $0.info.locationID == loc }) else {
            for e in entries { Self.releaseEntry(for: e) }
            return false
        }
        for e in entries where e.entry != match.entry { Self.releaseEntry(for: e) }
        return openSpecific(match)
    }

    // MARK: - Input reports

    private func handleIncoming(_ chunk: [UInt8]) {
        guard chunk.count >= 2 else { return }
        let isHeader = (chunk[0] == 0x52 && chunk[1] == 0x42) || (chunk[0] == 0x53 && chunk[1] == 0x43)
        lock.lock()
        if isHeader { readBuffer = chunk } else { readBuffer.append(contentsOf: chunk) }
        lastResponse = readBuffer
        responseReady = true
        lock.unlock()
    }

    /// Most recent response seen from the device (best effort).
    func latestResponse() -> [UInt8] {
        lock.lock(); let r = lastResponse; lock.unlock()
        return r
    }

    // MARK: - Write

    /// Write "RB..."/"SC..." frame bytes (no leading report-id byte) as a fixed
    /// 64-byte output report, matching hidapi's behaviour for report id 0.
    @discardableResult
    func write(_ frame: [UInt8]) -> Bool {
        guard let dev = device else { return false }

        var ok = true
        var offset = 0
        repeat {
            let end = min(offset + Self.outputReportSize, frame.count)
            var out = [UInt8](repeating: 0, count: Self.outputReportSize)
            let n = end - offset
            for k in 0..<n { out[k] = frame[offset + k] }
            let ret = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, out, out.count)
            if ret != kIOReturnSuccess { ok = false }
            offset = end
        } while offset < frame.count
        return ok
    }

    func nextSeq() -> UInt8 { seqGen.next() }
}

/// Rolling sequence id, 1..254 then wraps to 1 (mirrors module 72299).
final class SequenceGenerator {
    private var id: UInt8 = 1
    func next() -> UInt8 {
        id = id &+ 1
        if id >= 255 { id = 1 }
        return id
    }
}
