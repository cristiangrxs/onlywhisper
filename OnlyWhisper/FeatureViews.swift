import SwiftUI

struct MeetingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(t("Meeting", "Meeting"))
                    .font(.title2)
                Spacer()
                if model.meetingActive {
                    Button(t("Stop", "Stopp")) { Task { await model.stopMeeting() } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(t("Record", "Aufnehmen")) { Task { await model.startMeeting() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.meetingChunks.isEmpty {
                        Text(model.meetingStatus.isEmpty ? t("Start a meeting to see the transcript.", "Starte ein Meeting, dann erscheint das Transkript.") : model.meetingStatus)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.meetingChunks) { chunk in
                        VStack(alignment: .leading, spacing: 2) {
                            if let speaker = chunk.speaker {
                                Text(speaker)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(chunk.text)
                        }
                    }
                    if let notes = model.meetingNotes {
                        Divider()
                        Text(notes.summary)
                        if !notes.decisions.isEmpty {
                            Text(t("Decisions", "Entscheidungen")).font(.headline)
                            ForEach(notes.decisions, id: \.self) { Text("• \($0)") }
                        }
                        if !notes.tasks.isEmpty {
                            Text(t("Tasks", "Aufgaben")).font(.headline)
                            ForEach(notes.tasks, id: \.self) { Text("• \($0)") }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

struct FilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Drop audio, video, or a folder", "Audio, Video oder einen Ordner ablegen"))
                .font(.title3)
            Text(t("Each recording becomes one text file next to the original.", "Jede Aufnahme wird zu einer Textdatei neben dem Original."))
                .foregroundStyle(.secondary)
            List(model.files.jobs) { job in
                LabeledContent(job.url.lastPathComponent) {
                    Text(job.state.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueueFiles(urls)
            return true
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.history.entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.polished)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .overlay {
            if model.history.entries.isEmpty {
                Text(t("Nothing dictated yet.", "Noch nichts diktiert."))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RewriteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.rewriteText)
                .lineLimit(4)
                .foregroundStyle(.secondary)
            TextField(t("Instruction", "Anweisung"), text: Binding(
                get: { model.rewriteInstruction },
                set: { model.rewriteInstruction = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            HStack {
                Button(t("Speak instruction", "Anweisung sprechen")) {
                    Task { await model.dictateRewriteInstruction() }
                }
                Button(t("Apply", "Anwenden")) {
                    Task { await model.applyCustomRewrite() }
                }
                .keyboardShortcut(.defaultAction)
                Menu(t("Actions", "Aktionen")) {
                    ForEach(RewriteAction.allCases) { action in
                        Button(action.title) { Task { await model.applyRewrite(action) } }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
