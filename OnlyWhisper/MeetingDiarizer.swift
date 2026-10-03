import FluidAudio
import Foundation

actor MeetingDiarizer {
    private var diarizer: LSEENDDiarizer?

    func prepare() async throws {
        if diarizer != nil { return }
        ModelHub.offlineMode = false
        let created = LSEENDDiarizer()
        try await created.initialize(
            variant: .dihard3,
            cacheDirectory: ModelPaths.diarization,
            computeUnits: .cpuAndNeuralEngine
        )
        ModelHub.offlineMode = true
        diarizer = created
    }

    func begin() {
        diarizer?.reset()
    }

    /// Feeds newly captured audio and returns the whole speaker timeline, including tentative labels.
    func ingest(_ samples: [Float]) throws -> [SpeakerSpan] {
        guard let diarizer else { return [] }
        if !samples.isEmpty {
            try diarizer.addAudio(samples, sourceSampleRate: 16_000)
            _ = try diarizer.process()
        }
        return spans(from: diarizer)
    }

    func finish() throws -> [SpeakerSpan] {
        guard let diarizer else { return [] }
        _ = try diarizer.finalizeSession()
        return spans(from: diarizer)
    }

    private func spans(from diarizer: LSEENDDiarizer) -> [SpeakerSpan] {
        var result: [SpeakerSpan] = []
        for (index, speaker) in diarizer.timeline.speakers {
            let id = "s-\(index)"
            for segment in speaker.finalizedSegments where segment.endTime > segment.startTime {
                result.append(SpeakerSpan(
                    id: id,
                    start: TimeInterval(segment.startTime),
                    end: TimeInterval(segment.endTime),
                    finalized: true
                ))
            }
            for segment in speaker.tentativeSegments where segment.endTime > segment.startTime {
                result.append(SpeakerSpan(
                    id: id,
                    start: TimeInterval(segment.startTime),
                    end: TimeInterval(segment.endTime),
                    finalized: false
                ))
            }
        }
        return result
    }
}
