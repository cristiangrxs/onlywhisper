import FluidAudio
import Foundation

struct ModelInfo: Identifiable, Sendable {
    let id: ModelID
    let name: String
    let role: String
    let size: String
    let symbol: String
    /// Share of a full download, used to weight progress when several models are fetched together.
    let progressWeight: Double

    static let catalog: [ModelInfo] = [
        ModelInfo(
            id: .whisper,
            name: WhisperModelChoice.displayName,
            role: t("Speech recognition", "Spracherkennung"),
            size: WhisperModelChoice.displaySize,
            symbol: "waveform",
            progressWeight: 0.40
        ),
        ModelInfo(
            id: .qwen,
            name: "Qwen3 4B",
            role: t("Polish and rewrite", "Glätten und Umschreiben"),
            size: "≈ 2.5 GB",
            symbol: "text.badge.star",
            progressWeight: 0.60
        ),
    ]

    /// Models this build downloads and treats as required. Parakeet is not part of speech recognition.
    static let requiredIDs: [ModelID] = [.whisper, .qwen]

    static func info(_ id: ModelID) -> ModelInfo? {
        catalog.first { $0.id == id }
    }
}

enum ModelState: Equatable {
    case ready
    case updateAvailable
    case downloading(Double)
    case waiting
    case missing
}

@MainActor
@Observable
final class ModelDownloadManager {
    var fraction: Double = 0
    var status: String = ""
    var isRunning = false
    var lastError: String?
    private(set) var isReady = false
    private(set) var missingIDs: [ModelID] = []
    private(set) var outdatedIDs: [ModelID] = []

    private var installations = ModelInstallationStore()
    private var activeModel: ModelID?
    private var queued: Set<ModelID> = []
    private var activePortion: Double = 0

    func refreshReadyState() {
        installations = ModelInstallationStore.load(from: ModelPaths.installations)
        var changed = false
        for id in ModelID.allCases {
            if installations.adopt(id: id, filesPresent: filesPresent(id), expected: ModelRevision.expected(id)) {
                changed = true
            }
        }
        if changed {
            try? installations.save(to: ModelPaths.installations)
        }
        syncCatalog()
    }

    func state(of model: ModelInfo) -> ModelState {
        if isRunning, activeModel == model.id {
            return .downloading(activePortion)
        }
        if isRunning, queued.contains(model.id) {
            return .waiting
        }
        switch installStatus(model.id) {
        case .current: return .ready
        case .outdated: return .updateAvailable
        case .missing: return .missing
        }
    }

    /// The expected build is on disk and can still be used, including while an update is waiting.
    func isUsable(_ id: ModelID) -> Bool {
        filesPresent(id)
    }

    func download(_ id: ModelID) async {
        guard installStatus(id) == .missing else { return }
        await run([id], replacingOutdated: false)
    }

    func downloadMissing() async {
        await run(missingIDs, replacingOutdated: false)
    }

    func update(_ id: ModelID) async {
        guard installStatus(id) == .outdated else { return }
        await run([id], replacingOutdated: true)
    }

    func updateOutdated() async {
        await run(outdatedIDs, replacingOutdated: true)
    }

    /// Downloads every model that is missing or older than the build shipped with this app.
    func downloadRequiredModels() async {
        let needed = ModelInfo.requiredIDs.filter { installStatus($0) != .current }
        await run(needed, replacingOutdated: true)
    }

