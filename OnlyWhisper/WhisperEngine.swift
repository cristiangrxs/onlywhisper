import Foundation
import WhisperKit

actor WhisperEngine {
    private var pipe: WhisperKit?
    /// Language detected for the current utterance, so later live passes skip detection.
    private var lockedLanguage: String?

    func prepare() async {
        _ = try? await load()
    }

    func resetUtterance() {
        lockedLanguage = nil
    }

    /// `live` keeps an uncertain word that is still being spoken, and reuses a language found earlier in the utterance.
    /// `dictation` skips the hotter retry, which invents words on silence.
    func transcribe(
        samples: [Float],
        languageCode: String?,
        live: Bool = false,
        dictation: Bool = false
    ) async throws -> String {
        let pipe = try await load()
        let language = languageCode ?? (live ? lockedLanguage : nil)
        let url = try WavWriter.write(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }
        let options = DecodingOptions(
            language: language,
            temperatureFallbackCount: dictation || live ? 0 : 1,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            windowClipTime: 0,
            compressionRatioThreshold: Self.compressionRatioThreshold,
            logProbThreshold: live ? nil : Self.logProbThreshold,
            firstTokenLogProbThreshold: live ? nil : Self.firstTokenLogProbThreshold,
            noSpeechThreshold: Self.noSpeechThreshold
        )
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        if live, languageCode == nil, lockedLanguage == nil {
            let detected = results.first?.language ?? ""
            if !detected.isEmpty { lockedLanguage = detected }
        }
        return Self.acceptedText(from: results, live: live)
    }

    static let noSpeechThreshold: Float = 0.6
    static let compressionRatioThreshold: Float = 2.4
    static let logProbThreshold: Float = -1.0
    private static let firstTokenLogProbThreshold: Float = -1.5

    /// Drops silence the model is sure about, even when that silence was decoded as a confident phrase.
    /// A live pass still keeps a low-confidence word so it can correct itself on the next pass.
    static func acceptedText(from results: [TranscriptionResult], live: Bool) -> String {
        results.flatMap(\.segments).compactMap { segment in
            keepSegment(
                text: segment.text,
                noSpeechProb: segment.noSpeechProb,
                compressionRatio: segment.compressionRatio,
                avgLogprob: segment.avgLogprob,
                live: live
            )
        }.joined(separator: " ")
    }

    static func keepSegment(
        text: String,
        noSpeechProb: Float,
        compressionRatio: Float,
        avgLogprob: Float,
        live: Bool
    ) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if noSpeechProb > noSpeechThreshold { return nil }
        if compressionRatio > compressionRatioThreshold { return nil }
        if !live, avgLogprob < logProbThreshold { return nil }
        return text
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
