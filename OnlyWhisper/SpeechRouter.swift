import Foundation

actor SpeechRouter {
    private let whisper = WhisperEngine()

    func prepare() async throws {
        try await whisper.prepare()
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
        try await whisper.transcribe(
            samples: samples,
            languageCode: choice.code,
            live: live,
            dictation: dictation
        )
    }

    func unload() async {
        await whisper.unload()
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
