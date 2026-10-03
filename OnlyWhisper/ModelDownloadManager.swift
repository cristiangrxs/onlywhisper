import FluidAudio
import Foundation

struct ModelInfo: Identifiable, Sendable {
    let id: ModelID
    let name: String
    let role: String
    /// What this model is good at. Speech models share this text in setup and Settings.
    let summary: String
    let size: String
    let symbol: String
    /// Share of a full download, used to weight progress when several models are fetched together.
    let progressWeight: Double

    static let catalog: [ModelInfo] = [
        ModelInfo(
            id: .parakeet,
            name: "Parakeet Ultra",
            role: t("Speech recognition", "Spracherkennung"),
            summary: t(
                "Fast on this Mac. Strong for German, English, and the other European languages, with punctuation. Not for languages outside that set.",
                "Schnell auf diesem Mac. Stark bei Deutsch, Englisch und den anderen europäischen Sprachen, mit Satzzeichen. Nicht für Sprachen außerhalb dieser Auswahl."
            ),
            size: "",
            symbol: "bolt.fill",
            progressWeight: 0.40
        ),
        ModelInfo(
            id: .whisper,
            name: WhisperModelChoice.displayName,
            role: t("Speech recognition", "Spracherkennung"),
            summary: t(
                "Many more languages, including when the language changes. A little larger and a little slower.",
                "Viele weitere Sprachen, auch wenn die Sprache wechselt. Etwas größer und etwas langsamer."
            ),
            size: "",
            symbol: "waveform",
            progressWeight: 0.40
        ),
        ModelInfo(
            id: .qwen,
            name: "Qwen3 4B",
            role: t("Polish and rewrite", "Glätten und Umschreiben"),
            summary: "",
            size: "",
            symbol: "text.badge.star",
            progressWeight: 0.60
        ),
    ]

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
    /// Byte progress for the model that is downloading, such as "840 MB of 2.5 GB".
    private(set) var progressDetail: String?
    private(set) var isReady = false
    private(set) var missingIDs: [ModelID] = []
    private(set) var outdatedIDs: [ModelID] = []
    private(set) var exactByteCounts: [ModelID: Int64] = [:]
    private(set) var failedModelID: ModelID?

    private var installations = ModelInstallationStore()
    /// The speech model that must be present. The other speech model can stay installed without counting as required.
    private var speechRequirement: ModelID = .whisper
    private var activeModel: ModelID?
    /// Set only while that model's files are being fetched, so cancel can drop an unfinished download.
    private var downloadingID: ModelID?
    private var queued: Set<ModelID> = []
    private var activePortion: Double = 0
    private let downloadRun = DownloadRun()
    private var trackedDownload: Task<Void, Never>?

    /// Sets which speech model counts as required, then refreshes what is missing.
    func setSpeechRequirement(_ id: ModelID) {
        speechRequirement = id
    }

    func useSpeechRequirement(_ id: ModelID) {
        speechRequirement = id
        syncCatalog()
    }

    private var requiredIDs: [ModelID] {
        [speechRequirement, .qwen]
    }

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
    /// A model that is still downloading is not usable, even if a previous partial file is already there.
    func isUsable(_ id: ModelID) -> Bool {
        if isRunning, activeModel == id || queued.contains(id) {
            return false
        }
        return filesPresent(id)
    }

    func sizeText(for id: ModelID) -> String? {
        exactByteCounts[id].map { ModelByteFormat.string(from: $0) }
    }

    /// Loads the exact download size for each model from the file listing.
    func loadExactSizes() async {
        if let whisper = await Self.listedBytes(
            repository: ModelPaths.whisperRepository,
            directory: WhisperModelChoice.folderName(for: ModelPaths.whisperModelName)
        ) {
            exactByteCounts[.whisper] = whisper
        }
        if let qwen = await Self.listedBytes(repository: ModelPaths.qwenRepository, directory: nil) {
            exactByteCounts[.qwen] = qwen
        }
    }

