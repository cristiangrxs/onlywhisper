import Foundation

actor SpeechRouter {
    private let whisper = WhisperEngine()

    func prepare() async {
        await whisper.prepare()
    }

    func resetUtterance() async {
        await whisper.resetUtterance()
    }

    func transcribe(samples: [Float], choice: SpeechChoice, live: Bool = false) async throws -> String {
        try await whisper.transcribe(samples: samples, languageCode: choice.code, live: live)
    }

    func unload() async {
        await whisper.unload()
    }
}
