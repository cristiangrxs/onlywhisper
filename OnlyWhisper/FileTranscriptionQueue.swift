import Foundation

enum FileJobState: Equatable, Sendable {
    case waiting
    case working
    case done
    case failed(String)

    var title: String {
        switch self {
        case .waiting: t("Waiting", "Wartet")
        case .working: t("Transcribing", "Schreibt mit")
        case .done: t("Done", "Fertig")
        case .failed(let message): message
        }
    }
}

struct FileJob: Identifiable, Equatable, Sendable {
    var id = UUID()
    var url: URL
    var state: FileJobState
}

@MainActor
@Observable
final class FileTranscriptionQueue {
    var jobs: [FileJob] = []
    private var isWorking = false

    func enqueue(_ urls: [URL], speech: SpeechRouter, language: SpeechChoice) {
        let files = AudioFiles.collect(urls: urls)
        jobs.append(contentsOf: files.map { FileJob(url: $0, state: .waiting) })
        guard !isWorking else { return }
        isWorking = true
        Task { await drain(speech: speech, language: language) }
    }

    private func drain(speech: SpeechRouter, language: SpeechChoice) async {
        defer { isWorking = false }
        while let index = jobs.firstIndex(where: { $0.state == .waiting }) {
            jobs[index].state = .working
            let url = jobs[index].url
            do {
                let samples = try await AudioFiles.samples(from: url)
                let text = try await speech.transcribe(samples: samples, choice: language)
                let output = url.deletingPathExtension().appendingPathExtension("txt")
                try text.write(to: output, atomically: true, encoding: .utf8)
                jobs[index].state = .done
            } catch {
                jobs[index].state = .failed(error.localizedDescription)
            }
        }
        await speech.unload()
    }
}
