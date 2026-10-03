import Foundation

enum SpeechEngineError: LocalizedError {
    case unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage:
            t(
                "Parakeet doesn't cover this language. Pick Whisper, or a European language.",
                "Parakeet kann diese Sprache nicht. Wähle Whisper oder eine europäische Sprache."
            )
        }
    }
}

actor SpeechRouter {
    private let whisper = WhisperEngine()
    private let parakeet = ParakeetEngine()
    private var engine: SpeechEngine = .whisper

    func use(_ engine: SpeechEngine) async {
        guard engine != self.engine else { return }
        await unload()
        self.engine = engine
    }

    func prepare() async throws {
        switch engine {
        case .whisper:
            try await whisper.prepare()
        case .parakeet:
            try await parakeet.prepare()
        }
    }

    func resetUtterance() async {
        await whisper.resetUtterance()
    }

    func transcribe(
        samples: [Float],
        choice: SpeechChoice,
        live: Bool = false,
        dictation: Bool = false
    ) async throws -> String {
        if engine == .parakeet, !choice.supportsParakeet {
            throw SpeechEngineError.unsupportedLanguage
        }
        switch engine {
        case .whisper:
            return try await whisper.transcribe(
                samples: samples,
                languageCode: choice.code,
                live: live,
                dictation: dictation
            )
        case .parakeet:
            return try await parakeet.transcribe(samples: samples, languageCode: choice.code)
        }
    }

    func unload() async {
        await whisper.unload()
        await parakeet.unload()
    }
}

extension SpeechRouter: FileSpeechTranscribing {
    func transcribeFile(samples: [Float], language: SpeechChoice) async throws -> String {
        try await transcribe(samples: samples, choice: language)
    }

    func unloadFileModel() async {
        await unload()
    }
}
