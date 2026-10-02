import AVFoundation
import XCTest
@testable import OnlyWhisper

final class AudioFilesTests: XCTestCase {
    func testPickerTypesIncludeOggAndOpus() {
        let identifiers = Set(AudioFiles.contentTypes.map(\.identifier))
        XCTAssertTrue(identifiers.contains("org.xiph.ogg-audio"))
        XCTAssertTrue(identifiers.contains("public.mp3"))
        XCTAssertTrue(AudioFiles.extensions.isSuperset(of: ["ogg", "oga", "opus", "mp3", "m4a", "wav", "mp4"]))
    }

    func testCollectAcceptsSupportedFilesAndRejectsTheRest() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = folder.appending(path: "nested/song.ogg")
        try FileManager.default.createDirectory(at: song.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ogg".utf8).write(to: song)
        try Data("notes".utf8).write(to: folder.appending(path: "notes.txt"))
        let loose = folder.appending(path: "voice.opus")
        try Data("opus".utf8).write(to: loose)
        let missing = folder.appending(path: "gone.wav")

        let intake = AudioFiles.collect(urls: [folder, loose, missing, folder.appending(path: "notes.txt")])

        XCTAssertEqual(Set(intake.accepted.map(\.lastPathComponent)), ["song.ogg", "voice.opus"])
        XCTAssertEqual(intake.rejected.map(\.reason), [
            FileTranscriptionCopy.unreadable,
            FileTranscriptionCopy.formatUnsupported,
        ])
    }

    func testCollectReportsAnEmptyFolder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x".utf8).write(to: folder.appending(path: "readme.txt"))

        let intake = AudioFiles.collect(urls: [folder])

        XCTAssertTrue(intake.accepted.isEmpty)
        XCTAssertEqual(intake.rejected, [RejectedFile(url: folder, reason: FileTranscriptionCopy.emptyFolder)])
    }

    func testResampledWavKeepsTheWholeDuration() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "tone.wav")
        let frames = 44_100
        try writeWAV(sine(frames: frames, sampleRate: 44_100), sampleRate: 44_100, to: url)

        let samples = try await AudioFiles.samples(from: url)

        XCTAssertEqual(samples.count, 16_000, accuracy: 128)
        XCTAssertGreaterThan(rms(samples), 0.05)
    }

    func testVorbisFixtureDecodesAtWhisperRate() async throws {
        try await assertRoundTrip(.vorbis, name: "tone.ogg")
    }

    func testOpusFixtureDecodesAtWhisperRate() async throws {
        try await assertRoundTrip(.opus, name: "tone.opus")
    }

    func testDownloadsOggDecodesToSamples() async throws {
        let source = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads/Audio_test_german.ogg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path), "Test audio is not in Downloads")

        let samples = try await AudioFiles.samples(from: source)

        XCTAssertGreaterThan(samples.count, 16_000)
        XCTAssertGreaterThan(rms(samples), 0.001)
    }

    private func assertRoundTrip(_ codec: CompressedFixtureCodec, name: String) async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: name)
        let sourceRate = 48_000.0
        let frames = 24_000
        try AudioFiles.writeCompressedFixture(
            samples: sine(frames: frames, sampleRate: sourceRate),
            sampleRate: sourceRate,
            codec: codec,
            to: url
        )

        let samples = try await AudioFiles.samples(from: url)
        let expected = Int(Double(frames) * 16_000 / sourceRate)

        XCTAssertEqual(samples.count, expected, accuracy: 3_200)
        XCTAssertGreaterThan(rms(samples), 0.05)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "onlywhisper-audio-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func sine(frames: Int, sampleRate: Double) -> [Float] {
        (0..<frames).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.4)
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let energy = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(energy / Float(samples.count))
    }

    private func writeWAV(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { raw in
            guard let base = raw.baseAddress, let channel = buffer.floatChannelData else { return }
            channel[0].update(from: base, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
