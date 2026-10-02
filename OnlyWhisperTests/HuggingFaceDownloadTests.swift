import XCTest
@testable import OnlyWhisper

final class HuggingFaceDownloadTests: XCTestCase {
    func testByteCountFollowsFileGrowth() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "generation_config.json")

        XCTAssertEqual(DownloadByteCount.at(url), 0)

        let first = Data(repeating: 1, count: 10)
        FileManager.default.createFile(atPath: url.path, contents: first)
        XCTAssertEqual(DownloadByteCount.at(url), Int64(first.count))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let extra = Data(repeating: 2, count: 25)
        try handle.write(contentsOf: extra)
        try handle.close()
        XCTAssertEqual(DownloadByteCount.at(url), Int64(first.count + extra.count))
    }

    func testTransferPlanSkipsACompleteFile() {
        XCTAssertEqual(DownloadTransferPlan.decide(localSize: 238, expected: 238), .alreadyComplete)
    }

    func testTransferPlanResumesAPartialFile() {
        XCTAssertEqual(DownloadTransferPlan.decide(localSize: 100, expected: 238), .resume)
    }

    func testTransferPlanStartsFreshWhenTheFileIsEmpty() {
        XCTAssertEqual(DownloadTransferPlan.decide(localSize: 0, expected: 238), .fresh)
        XCTAssertEqual(DownloadTransferPlan.decide(localSize: 300, expected: 238), .fresh)
    }

    func testDirectoryByteCountFollowsGrowthAndIgnoresOtherModels() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let marker = "openai_whisper-large-v3-v20240930_turbo"
        let model = root.appending(path: "models/argmaxinc/whisperkit-coreml/\(marker)", directoryHint: .isDirectory)
        let incomplete = root.appending(path: ".cache/huggingface/download/\(marker)", directoryHint: .isDirectory)
        let other = root.appending(path: "models/argmaxinc/whisperkit-coreml/openai_whisper-other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = Data(repeating: 1, count: 10)
        FileManager.default.createFile(atPath: model.appending(path: "config.json").path, contents: config)
        let partial = incomplete.appending(path: "weight.bin.etag.incomplete")
        FileManager.default.createFile(atPath: partial.path, contents: Data(repeating: 2, count: 25))
        FileManager.default.createFile(atPath: other.appending(path: "weight.bin").path, contents: Data(repeating: 3, count: 1000))

        XCTAssertEqual(DirectoryByteCount.at(root, containing: marker), 35)

        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 4, count: 15))
        try handle.close()
        XCTAssertEqual(DirectoryByteCount.at(root, containing: marker), 50)
    }

    func testWhisperInstallNeedsWeightsNotOnlyConfig() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let name = WhisperModelChoice.turbo
        let folder = WhisperModelChoice.installedFolder(downloadBase: root, modelName: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: folder.appending(path: "config.json").path, contents: Data([1]))
        XCTAssertFalse(WhisperModelChoice.isInstalled(downloadBase: root, modelName: name))

        let requirements = [
            "config.json": Int64(1),
            "AudioEncoder.mlmodelc/weights/weight.bin": Int64(1),
            "TextDecoder.mlmodelc/weights/weight.bin": Int64(1),
        ]
        for relative in requirements.keys where relative != "config.json" {
            let url = folder.appending(path: relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data([1]))
        }
        XCTAssertFalse(
            WhisperModelChoice.isInstalled(
                downloadBase: root,
                modelName: name,
                requirements: ["config.json": 1, "AudioEncoder.mlmodelc/weights/weight.bin": 4]
            )
        )
        XCTAssertTrue(WhisperModelChoice.isInstalled(downloadBase: root, modelName: name, requirements: requirements))
    }

    func testCancellationCoversURLSessionCancel() {
        XCTAssertTrue(DownloadStop.isCancellation(CancellationError()))
        XCTAssertTrue(DownloadStop.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(DownloadStop.isCancellation(URLError(.networkConnectionLost)))
    }

    func testCancelKillsTheRunningProcess() throws {
        let run = DownloadRun()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        run.begin(process)
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        run.cancel()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(process.isRunning)
        XCTAssertTrue(run.isCancelled)
    }

    func testExactByteFormatUsesTheFileTotal() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ModelByteFormat.string(from: 1_638_464_446, locale: english), "1.64 GB")
        XCTAssertEqual(ModelByteFormat.string(from: 626_718_238, locale: english), "627 MB")
        XCTAssertFalse(ModelByteFormat.string(from: 1_638_464_446, locale: english).contains("≈"))
    }

    func testRemovingATreeAlsoDeletesHiddenDownloadJunk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = root.appending(path: ".cache/huggingface/download/model", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: cache.appending(path: "weight.bin.etag.incomplete").path,
            contents: Data(repeating: 1, count: 32)
        )
        FileManager.default.createFile(atPath: root.appending(path: "config.json").path, contents: Data([1]))

        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}

@MainActor
final class WhisperCancelCleanupTests: XCTestCase {
    func testCancelDeletesEveryWhisperFileIncludingHiddenOnes() async throws {
        let root = ModelPaths.whisper
        let installed = WhisperModelChoice.isInstalled(
            downloadBase: root,
            modelName: ModelPaths.whisperModelName
        ) && WhisperTokenizerFiles.isInstalled(downloadBase: root)
        try XCTSkipIf(installed, "Refuses to delete the Whisper model installed on this Mac")
        let manager = ModelDownloadManager()
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let download = Task { await manager.download(.whisper) }
        let deadline = Date().addingTimeInterval(45)
        var sawBytes = false
        while Date() < deadline {
            if DirectoryByteCount.at(root, containing: "openai_whisper") > 0 {
                sawBytes = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        manager.cancel()
        await download.value

        XCTAssertTrue(sawBytes)
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(Self.leftoverFiles(at: root), [])
    }

    private static func leftoverFiles(at root: URL) -> [String] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { ($0 as? URL)?.path }
    }
}
