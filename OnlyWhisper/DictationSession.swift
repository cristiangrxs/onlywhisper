import Foundation

/// Raw words heard during one dictation. Settled segments stay fixed, the open segment is replaced
/// every time its audio is transcribed again, so words cut off mid-way correct themselves.
struct DictationSession: Equatable, Sendable {
    private(set) var settled: String = ""
    private(set) var open: String = ""

    var text: String {
        Self.joined(settled, open)
    }

    /// Replaces the open segment. Returns whether the visible text changed.
    @discardableResult
    mutating func updateOpen(_ text: String) -> Bool {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != open else { return false }
        open = next
        return true
    }

    /// Freezes the open segment once its audio will not be transcribed again.
    mutating func settleOpen() {
        settled = Self.joined(settled, open)
        open = ""
    }

    mutating func reset() {
        settled = ""
        open = ""
    }

    /// Splits text at sentence ends into pieces the writing model can handle in one pass.
    /// A sentence longer than `limit` becomes its own piece rather than being cut.
    static func polishChunks(_ text: String, limit: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed.isEmpty ? [] : [trimmed] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(trimmed) {
            let candidate = joined(current, sentence)
            if candidate.count > limit, !current.isEmpty {
                chunks.append(current)
                current = sentence
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    static func joined(_ left: String, _ right: String) -> String {
        let left = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result
    }
}

/// Picks where the open audio segment can be frozen without cutting through a word.
enum SpeechPause {
    static let sampleRate = 16_000
    private static let frame = sampleRate / 10
    private static let pauseFrames = 6
    private static let minSegment = sampleRate
    private static let maxSegment = 8 * sampleRate
    private static let searchWindow = 3 * sampleRate

    /// The sample index to settle at, or nil while the segment should stay open.
    /// A trailing pause settles everything. A segment past the length cap settles at its quietest recent frame.
    static func settlePoint(in samples: [Float], from start: Int, to end: Int) -> Int? {
        let length = end - start
        guard length >= minSegment else { return nil }
        let energies = frameEnergies(samples, from: start, to: end)
        guard !energies.isEmpty else { return nil }
        let threshold = silenceThreshold(energies)
        if energies.suffix(pauseFrames).count == pauseFrames,
           energies.suffix(pauseFrames).allSatisfy({ $0 < threshold }) {
            return end
        }
        guard length >= maxSegment else { return nil }
        let firstFrame = max(0, energies.count - searchWindow / frame)
        let lastFrame = energies.count - 3
        guard lastFrame > firstFrame else { return end }
        var quietest = firstFrame
        for index in firstFrame..<lastFrame where energies[index] < energies[quietest] {
            quietest = index
        }
        return start + quietest * frame + frame / 2
    }

    private static func frameEnergies(_ samples: [Float], from start: Int, to end: Int) -> [Float] {
        var energies: [Float] = []
        var index = start
        while index + frame <= end {
            var sum: Float = 0
            for sample in samples[index..<(index + frame)] {
                sum += sample * sample
            }
            energies.append((sum / Float(frame)).squareRoot())
            index += frame
        }
        return energies
    }

    /// Relative to the loudest speech in the segment, so quiet microphones still find pauses.
    private static func silenceThreshold(_ energies: [Float]) -> Float {
        let sorted = energies.sorted()
        let loud = sorted[min(sorted.count - 1, Int(Float(sorted.count) * 0.9))]
        return max(0.004, loud * 0.2)
    }
}
