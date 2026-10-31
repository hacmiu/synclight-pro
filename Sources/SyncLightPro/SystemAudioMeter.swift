import Foundation
import ScreenCaptureKit
import AVFoundation

/// Captures the system's audio output (the music actually playing on the Mac)
/// via ScreenCaptureKit's audio stream and reports a smoothed, gated level
/// (0..1) at ~30 Hz. This is the correct source for the "sound pickup" LED
/// effects — the original app's audio worker does the same (loopback audio,
/// not the microphone). It reuses the Screen Recording permission the app
/// already needs for screen sync.
@available(macOS 13.0, *)
final class SystemAudioMeter: NSObject {

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "sync.audiometer")

    var noiseFloor: Float = 0.008
    var gain: Float = 1.0
    /// Called on the main queue with a 0..1 level at ~30 Hz.
    var onLevel: ((Double) -> Void)?

    private var smoothed: Float = 0
    private var lastEmit = CACurrentMediaTime()
    private let emitInterval: CFTimeInterval = 1.0 / 30.0

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "SystemAudioMeter", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // ignore our own sounds
        config.sampleRate = 48_000
        config.channelCount = 2
        // Keep the video side tiny; we only need audio.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        smoothed = 0
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let rms = Self.rms(of: sampleBuffer) else { return }
        let gated = max(0, rms - noiseFloor)
        let target = min(1, gated * 8.0 * gain)
        let coeff: Float = target > smoothed ? 0.6 : 0.22
        smoothed += (target - smoothed) * coeff

        let now = CACurrentMediaTime()
        guard now - lastEmit >= emitInterval else { return }
        lastEmit = now
        let level = Double(smoothed)
        DispatchQueue.main.async { self.onLevel?(level) }
    }

    /// RMS of an audio CMSampleBuffer (float32 PCM interleaved).
    private static func rms(of sampleBuffer: CMSampleBuffer) -> Float? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
        // SCStream delivers 32-bit float PCM.
        guard asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        var sum: Float = 0
        var count = 0
        for buf in buffers {
            guard let mData = buf.mData else { continue }
            let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let floats = mData.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { let s = floats[i]; sum += s * s }
            count += n
        }
        guard count > 0 else { return nil }
        return sqrt(sum / Float(count))
    }
}

@available(macOS 13.0, *)
extension SystemAudioMeter: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        handleAudio(sampleBuffer)
    }
}

@available(macOS 13.0, *)
extension SystemAudioMeter: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[SystemAudioMeter] stopped: \(error.localizedDescription)")
    }
}
