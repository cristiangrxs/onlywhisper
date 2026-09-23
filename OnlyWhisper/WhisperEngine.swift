import Foundation
import WhisperKit

actor WhisperEngine {
    private var pipe: WhisperKit?

    static func downloadIfNeeded() async throws {
        let config = WhisperKitConfig(
            model: ModelPaths.whisperModelName,
            downloadBase: ModelPaths.whisper,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: true
        )
        _ = try await WhisperKit(config)
    }

    func transcribe(samples: [Float], languageCode: String?) async throws -> String {
        let pipe = try await load()
        let url = try WavWriter.write(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }
        let options = DecodingOptions(
            language: languageCode,
            detectLanguage: languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        pipe = nil
    }

    private func load() async throws -> WhisperKit {
        if let pipe { return pipe }
        let config = WhisperKitConfig(
            model: ModelPaths.whisperModelName,
            downloadBase: ModelPaths.whisper,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        let created = try await WhisperKit(config)
        pipe = created
        return created
    }
}
