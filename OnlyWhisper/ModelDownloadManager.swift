import FluidAudio
import Foundation

@MainActor
@Observable
final class ModelDownloadManager {
    var fraction: Double = 0
    var status: String = ""
    var isRunning = false
    var lastError: String?
    private(set) var isReady = false

    func refreshReadyState() {
        isReady = FileManager.default.fileExists(atPath: ModelPaths.readyMarker.path)
            && AsrModels.modelsExist(at: ModelPaths.parakeet, version: .v3, encoderPrecision: .int8)
            && qwenWeightsPresent
    }

    var qwenWeightsPresent: Bool {
        FileManager.default.fileExists(atPath: ModelPaths.qwen.appending(path: "model.safetensors").path)
            && FileManager.default.fileExists(atPath: ModelPaths.qwen.appending(path: "config.json").path)
    }

    func downloadRequiredModels() async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        defer { isRunning = false }
        ModelHub.offlineMode = false
        do {
            try FileManager.default.createDirectory(at: ModelPaths.parakeet, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ModelPaths.whisper, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: ModelPaths.qwen, withIntermediateDirectories: true)

            status = t("Downloading speech model", "Sprachmodell wird geladen")
            if !AsrModels.modelsExist(at: ModelPaths.parakeet, version: .v3, encoderPrecision: .int8) {
                _ = try await AsrModels.download(
                    to: ModelPaths.parakeet,
                    version: .v3,
                    encoderPrecision: .int8
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.fraction = progress.fractionCompleted * 0.25
                    }
                }
            } else {
                fraction = 0.25
            }

            status = t("Downloading Whisper", "Whisper wird geladen")
            try await WhisperEngine.downloadIfNeeded()
            fraction = 0.55

            status = t("Downloading writing model", "Schreibmodell wird geladen")
            try await downloadQwen()
            fraction = 1
            let marker = Data("{\"ready\":true}".utf8)
            try marker.write(to: ModelPaths.readyMarker, options: .atomic)
            ModelHub.offlineMode = true
            isReady = true
            status = t("Ready", "Bereit")
        } catch {
            lastError = error.localizedDescription
            status = t("Download stopped", "Download angehalten")
            ModelHub.offlineMode = false
        }
    }

    private func downloadQwen() async throws {
        let files = try await HuggingFaceDownloader.list(repository: ModelPaths.qwenRepository)
        let total = max(files.reduce(Int64(0)) { $0 + Int64($1.size ?? 0) }, 1)
        var completed = Int64(0)
        for file in files {
            let already = completed
            let size = Int64(file.size ?? 0)
            try await HuggingFaceDownloader.download(
                repository: ModelPaths.qwenRepository,
                file: file,
                to: ModelPaths.qwen
            ) { [weak self] received, _ in
                let overall = already + received
                Task { @MainActor in
                    let portion = Double(overall) / Double(total)
                    self?.fraction = 0.55 + min(portion, 1) * 0.45
                }
            }
            completed += size
        }
    }
}
