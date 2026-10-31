import Foundation
import CoreGraphics

/// Ports the original app's `getAspectRatio` + `getColsAndRows`
/// (webpack modules 2930 / 54790) so the sampling grid — and therefore the
/// number of perimeter zones — adapts to the actual LED count and display.
///
/// In the Electron app this drives how many `cols x rows` cells the capture
/// thread averages into, and the perimeter walk that maps those cells onto the
/// strip. Hard-coding 16x9 (as the app originally did for a 112-lamp bar) is
/// only correct for one device; using these functions makes any Robobloq strip
/// length / monitor aspect work like the original.
enum GridLayout {

    struct Dims { var cols: Int; var rows: Int }

    /// `getAspectRatio(aspectWidth, aspectHeight)` — the sampling `cols/rows`
    /// for a display aspect ratio. (realCols/realRows from the original are
    /// only used for area mapping and are omitted here.)
    static func aspectRatio(_ width: Int, _ height: Int) -> Dims {
        guard height != 0 else { return Dims(cols: 6, rows: 4) }
        let r = Double(width) / Double(height)
        let key = (r * 10).rounded(.down) / 10

        func k(_ v: Double) -> Double { (v * 10).rounded(.down) / 10 }

        switch key {
        case k(16.0 / 9.0):  return Dims(cols: 16, rows: 9)
        case k(5.625):       return Dims(cols: 9, rows: 16)
        case k(16.0):        return Dims(cols: 8, rows: 5)
        case k(6.25):        return Dims(cols: 5, rows: 8)
        case k(1512.0 / 982.0): return Dims(cols: 8, rows: 5)
        case k(4.0 / 3.0):   return Dims(cols: 4, rows: 3)
        case k(15.0):        return Dims(cols: 6, rows: 4)
        case k(12.5):        return Dims(cols: 10, rows: 8)
        case k(5.0 / 3.0):   return Dims(cols: 10, rows: 6)
        case k(21.0 / 9.0):  return Dims(cols: 16, rows: 9)
        case k(32.0 / 9.0):  return Dims(cols: 16, rows: 9)
        default:             return Dims(cols: 6, rows: 4)
        }
    }

    /// `getColsAndRows(deviceId, lampsAmount, monitor, productType)`.
    /// `deviceId` is the 6-char hex id from `readDeviceInfo` (bytes 5..<8).
    static func colsAndRows(deviceId: String,
                            lampsAmount: Int,
                            displayWidth: Int,
                            displayHeight: Int,
                            productType: String = "light") -> Dims {
        let special = ["000100", "000101", "000102", "000103", "001c00"].contains(deviceId)
        let base = aspectRatio(displayWidth, displayHeight)
        let sum = base.cols + base.rows

        if deviceId.count == 8 || deviceId == "888888" || deviceId == "000608" {
            return base
        }
        if deviceId == "001102" {
            return Dims(cols: 16, rows: 9)
        }
        if special {
            return Dims(cols: 6, rows: 5)
        }
        if lampsAmount >= 2 * sum {
            return base
        }
        if lampsAmount < 2 * sum && lampsAmount >= 22 {
            return Dims(cols: 6, rows: 5)
        }
        if productType == "keyboard" {
            return Dims(cols: 21, rows: 6)
        }
        return Dims(cols: 3, rows: 2)
    }
}
