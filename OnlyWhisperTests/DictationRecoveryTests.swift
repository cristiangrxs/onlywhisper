import AVFoundation
import XCTest
@testable import OnlyWhisper

final class DictationRecoveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        if FileManager.default.fileExists(atPath: "/tmp/onlywhisper-load-models") {
            executionTimeAllowance = 1800
        }
    }

    func testLoadStartedBeforeUnloadIsDiscarded() {
        XCTAssertFalse(ModelLoadGuard.keeps(started: 1, current: 2))
        XCTAssertTrue(ModelLoadGuard.keeps(started: 2, current: 2))
    }

    func testRevisionIsRecordedOnlyForACompleteInstall() {
        XCTAssertTrue(InstallCommit.shouldRecord(filesPresent: true))
        XCTAssertFalse(InstallCommit.shouldRecord(filesPresent: false))
    }

    func testIncompleteQwenStaysMissingSoItCanBeDownloadedAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let weights = directory.appending(path: "model.safetensors")
        FileManager.default.createFile(atPath: weights.path, contents: Data())
        FileManager.default.createFile(atPath: directory.appending(path: "config.json").path, contents: Data([1]))

        XCTAssertFalse(QwenModelFiles.isInstalled(at: directory))
        var store = ModelInstallationStore()
        XCTAssertFalse(store.adopt(id: .qwen, filesPresent: false, expected: ModelRevision.qwen))
        XCTAssertEqual(
            store.status(id: .qwen, filesPresent: false, legacyPresent: false, expected: ModelRevision.qwen),
            .missing
        )
    }

    func testQwenInstallNeedsTheFullWeightsAndTokenizer() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for (name, size) in QwenModelFiles.requirements where name != "model.safetensors" {
            FileManager.default.createFile(atPath: directory.appending(path: name).path, contents: Data(count: Int(size)))
        }
        XCTAssertFalse(QwenModelFiles.isInstalled(at: directory))

        let weights = directory.appending(path: "model.safetensors")
        FileManager.default.createFile(atPath: weights.path, contents: Data(count: 1))
        XCTAssertFalse(QwenModelFiles.isInstalled(at: directory))
    }

    func testWhisperWithoutTheTokenizerIsNotReady() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(WhisperTokenizerFiles.isInstalled(downloadBase: root))
        let folder = WhisperTokenizerFiles.folder(downloadBase: root)
        XCTAssertTrue(folder.path.hasSuffix("models/openai/whisper-large-v3"))
    }

    func testWhisperRequirementsIncludeTheMelSpectrogram() {
        let requirements = WhisperModelChoice.weightRequirements(for: WhisperModelChoice.turbo)
        XCTAssertEqual(requirements["MelSpectrogram.mlmodelc/weights/weight.bin"], 373_376)
        XCTAssertEqual(requirements["MelSpectrogram.mlmodelc/model.mil"], 10_143)
        let compact = WhisperModelChoice.weightRequirements(for: WhisperModelChoice.compact)
        XCTAssertEqual(compact["MelSpectrogram.mlmodelc/coremldata.bin"], 329)
    }

    func testPolishFailureKeepsTheOriginalWords() {
        let step = PolishFallback.resolve(original: "morgen treffen", result: .failure(CancellationError()))
        XCTAssertEqual(step.text, "morgen treffen")
        XCTAssertTrue(step.fellBack)
    }

    func testEmptyPolishKeepsTheOriginalWords() {
        let step = PolishFallback.resolve(original: "morgen treffen", result: .success("  "))
        XCTAssertEqual(step.text, "morgen treffen")
        XCTAssertTrue(step.fellBack)
    }

    func testPolishSuccessReplacesTheDraft() {
        let step = PolishFallback.resolve(original: "äh morgen", result: .success("Morgen"))
        XCTAssertEqual(step.text, "Morgen")
        XCTAssertFalse(step.fellBack)
    }

    func testDeadlineReturnsAFastValue() async throws {
        let value = try await AsyncDeadline.value(.milliseconds(500)) { 7 }
        XCTAssertEqual(value, 7)
    }

    func testDeadlineThrowsWhenTheWorkOutlastsIt() async {
        do {
            _ = try await AsyncDeadline.value(.milliseconds(40)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
            XCTFail("expected a timeout")
        } catch is AsyncDeadline.TimedOut {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// Opt-in check against the models on this Mac. Normal test runs skip it.
    func testInstalledModelsAnswerAndSurviveUnload() async throws {
        let loadModels = ProcessInfo.processInfo.environment["ONLYWHISPER_LOAD_MODELS"] == "1"
            || FileManager.default.fileExists(atPath: "/tmp/onlywhisper-load-models")
        try XCTSkipUnless(loadModels)
        let samples = try Self.spokenSamples("Hallo das ist ein Test")
        let ready = await Self.ensureModels()
        guard ready else { return }
        let engine = WhisperEngine()
        try await engine.prepare()
        let text = try await engine.transcribe(samples: samples, languageCode: "de", dictation: true)
        await engine.unload()
        try await engine.prepare()
        let again = try await engine.transcribe(samples: samples, languageCode: "de", dictation: true)
        await engine.unload()
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(again.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let qwen = QwenPolisher()
        let polished = try await qwen.polish(raw: "äh hallo das ist ein test", kind: .dictation)
        await qwen.unload()
        XCTAssertFalse(polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    private static func ensureModels() async -> Bool {
        let whisperBase = ModelPaths.whisper
        let downloads = ModelDownloadManager()
        downloads.refreshReadyState()
        if !WhisperModelChoice.isInstalled(downloadBase: whisperBase, modelName: ModelPaths.whisperModelName)
            || !WhisperTokenizerFiles.isInstalled(downloadBase: whisperBase) {
            await downloads.download(.whisper)
        }
        let weightsReady = WhisperModelChoice.isInstalled(
            downloadBase: whisperBase,
            modelName: ModelPaths.whisperModelName
        )
        let tokenizerReady = WhisperTokenizerFiles.isInstalled(downloadBase: whisperBase)
        let qwenReady = QwenModelFiles.isInstalled(at: ModelPaths.qwen)
        XCTAssertTrue(
            weightsReady && tokenizerReady && qwenReady,
            "weights=\(weightsReady) tokenizer=\(tokenizerReady) qwen=\(qwenReady) error=\(downloads.lastError ?? "none")"
        )
        return weightsReady && tokenizerReady && qwenReady
    }

    private static func spokenSamples(_ phrase: String) throws -> [Float] {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let aiff = directory.appending(path: "speech.aiff")
        let wav = directory.appending(path: "speech.wav")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, phrase]
        try say.run()
        say.waitUntilExit()
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path]
        try convert.run()
        convert.waitUntilExit()
        let file = try AVAudioFile(forReading: wav)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let channel = buffer.floatChannelData else {
            throw NSError(domain: "DictationRecoveryTests", code: 1)
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}
