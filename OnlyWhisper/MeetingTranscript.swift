import Foundation

struct MeetingNotes: Codable, Equatable, Sendable {
    var summary: String
    var decisions: [String]
    var tasks: [String]
}

struct SpeakerSpan: Equatable, Sendable {
    var id: String
    var start: TimeInterval
    var end: TimeInterval
    var finalized: Bool
}

enum SpeechTrack: Equatable, Sendable {
    case local
    case remote
}

struct MeetingUtterance: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var track: SpeechTrack
}

struct MeetingTurn: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var speakerID: String
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var isLocal: Bool
}

struct MeetingRecord: Codable, Equatable, Sendable {
    var duration: TimeInterval
    var turns: [MeetingTurn]
    var notes: MeetingNotes?
    var names: [String: String]
    var separatesLocalVoice: Bool
}

enum MeetingMerger {
    static let pauseGap: TimeInterval = 1.2
    static let localSpeakerID = "local"
    static let unknownSpeakerID = "unknown"

    static func turns(
        utterances: [MeetingUtterance],
        speakers: [SpeakerSpan],
        separatesLocalVoice: Bool
    ) -> [MeetingTurn] {
        var built: [MeetingTurn] = []
        for utterance in utterances.sorted(by: { $0.start < $1.start }) {
            let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let (speakerID, isLocal) = identity(for: utterance, speakers: speakers, separatesLocalVoice: separatesLocalVoice)
            if var last = built.last, last.speakerID == speakerID, utterance.start - last.end < pauseGap {
                last.end = max(last.end, utterance.end)
                last.text = DictationSession.joined(last.text, text)
                built[built.count - 1] = last
            } else {
                built.append(MeetingTurn(
                    id: "\(speakerID)@\(Int((utterance.start * 1000).rounded()))",
                    speakerID: speakerID,
                    start: utterance.start,
                    end: utterance.end,
                    text: text,
                    isLocal: isLocal
                ))
            }
        }
        return built
    }

    static func displayName(speakerID: String, isLocal: Bool, names: [String: String], separatesLocalVoice: Bool) -> String {
        if let custom = names[speakerID]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        if isLocal, separatesLocalVoice {
            return t("You", "Du")
        }
        if speakerID.hasPrefix("s-"), let index = Int(speakerID.dropFirst(2)) {
            let number = index + 1
            return t("Speaker \(number)", "Sprecher \(number)")
        }
        return t("Speaker", "Sprecher")
    }

    static func plainTranscript(turns: [MeetingTurn], names: [String: String], separatesLocalVoice: Bool) -> String {
        turns.map { turn in
            let name = displayName(
                speakerID: turn.speakerID,
                isLocal: turn.isLocal,
                names: names,
                separatesLocalVoice: separatesLocalVoice
            )
            return "\(name): \(turn.text)"
        }.joined(separator: "\n")
    }

    static func document(turns: [MeetingTurn], names: [String: String], separatesLocalVoice: Bool, notes: MeetingNotes?) -> String {
        var lines = [plainTranscript(turns: turns, names: names, separatesLocalVoice: separatesLocalVoice)]
        if let notes, !notes.summary.isEmpty {
            lines.append("")
            lines.append(notes.summary)
            lines.append(contentsOf: notes.decisions.map { "- \($0)" })
            lines.append(contentsOf: notes.tasks.map { "[ ] \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func identity(
        for utterance: MeetingUtterance,
        speakers: [SpeakerSpan],
        separatesLocalVoice: Bool
    ) -> (String, Bool) {
        if separatesLocalVoice, utterance.track == .local {
            return (localSpeakerID, true)
        }
        if let span = bestSpan(for: utterance, speakers: speakers) {
            return (span.id, false)
        }
        return (unknownSpeakerID, false)
    }

    private static func bestSpan(for utterance: MeetingUtterance, speakers: [SpeakerSpan]) -> SpeakerSpan? {
        let overlapping = speakers.filter { overlap($0, utterance) > 0 }
        let finalized = overlapping.filter(\.finalized)
        let pool = finalized.isEmpty ? overlapping : finalized
        return pool.max { overlap($0, utterance) < overlap($1, utterance) }
    }

    private static func overlap(_ span: SpeakerSpan, _ utterance: MeetingUtterance) -> TimeInterval {
        min(utterance.end, span.end) - max(utterance.start, span.start)
    }
}
