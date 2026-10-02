import AppKit
import KeyboardShortcuts
import SwiftUI

enum PaletteSection: Int, CaseIterable, Sendable {
    case now
    case dictation
    case transcribe
    case recent
    case app

    var title: String {
        switch self {
        case .now: t("Now", "Aktuell")
        case .dictation: t("Dictation", "Diktat")
        case .transcribe: t("Transcribe", "Transkribieren")
        case .recent: t("Recent", "Zuletzt")
        case .app: "OnlyWhisper"
        }
    }
}

struct PaletteCommand: Identifiable {
    let id: String
    var section: PaletteSection
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var accessory: String?
    /// Shown on the row only. Local shortcuts live on the actions.
    var keys: [String] = []
    var keywords: [String] = []
    var isEnabled = true
    /// The first action is the primary one (Return). All of them appear in the Cmd+K menu.
    var actions: [MenuAction] = []
}

enum PaletteSearch {
    /// Higher is better, nil means no match. Every query word must match the title or a keyword.
    static func score(title: String, keywords: [String], query: String) -> Int? {
        let normalizedQuery = normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let titleText = normalize(title)
        let titleWords = words(titleText)
        let keywordWords = keywords.flatMap { words(normalize($0)) }
        var total = 0
        for token in tokens {
            if titleWords.contains(where: { $0.hasPrefix(token) }) {
                total += 3
            } else if titleText.contains(token) {
                total += 2
            } else if keywordWords.contains(where: { $0.hasPrefix(token) }) {
                total += 1
            } else {
                return nil
            }
        }
        if titleText.hasPrefix(normalizedQuery) {
            total += 2
        }
        return total
    }

    static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return commands }
        var matches: [(index: Int, command: PaletteCommand, score: Int)] = []
        for (index, command) in commands.enumerated() {
            if let score = score(title: command.title, keywords: command.keywords, query: query) {
                matches.append((index, command, score))
            }
        }
        matches.sort { left, right in
            left.score == right.score ? left.index < right.index : left.score > right.score
        }
        return matches.map(\.command)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

enum PaletteContext {
    case floating
    case menuBar

