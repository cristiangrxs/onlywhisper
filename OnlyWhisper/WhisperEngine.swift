import Foundation
import WhisperKit

actor WhisperEngine {
    private var pipe: WhisperKit?
    /// Language detected for the current utterance, so later live passes skip detection.
    private var lockedLanguage: String?

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

    func prepare() async {
        _ = try? await load()
    }

    func resetUtterance() {
        lockedLanguage = nil
    }

    /// `live` keeps partial speech instead of dropping it, and reuses a language found earlier in the utterance.
    func transcribe(samples: [Float], languageCode: String?, live: Bool = false) async throws -> String {
        let pipe = try await load()
        let language = languageCode ?? (live ? lockedLanguage : nil)
        let url = try WavWriter.write(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }
        let options = DecodingOptions(
            language: language,
            temperatureFallbackCount: live ? 0 : 1,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            windowClipTime: 0,
            compressionRatioThreshold: live ? nil : 2.4,
            logProbThreshold: live ? nil : -1.0,
            firstTokenLogProbThreshold: live ? nil : -1.5,
            noSpeechThreshold: live ? nil : 0.6
        )
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        if live, languageCode == nil, lockedLanguage == nil {
            let detected = results.first?.language ?? ""
            if !detected.isEmpty { lockedLanguage = detected }
        }
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() {
        pipe = nil
        lockedLanguage = nil
    }

    private func load() async throws -> WhisperKit {
        if let pipe { return pipe }
        let folder = WhisperModelChoice.installedFolder(
            downloadBase: ModelPaths.whisper,
            modelName: ModelPaths.whisperModelName
        )
        let config = WhisperKitConfig(
            model: ModelPaths.whisperModelName,
            downloadBase: ModelPaths.whisper,
            modelFolder: folder.path,
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
