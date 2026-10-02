import AVFoundation
import Foundation
import SFBAudioEngine
import UniformTypeIdentifiers

enum FileTranscriptionCopy {
    static var formatUnsupported: String { t("Format not supported.", "Format wird nicht unterstützt.") }
    static var unreadable: String { t("Couldn't read this file.", "Diese Datei konnte nicht gelesen werden.") }
    static var noSpeech: String { t("No speech found.", "Keine Sprache gefunden.") }
    static var interrupted: String { t("Transcription was interrupted.", "Die Transkription wurde unterbrochen.") }
    static var modelFailed: String { t("Transcription failed.", "Die Transkription ist fehlgeschlagen.") }
    static var emptyFolder: String { t("No supported audio or video in this folder.", "In diesem Ordner gibt es keine unterstützte Datei.") }
    static var alreadyQueued: String { t("These files are already in the list.", "Diese Dateien sind bereits in der Liste.") }
    static var importFailed: String { t("Couldn't open the selected files.", "Die ausgewählten Dateien konnten nicht geöffnet werden.") }
}

struct RejectedFile: Equatable, Sendable {
    var url: URL
    var reason: String
}

struct FileIntake: Equatable, Sendable {
    var accepted: [URL]
    var rejected: [RejectedFile]
}

enum CompressedFixtureCodec: Sendable {
    case vorbis
    case opus
}