    private static func listedBytes(repository: String, directory: String?) async -> Int64? {
        guard let files = try? await HuggingFaceDownloader.list(repository: repository, directory: directory) else {
            return nil
        }
        let total = files.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }
        return total > 0 ? total : nil
    }

    func errorMessage(for id: ModelID) -> String? {
        guard failedModelID == id else { return nil }
        return lastError
    }

    func progressDetail(for id: ModelID) -> String? {
        guard isRunning, activeModel == id else { return nil }
        return progressDetail
    }

    /// Stops the current transfer and discards what it has written, so the next download starts over.
    func cancel() {
        downloadRun.cancel()
        trackedDownload?.cancel()
    }

    /// Cancels the current transfer and waits until it has released the download slot.
    func stop() async {
        let task = trackedDownload
        cancel()
        await task?.value
    }

    /// Deletes a model directory, retrying while a cancelled transfer is still closing its files.
    func discardDownloadedFiles(_ id: ModelID) async {
        await discardPartialDownload(id)
        syncCatalog()
    }

    func isTransferring(_ id: ModelID) -> Bool {
        guard let info = ModelInfo.info(id) else { return false }
        switch state(of: info) {
        case .downloading, .waiting:
            return true
        case .ready, .updateAvailable, .missing:
            return false
        }
    }

    func download(_ id: ModelID) async {
        guard installStatus(id) == .missing else { return }
        await track { await self.run([id], replacingOutdated: false) }
    }

    func downloadMissing() async {
        await track { await self.run(self.missingIDs, replacingOutdated: false) }
    }

    func update(_ id: ModelID) async {
        guard installStatus(id) == .outdated else { return }
        await track { await self.run([id], replacingOutdated: true) }
    }

    func updateOutdated() async {
        await track { await self.run(self.outdatedIDs, replacingOutdated: true) }
    }

    /// Downloads every required model that is missing or older than the build shipped with this app.
    func downloadRequiredModels() async {
        let needed = requiredIDs.filter { installStatus($0) != .current }
        await track { await self.run(needed, replacingOutdated: true) }
    }

    /// Downloads these models, including a speech model that is not the required one yet.
    func download(_ ids: [ModelID], replacingOutdated: Bool) async {
        let needed = ids.filter { installStatus($0) != .current }
        guard !needed.isEmpty else { return }
        await track { await self.run(needed, replacingOutdated: replacingOutdated) }
    }

    private func track(_ operation: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in
            await operation()
        }
        trackedDownload = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if trackedDownload == task {
            trackedDownload = nil
        }
    }

    func remove(_ id: ModelID) {
        do {
            try deleteFiles(id)
            installations.clear(id: id)
            try installations.save(to: ModelPaths.installations)
            lastError = nil
            failedModelID = nil
        } catch {
            lastError = error.localizedDescription
            failedModelID = id
        }
        syncCatalog()
    }

    private func run(_ ids: [ModelID], replacingOutdated: Bool) async {
        guard !isRunning, !ids.isEmpty else { return }
        isRunning = true
        lastError = nil
        failedModelID = nil
        progressDetail = nil
        fraction = 0
        activePortion = 0
        queued = Set(ids)
        activeModel = nil
        downloadRun.reset()
        defer {
            isRunning = false
            activeModel = nil
            downloadingID = nil
            queued = []
            activePortion = 0
            progressDetail = nil
            refreshReadyState()
        }
        ModelHub.offlineMode = false
        do {
            for id in ids {
                if downloadRun.isCancelled { throw CancellationError() }
                queued.remove(id)
                activeModel = id
                activePortion = 0
                progressDetail = nil
                if replacingOutdated, installStatus(id) == .outdated {
                    try deleteFiles(id)
                    installations.clear(id: id)
                    try installations.save(to: ModelPaths.installations)
                }
                downloadingID = id
                try await fetch(id, among: ids)
                guard InstallCommit.shouldRecord(filesPresent: filesPresent(id)) else {
                    throw DownloadError.failed
                }
                installations.set(id: id, revision: ModelRevision.expected(id))
                try installations.save(to: ModelPaths.installations)
                downloadingID = nil
                syncCatalog()
            }
            ModelHub.offlineMode = true
            fraction = 1
            status = t("Ready", "Bereit")
        } catch {
            let interrupted = downloadingID
            downloadingID = nil
            if let interrupted {
                await discardPartialDownload(interrupted)
            }
            if DownloadStop.isCancellation(error) || downloadRun.isCancelled {
                lastError = nil
                failedModelID = nil
                status = ""
                ModelHub.offlineMode = false
            } else {
                failedModelID = activeModel
                lastError = Self.failureMessage(for: activeModel)
                status = ""
                ModelHub.offlineMode = false
            }
        }
    }

    static func failureMessage(for id: ModelID?) -> String {
        let name = id.flatMap { ModelInfo.info($0)?.name } ?? t("The model", "Das Modell")
        return t(
            "\(name) could not be downloaded. Check your connection and try again.",
            "\(name) konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut."
        )
    }

    static func byteProgress(transferred: Int64, total: Int64) -> String {
        let done = ModelByteFormat.string(from: transferred)
        let all = ModelByteFormat.string(from: total)
        return t("\(done) of \(all)", "\(done) von \(all)")
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
            try await downloadWhisper(among: ids)
        case .qwen:
            status = t("Downloading writing model", "Schreibmodell wird geladen")
            try FileManager.default.createDirectory(at: ModelPaths.qwen, withIntermediateDirectories: true)
            try await downloadQwen(among: ids)
        }
    }

    private func downloadWhisper(among ids: [ModelID]) async throws {
        let folder = WhisperModelChoice.folderName(for: ModelPaths.whisperModelName)
        let modelFiles = try await HuggingFaceDownloader.list(
            repository: ModelPaths.whisperRepository,
            directory: folder
        )
        let tokenizerFiles = try await tokenizerFilesToFetch()
        let total = max(
            modelFiles.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }
                + tokenizerFiles.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) },
            1
        )
        exactByteCounts[.whisper] = total
        let destination = ModelPaths.whisper.appending(
            path: "models/argmaxinc/whisperkit-coreml",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        report(id: .whisper, ids: ids, portion: 0, transferred: 0, byteTotal: total)
        var completed = Int64(0)
        completed = try await transfer(
            modelFiles,
            repository: ModelPaths.whisperRepository,
            to: destination,
            ids: ids,
            model: .whisper,
            total: total,
            completed: completed
        )
        let tokenizerDestination = WhisperTokenizerFiles.folder(downloadBase: ModelPaths.whisper)
        try FileManager.default.createDirectory(at: tokenizerDestination, withIntermediateDirectories: true)
        completed = try await transfer(
            tokenizerFiles,
            repository: WhisperTokenizerFiles.repository,
            to: tokenizerDestination,
            ids: ids,
            model: .whisper,
            total: total,
            completed: completed
        )
        report(id: .whisper, ids: ids, portion: 1, transferred: total, byteTotal: total)
    }

    private func tokenizerFilesToFetch() async throws -> [HuggingFaceFile] {
        let needed = WhisperTokenizerFiles.requirements
        let listed = try await HuggingFaceDownloader.list(repository: WhisperTokenizerFiles.repository)
        let selected = listed.filter { needed[$0.path] != nil }
        guard selected.count == needed.count else { throw DownloadError.failed }
        return selected
    }

    private func transfer(
        _ files: [HuggingFaceFile],
        repository: String,
        to destination: URL,
        ids: [ModelID],
        model: ModelID,
        total: Int64,
        completed: Int64
    ) async throws -> Int64 {
        var completed = completed
        for file in files {
            if downloadRun.isCancelled || Task.isCancelled { throw CancellationError() }
            let already = completed
            let size = Int64(file.size ?? 0)
            try await HuggingFaceDownloader.download(
                repository: repository,
                file: file,
                to: destination,
                run: downloadRun
            ) { [weak self] received, _ in
                let overall = already + received
                let portion = Double(overall) / Double(total)
                Task { @MainActor in
                    self?.report(id: model, ids: ids, portion: portion, transferred: overall, byteTotal: total)
                }
            }
            completed += size
        }
        return completed
    }

    private func downloadQwen(among ids: [ModelID]) async throws {
        let files = try await HuggingFaceDownloader.list(repository: ModelPaths.qwenRepository)
        let total = max(files.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }, 1)
        exactByteCounts[.qwen] = total
        var completed = Int64(0)
        report(id: .qwen, ids: ids, portion: 0, transferred: 0, byteTotal: total)
        for file in files {
            if downloadRun.isCancelled { throw CancellationError() }
            let already = completed
            let size = Int64(file.size ?? 0)
            try await HuggingFaceDownloader.download(
                repository: ModelPaths.qwenRepository,
                file: file,
                to: ModelPaths.qwen,
                run: downloadRun
            ) { [weak self] received, _ in
                let overall = already + received
                let portion = Double(overall) / Double(total)
                Task { @MainActor in
                    self?.report(id: .qwen, ids: ids, portion: portion, transferred: overall, byteTotal: total)
                }
            }
            completed += size
        }
        report(id: .qwen, ids: ids, portion: 1, transferred: total, byteTotal: total)
    }

    private func report(id: ModelID, ids: [ModelID], portion: Double, transferred: Int64? = nil, byteTotal: Int64? = nil) {
        guard activeModel == id else { return }
        let clamped = min(max(portion, 0), 1)
        activePortion = clamped
        if let transferred, let byteTotal, byteTotal > 0 {
            progressDetail = Self.byteProgress(transferred: min(transferred, byteTotal), total: byteTotal)
        }
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
                && WhisperTokenizerFiles.isInstalled(downloadBase: ModelPaths.whisper)
        case .qwen:
            QwenModelFiles.isInstalled(at: ModelPaths.qwen)
        }
    }

    /// Removes an unfinished model so the next download does not continue the partial files.
    private func discardPartialDownload(_ id: ModelID) async {
        for _ in 0..<5 {
            try? deleteFiles(id)
            if !partialFilesRemain(id) {
                break
            }
            try? await Task.detached {
                try await Task.sleep(for: .milliseconds(200))
            }.value
        }
        installations.clear(id: id)
        try? installations.save(to: ModelPaths.installations)
        if id == .whisper {
            URLCache.shared.removeAllCachedResponses()
        }
    }

    private func partialFilesRemain(_ id: ModelID) -> Bool {
        switch id {
        case .parakeet:
            ModelPaths.parakeetStorageURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
        case .whisper:
            FileManager.default.fileExists(atPath: ModelPaths.whisper.path)
        case .qwen:
            FileManager.default.fileExists(atPath: ModelPaths.qwen.path)
        }
    }

    private func deleteFiles(_ id: ModelID) throws {
        switch id {
        case .parakeet:
            for url in ModelPaths.parakeetStorageURLs {
                try removeIfPresent(url)
            }
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
        missingIDs = requiredIDs.filter { installStatus($0) == .missing }
        outdatedIDs = requiredIDs.filter { installStatus($0) == .outdated }
        isReady = missingIDs.isEmpty && outdatedIDs.isEmpty
    }
}
