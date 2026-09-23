import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "app.onlywhisper.system-audio")
    var onSamples: (@Sendable ([Float]) -> Void)?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CocoaError(.fileReadNoSuchFile) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        let stream = stream
        self.stream = nil
        stream?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let samples = Self.floats(from: sampleBuffer) else { return }
        onSamples?(samples)
    }

    private static func floats(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer else { return nil }
        let sourceRate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)
        guard channels > 0, sourceRate > 0 else { return nil }
        let frames = length / (MemoryLayout<Float>.size * channels)
        guard asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, frames > 0 else { return nil }
        let pointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        var mono: [Float] = []
        mono.reserveCapacity(frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += pointer[frame * channels + channel]
            }
            mono.append(sum / Float(channels))
        }
        let step = sourceRate / 16_000
        guard step > 0 else { return mono }
        return stride(from: 0, to: Double(mono.count), by: step).map { mono[Int($0)] }
    }
}
