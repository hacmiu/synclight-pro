import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreImage
import AppKit

/// Captures the main display and computes average / dominant color using
/// ScreenCaptureKit (native, Apple Silicon). Replaces the x64-only `quiklight.node`.
@available(macOS 13.0, *)
final class ScreenColorSampler: NSObject {

    struct SampledColor {
        var r: UInt8
        var g: UInt8
        var b: UInt8
    }

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "sync.screensampler")

    var onColor: ((SampledColor) -> Void)?
    /// Perimeter zone colours in wrap order (see `perimeter` in process()).
    var onZones: (([SampledColor]) -> Void)?
    var fps: Double = 30

    /// Display to capture. `nil` → main display. Set before `start()`.
    var displayID: UInt32?

    /// Grid dimensions matching the display aspect ratio (21:9 => 16x9), as
    /// returned by the original `getColsAndRows` for a 112-lamp device.
    var cols: Int = 16
    var rows: Int = 9

    /// When true the perimeter follows installationMethod==1 ordering
    /// ("from right to left"). Evaluated every frame so toggling the switch
    /// takes effect live without restarting capture.
    var mirrorHorizontal: Bool = false
    /// Optional live provider; when set, overrides `mirrorHorizontal` per frame.
    var mirrorProvider: (() -> Bool)?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Capture the requested display, else the main one (not merely the
        // first enumerable display, which may be a secondary monitor).
        let wantedID = displayID ?? CGMainDisplayID()
        let display = content.displays.first(where: { $0.displayID == wantedID })
            ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first
        guard let display = display else {
            throw NSError(domain: "ScreenColorSampler", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Capture a small-but-valid frame whose ASPECT MATCHES the display, so
        // ScreenCaptureKit does not letterbox it. A 16:9 (160x90) capture config
        // on a 21:9 display adds BLACK BARS top/bottom -> the top/bottom grid
        // cells read black -> those LEDs looked "off". Derive width from height.
        let dispW = Double(display.width)
        let dispH = Double(display.height)
        let capH = 90.0
        let capW = max(64.0, (capH * dispW / max(1, dispH)).rounded())
        config.width = Int(capW)
        config.height = Int(capH)
        config.scalesToFit = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    private func process(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        guard w > 0, h > 0 else { return }

        let c = max(2, cols)
        let r = max(2, rows)

        // 1) Average the frame into a c*r grid (BGRA), like getAroundAreaAvgColors.
        var grid = [SampledColor](repeating: SampledColor(r: 0, g: 0, b: 0), count: c * r)
        for gy in 0..<r {
            let y0 = h * gy / r
            let y1 = max(y0 + 1, h * (gy + 1) / r)
            let stepY = max(1, (y1 - y0) / 6)
            for gx in 0..<c {
                let x0 = w * gx / c
                let x1 = max(x0 + 1, w * (gx + 1) / c)
                let stepX = max(1, (x1 - x0) / 6)
                var cr = 0, cg = 0, cb = 0, n = 0
                var yy = y0
                while yy < y1 {
                    var xx = x0
                    while xx < x1 {
                        let off = yy * bytesPerRow + xx * 4
                        cb += Int(ptr[off]); cg += Int(ptr[off + 1]); cr += Int(ptr[off + 2])
                        n += 1
                        xx += stepX
                    }
                    yy += stepY
                }
                let d = max(1, n)
                grid[gy * c + gx] = SampledColor(r: UInt8(min(255, cr / d)),
                                                 g: UInt8(min(255, cg / d)),
                                                 b: UInt8(min(255, cb / d)))
            }
        }

        // 2) Perimeter cells in wrap order. The physical strip runs
        //    vertical → top → vertical → bottom, i.e. left, top, right, bottom,
        //    continuously around the border. To keep it seamless we walk:
        //      left  (bottom→top)  → top (left→right)
        //      → right (top→bottom) → bottom (right→left)
        //    (drop the shared corner cells so each appears once). The direction
        //    toggle reverses this upstream.
        // 2) Perimeter cells in wrap order — exactly the two branches of the
        //    original `getBackSideProto` (the wrap-around / "back side" model):
        //      installationMethod 0:
        //        left(bottom→top) , top(left→right) , right(top→bottom) , bottom(right→left)
        //      installationMethod 1:
        //        right(bottom→top), top(right→left) , left(top→bottom) , bottom(right→left)
        //    i.e. it swaps which vertical side is walked first and reverses the
        //    reading direction of each side accordingly (NOT a column mirror).
        var perim: [SampledColor] = []
        perim.reserveCapacity(2 * (c + r) - 4)
        let leftBottomUp   = stride(from: r - 1, through: 0, by: -1).map { grid[$0 * c + 0] }
        let leftTopDown    = (0..<r).map { grid[$0 * c + 0] }
        let rightBottomUp  = stride(from: r - 1, through: 0, by: -1).map { grid[$0 * c + (c - 1)] }
        let rightTopDown   = (0..<r).map { grid[$0 * c + (c - 1)] }
        let topLeftToRight = (0..<c).map { grid[0 * c + $0] }
        let topRightToLeft = stride(from: c - 1, through: 0, by: -1).map { grid[0 * c + $0] }
        let bottomLeftToRight = (0..<c).map { grid[(r - 1) * c + $0] }
        let bottomRightToLeft = stride(from: c - 1, through: 0, by: -1).map { grid[(r - 1) * c + $0] }

        if mirrorProvider?() ?? mirrorHorizontal {
            // installationMethod == 1: right → top → left → bottom
            // (bottom is pushed as-is, i.e. left→right, matching getBackSideProto).
            perim += rightBottomUp
            perim += topRightToLeft
            perim += leftTopDown
            perim += bottomLeftToRight
        } else {
            // installationMethod == 0: left → top → right → bottom
            // (bottom is reversed, i.e. right→left).
            perim += leftBottomUp
            perim += topLeftToRight
            perim += rightTopDown
            perim += bottomRightToLeft
        }

        onZones?(perim)

        // Average colour (fallback).
        var sr = 0, sg = 0, sb = 0
        for cell in grid { sr += Int(cell.r); sg += Int(cell.g); sb += Int(cell.b) }
        let gcount = grid.count
        onColor?(SampledColor(r: UInt8(sr / gcount), g: UInt8(sg / gcount), b: UInt8(sb / gcount)))
    }
}

@available(macOS 13.0, *)
extension ScreenColorSampler: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        process(pixelBuffer: pixelBuffer)
    }
}

@available(macOS 13.0, *)
extension ScreenColorSampler: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Stream stopped (e.g. permission revoked). Caller can restart.
        NSLog("[ScreenColorSampler] stopped: \(error.localizedDescription)")
    }
}
