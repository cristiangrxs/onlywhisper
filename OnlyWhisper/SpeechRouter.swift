import Foundation

actor SpeechRouter {
    private let parakeet = ParakeetEngine()
    private let whisper = WhisperEngine()

    func transcribe(samples: [Float], choice: SpeechChoice) async throws -> String {
        if choice.usesWhisper {
            return try await whisper.transcribe(samples: samples, languageCode: choice.code)
        }
        return try await parakeet.transcribe(samples: samples, languageCode: choice.code)
    }

    func unload() async {
        await parakeet.unload()
        await whisper.unload()
    }
}
