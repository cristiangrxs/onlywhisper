import AVFoundation
import Foundation

enum AudioFiles {
    static let extensions: Set<String> = ["mp3", "m4a", "wav", "aac", "caf", "flac", "aiff", "mp4", "mov", "m4v"]

    static func samples(from url: URL) async throws -> [Float] {
        let audioURL = try await monoAudioURL(for: url)
        let file = try AVAudioFile(forReading: audioURL)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadUnknown)
        }
        try file.read(into: input)
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let channel = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }

    static func collect(urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
                for case let item as URL in enumerator where extensions.contains(item.pathExtension.lowercased()) {
                    files.append(item)
                }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    private static func monoAudioURL(for url: URL) async throws -> URL {
        let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "caf", "flac", "aiff"]
        if audioExtensions.contains(url.pathExtension.lowercased()) {
            return url
        }
        let asset = AVURLAsset(url: url)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let destination = FileManager.default.temporaryDirectory.appending(path: "onlywhisper-\(UUID().uuidString).m4a")
        try await exporter.export(to: destination, as: .m4a)
        return destination
    }
}
