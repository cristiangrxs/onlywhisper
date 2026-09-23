import FluidAudio
import Foundation

struct TranscriptChunk: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var speaker: String?
}

struct MeetingNotes: Codable, Equatable, Sendable {
    var summary: String
    var decisions: [String]
    var tasks: [String]
}

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

    func assignSpeakers(to chunks: [TranscriptChunk], samples: [Float]) throws -> [TranscriptChunk] {
        guard let diarizer else { return chunks }
        let timeline = try diarizer.processComplete(samples, sourceSampleRate: 16_000)
        var labeled = chunks
        for index in labeled.indices {
            let chunk = labeled[index]
            var bestSpeaker: String?
            var bestOverlap: TimeInterval = 0
            for speaker in timeline.speakers.values {
                for segment in speaker.finalizedSegments {
                    let start = TimeInterval(segment.startTime)
                    let end = TimeInterval(segment.endTime)
                    let overlap = min(chunk.end, end) - max(chunk.start, start)
                    if overlap > bestOverlap {
                        bestOverlap = overlap
                        bestSpeaker = speaker.name ?? segment.speakerLabel
                    }
                }
            }
            labeled[index].speaker = bestSpeaker
        }
        return labeled
    }
}
