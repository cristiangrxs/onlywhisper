import Foundation

/// Tracks dictated text that is already settled and the sentence still open for live editing.
struct DictationSession: Equatable, Sendable {
    private(set) var committed: String = ""
    private(set) var openText: String = ""
    private(set) var generation: Int = 0
    private var requestedGeneration: Int?
    private var pendingRemainder: String = ""

    var visibleText: String {
        joined(committed, openText)
    }

    /// Replaces the uncommitted sentence. A change invalidates a polish that is already running.
    mutating func updateOpenText(_ text: String) {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next != openText else { return }
        openText = next
        generation += 1
        requestedGeneration = nil
        pendingRemainder = ""
    }

    /// The open sentence to send to the writing model, when a pause or punctuation makes it safe to settle.
    mutating func polishRequest(paused: Bool) -> (generation: Int, sentence: String)? {
        let text = openText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let sentence: String
        let remainder: String
        if let split = Self.splitSentence(text) {
            sentence = split.ready
            remainder = split.remainder
        } else if paused {
            sentence = text
            remainder = ""
        } else {
            return nil
        }
        guard requestedGeneration != generation else { return nil }
        requestedGeneration = generation
        pendingRemainder = remainder
        return (generation, sentence)
    }

    /// Settles a polish result only when the open sentence has not moved on.
    @discardableResult
    mutating func acceptPolish(_ polished: String, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        let cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        committed = joined(committed, cleaned)
        openText = pendingRemainder
        pendingRemainder = ""
        self.generation += 1
        requestedGeneration = nil
        return true
    }

    /// Settles whatever is still open when the user stops dictating.
    mutating func commitFinal(_ polished: String) {
        let cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        let piece = cleaned.isEmpty ? openText : cleaned
        if !piece.isEmpty {
            committed = joined(committed, piece)
        }
        openText = ""
        pendingRemainder = ""
        generation += 1
        requestedGeneration = nil
    }

    mutating func reset() {
        committed = ""
        openText = ""
        pendingRemainder = ""
        generation += 1
        requestedGeneration = nil
    }

    private static func splitSentence(_ text: String) -> (ready: String, remainder: String)? {
        guard let index = text.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) else { return nil }
        let ready = text[...index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ready.isEmpty else { return nil }
        let after = text.index(after: index)
        let remainder = after < text.endIndex
            ? text[after...].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (ready, remainder)
    }

    private func joined(_ left: String, _ right: String) -> String {
        let left = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }
}
