import Foundation

struct HistoryFocus: Equatable {
    var id: HistoryEntry.ID
    var token = UUID()
}

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var source: String
    /// File name for a transcribed file. Dictation and rewrite leave this empty.
    var title: String?
    var raw: String
    var polished: String
    /// Structured speaker turns for a meeting. Older entries leave this empty.
    var meeting: MeetingRecord?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        source: String,
        title: String? = nil,
        raw: String,
        polished: String,
        meeting: MeetingRecord? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.title = title
        self.raw = raw
        self.polished = polished
        self.meeting = meeting
    }

    /// Filename for a file transcript, otherwise the first line of the text.
    var listTitle: String {
        if let title, !title.isEmpty { return title }
        return polished.firstLine
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

    @discardableResult
    func add(source: String, title: String? = nil, raw: String, polished: String, meeting: MeetingRecord? = nil) -> UUID {
        let entry = HistoryEntry(source: source, title: title, raw: raw, polished: polished, meeting: meeting)
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries.removeLast(entries.count - 200)
        }
        save()
        return entry.id
    }

    func updateMeeting(_ id: UUID, raw: String, polished: String, meeting: MeetingRecord) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].raw = raw
        entries[index].polished = polished
        entries[index].meeting = meeting
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
