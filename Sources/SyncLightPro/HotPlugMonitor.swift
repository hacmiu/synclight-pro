import Foundation
import IOKit
import IOKit.hid

/// Lightweight USB hot-plug watcher for Robobloq lights.
///
/// IMPORTANT: this uses `IOHIDManager` *only* for device match/removal
/// callbacks. It never opens, reads from, or writes to the device — the actual
/// I/O goes through `HIDTransport`, which must keep following the five hard
/// requirements in `DEV_NOTES.md`. Using IOHIDManager purely as an
/// add/remove notifier is safe and does not interfere with that transport.
///
/// `onChanged(true)` fires when a Robobloq device appears, `onChanged(false)`
/// when one is removed. Callbacks are delivered on the main run loop; the
/// consumer hops to the main actor as needed.
final class HotPlugMonitor {

    /// Called with `present == true` on device add, `false` on device removal.
    var onChanged: ((Bool) -> Void)?

    private var manager: IOHIDManager?

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = ["Manufacturer": "ROBOBLOQ"]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, _ in
            guard let context = context else { return }
            let monitor = Unmanaged<HotPlugMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChanged?(true)
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, _ in
            guard let context = context else { return }
            let monitor = Unmanaged<HotPlugMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChanged?(false)
        }, ctx)

        // A dedicated run-loop mode so we don't fight other clients of defaultMode.
        let mode = CFRunLoopMode("SYNCLIGHT_HOTPLUG" as CFString)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), mode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        manager = mgr
    }

    func stop() {
        guard let mgr = manager else { return }
        let mode = CFRunLoopMode("SYNCLIGHT_HOTPLUG" as CFString)
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), mode.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    deinit { stop() }
}
