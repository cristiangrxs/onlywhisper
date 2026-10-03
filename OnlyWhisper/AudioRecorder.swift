import AVFoundation
import Foundation

/// Mono 16 kHz samples. Pausing rejects new audio and leaves what was already captured.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var accepts = true

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        accepts = true
        lock.unlock()
    }

    func setAccepting(_ accepts: Bool) {
        lock.lock()
        self.accepts = accepts
        lock.unlock()
    }

    func append(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard accepts else { return }
        samples.append(contentsOf: chunk)
    }

    func snapshot() -> [Float] {
        lock.lock()
        let copy = samples
        lock.unlock()
        return copy
    }

    func take() -> [Float] {
        lock.lock()
        let copy = samples
        samples.removeAll(keepingCapacity: false)
        accepts = true
        lock.unlock()
        return copy
    }
}

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer = SampleBuffer()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var started = false

    var isRunning: Bool { engine.isRunning }

    func setLevelHandler(_ handler: @escaping @Sendable (Float) -> Void) {
        levelHandler = handler
    }

    func start() throws {
        buffer.reset()
        started = true
        try installAndStart()
    }

    /// Stops the microphone without dropping samples already captured.
    func pause() {
        guard started, engine.isRunning else { return }
        buffer.setAccepting(false)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func resume() throws {
        guard started, !engine.isRunning else { return }
        buffer.setAccepting(true)
        try installAndStart()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        started = false
        return buffer.take()
    }

    func snapshot() -> [Float] {
        buffer.snapshot()
    }

    private func installAndStart() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        try input.installAudioTap(
            onBus: 0,
            bufferSize: tapBufferFrameCount(for: inputFormat),
            format: inputFormat
        ) { [weak self] buffer, _ in
            let pcm = AVAudioPCMBuffer(copying: buffer)
            self?.consume(pcm)
        }
        engine.prepare()
        try engine.start()
    }

    /// Apple accepts tap buffers of 100–400 ms. A fixed frame count falls outside that at 48 kHz.
    private func tapBufferFrameCount(for format: AVAudioFormat) -> AVAudioFrameCount {
        let frames = format.sampleRate * 0.15
        return AVAudioFrameCount(max(1, frames.rounded()))
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
        self.buffer.append(chunk)
        levelHandler?(level)
    }
}
