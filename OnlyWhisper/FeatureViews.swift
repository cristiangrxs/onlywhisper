import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared

private struct WindowHeader<Trailing: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.spacingM) {
            IconTile(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.spacingM)
            trailing
        }
        .padding(.horizontal, DS.spacingXL)
        .padding(.vertical, DS.spacingM)
    }
}

private struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(DS.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Files

struct FilesView: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(
                symbol: "doc.text.fill",
                tint: .teal,
                title: t("Transcribe files", "Dateien transkribieren"),
                subtitle: t("Transcripts are saved in History.", "Transkripte landen im Verlauf.")
            ) {
                EmptyView()
            }
            Hairline()
            VStack(spacing: DS.spacingM) {
                dropZone
                if let modelNotice {
                    noticeBanner(modelNotice, tint: .orange) {
                        Button(t("Open Models", "Modelle öffnen")) {
                            openModels()
                        }
                        .controlSize(.small)
                    }
                }
                if let notice = model.files.notice {
                    noticeBanner(notice, tint: .secondary) { EmptyView() }
                }
                if !model.files.jobs.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.files.jobs) { job in
                                FileJobRow(job: job, onRetry: {
                                    model.retryFile(job.id)
                                }, onShow: {
                                    if let id = job.historyID {
                                        model.showFileTranscript(id)
                                    }
                                })
                            }
                        }
                    }
                }
            }
            .padding(DS.spacingL)
            .frame(maxHeight: .infinity, alignment: .top)
            ActionBar {
                AppBadge(text: summary)
            } trailing: {
                ActionBarButton(title: t("Clear Finished", "Fertige entfernen")) {
                    model.clearFinishedFiles()
                }
                .disabled(!model.files.hasFinishedJobs)
                ActionBarButton(title: t("Choose Files…", "Dateien wählen…"), keys: ["⌘", "O"], isPrimary: true) {
                    importing = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .glassWindow()
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueueFiles(urls)
            return true
        } isTargeted: { targeted = $0 }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: AudioFiles.contentTypes + [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                model.enqueueFiles(urls)
            case .failure(let error):
                model.noteFileImportFailure(error)
            }
        }
    }

    private var modelNotice: String? {
        guard !model.canTranscribeFiles else { return nil }
        if model.downloads.isRunning {
            return t("The model is still downloading.", "Das Modell wird noch geladen.")
        }
        return t("Install a speech model to transcribe files.", "Installiere ein Sprachmodell, um Dateien zu transkribieren.")
    }

    private func openModels() {
        model.showFileModelHelp()
    }

    private func noticeBanner<Accessory: View>(_ text: String, tint: Color, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: DS.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(DS.spacingM)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous))
    }

    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
        return VStack(spacing: DS.spacingS) {
            Image(systemName: targeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: model.files.jobs.isEmpty ? 36 : 22, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(t("Drop audio, video, or a folder", "Audio, Video oder einen Ordner ablegen"))
                .font(.system(size: 13, weight: .medium))
            Button(t("Choose Files…", "Dateien wählen…")) { importing = true }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity)
        .frame(height: model.files.jobs.isEmpty ? 240 : 120)
        .background(targeted ? Color.accentColor.opacity(0.1) : DS.cardFill, in: shape)
        .overlay(
            shape.strokeBorder(
                targeted ? Color.accentColor : Color.primary.opacity(0.18),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        )
        .animation(.snappy(duration: 0.2), value: targeted)
    }

    private var summary: String {
        let jobs = model.files.jobs
        guard !jobs.isEmpty else { return AudioFiles.formatSummary }
        let done = jobs.filter { $0.state == .done }.count
        return t("\(done) of \(jobs.count) done", "\(done) von \(jobs.count) fertig")
    }
}