enum AudioFiles {
    static let nativeExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "caf", "flac", "aiff", "aif"]
    static let oggExtensions: Set<String> = ["ogg", "oga", "opus"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let extensions: Set<String> = nativeExtensions.union(oggExtensions).union(videoExtensions)
    static let formatSummary = "MP3, M4A, WAV, MP4, MOV, OGG, OPUS"

    /// Types the file picker and `collect` both accept. Ogg and Opus share `org.xiph.ogg-audio` on macOS.
    static var contentTypes: [UTType] {
        var types: [UTType] = []
        func add(_ type: UTType?) {
            guard let type, !types.contains(type) else { return }
            types.append(type)
        }
        add(.mp3)
        add(.wav)
        add(.aiff)
        add(.mpeg4Audio)
        add(.mpeg4Movie)
        add(.quickTimeMovie)
        add(UTType("com.apple.m4a-audio"))
        add(UTType("public.aac-audio"))
        add(UTType("org.xiph.flac"))
        add(UTType("com.apple.coreaudio-format"))
        add(UTType("org.xiph.ogg-audio"))
        add(UTType("com.apple.m4v-video"))
        for ext in extensions.sorted() {
            add(UTType(filenameExtension: ext))
        }
        return types
    }

    static func samples(from url: URL) async throws -> [Float] {
        let ext = url.pathExtension.lowercased()
        if oggExtensions.contains(ext) {
            return try samples(fromOgg: url)
        }
        if videoExtensions.contains(ext) {
            let temporary = try await exportAudio(from: url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            return try samples(fromAudioFile: temporary)
        }
        return try samples(fromAudioFile: url)
    }

    static func collect(urls: [URL]) -> FileIntake {
        var accepted: [URL] = []
        var rejected: [RejectedFile] = []
        var seen: Set<String> = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                rejected.append(RejectedFile(url: url, reason: FileTranscriptionCopy.unreadable))
                continue
            }
            if isDirectory.boolValue {
                let found = files(in: url)
                if found.isEmpty {
                    rejected.append(RejectedFile(url: url, reason: FileTranscriptionCopy.emptyFolder))
                } else {
                    for file in found {
                        append(file, to: &accepted, seen: &seen)
                    }
                }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                append(url, to: &accepted, seen: &seen)
            } else {
                rejected.append(RejectedFile(url: url, reason: FileTranscriptionCopy.formatUnsupported))
            }
        }
        return FileIntake(accepted: accepted, rejected: rejected)
    }

    /// Encodes a short PCM buffer so tests can round-trip Vorbis and Opus without a checked-in binary.
    static func writeCompressedFixture(
        samples: [Float],
        sampleRate: Double,
        codec: CompressedFixtureCodec,
        to url: URL
    ) throws {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let encoderName: AudioEncoder.Name = codec == .opus ? .oggOpus : .oggVorbis
        let encoder = try AudioEncoder(url: url, encoderName: encoderName)
        try encoder.setSourceFormat(sourceFormat)
        try encoder.openReturningError()
        defer { try? encoder.close() }
        guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        input.frameLength = AVAudioFrameCount(samples.count)
        if let channel = input.floatChannelData {
            samples.withUnsafeBufferPointer { raw in
                guard let base = raw.baseAddress else { return }
                channel[0].update(from: base, count: samples.count)
            }
        }
        let processing = encoder.processingFormat
        let encoded = try convert(input, to: processing)
        let slice = AVAudioFrameCount(max(processing.sampleRate * 0.02, 1))
        var offset: AVAudioFrameCount = 0
        while offset < encoded.frameLength {
            let count = min(slice, encoded.frameLength - offset)
            guard let chunk = sliceBuffer(encoded, from: offset, count: count) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try encoder.encode(from: chunk)
            offset += count
        }
        try encoder.finish()
    }

    private static func append(_ url: URL, to accepted: inout [URL], seen: inout Set<String>) {
        let path = url.standardizedFileURL.path
        guard seen.insert(path).inserted else { return }
        accepted.append(url)
    }

    private static func files(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var found: [URL] = []
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            if extensions.contains(item.pathExtension.lowercased()) {
                found.append(item)
            }
        }
        return found
    }

    private static func samples(fromOgg url: URL) throws -> [Float] {
        let decoder = try AudioDecoder(url: url)
        try decoder.open()
        defer { try? decoder.close() }
        let format = decoder.processingFormat
        return try resample(format: format) {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
                throw CocoaError(.fileReadUnknown)
            }
            try decoder.decode(into: buffer)
            return buffer.frameLength == 0 ? nil : buffer
        }
    }

    private static func samples(fromAudioFile url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 4_096
        return try resample(format: format) {
            guard file.framePosition < file.length else { return nil }
            let frames = min(chunk, AVAudioFrameCount(file.length - file.framePosition))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
                return nil
            }
            try file.read(into: buffer, frameCount: frames)
            return buffer.frameLength == 0 ? nil : buffer
        }
    }

    private static func exportAudio(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let destination = FileManager.default.temporaryDirectory.appending(path: "onlywhisper-\(UUID().uuidString).m4a")
        do {
            try await exporter.export(to: destination, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    /// `.endOfStream` flushes the resampler. `.noDataNow` keeps the last samples in the converter.
    private static func resample(format: AVAudioFormat, read: @escaping () throws -> AVAudioPCMBuffer?) throws -> [Float] {
        let target = whisperFormat
        if isWhisperFormat(format) {
            var samples: [Float] = []
            while let buffer = try read() {
                guard let channel = buffer.floatChannelData else { continue }
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
            }
            return samples
        }
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let feed = ConverterFeed(read: read)
        var samples: [Float] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8_192) else {
                throw CocoaError(.fileReadUnknown)
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                feed.next(outStatus)
            }
            if let feedError = feed.readError { throw feedError }
            if let error { throw error }
            if status == .error { throw CocoaError(.fileReadCorruptFile) }
            if output.frameLength > 0, let channel = output.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
            }
            if status == .endOfStream { break }
            if feed.inputExhausted, output.frameLength == 0 { break }
        }
        return samples
    }

    private static var whisperFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    }

    private static func isWhisperFormat(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && format.sampleRate == 16_000
            && format.channelCount == 1
            && !format.isInterleaved
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        if status == .error { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    private static func sliceBuffer(
        _ buffer: AVAudioPCMBuffer,
        from offset: AVAudioFrameCount,
        count: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count) else { return nil }
        slice.frameLength = count
        let channels = Int(buffer.format.channelCount)
        if let source = buffer.floatChannelData, let destination = slice.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
            }
            return slice
        }
        if let source = buffer.int16ChannelData, let destination = slice.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
            }
            return slice
        }
        if let source = buffer.int32ChannelData, let destination = slice.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel].advanced(by: Int(offset)), count: Int(count))
            }
            return slice
        }
        return nil
    }
}

/// Holds converter input across the synchronous input callback without crossing an actor.
private final class ConverterFeed: @unchecked Sendable {
    var inputExhausted = false
    var readError: Error?
    private let read: () throws -> AVAudioPCMBuffer?

    init(read: @escaping () throws -> AVAudioPCMBuffer?) {
        self.read = read
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if inputExhausted {
            outStatus.pointee = .endOfStream
            return nil
        }
        do {
            if let buffer = try read(), buffer.frameLength > 0 {
                outStatus.pointee = .haveData
                return buffer
            }
        } catch {
            readError = error
        }
        inputExhausted = true
        outStatus.pointee = .endOfStream
        return nil
    }
}
