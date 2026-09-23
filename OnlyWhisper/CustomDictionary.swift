import Foundation

struct CustomDictionary: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var heard: String
        var written: String

        init(id: UUID = UUID(), heard: String, written: String) {
            self.id = id
            self.heard = heard
            self.written = written
        }
    }

    var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    func apply(to text: String) -> String {
        var result = text
        for entry in entries where !entry.heard.isEmpty && !entry.written.isEmpty {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.heard))\\b"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: entry.written)
        }
        return result
    }
}

@MainActor
@Observable
final class DictionaryStore {
    var dictionary: CustomDictionary {
        didSet { save() }
    }

    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OnlyWhisper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appending(path: "dictionary.json")
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(CustomDictionary.self, from: data) {
            dictionary = stored
        } else {
            dictionary = CustomDictionary()
        }
    }

    func add(heard: String, written: String) {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !written.isEmpty else { return }
        dictionary.entries.append(CustomDictionary.Entry(heard: heard, written: written))
    }

    func remove(_ entry: CustomDictionary.Entry) {
        dictionary.entries.removeAll { $0.id == entry.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(dictionary) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
