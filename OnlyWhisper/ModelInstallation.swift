import Foundation

enum ModelID: String, Codable, CaseIterable, Identifiable, Sendable {
    case parakeet
    case whisper
    case qwen

    var id: String { rawValue }
}

/// Revisions shipped with this app. Bump the constant when a model build changes,
/// so existing installs show an update instead of keeping the previous files.
enum ModelRevision {
    static let parakeet = "ultra-int8-1"
    static let qwen = "Qwen3-4B-Instruct-2507-4bit-1"

    /// Whisper's identity is the model folder name.
    static var whisper: String { WhisperModelChoice.current }

    static func expected(_ id: ModelID) -> String {
        switch id {
        case .parakeet: parakeet
        case .whisper: whisper
        case .qwen: qwen
        }
    }
}

enum ModelInstallStatus: Equatable, Sendable {
    case missing
    case current
    case outdated

    /// Files with no recorded revision are the install that predates this manifest.
    /// They count as current until a later app version bumps `expected`.
    static func resolve(filesPresent: Bool, installedRevision: String?, expected: String) -> ModelInstallStatus {
        guard filesPresent else { return .missing }
        guard let installedRevision else { return .current }
        return installedRevision == expected ? .current : .outdated
    }
}

struct ModelInstallationStore: Equatable, Codable, Sendable {
    var revisions: [String: String]

    init(revisions: [String: String] = [:]) {
        self.revisions = revisions
    }

    static func load(from url: URL) -> ModelInstallationStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(ModelInstallationStore.self, from: data) else {
            return ModelInstallationStore()
        }
        return store
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Records the expected revision once, for weights that were downloaded before the manifest existed.
    @discardableResult
    mutating func adopt(id: ModelID, filesPresent: Bool, expected: String) -> Bool {
        guard filesPresent, revisions[id.rawValue] == nil else { return false }
        revisions[id.rawValue] = expected
        return true
    }

    mutating func set(id: ModelID, revision: String) {
        revisions[id.rawValue] = revision
    }

    mutating func clear(id: ModelID) {
        revisions[id.rawValue] = nil
    }

    func status(id: ModelID, filesPresent: Bool, legacyPresent: Bool, expected: String) -> ModelInstallStatus {
        if filesPresent {
            return ModelInstallStatus.resolve(
                filesPresent: true,
                installedRevision: revisions[id.rawValue],
                expected: expected
            )
        }
        if legacyPresent { return .outdated }
        return .missing
    }
}

enum InstallCommit {
    /// A revision is stored only after every required file is complete. Otherwise the download is discarded.
    static func shouldRecord(filesPresent: Bool) -> Bool {
        filesPresent
    }
}
