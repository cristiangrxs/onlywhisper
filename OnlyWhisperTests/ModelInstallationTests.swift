import XCTest
@testable import OnlyWhisper

final class ModelInstallationTests: XCTestCase {
    func testMissingWhenFilesAreAbsent() {
        XCTAssertEqual(
            ModelInstallStatus.resolve(filesPresent: false, installedRevision: nil, expected: "ultra-int8-1"),
            .missing
        )
    }

    func testCurrentWhenRevisionMatches() {
        XCTAssertEqual(
            ModelInstallStatus.resolve(filesPresent: true, installedRevision: "ultra-int8-1", expected: "ultra-int8-1"),
            .current
        )
    }

    func testOutdatedWhenRevisionDiffers() {
        XCTAssertEqual(
            ModelInstallStatus.resolve(filesPresent: true, installedRevision: "ultra-int8-1", expected: "ultra-int8-2"),
            .outdated
        )
    }

    func testExistingInstallWithoutRevisionCountsAsCurrent() {
        XCTAssertEqual(
            ModelInstallStatus.resolve(filesPresent: true, installedRevision: nil, expected: "ultra-int8-1"),
            .current
        )
    }

    func testParakeetCleanupCoversTheFolderFluidAudioWrites() {
        let names = ModelPaths.parakeetStorageURLs(in: URL(fileURLWithPath: "/models")).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Parakeet", "parakeet-ultra", "parakeet-ultra-coreml"])
    }

    func testStoreAdoptsExistingInstallOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "installations.json")

        var store = ModelInstallationStore.load(from: url)
        XCTAssertTrue(store.adopt(id: .parakeet, filesPresent: true, expected: ModelRevision.parakeet))
        XCTAssertFalse(store.adopt(id: .parakeet, filesPresent: true, expected: "ultra-int8-2"))
        try store.save(to: url)

        let loaded = ModelInstallationStore.load(from: url)
        XCTAssertEqual(loaded.revisions["parakeet"], ModelRevision.parakeet)
        XCTAssertEqual(
            loaded.status(id: .parakeet, filesPresent: true, legacyPresent: false, expected: ModelRevision.parakeet),
            .current
        )
    }

    func testStoreKeepsOlderRevision() {
        var store = ModelInstallationStore(revisions: ["qwen": "old"])
        XCTAssertFalse(store.adopt(id: .qwen, filesPresent: true, expected: ModelRevision.qwen))
        XCTAssertEqual(
            store.status(id: .qwen, filesPresent: true, legacyPresent: false, expected: ModelRevision.qwen),
            .outdated
        )
    }

    func testLegacyFilesWithoutTheCurrentBuildAreOutdated() {
        let store = ModelInstallationStore()
        XCTAssertEqual(
            store.status(id: .whisper, filesPresent: false, legacyPresent: true, expected: "large-v3"),
            .outdated
        )
        XCTAssertEqual(
            store.status(id: .whisper, filesPresent: false, legacyPresent: false, expected: "large-v3"),
            .missing
        )
    }

    func testWhisperLegacyDetectsADifferentFolder() {
        XCTAssertTrue(
            WhisperModelChoice.hasLegacyInstall(
                folderNames: ["openai_whisper-large-v3-v20240930_626MB", "tokenizer"],
                currentModelName: WhisperModelChoice.turbo
            )
        )
        XCTAssertFalse(
            WhisperModelChoice.hasLegacyInstall(
                folderNames: [WhisperModelChoice.folderName(for: WhisperModelChoice.turbo)],
                currentModelName: WhisperModelChoice.turbo
            )
        )
    }
}