    var size: CGSize {
        switch self {
        case .floating: CGSize(width: DS.panelWidth, height: DS.panelHeight)
        case .menuBar: CGSize(width: 420, height: 460)
        }
    }
}

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var context: PaletteContext
    var onClose: () -> Void = {}

    @State private var query = ""
    @State private var selection = 0
    @State private var showsActions = false
    @State private var actionSelection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let visible = PaletteSearch.filter(commands, query: query)
        let selected = visible.indices.contains(selection) ? visible[selection] : nil
        VStack(spacing: 0) {
            PaletteSearchField(
                placeholder: t("Search commands and history…", "Befehle und Verlauf durchsuchen…"),
                text: $query,
                focus: $searchFocused,
                fontSize: context == .floating ? 18 : 15
            )
            Rectangle().fill(DS.hairline).frame(height: 1)
            results(visible)
            actionBar(selected)
        }
        .frame(width: context.size.width, height: context.size.height)
        .overlay(alignment: .bottomTrailing) {
            if showsActions, let selected, !selected.actions.isEmpty {
                ActionMenu(
                    title: selected.title,
                    actions: selected.actions,
                    selection: $actionSelection,
                    onRun: run
                )
                .padding(.trailing, DS.spacingS)
                .padding(.bottom, DS.actionBarHeight + DS.spacingXS)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
            }
        }
        .animation(.snappy(duration: 0.15), value: showsActions)
        .modifier(PaletteSurface(context: context))
        .onKeyDown { handleKey($0) }
        .onChange(of: query) {
            selection = 0
            showsActions = false
        }
        .onAppear {
            searchFocused = true
            if context == .menuBar {
                model.bootstrap()
                model.ensureHotkeys()
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ visible: [PaletteCommand]) -> some View {
        if visible.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: t("No results", "Keine Ergebnisse"),
                message: t("Try another word.", "Versuche ein anderes Wort.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups(visible), id: \.title) { group in
                            SectionHeader(group.title)
                            ForEach(group.rows, id: \.command.id) { row in
                                commandRow(row.command, index: row.index)
                                    .id(row.command.id)
                            }
                        }
                    }
                    .padding(.horizontal, DS.spacingS)
                    .padding(.bottom, DS.spacingS)
                }
                .scrollIndicators(.never)
                .onChange(of: selection) { _, newValue in
                    if visible.indices.contains(newValue) {
                        proxy.scrollTo(visible[newValue].id)
                    }
                }
            }
        }
    }

    private func commandRow(_ command: PaletteCommand, index: Int) -> some View {
        PaletteRow(
            symbol: command.symbol,
            tint: command.tint,
            title: command.title,
            subtitle: command.subtitle,
            accessory: command.accessory,
            keys: command.keys,
            isSelected: index == selection,
            isEnabled: command.isEnabled
        )
        .onHover { hovering in
            if hovering, !showsActions { selection = index }
        }
        .onTapGesture {
            selection = index
            runPrimary(command)
        }
    }

    private struct Group {
        var title: String
        var rows: [(index: Int, command: PaletteCommand)]
    }

    private func groups(_ visible: [PaletteCommand]) -> [Group] {
        let indexed = visible.enumerated().map { (index: $0.offset, command: $0.element) }
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return [Group(title: t("Results", "Ergebnisse"), rows: indexed)]
        }
        return PaletteSection.allCases.compactMap { section in
            let rows = indexed.filter { $0.command.section == section }
            return rows.isEmpty ? nil : Group(title: section.title, rows: rows)
        }
    }

    // MARK: Action bar

    private func actionBar(_ selected: PaletteCommand?) -> some View {
        ActionBar {
            if showsHotkeyWarning {
                Button {
                    model.openInputMonitoringSettings()
                } label: {
                    AppBadge(text: statusText)
                }
                .buttonStyle(.plain)
                .help(t("Open Input Monitoring settings", "Eingabeüberwachung öffnen"))
            } else {
                AppBadge(text: statusText)
            }
        } trailing: {
            if let selected, selected.isEnabled, let primary = selected.actions.first {
                ActionBarButton(title: primary.title, keys: ["↵"], isPrimary: true) {
                    run(primary)
                }
                if selected.actions.count > 1 {
                    ActionBarDivider()
                    ActionBarButton(title: t("Actions", "Aktionen"), keys: ["⌘", "K"]) {
                        toggleActions()
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch model.phase {
        case .recording, .handsFree: return t("Listening…", "Hört zu…")
        case .working(let text): return text
        case .idle: break
        }
        if model.meetingActive { return t("Meeting is recording", "Meeting wird aufgenommen") }
        if !model.statusMessage.isEmpty { return model.statusMessage }
        if showsHotkeyWarning {
            return t("Allow Input Monitoring to dictate", "Eingabeüberwachung fürs Diktat erlauben")
        }
        return t("Ready", "Bereit")
    }

    private var showsHotkeyWarning: Bool {
        if case .idle = model.phase, !model.meetingActive, model.statusMessage.isEmpty {
            return !model.hotkeyReady
        }
        return false
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let visible = PaletteSearch.filter(commands, query: query)
        let selected = visible.indices.contains(selection) ? visible[selection] : nil
        let modifiers = Key.modifiers(event)

        if showsActions, let selected {
            switch event.keyCode {
            case Key.up:
                actionSelection = max(0, actionSelection - 1)
                return true
            case Key.down:
                actionSelection = min(selected.actions.count - 1, actionSelection + 1)
                return true
            case Key.escape:
                showsActions = false
                return true
            default:
                break
            }
            if Key.isReturn(event), modifiers.isEmpty, selected.actions.indices.contains(actionSelection) {
                run(selected.actions[actionSelection])
                return true
            }
        }

        switch event.keyCode {
        case Key.up:
            selection = max(0, selection - 1)
            return true
        case Key.down:
            selection = min(max(visible.count - 1, 0), selection + 1)
            return true
        case Key.escape:
            if !query.isEmpty {
                query = ""
            } else {
                close()
            }
            return true
        default:
            break
        }

        if modifiers == .command, Key.character(event) == "k" {
            toggleActions()
            return true
        }
        if Key.isReturn(event), modifiers.isEmpty {
            if let selected { runPrimary(selected) }
            return true
        }
        if modifiers == .command, let digit = Int(Key.character(event)), (1...9).contains(digit) {
            if visible.indices.contains(digit - 1) { runPrimary(visible[digit - 1]) }
            return true
        }
        if let selected, selected.isEnabled, let action = selected.actions.first(where: { Key.matches(event, $0.keys) }) {
            run(action)
            return true
        }
        let global = commands.filter { $0.section == .app && $0.isEnabled }.flatMap(\.actions)
        if let action = global.first(where: { Key.matches(event, $0.keys) }) {
            run(action)
            return true
        }
        return false
    }

    private func toggleActions() {
        let visible = PaletteSearch.filter(commands, query: query)
        guard visible.indices.contains(selection), visible[selection].isEnabled, !visible[selection].actions.isEmpty else { return }
        actionSelection = 0
        showsActions.toggle()
    }

    private func runPrimary(_ command: PaletteCommand) {
        guard command.isEnabled, let primary = command.actions.first else { return }
        run(primary)
    }

    private func run(_ action: MenuAction) {
        showsActions = false
        close()
        action.perform()
    }

    private func close() {
        switch context {
        case .floating:
            onClose()
        case .menuBar:
            let window = NSApp.keyWindow
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                if let window, window.isVisible {
                    window.orderOut(nil)
                }
            }
        }
    }

    // MARK: Commands

    private var commands: [PaletteCommand] {
        var result: [PaletteCommand] = []
        let model = model

        switch model.phase {
        case .recording, .handsFree:
            result.append(PaletteCommand(
                id: "finish",
                section: .now,
                title: t("Finish dictation", "Diktat beenden"),
                subtitle: t("Insert the text", "Text einfügen"),
                symbol: "checkmark",
                tint: .green,
                keywords: ["stop", "done", "fertig", "beenden"],
                actions: [MenuAction(id: "finish.run", title: t("Finish Dictation", "Diktat beenden"), symbol: "checkmark.circle") {
                    model.finishHandsFree()
                }]
            ))
            result.append(PaletteCommand(
                id: "cancel",
                section: .now,
                title: t("Cancel dictation", "Diktat abbrechen"),
                subtitle: t("Listening", "Hört zu"),
                symbol: "xmark",
                tint: .red,
                keys: ["esc"],
                keywords: ["stop", "abbrechen"],
                actions: [MenuAction(id: "cancel.run", title: t("Cancel Dictation", "Diktat abbrechen"), symbol: "xmark.circle") {
                    model.cancelCapture()
                }]
            ))
        case .working(let text):
            result.append(PaletteCommand(
                id: "working",
                section: .now,
                title: text,
                symbol: "ellipsis",
                tint: .gray,
                isEnabled: false
            ))
        case .idle:
            break
        }

        if model.meetingActive {
            result.append(PaletteCommand(
                id: "meeting.live",
                section: .now,
                title: t("Meeting is recording", "Meeting läuft"),
                symbol: "record.circle",
                tint: .red,
                keywords: ["meeting", "stop"],
                actions: [
                    MenuAction(id: "meeting.live.open", title: t("Show Meeting", "Meeting zeigen"), symbol: "arrow.up.forward.app") {
                        model.open("meeting")
                    },
                    MenuAction(id: "meeting.live.stop", title: t("Stop Meeting", "Meeting beenden"), symbol: "stop.circle", keys: ["⌘", "."], isDestructive: true) {
                        Task { await model.stopMeeting() }
                    },
                ]
            ))
        }

        if model.needsSetup {
            result.append(PaletteCommand(
                id: "setup",
                section: .now,
                title: t("Finish setup", "Einrichtung abschließen"),
                subtitle: t("Required once", "Einmalig nötig"),
                symbol: "sparkles",
                tint: .pink,
                keywords: ["setup", "einrichtung", "permissions", "download"],
                actions: [MenuAction(id: "setup.open", title: t("Open Setup", "Einrichtung öffnen"), symbol: "arrow.up.forward.app") {
                    model.open("setup")
                }]
            ))
        }

        result.append(PaletteCommand(
            id: "dictate",
            section: .dictation,
            title: t("Start dictation", "Diktat starten"),
            subtitle: t("Hands-free", "Freisprechen"),
            symbol: "mic.fill",
            tint: .blue,
            accessory: t("or hold \(model.settings.dictationKey.title)", "oder \(model.settings.dictationKey.title) halten"),
            keywords: ["dictate", "speak", "record", "voice", "diktieren", "sprechen", "aufnehmen", "stimme"],
            isEnabled: model.phase == .idle,
            actions: [MenuAction(id: "dictate.run", title: t("Start Dictation", "Diktat starten"), symbol: "mic") {
                model.returnFocus { model.startHandsFree() }
            }]
        ))

        result.append(PaletteCommand(
            id: "rewrite",
            section: .dictation,
            title: t("Rewrite selection", "Markierung umschreiben"),
            subtitle: t("Selected text", "Markierter Text"),
            symbol: "wand.and.stars",
            tint: .purple,
            keys: shortcutKeys(.rewriteSelection),
            keywords: ["rewrite", "improve", "translate", "umschreiben", "verbessern", "übersetzen"],
            isEnabled: model.phase == .idle,
            actions: [MenuAction(id: "rewrite.run", title: t("Rewrite Selection", "Umschreiben"), symbol: "wand.and.stars") {
                model.returnFocus { model.beginRewrite() }
            }]
        ))

        result.append(PaletteCommand(
            id: "meeting",
            section: .transcribe,
            title: t("Meeting", "Meeting"),
            subtitle: t("Transcript with speakers", "Transkript mit Sprechern"),
            symbol: "person.2.wave.2.fill",
            tint: .orange,
            accessory: model.meetingActive ? t("Recording", "Läuft") : nil,
            keywords: ["meeting", "call", "transcript", "notes", "protokoll", "besprechung"],
            actions: [MenuAction(id: "meeting.open", title: t("Open Meeting", "Meeting öffnen"), symbol: "arrow.up.forward.app") {
                model.open("meeting")
            }]
        ))

        result.append(PaletteCommand(
            id: "files",
            section: .transcribe,
            title: t("Transcribe files", "Dateien transkribieren"),
            subtitle: t("Audio and video", "Audio und Video"),
            symbol: "doc.text.fill",
            tint: .teal,
            keywords: ["files", "audio", "video", "folder", "dateien", "ordner"],
            actions: [MenuAction(id: "files.open", title: t("Open Files", "Dateien öffnen"), symbol: "arrow.up.forward.app") {
                model.open("files")
            }]
        ))

        for entry in model.history.entries.prefix(5) {
            let style = HistoryStyle(source: entry.source)
            result.append(PaletteCommand(
                id: "history.\(entry.id.uuidString)",
                section: .recent,
                title: entry.listTitle,
                symbol: style.symbol,
                tint: style.tint,
                accessory: entry.date.formatted(.relative(presentation: .named)),
                keywords: [entry.polished],
                actions: [
                    MenuAction(id: "paste", title: t("Paste", "Einfügen"), symbol: "doc.on.clipboard", keys: ["↵"]) {
                        model.paste(entry.polished)
                    },
                    MenuAction(id: "copy", title: t("Copy to Clipboard", "Kopieren"), symbol: "doc.on.doc", keys: ["⌘", "↵"]) {
                        model.copy(entry.polished)
                    },
                    MenuAction(id: "delete", title: t("Delete Entry", "Eintrag löschen"), symbol: "trash", keys: ["⌃", "X"], isDestructive: true) {
                        model.history.remove(entry)
                    },
                ]
            ))
        }

        result.append(PaletteCommand(
            id: "history",
            section: .app,
            title: t("History", "Verlauf"),
            subtitle: t("\(model.history.entries.count) entries", "\(model.history.entries.count) Einträge"),
            symbol: "clock.arrow.circlepath",
            tint: .indigo,
            keywords: ["history", "verlauf", "clipboard"],
            actions: [MenuAction(id: "history.open", title: t("Open History", "Verlauf öffnen"), symbol: "arrow.up.forward.app") {
                model.open("history")
            }]
        ))

        result.append(PaletteCommand(
            id: "settings",
            section: .app,
            title: t("Settings", "Einstellungen"),
            symbol: "gearshape.fill",
            tint: .gray,
            keys: ["⌘", ","],
            keywords: ["settings", "preferences", "einstellungen", "optionen"],
            actions: [MenuAction(id: "settings.open", title: t("Open Settings", "Einstellungen öffnen"), symbol: "gearshape", keys: ["⌘", ","]) {
                model.showSettings()
            }]
        ))

        result.append(PaletteCommand(
            id: "updates",
            section: .app,
            title: t("Check for updates", "Nach Updates suchen"),
            symbol: "arrow.triangle.2.circlepath",
            tint: .green,
            keywords: ["update", "version"],
            isEnabled: Updater.shared.canCheckForUpdates,
            actions: [MenuAction(id: "updates.run", title: t("Check for Updates", "Nach Updates suchen"), symbol: "arrow.triangle.2.circlepath") {
                Updater.shared.checkForUpdates()
            }]
        ))

        result.append(PaletteCommand(
            id: "quit",
            section: .app,
            title: t("Quit OnlyWhisper", "OnlyWhisper beenden"),
            symbol: "power",
            tint: .red,
            keys: ["⌘", "Q"],
            keywords: ["quit", "exit", "beenden"],
            actions: [MenuAction(id: "quit.run", title: t("Quit", "Beenden"), symbol: "power", keys: ["⌘", "Q"]) {
                NSApp.terminate(nil)
            }]
        ))

        return result
    }

    private func shortcutKeys(_ name: KeyboardShortcuts.Name) -> [String] {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return [] }
        return shortcut.description.map { String($0) }
    }
}

private struct PaletteSurface: ViewModifier {
    var context: PaletteContext

    func body(content: Content) -> some View {
        switch context {
        case .floating: content.glassPanel()
        case .menuBar: content
        }
    }
}

struct HistoryStyle {
    var symbol: String
    var tint: Color
    var title: String

    init(source: String) {
        switch source {
        case "rewrite":
            symbol = "wand.and.stars"
            tint = .purple
            title = t("Rewrite", "Umschreiben")
        case "meeting":
            symbol = "person.2.fill"
            tint = .orange
            title = t("Meeting", "Meeting")
        case "file":
            symbol = "doc.text.fill"
            tint = .teal
            title = t("File", "Datei")
        default:
            symbol = "mic.fill"
            tint = .blue
            title = t("Dictation", "Diktat")
        }
    }
}

extension String {
    var firstLine: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
    }
}

// MARK: - Floating panel

final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        CommandPaletteController.shared.hide()
    }
}

@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    static let shared = CommandPaletteController()
    private var panel: CommandPalettePanel?
    private var shownAt: Date?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let size = PaletteContext.floating.size
        let root = CommandPaletteView(context: .floating) { [weak self] in self?.hide() }
            .environment(AppModel.shared)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - visible.height * 0.22 - size.height
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        shownAt = .now
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Right after a global hotkey the previous app can briefly take key status back.
        if let shownAt, Date.now.timeIntervalSince(shownAt) < 0.3 {
            panel?.makeKey()
            return
        }
        hide()
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel(
            contentRect: NSRect(origin: .zero, size: PaletteContext.floating.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        return panel
    }
}
