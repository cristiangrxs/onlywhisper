import AVFoundation
import XCTest
@testable import OnlyWhisper

@MainActor
final class FileTranscriptionQueueTests: XCTestCase {
    func testRejectedFileBecomesAFailedJob() {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = folder.appending(path: "notes.txt")
        try? Data("hello".utf8).write(to: notes)
        let queue = FileTranscriptionQueue()

        queue.enqueue([notes], speech: ScriptedTranscription(results: []), language: .automatic)

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs[0].state, .failed(FileTranscriptionCopy.formatUnsupported))
        XCTAssertEqual(queue.notice, FileTranscriptionCopy.formatUnsupported)
        XCTAssertFalse(queue.isDraining)
    }

    func testEmptyFolderShowsANotice() {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = FileTranscriptionQueue()

        queue.enqueue([folder], speech: ScriptedTranscription(results: []), language: .automatic)

        XCTAssertEqual(queue.jobs.map(\.state), [.failed(FileTranscriptionCopy.emptyFolder)])
        XCTAssertEqual(queue.notice, FileTranscriptionCopy.emptyFolder)
    }

    func testDuplicateWaitingFileIsSkipped() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let queue = FileTranscriptionQueue()
        let speech = ScriptedTranscription(results: [.success("Hallo")])

        queue.enqueue([wav], speech: speech, language: .german)
        queue.enqueue([wav], speech: speech, language: .german)

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.notice, FileTranscriptionCopy.alreadyQueued)
        await waitUntilIdle(queue)
        XCTAssertEqual(queue.jobs[0].state, .done)
    }

    func testTranscriptIsRecordedWithoutASidecarFile() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let existing = folder.appending(path: "voice.txt")
        try "old".write(to: existing, atomically: true, encoding: .utf8)
        let queue = FileTranscriptionQueue()
        let historyID = UUID()
        var recorded: [(name: String, text: String)] = []
        queue.record = { url, text in
            recorded.append((url.lastPathComponent, text))
            return historyID
        }

        queue.enqueue([wav], speech: ScriptedTranscription(results: [.success("Hallo")]), language: .german)
        await waitUntilIdle(queue)

        XCTAssertEqual(queue.jobs[0].state, .done)
        XCTAssertEqual(queue.jobs[0].transcript, "Hallo")
        XCTAssertEqual(queue.jobs[0].historyID, historyID)
        XCTAssertEqual(recorded.map(\.name), ["voice.wav"])
        XCTAssertEqual(recorded.map(\.text), ["Hallo"])
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "voice 2.txt").path))
    }

    func testRetryTranscribesAFailedFile() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let speech = ScriptedTranscription(results: [.failure(ProbeError()), .success("Hallo")])
        let queue = FileTranscriptionQueue()

        queue.enqueue([wav], speech: speech, language: .german)
        await waitUntilIdle(queue)
        XCTAssertEqual(queue.jobs[0].state, .failed(FileTranscriptionCopy.modelFailed))

        queue.retry(queue.jobs[0].id, speech: speech, language: .german)
        await waitUntilIdle(queue)

        XCTAssertEqual(queue.jobs[0].state, .done)
        XCTAssertEqual(queue.jobs[0].transcript, "Hallo")
    }

    func testFileAddedWhileWorkingIsTranscribedBeforeUnload() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try writeTone(named: "a.wav", in: folder)
        let second = try writeTone(named: "b.wav", in: folder)
        let speech = PausingTranscription()
        let queue = FileTranscriptionQueue()

        queue.enqueue([first], speech: speech, language: .german)
        await waitUntil { await speech.didStart() }
        queue.enqueue([second], speech: speech, language: .german)
        await speech.release()
        await waitUntilIdle(queue)

        XCTAssertEqual(queue.jobs.map(\.state), [.done, .done])
        let unloads = await speech.unloads()
        XCTAssertEqual(unloads, 1)
    }

    func testClearFinishedRemovesDoneAndFailedJobs() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let notes = folder.appending(path: "notes.txt")
        try "x".write(to: notes, atomically: true, encoding: .utf8)
        let queue = FileTranscriptionQueue()

        queue.enqueue([wav], speech: ScriptedTranscription(results: [.success("Hallo")]), language: .german)
        await waitUntilIdle(queue)
        queue.enqueue([notes], speech: ScriptedTranscription(results: []), language: .german)
        XCTAssertTrue(queue.hasFinishedJobs)

        queue.clearFinished()

        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertNil(queue.notice)
        XCTAssertFalse(queue.hasFinishedJobs)
    }

    func testRefineReplacesTheTranscript() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let queue = FileTranscriptionQueue()
        let gate = RefineGate()
        var recorded: [String] = []
        queue.record = { _, text in
            recorded.append(text)
            return UUID()
        }
        queue.refine = { text in
            await gate.entered()
            return "DE: \(text)"
        }
        var drained = false
        queue.onDrainFinished = { drained = true }

        queue.enqueue([wav], speech: ScriptedTranscription(results: [.success("Hallo")]), language: .romanian)
        await waitUntil { await gate.isWaiting() }
        XCTAssertEqual(queue.jobs.first?.state, .translating)
        await gate.release()
        await waitUntilIdle(queue)

        XCTAssertEqual(queue.jobs[0].state, .done)
        XCTAssertEqual(queue.jobs[0].transcript, "DE: Hallo")
        XCTAssertEqual(recorded, ["DE: Hallo"])
        XCTAssertTrue(drained)
    }

    func testEmptyRefineKeepsTheTranscript() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = try writeTone(named: "voice.wav", in: folder)
        let queue = FileTranscriptionQueue()
        queue.refine = { _ in "  " }

        queue.enqueue([wav], speech: ScriptedTranscription(results: [.success("Hallo")]), language: .romanian)
        await waitUntilIdle(queue)

        XCTAssertEqual(queue.jobs[0].transcript, "Hallo")
        XCTAssertEqual(queue.jobs[0].state, .done)
    }

    func testGermanDownloadProducesATranscript() async throws {
        let source = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads/Audio_test_german.ogg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path), "Test audio is not in Downloads")
        let weights = WhisperModelChoice.isInstalled(
            downloadBase: ModelPaths.whisper,
            modelName: ModelPaths.whisperModelName
        )
        let tokenizer = WhisperTokenizerFiles.isInstalled(downloadBase: ModelPaths.whisper)
        try XCTSkipUnless(weights && tokenizer, "Whisper model is not installed")

        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appending(path: "Audio_test_german.ogg")
        try FileManager.default.copyItem(at: source, to: copy)
        let queue = FileTranscriptionQueue()
        queue.enqueue([copy], speech: SpeechRouter(), language: .german)
        await waitUntilIdle(queue, timeout: .seconds(240))

        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs[0].state, .done)
        let text = try XCTUnwrap(queue.jobs[0].transcript)
        XCTAssertGreaterThan(text.count, 10)
        XCTAssertTrue(text.contains { $0.isLetter })
    }

    private func waitUntilIdle(_ queue: FileTranscriptionQueue, timeout: Duration = .seconds(5)) async {
        await waitUntil(timeout: timeout) {
            !queue.isDraining && queue.jobs.allSatisfy(\.state.isFinished)
        }
    }

    private func waitUntil(timeout: Duration = .seconds(5), condition: () async -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while await !condition() {
            if clock.now - start > timeout {
                XCTFail("Timed out waiting for the queue")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "onlywhisper-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeTone(named name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        let sampleRate = 16_000.0
        let frames = 8_000
        let samples = (0..<frames).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.2)
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { raw in
            guard let base = raw.baseAddress, let channel = buffer.floatChannelData else { return }
            channel[0].update(from: base, count: frames)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}

private actor RefineGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting = false

    func isWaiting() -> Bool { waiting }

    func entered() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
            waiting = true
        }
    }

    func release() {
        waiting = false
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private struct ProbeError: Error {}

private actor ScriptedTranscription: FileSpeechTranscribing {
    private var results: [Result<String, Error>]

    init(results: [Result<String, Error>]) {
        self.results = results
    }

    func transcribeFile(samples: [Float], language: SpeechChoice) async throws -> String {
        guard !results.isEmpty else { throw ProbeError() }
        return try results.removeFirst().get()
    }

    func unloadFileModel() async {}
}

private actor PausingTranscription: FileSpeechTranscribing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var calls = 0
    private(set) var unloadCount = 0

    func didStart() -> Bool { started }

    func unloads() -> Int { unloadCount }

    func transcribeFile(samples: [Float], language: SpeechChoice) async throws -> String {
        calls += 1
        let call = calls
        if call == 1 {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                continuation = cont
                started = true
            }
        }
        return call == 1 ? "Eins" : "Zwei"
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }

    func unloadFileModel() async {
        unloadCount += 1
    }
}
