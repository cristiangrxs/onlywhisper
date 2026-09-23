import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var source: String
    var raw: String
    var polished: String

    init(id: UUID = UUID(), date: Date = .now, source: String, raw: String, polished: String) {
        self.id = id
        self.date = date
        self.source = source
        self.raw = raw
        self.polished = polished
    }
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OnlyWhisper", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appending(path: "history.json")
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = stored
        }
    }

    func add(source: String, raw: String, polished: String) {
        entries.insert(HistoryEntry(source: source, raw: raw, polished: polished), at: 0)
        if entries.count > 200 {
            entries.removeLast(entries.count - 200)
        }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