private struct FileJobRow: View {
    var job: FileJob
    var onRetry: () -> Void
    var onShow: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.spacingM) {
            IconTile(symbol: isVideo ? "film" : "waveform", tint: isVideo ? .pink : .teal, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let message = job.state.failureMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.spacingS)
            status
            if case .failed = job.state {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(t("Retry", "Erneut versuchen"))
                .accessibilityLabel(t("Retry", "Erneut versuchen"))
            }
            if job.state == .done, job.historyID != nil {
                Button(action: onShow) {
                    Image(systemName: "text.alignleft")
                }
                .buttonStyle(.borderless)
                .help(t("Show in History", "Im Verlauf zeigen"))
                .accessibilityLabel(t("Show in History", "Im Verlauf zeigen"))
            }
        }
        .padding(.horizontal, DS.spacingS)
        .padding(.vertical, DS.spacingS)
        .background(
            RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous)
                .fill(hovering ? DS.hover : .clear)
        )
        .onHover { hovering = $0 }
    }

    private var isVideo: Bool {
        ["mp4", "mov", "m4v"].contains(job.url.pathExtension.lowercased())
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .waiting:
            StatusBadge(title: job.state.title, tint: .secondary)
        case .working, .translating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(job.state.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .done:
            StatusBadge(title: job.state.title, tint: .green)
        case .failed(let message):
            StatusBadge(title: t("Failed", "Fehler"), tint: .red)
                .help(message)
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var query = ""
    @State private var selection: HistoryEntry.ID?
    @State private var showsRaw = false
    @State private var showsActions = false
    @State private var actionSelection = 0
    @State private var applyingFocus = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let entries = filtered
        let selected = entries.first { $0.id == selection } ?? entries.first
        VStack(spacing: 0) {
            PaletteSearchField(
                placeholder: t("Search history…", "Verlauf durchsuchen…"),
                text: $query,
                focus: $searchFocused
            )
            Hairline()
            if entries.isEmpty {
                EmptyStateView(
                    symbol: query.isEmpty ? "clock" : "magnifyingglass",
                    title: query.isEmpty ? t("Nothing dictated yet", "Noch nichts diktiert") : t("No results", "Keine Ergebnisse"),
                    message: query.isEmpty ? t("Everything you dictate, rewrite, or transcribe from a file shows up here.", "Alles, was du diktierst, umschreibst oder aus einer Datei transkribierst, erscheint hier.") : nil
                )
            } else {
                HStack(spacing: 0) {
                    list(entries, selected: selected)
                        .frame(width: 300)
                    Hairline(vertical: true)
                    HistoryDetail(entry: selected, showsRaw: $showsRaw)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            ActionBar {
                AppBadge(text: t("\(model.history.entries.count) entries", "\(model.history.entries.count) Einträge"))
            } trailing: {
                if let selected {
                    ActionBarButton(title: t("Paste", "Einfügen"), keys: ["↵"], isPrimary: true) {
                        paste(selected)
                    }
                    ActionBarDivider()
                    ActionBarButton(title: t("Actions", "Aktionen"), keys: ["⌘", "K"]) {
                        actionSelection = 0
                        showsActions.toggle()
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsActions, let selected {
                ActionMenu(title: selected.listTitle, actions: actions(for: selected), selection: $actionSelection) { action in
                    showsActions = false
                    action.perform()
                }
                .padding(.trailing, DS.spacingS)
                .padding(.bottom, DS.actionBarHeight + DS.spacingXS)
            }
        }
        .animation(.snappy(duration: 0.15), value: showsActions)
        .frame(minWidth: 720, minHeight: 440)
        .glassWindow()
        .onKeyDown { handleKey($0) }
        .onAppear {
            searchFocused = true
            revealFocusedEntry()
        }
        .onChange(of: model.historyFocus?.token) { _, _ in
            revealFocusedEntry()
        }
        .onChange(of: query) {
            showsActions = false
            if applyingFocus {
                applyingFocus = false
                return
            }
            selection = nil
        }
        .onChange(of: selection) { showsRaw = false }
    }

    private var filtered: [HistoryEntry] {
        let entries = model.history.entries
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter {
            $0.polished.localizedStandardContains(trimmed)
                || $0.raw.localizedStandardContains(trimmed)
                || ($0.title?.localizedStandardContains(trimmed) ?? false)
        }
    }

    private func list(_ entries: [HistoryEntry], selected: HistoryEntry?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(dayGroups(entries), id: \.title) { group in
                        SectionHeader(group.title)
                        ForEach(group.entries) { entry in
                            let style = HistoryStyle(source: entry.source)
                            PaletteRow(
                                symbol: style.symbol,
                                tint: style.tint,
                                title: entry.listTitle,
                                subtitle: entry.source == "file" ? entry.polished.firstLine : nil,
                                accessory: entry.date.formatted(date: .omitted, time: .shortened),
                                isSelected: entry.id == selected?.id
                            )
                            .id(entry.id)
                            .onTapGesture { selection = entry.id }
                            .onTapGesture(count: 2) { paste(entry) }
                        }
                    }
                }
                .padding(.horizontal, DS.spacingS)
                .padding(.bottom, DS.spacingS)
            }
            .scrollIndicators(.never)
            .onChange(of: selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private struct DayGroup {
        var title: String
        var entries: [HistoryEntry]
    }

    private func dayGroups(_ entries: [HistoryEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        let today = entries.filter { calendar.isDateInToday($0.date) }
        let yesterday = entries.filter { calendar.isDateInYesterday($0.date) }
        let earlier = entries.filter { !calendar.isDateInToday($0.date) && !calendar.isDateInYesterday($0.date) }
        return [
            DayGroup(title: t("Today", "Heute"), entries: today),
            DayGroup(title: t("Yesterday", "Gestern"), entries: yesterday),
            DayGroup(title: t("Earlier", "Früher"), entries: earlier),
        ].filter { !$0.entries.isEmpty }
    }

    private func actions(for entry: HistoryEntry) -> [MenuAction] {
        [
            MenuAction(id: "paste", title: t("Paste", "Einfügen"), symbol: "doc.on.clipboard", keys: ["↵"]) {
                paste(entry)
            },
            MenuAction(id: "copy", title: t("Copy to Clipboard", "Kopieren"), symbol: "doc.on.doc", keys: ["⌘", "↵"]) {
                model.copy(entry.polished)
            },
            MenuAction(id: "copyRaw", title: t("Copy Original", "Original kopieren"), symbol: "text.quote", keys: ["⇧", "⌘", "↵"]) {
                model.copy(entry.raw)
            },
            MenuAction(id: "delete", title: t("Delete Entry", "Eintrag löschen"), symbol: "trash", keys: ["⌃", "X"], isDestructive: true) {
                delete(entry)
            },
        ]
    }

    private func revealFocusedEntry() {
        guard let id = model.historyFocus?.id else { return }
        if query.isEmpty {
            selection = id
        } else {
            applyingFocus = true
            selection = id
            query = ""
        }
    }

    private func paste(_ entry: HistoryEntry) {
        dismissWindow(id: "history")
        model.paste(entry.polished)
    }

    private func delete(_ entry: HistoryEntry) {
        let entries = filtered
        if let index = entries.firstIndex(of: entry) {
            let next = entries.indices.contains(index + 1) ? entries[index + 1] : (index > 0 ? entries[index - 1] : nil)
            selection = next?.id
        }
        model.history.remove(entry)
    }

    private func closeOrClearSearch() {
        if query.isEmpty {
            dismissWindow(id: "history")
        } else {
            query = ""
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let entries = filtered
        guard let selected = entries.first(where: { $0.id == selection }) ?? entries.first else {
            if event.keyCode == Key.escape {
                closeOrClearSearch()
                return true
            }
            return false
        }
        let modifiers = Key.modifiers(event)
        let actions = actions(for: selected)

        if showsActions {
            switch event.keyCode {
            case Key.up: actionSelection = max(0, actionSelection - 1); return true
            case Key.down: actionSelection = min(actions.count - 1, actionSelection + 1); return true
            case Key.escape: showsActions = false; return true
            default: break
            }
            if Key.isReturn(event), modifiers.isEmpty {
                showsActions = false
                actions[actionSelection].perform()
                return true
            }
        }

        let index = entries.firstIndex(of: selected) ?? 0
        switch event.keyCode {
        case Key.up:
            selection = entries[max(0, index - 1)].id
            return true
        case Key.down:
            selection = entries[min(entries.count - 1, index + 1)].id
            return true
        case Key.escape:
            closeOrClearSearch()
            return true
        default:
            break
        }
        if modifiers == .command, Key.character(event) == "k" {
            actionSelection = 0
            showsActions.toggle()
            return true
        }
        if let action = actions.first(where: { Key.matches(event, $0.keys) }) {
            showsActions = false
            action.perform()
            return true
        }
        return false
    }
}

private struct HistoryDetail: View {
    var entry: HistoryEntry?
    @Binding var showsRaw: Bool

    var body: some View {
        if let entry {
            let style = HistoryStyle(source: entry.source)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spacingL) {
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    if let meeting = entry.meeting {
                        MeetingChatList(
                            turns: meeting.turns,
                            names: meeting.names,
                            separatesLocalVoice: meeting.separatesLocalVoice,
                            notes: meeting.notes,
                            scrolls: false
                        )
                    } else {
                        Text(entry.polished)
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if entry.meeting == nil, entry.source != "file", entry.raw != entry.polished, !entry.raw.isEmpty {
                        DisclosureGroup(t("Original", "Original"), isExpanded: $showsRaw) {
                            Text(entry.raw)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, DS.spacingXS)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    Hairline()
                    VStack(spacing: DS.spacingS) {
                        metadata(t("Source", "Quelle")) {
                            HStack(spacing: 6) {
                                IconTile(symbol: style.symbol, tint: style.tint, size: 16)
                                Text(style.title)
                            }
                        }
                        if entry.source == "file", !entry.raw.isEmpty {
                            metadata(t("File", "Datei")) {
                                Text(entry.raw)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(entry.raw)
                            }
                        }
                        metadata(t("Date", "Datum")) {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        metadata(t("Words", "Wörter")) {
                            Text("\(entry.polished.split(whereSeparator: \.isWhitespace).count)")
                        }
                        metadata(t("Characters", "Zeichen")) {
                            Text("\(entry.polished.count)")
                        }
                    }
                }
                .padding(DS.spacingXL)
            }
        } else {
            Color.clear
        }
    }

    private func metadata<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.system(size: 12))
    }
}

// MARK: - Rewrite

extension RewriteAction {
    var symbol: String {
        switch self {
        case .improve: "sparkles"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .professional: "briefcase.fill"
        case .casual: "face.smiling"
        case .bullets: "list.bullet"
        case .tasks: "checklist"
        case .translate: "character.bubble"
        }
    }

    var tint: Color {
        switch self {
        case .improve: .blue
        case .shorten: .orange
        case .expand: .green
        case .professional: .indigo
        case .casual: .yellow
        case .bullets: .teal
        case .tasks: .pink
        case .translate: .purple
        }
    }
}

struct RewriteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection = 0
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PaletteSearchField(
                placeholder: t("Describe the change or pick an action…", "Änderung beschreiben oder Aktion wählen…"),
                text: Binding(get: { model.rewriteInstruction }, set: { model.rewriteInstruction = $0 }),
                focus: $instructionFocused
            )
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(t("Selected text", "Markierter Text"))
                    Text(model.rewriteText.isEmpty ? t("Nothing selected", "Nichts markiert") : model.rewriteText)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .card(padding: DS.spacingM)
                        .padding(.horizontal, DS.spacingS)
                        .padding(.bottom, DS.spacingS)
                    SectionHeader(t("Actions", "Aktionen"))
                    ForEach(Array(RewriteAction.allCases.enumerated()), id: \.element.id) { index, action in
                        PaletteRow(
                            symbol: action.symbol,
                            tint: action.tint,
                            title: action.title,
                            subtitle: action == .translate ? (model.settings.translateTarget?.title ?? t("Off", "Aus")) : nil,
                            keys: ["⌘", "\(index + 1)"],
                            isSelected: !hasInstruction && index == selection
                        )
                        .onHover { if $0 { selection = index } }
                        .onTapGesture { apply(action) }
                    }
                }
                .padding(.horizontal, DS.spacingS)
                .padding(.bottom, DS.spacingS)
            }
            .scrollIndicators(.never)
            ActionBar {
                AppBadge(text: statusText)
            } trailing: {
                ActionBarButton(title: t("Speak Instruction", "Anweisung sprechen"), keys: ["⌘", "D"]) {
                    speak()
                }
                .disabled(model.phase != .idle)
                ActionBarDivider()
                ActionBarButton(title: primaryTitle, keys: ["↵"], isPrimary: true) {
                    applyPrimary()
                }
            }
        }
        .frame(width: 560, height: 540)
        .glassWindow()
        .onKeyDown { handleKey($0) }
        .onAppear {
            selection = 0
            instructionFocused = true
        }
    }

    private var hasInstruction: Bool {
        !model.rewriteInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryTitle: String {
        hasInstruction ? t("Apply Instruction", "Anweisung anwenden") : RewriteAction.allCases[selection].title
    }

    private var statusText: String {
        switch model.phase {
        case .recording, .handsFree: t("Listening…", "Hört zu…")
        case .working(let text): text
        case .idle: t("Result replaces the selection", "Ergebnis ersetzt die Markierung")
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = Key.modifiers(event)
        let count = RewriteAction.allCases.count
        switch event.keyCode {
        case Key.up:
            selection = max(0, selection - 1)
            return true
        case Key.down:
            selection = min(count - 1, selection + 1)
            return true
        case Key.escape:
            dismissWindow(id: "rewrite")
            return true
        default:
            break
        }
        if Key.isReturn(event), modifiers.isEmpty {
            applyPrimary()
            return true
        }
        if modifiers == .command, let digit = Int(Key.character(event)), (1...count).contains(digit) {
            apply(RewriteAction.allCases[digit - 1])
            return true
        }
        if modifiers == .command, Key.character(event) == "d" {
            speak()
            return true
        }
        return false
    }

    private func applyPrimary() {
        if hasInstruction {
            dismissWindow(id: "rewrite")
            model.returnFocus { Task { await model.applyCustomRewrite() } }
        } else {
            apply(RewriteAction.allCases[selection])
        }
    }

    private func apply(_ action: RewriteAction) {
        dismissWindow(id: "rewrite")
        model.returnFocus { Task { await model.applyRewrite(action) } }
    }

    private func speak() {
        guard model.phase == .idle else { return }
        Task { await model.dictateRewriteInstruction() }
    }
}
