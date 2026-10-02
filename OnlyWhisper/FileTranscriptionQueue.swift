import Foundation

protocol FileSpeechTranscribing: Sendable {
    func transcribeFile(samples: [Float], language: SpeechChoice) async throws -> String
    func unloadFileModel() async
}

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
        case .failed: t("Failed", "Fehler")
        }
    }

    var isFinished: Bool {
        switch self {
        case .done, .failed: true
        case .waiting, .working: false
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct FileJob: Identifiable, Equatable, Sendable {
    var id = UUID()
    var url: URL
    var state: FileJobState
    /// Transcript text, once the job has finished.
    var transcript: String?
    /// History entry that holds this transcript.
    var historyID: UUID?
}

@MainActor
@Observable
final class FileTranscriptionQueue {
    var jobs: [FileJob] = []
    var notice: String?
    private(set) var isDraining = false
    private var speech: (any FileSpeechTranscribing)?
    private var language: SpeechChoice = .automatic
    private var scopes: [ScopedAccess] = []
    /// Saves a finished transcript where dictation is saved and returns that history entry.
    var record: ((URL, String) -> UUID)?

    var hasFinishedJobs: Bool {
        jobs.contains { $0.state.isFinished }
    }

    func enqueue(_ urls: [URL], speech: any FileSpeechTranscribing, language: SpeechChoice) {
        self.speech = speech
        self.language = language
        var added = 0
        var skippedActive = 0
        var firstRejection: String?
        for url in urls {
            let started = url.startAccessingSecurityScopedResource()
            let intake = AudioFiles.collect(urls: [url])
            var jobIDs: [UUID] = []
            for file in intake.accepted {
                if isActive(file) {
                    skippedActive += 1
                    continue
                }
                let id = UUID()
                jobs.append(FileJob(id: id, url: file, state: .waiting))
                jobIDs.append(id)
                added += 1
            }
            for rejected in intake.rejected {
                let id = UUID()
                jobs.append(FileJob(id: id, url: rejected.url, state: .failed(rejected.reason)))
                jobIDs.append(id)
                firstRejection = firstRejection ?? rejected.reason
            }
            if jobIDs.isEmpty {
                if started { url.stopAccessingSecurityScopedResource() }
            } else if started {
                scopes.append(ScopedAccess(url: url, jobIDs: Set(jobIDs)))
            }
        }
        if added > 0 {
            notice = nil
        } else if skippedActive > 0, firstRejection == nil {
            notice = FileTranscriptionCopy.alreadyQueued
        } else if let firstRejection {
            notice = firstRejection
        }
        start()
    }

    func retry(_ id: FileJob.ID, speech: any FileSpeechTranscribing, language: SpeechChoice) {
        self.speech = speech
        self.language = language
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].state.failureMessage != nil else { return }
        let url = jobs[index].url
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            jobs.remove(at: index)
            releaseScope(id)
            enqueue([url], speech: speech, language: language)
            return
        }
        jobs[index].state = .waiting
        jobs[index].transcript = nil
        jobs[index].historyID = nil
        notice = nil
        start()
    }

    func clearFinished() {
        let removed = jobs.filter { $0.state.isFinished }
        jobs.removeAll { $0.state.isFinished }
        for job in removed {
            releaseScope(job.id)
        }
        notice = nil
    }

    func noteImportFailure(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.userCancelled.rawValue { return }
        notice = FileTranscriptionCopy.importFailed
    }

    private func start() {
        guard jobs.contains(where: { $0.state == .waiting }) else { return }
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    /// Stays the only drain until the queue is empty, including files added while a job or unload is running.
    private func drain() async {
        while true {
            while let index = jobs.firstIndex(where: { $0.state == .waiting }) {
                await transcribeJob(at: index)
            }
            await speech?.unloadFileModel()
            if !jobs.contains(where: { $0.state == .waiting }) { break }
        }
        isDraining = false
    }

    private func transcribeJob(at index: Int) async {
        let id = jobs[index].id
        let url = jobs[index].url
        jobs[index].state = .working
        let speech = speech
        let language = language

        let intake = AudioFiles.collect(urls: [url])
        let path = url.standardizedFileURL.path
        let accepted = intake.accepted.contains { $0.standardizedFileURL.path == path }
        if !accepted {
            let reason = intake.rejected.first { $0.url.standardizedFileURL.path == path }?.reason
                ?? FileTranscriptionCopy.formatUnsupported
            finish(id, .failed(reason))
            return
        }

        let samples: [Float]
        do {
            samples = try await AudioFiles.samples(from: url)
        } catch {
            finish(id, .failed(FileTranscriptionCopy.unreadable))
            return
        }
        guard !samples.isEmpty else {
            finish(id, .failed(FileTranscriptionCopy.noSpeech))
            return
        }

        let text: String
        do {
            guard let speech else {
                finish(id, .failed(FileTranscriptionCopy.modelFailed))
                return
            }
            text = try await speech.transcribeFile(samples: samples, language: language)
        } catch is CancellationError {
            finish(id, .failed(FileTranscriptionCopy.interrupted))
            return
        } catch {
            finish(id, .failed(FileTranscriptionCopy.modelFailed))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(id, .failed(FileTranscriptionCopy.noSpeech))
            return
        }

        let historyID = record?(url, trimmed)
        guard let current = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[current].transcript = trimmed
        jobs[current].historyID = historyID
        jobs[current].state = .done
    }

    private func finish(_ id: FileJob.ID, _ state: FileJobState) {
        guard let current = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[current].state = state
    }

    private func isActive(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return jobs.contains { job in
            switch job.state {
            case .waiting, .working:
                return job.url.standardizedFileURL.path == path
            case .done, .failed:
                return false
            }
        }
    }

    private func releaseScope(_ id: UUID) {
        for scope in scopes {
            scope.release(id)
        }
        scopes.removeAll { $0.isSpent }
    }
}

private final class ScopedAccess {
    let url: URL
    private var jobIDs: Set<UUID>
    private var started: Bool

    init(url: URL, jobIDs: Set<UUID>) {
        self.url = url
        self.jobIDs = jobIDs
        started = true
    }

    var isSpent: Bool { jobIDs.isEmpty }

    func release(_ id: UUID) {
        guard jobIDs.remove(id) != nil, jobIDs.isEmpty, started else { return }
        url.stopAccessingSecurityScopedResource()
        started = false
    }
}
