import Foundation
import SwiftUI

/// One physical light bound to one display, with its OWN settings + sampler.
///
/// Multi-light design (Part C): each connected light is a self-contained
/// controller. `AppModel` owns `[LightDevice]`; the Color/Effects/Settings pages
/// operate on the *selected* light, while the sync toggle is global and drives
/// every light's own sampler toward its own display.
///
/// This is a plain (non-observable) value-ish holder; `AppModel` republishes
/// changes by mutating its `@Published var devices`.
final class LightDevice: Identifiable {

    // MARK: Identity

    /// Stable runtime id for SwiftUI.
    let id = UUID()
    /// Registry location id (USB bus/port) captured at open time.
    let locationID: Int
    /// Bumped when the light (re)connects so views can refresh.
    var displayName: String

    // MARK: Transport / driver

    let transport: HIDTransport
    let driver: LightDriver
    var isConnected: Bool = false

    /// Which display this light mirrors. `nil` = main display.
    var displayID: UInt32?

    // MARK: Per-light settings (persisted)

    var hue: Double = 0.667          // 0..1
    var saturation: Double = 1.0     // 0..1
    var brightness: Double = 80      // 0..100
    var dynamicSpeed: Double = 50    // 5..100
    var soundSensitivity: Double = 50 // 5..100
    /// Strip direction as seen by the viewer: 0 = left→right, 1 = right→left.
    var installationMethod: Int = 0
    var autoOffEnabled: Bool = false
    var autoOffMinutes: Double = 30

    /// Current effect type in use (2 = dynamic, 3 = sound pickup, nil = none).
    var activeEffectType: UInt8?
    /// Last applied effect (restored on reconnect).
    var lastEffectType: UInt8?
    var lastEffectIndex: UInt8?

    /// Per-light screen sampler (only present while global sync is running).
    var sampler: ScreenColorSampler?
    /// Thread-safe mirror flag read from the sampler's capture queue.
    let mirrorBox = AtomicBool(false)

    // MARK: Derived

    /// Swift Color for this light's hue + saturation (full value).
    var color: Color { Color(hue: hue, saturation: saturation, brightness: 1) }

    var firmware: String { driver.meta.firmware.isEmpty ? "-" : driver.meta.firmware }
    var ledCount: Int { driver.meta.lampsAmount }

    /// Persistence key for this light. Uses the device uuid when the light has
    /// reported it, otherwise falls back to its registry location id.
    var persistenceKey: String {
        let k = driver.identityKey
        return k.isEmpty ? "loc:\(locationID)" : k
    }

    init(transport: HIDTransport, driver: LightDriver, locationID: Int, displayName: String) {
        self.transport = transport
        self.driver = driver
        self.locationID = locationID
        self.displayName = displayName
    }
}
