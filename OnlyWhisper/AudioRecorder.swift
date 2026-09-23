import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var levelHandler: (@Sendable (Float) -> Void)?

    var isRunning: Bool { engine.isRunning }

    func setLevelHandler(_ handler: @escaping @Sendable (Float) -> Void) {
        levelHandler = handler
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return captured
    }

    func appendSystemSamples(_ extra: [Float]) {
        lock.lock()
        samples.append(contentsOf: extra)
        lock.unlock()
    }

    func snapshot() -> [Float] {
        lock.lock()
        let captured = samples
        lock.unlock()
        return captured
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData else { return }
        let frames = Int(output.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: frames))
        let level = chunk.reduce(Float(0)) { max($0, abs($1)) }
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
        levelHandler?(level)
    }
}
