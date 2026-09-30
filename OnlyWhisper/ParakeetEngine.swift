import AVFoundation
import FluidAudio
import Foundation

actor ParakeetEngine {
    private var manager: AsrManager?

    func transcribe(samples: [Float], languageCode: String?) async throws -> String {
        let manager = try await load()
        var state = try TdtDecoderState()
        let language = languageCode.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(samples, decoderState: &state, language: language)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        manager = nil
    }

    private func load() async throws -> AsrManager {
        if let manager, await manager.isAvailable {
            return manager
        }
        ModelHub.offlineMode = true
        let models = try await AsrModels.downloadAndLoad(
            to: ModelPaths.parakeet,
            version: .ultra,
            encoderPrecision: .int8
        )
        let created = AsrManager()
        try await created.loadModels(models)
        manager = created
        return created
    }
}