    func remove(_ id: ModelID) {
        do {
            try deleteFiles(id)
            installations.clear(id: id)
            try installations.save(to: ModelPaths.installations)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        syncCatalog()
    }

    private func run(_ ids: [ModelID], replacingOutdated: Bool) async {
        guard !isRunning, !ids.isEmpty else { return }
        isRunning = true
        lastError = nil
        fraction = 0
        activePortion = 0
        queued = Set(ids)
        activeModel = nil
        defer {
            isRunning = false
            activeModel = nil
            queued = []
            activePortion = 0
            refreshReadyState()
        }
        ModelHub.offlineMode = false
        do {
            for id in ModelInfo.requiredIDs where ids.contains(id) {
                queued.remove(id)
                activeModel = id
                activePortion = 0
                if replacingOutdated, installStatus(id) == .outdated {
                    try deleteFiles(id)
                    installations.clear(id: id)
                    try installations.save(to: ModelPaths.installations)
                }
                try await fetch(id, among: ids)
                installations.set(id: id, revision: ModelRevision.expected(id))
                try installations.save(to: ModelPaths.installations)
                syncCatalog()
            }
            ModelHub.offlineMode = true
            fraction = 1
            status = t("Ready", "Bereit")
        } catch {
            lastError = error.localizedDescription
            status = t("Download stopped", "Download angehalten")
            ModelHub.offlineMode = false
        }
    }

    private func fetch(_ id: ModelID, among ids: [ModelID]) async throws {
        switch id {
        case .parakeet:
            status = t("Downloading speech model", "Sprachmodell wird geladen")
            try FileManager.default.createDirectory(at: ModelPaths.parakeet, withIntermediateDirectories: true)
            report(id: id, ids: ids, portion: 0)
            if !filesPresent(.parakeet) {
                _ = try await AsrModels.download(
                    to: ModelPaths.parakeet,
                    version: .ultra,
                    encoderPrecision: .int8
                ) { [weak self] progress in
                    let portion = progress.fractionCompleted
                    Task { @MainActor in
                        self?.report(id: id, ids: ids, portion: portion)
                    }
                }
            }
            report(id: id, ids: ids, portion: 1)
        case .whisper:
            status = t("Downloading Whisper", "Whisper wird geladen")
            try FileManager.default.createDirectory(at: ModelPaths.whisper, withIntermediateDirectories: true)
            report(id: id, ids: ids, portion: 0)
            try await WhisperEngine.downloadIfNeeded()
            report(id: id, ids: ids, portion: 1)
        case .qwen:
            status = t("Downloading writing model", "Schreibmodell wird geladen")
            try FileManager.default.createDirectory(at: ModelPaths.qwen, withIntermediateDirectories: true)
            try await downloadQwen(among: ids)
        }
    }

    private func downloadQwen(among ids: [ModelID]) async throws {
        let files = try await HuggingFaceDownloader.list(repository: ModelPaths.qwenRepository)
        let total = max(files.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }, 1)
        var completed = Int64(0)
        report(id: .qwen, ids: ids, portion: 0)
        for file in files {
            let already = completed
            let size = Int64(file.size ?? 0)
            try await HuggingFaceDownloader.download(
                repository: ModelPaths.qwenRepository,
                file: file,
                to: ModelPaths.qwen
            ) { [weak self] received, _ in
                let overall = already + received
                let portion = Double(overall) / Double(total)
                Task { @MainActor in
                    self?.report(id: .qwen, ids: ids, portion: portion)
                }
            }
            completed += size
        }
        report(id: .qwen, ids: ids, portion: 1)
    }

    private func report(id: ModelID, ids: [ModelID], portion: Double) {
        guard activeModel == id else { return }
        let clamped = min(max(portion, 0), 1)
        activePortion = clamped
        let weights = ids.map { ModelInfo.info($0)?.progressWeight ?? 1 }
        let total = max(weights.reduce(0, +), 0.01)
        var start = 0.0
        for (index, candidate) in ids.enumerated() {
            let span = weights[index] / total
            if candidate == id {
                fraction = start + span * clamped
                return
            }
            start += span
        }
    }

    private func installStatus(_ id: ModelID) -> ModelInstallStatus {
        installations.status(
            id: id,
            filesPresent: filesPresent(id),
            legacyPresent: id == .whisper && ModelPaths.whisperLegacyPresent(),
            expected: ModelRevision.expected(id)
        )
    }

    private func filesPresent(_ id: ModelID) -> Bool {
        switch id {
        case .parakeet:
            AsrModels.modelsExist(at: ModelPaths.parakeet, version: .ultra, encoderPrecision: .int8)
        case .whisper:
            WhisperModelChoice.isInstalled(downloadBase: ModelPaths.whisper, modelName: ModelPaths.whisperModelName)
        case .qwen:
            qwenWeightsPresent
        }
    }

    private var qwenWeightsPresent: Bool {
        FileManager.default.fileExists(atPath: ModelPaths.qwen.appending(path: "model.safetensors").path)
            && FileManager.default.fileExists(atPath: ModelPaths.qwen.appending(path: "config.json").path)
    }

    private func deleteFiles(_ id: ModelID) throws {
        switch id {
        case .parakeet:
            try removeIfPresent(ModelPaths.parakeet)
            try removeIfPresent(ModelPaths.parakeetWeights)
        case .whisper:
            try removeIfPresent(ModelPaths.whisper)
        case .qwen:
            try removeIfPresent(ModelPaths.qwen)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func syncCatalog() {
        missingIDs = ModelInfo.requiredIDs.filter { installStatus($0) == .missing }
        outdatedIDs = ModelInfo.requiredIDs.filter { installStatus($0) == .outdated }
        isReady = missingIDs.isEmpty && outdatedIDs.isEmpty
    }
}
