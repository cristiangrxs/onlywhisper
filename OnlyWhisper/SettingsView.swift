import AppKit
import KeyboardShortcuts
import SwiftUI

enum AppWindows {
    static let settings = NSUserInterfaceItemIdentifier("onlywhisper.settings")
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: BrandArtwork.menuBar)
            .accessibilityLabel("OnlyWhisper")
            .opacity(isRecording && !reduceMotion ? 0.45 : 1)
            .animation(isRecording && !reduceMotion ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: isRecording)
            .task {
                model.bind(openWindow: { openWindow(id: $0) }, openSettings: { openSettings() })
                model.bootstrap()
            }
    }

    private var isRecording: Bool {
        model.phase == .recording || model.phase == .handsFree
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { item in
                Tab(item.title, systemImage: item.symbol, value: item) {
                    item.content
                }
            }
        }
        .glassWindow()
        .background(SettingsWindowFinder())
        .onAppear {
            model.ensureHotkeys()
            applySettingsTabRequest()
        }
        .onChange(of: model.settingsTabRequest) { _, _ in
            applySettingsTabRequest()
        }
    }

    private func applySettingsTabRequest() {
        guard let raw = model.settingsTabRequest, let next = SettingsTab(rawValue: raw) else { return }
        tab = next
        model.settingsTabRequest = nil
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case dictation
    case language
    case dictionary
    case shortcuts
    case models
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: t("General", "Allgemein")
        case .dictation: t("Dictation", "Diktat")
        case .language: t("Language", "Sprache")
        case .dictionary: t("Dictionary", "Wörterbuch")
        case .shortcuts: t("Shortcuts", "Kurzbefehle")
        case .models: t("Models", "Modelle")
        case .about: t("About", "Über")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "mic"
        case .language: "globe"
        case .dictionary: "character.book.closed"
        case .shortcuts: "command"
        case .models: "cpu"
        case .about: "info.circle"
        }
    }

    @MainActor @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettings()
        case .dictation: DictationSettings()
        case .language: LanguageSettings()
        case .dictionary: DictionarySettings()
        case .shortcuts: ShortcutSettings()
        case .models: ModelSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - Shared layout

private struct SettingsPage<Content: View>: View {
    var width: CGFloat = 560
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.columns)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(width: width)
    }
}

private struct OptionToggle: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: $isOn)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
    }
}

// MARK: - Tabs

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPage {
            LabeledContent(t("Startup", "Start")) {
                OptionToggle(
                    title: t("Launch at login", "Beim Anmelden starten"),
                    detail: t("OnlyWhisper waits in the menu bar.", "OnlyWhisper wartet in der Menüleiste."),
                    isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
                )
            }
            LabeledContent(t("Updates", "Updates")) {
                OptionToggle(
                    title: t("Check automatically", "Automatisch suchen"),
                    detail: t("Updates are signed and installed after you confirm.", "Updates sind signiert und werden erst nach Bestätigung installiert."),
                    isOn: Binding(
                        get: { Updater.shared.automaticallyChecksForUpdates },
                        set: { Updater.shared.automaticallyChecksForUpdates = $0 }
                    )
                )
            }
        }
    }
}

private struct DictationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPage {
            LabeledContent(t("Text", "Text")) {
                OptionToggle(
                    title: t("Polish text", "Text glätten"),
                    detail: t("Fixes punctuation and filler words on this Mac.", "Korrigiert Satzzeichen und Füllwörter auf diesem Mac."),
                    isOn: Binding(get: { model.settings.polishEnabled }, set: { model.settings.polishEnabled = $0 })
                )
            }
            LabeledContent(t("Meetings", "Meetings")) {
                OptionToggle(
                    title: t("Record system audio", "Systemton aufnehmen"),
                    detail: t("Captures the other side of calls. Needs screen recording access.", "Nimmt auch die Gegenseite von Anrufen auf. Braucht Zugriff auf Bildschirmaufnahme."),
                    isOn: Binding(get: { model.settings.systemAudioInMeetings }, set: { model.settings.systemAudioInMeetings = $0 })
                )
            }
        }
    }
}

private struct LanguageSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPage {
            LanguageField(
                title: t("Speech", "Gesprochen"),
                selection: Binding(get: { model.settings.language }, set: { model.settings.language = $0 }),
                choices: SpeechChoice.allCases
            )
            LanguageField(
                title: t("Translate to", "Übersetzen nach"),
                selection: Binding(get: { model.settings.translateTarget }, set: { model.settings.translateTarget = $0 }),
                choices: SpeechChoice.allCases.filter { $0 != .automatic }
            )
            LabeledContent("") {
                Text(t(
                    "Automatic detects the spoken language. A fixed choice is faster and more accurate.",
                    "Automatisch erkennt die gesprochene Sprache. Eine feste Wahl ist schneller und genauer."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LanguageField: View {
    var title: String
    @Binding var selection: SpeechChoice
    var choices: [SpeechChoice]
    @State private var query = ""

    private var filtered: [SpeechChoice] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return choices }
        return choices.filter { choice in
            choice.title.localizedStandardContains(needle)
                || choice.code?.caseInsensitiveCompare(needle) == .orderedSame
        }
    }

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 6) {
                TextField(t("Search", "Suchen"), text: $query)
                    .textFieldStyle(.roundedBorder)
                List(filtered, selection: Binding<SpeechChoice?>(
                    get: { selection },
                    set: { if let choice = $0 { selection = choice } }
                )) { choice in
                    Text(choice.title).tag(choice)
                }
                .frame(height: 132)
            }
        }
    }
}

private struct DictionarySettings: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var heard = ""
    @State private var written = ""
    @State private var selection: CustomDictionary.Entry.ID?
    @FocusState private var heardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingM) {
            Text(t(
                "Words OnlyWhisper often mishears. They are replaced as you speak.",
                "Wörter, die OnlyWhisper oft falsch versteht. Sie werden beim Sprechen ersetzt."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: DS.spacingS) {
                TextField(t("Heard", "Gehört"), text: $heard)
                    .focused($heardFocused)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                TextField(t("Written", "Geschrieben"), text: $written)
                    .onSubmit(add)
                Button(t("Add", "Hinzufügen"), action: add)
                    .disabled(heard.trimmingCharacters(in: .whitespaces).isEmpty || written.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            VStack(spacing: 0) {
                Table(filtered, selection: $selection) {
                    TableColumn(t("Heard", "Gehört")) { entry in
                        TextField("", text: binding(entry, \.heard))
                            .textFieldStyle(.plain)
                    }
                    TableColumn(t("Written", "Geschrieben")) { entry in
                        TextField("", text: binding(entry, \.written))
                            .textFieldStyle(.plain)
                    }
                }
                .overlay {
                    if filtered.isEmpty {
                        EmptyStateView(
                            symbol: "character.book.closed",
                            title: search.isEmpty ? t("No words yet", "Noch keine Wörter") : t("No matches", "Keine Treffer"),
                            message: search.isEmpty ? t("Add a word above, e.g. “only whisper” → “OnlyWhisper”.", "Füge oben ein Wort hinzu, z. B. „only whisper“ → „OnlyWhisper“.") : nil
                        )
                    }
                }
                HStack(spacing: DS.spacingS) {
                    Button {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .accessibilityLabel(t("Remove word", "Wort entfernen"))
                    Spacer()
                    Text(t("\(model.dictionary.dictionary.entries.count) words", "\(model.dictionary.dictionary.entries.count) Wörter"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(t("Search", "Suchen"), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                .padding(DS.spacingS)
                .background(DS.cardFill)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous).strokeBorder(DS.hairline))
        }
        .padding(24)
        .frame(width: 560, height: 440)
    }

    private var filtered: [CustomDictionary.Entry] {
        let entries = model.dictionary.dictionary.entries
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.heard.localizedStandardContains(search) || $0.written.localizedStandardContains(search) }
    }

    private func binding(_ entry: CustomDictionary.Entry, _ path: WritableKeyPath<CustomDictionary.Entry, String>) -> Binding<String> {
        Binding(
            get: { model.dictionary.dictionary.entries.first { $0.id == entry.id }?[keyPath: path] ?? "" },
            set: { value in
                var updated = model.dictionary.dictionary.entries.first { $0.id == entry.id } ?? entry
                updated[keyPath: path] = value
                model.dictionary.update(updated)
            }
        )
    }

    private func add() {
        model.dictionary.add(heard: heard, written: written)
        heard = ""
        written = ""
        heardFocused = true
    }

    private func removeSelected() {
        guard let selection, let entry = model.dictionary.dictionary.entries.first(where: { $0.id == selection }) else { return }
        model.dictionary.remove(entry)
        self.selection = nil
    }
}

private struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        let _ = model.permissionRevision
        SettingsPage {
            LabeledContent(t("Command palette", "Befehlspalette")) {
                VStack(alignment: .leading, spacing: 6) {
                    GlobalShortcutRecorder(name: .commandPalette)
                    shortcutStatus(.commandPalette)
                    Text(t("Opens OnlyWhisper from any app.", "Öffnet OnlyWhisper aus jeder App."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(t("Rewrite selection", "Markierung umschreiben")) {
                VStack(alignment: .leading, spacing: 6) {
                    GlobalShortcutRecorder(name: .rewriteSelection)
                    shortcutStatus(.rewriteSelection)
                    if !model.accessibilityGranted {
                        Text(t(
                            "Accessibility is required to read the selected text.",
                            "Bedienungshilfen werden gebraucht, um den markierten Text zu lesen."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Button(t("Open System Settings", "Systemeinstellungen öffnen")) {
                            model.openAccessibilitySettings()
                        }
                    }
                }
            }
            LabeledContent(t("Dictation key", "Diktat-Taste")) {
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutRecorder(
                        mode: .dictation,
                        keys: model.settings.dictationKey.keycaps,
                        allowsClear: false,
                        onCommit: { model.updateDictationKey($0) }
                    )
                    if dictationOverlapsShortcut {
                        overlapNote
                    }
                    Text(t(
                        "Hold a modifier, or a modifier and a key. A bare letter is ignored.",
                        "Eine Sondertaste halten, oder eine Sondertaste und eine Taste. Ein einzelner Buchstabe gilt nicht."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent(t("Status", "Status")) {
                if model.hotkeyReady {
                    StatusBadge(title: t("Ready", "Bereit"), tint: .green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusBadge(
                            title: t("Input Monitoring required", "Eingabeüberwachung fehlt"),
                            tint: .orange
                        )
                        Text(t(
                            "OnlyWhisper needs this to hear the dictation key in other apps.",
                            "OnlyWhisper braucht das, um die Diktat-Taste in anderen Apps zu hören."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Button(t("Open System Settings", "Systemeinstellungen öffnen")) {
                            model.openInputMonitoringSettings()
                        }
                    }
                }
            }
            LabeledContent(t("How it works", "So geht’s")) {
                VStack(alignment: .leading, spacing: DS.spacingS) {
                    ShortcutHint(label: t("Hold to dictate", "Halten zum Diktieren"), keys: model.settings.dictationKey.keycaps)
                    ShortcutHint(label: t("Tap for hands-free", "Tippen für Freisprechen"), keys: model.settings.dictationKey.keycaps)
                    ShortcutHint(label: t("Cancel", "Abbrechen"), keys: ["esc"])
                }
                .font(.callout)
            }
            LabeledContent(t("Defaults", "Standardwerte")) {
                Button(t("Reset all", "Alle zurücksetzen")) {
                    confirmReset = true
                }
            }
        }
        .confirmationDialog(
            t("Reset all shortcuts?", "Alle Kurzbefehle zurücksetzen?"),
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button(t("Reset", "Zurücksetzen"), role: .destructive) {
                model.resetShortcuts()
            }
            Button(t("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(t(
                "Command palette, rewrite, and the dictation key return to their defaults.",
                "Befehlspalette, Umschreiben und die Diktat-Taste werden auf die Standardwerte gesetzt."
            ))
        }
    }

    @ViewBuilder
    private func shortcutStatus(_ name: KeyboardShortcuts.Name) -> some View {
        let _ = model.shortcutRevision
        if KeyboardShortcuts.getShortcut(for: name) == nil {
            StatusBadge(title: t("Not set", "Nicht festgelegt"), tint: .orange)
        } else if model.shortcutConflicts.contains(name) {
            VStack(alignment: .leading, spacing: 4) {
                StatusBadge(title: t("Taken by another app", "Von einer anderen App belegt"), tint: .orange)
                Text(t("Choose different keys.", "Bitte andere Tasten wählen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if overlapsDictation(name) {
            overlapNote
        } else {
            StatusBadge(title: t("Ready", "Bereit"), tint: .green)
        }
    }

    private var overlapNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusBadge(title: t("Same as another shortcut", "Gleich wie ein anderer Kurzbefehl"), tint: .orange)
            Text(t("Choose different keys.", "Bitte andere Tasten wählen."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dictationOverlapsShortcut: Bool {
        let _ = model.shortcutRevision
        return overlapsDictation(.commandPalette) || overlapsDictation(.rewriteSelection)
    }

    private func overlapsDictation(_ name: KeyboardShortcuts.Name) -> Bool {
        guard case .chord(let keyCode, let carbonModifiers, _) = model.settings.dictationKey else { return false }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }
        return shortcut.carbonKeyCode == keyCode && shortcut.carbonModifiers == carbonModifiers
    }
}

private struct ModelSettings: View {
    @Environment(AppModel.self) private var model
    @State private var prompt: ModelChangePrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingM) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Models on this Mac", "Modelle auf diesem Mac"))
                        .font(.headline)
                    Text(t("Everything runs offline once downloaded.", "Nach dem Laden läuft alles offline."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !model.canChangeModels {
                        Text(t("Finish what you're doing first.", "Bitte zuerst beenden."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: DS.spacingS)
                headerActions
            }
            ForEach(ModelInfo.catalog) { info in
                let state = model.downloads.state(of: info)
                ModelCard(
                    info: info,
                    state: state,
                    showsActions: true,
                    actionsEnabled: model.canChangeModels,
                    errorMessage: model.downloads.errorMessage(for: info.id),
                    progressDetail: model.downloads.progressDetail(for: info.id),
                    sizeText: model.downloads.sizeText(for: info.id),
                    canCancel: isDownloading(state),
                    onDownload: { Task { await model.downloadModel(info.id) } },
                    onUpdate: { prompt = .update(info.id) },
                    onRemove: { prompt = .remove(info.id) },
                    onCancel: { model.downloads.cancel() }
                )
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if !model.downloads.isRunning {
                model.downloads.refreshReadyState()
            }
            Task { await model.downloads.loadExactSizes() }
        }
        .confirmationDialog(
            promptTitle,
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            titleVisibility: .visible
        ) {
            confirmButton
            Button(t("Cancel", "Abbrechen"), role: .cancel) {}
        } message: {
            Text(promptMessage)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: DS.spacingS) {
            if !model.downloads.missingIDs.isEmpty {
                Button(t("Download missing", "Fehlende laden")) {
                    Task { await model.downloadMissingModels() }
                }
                .disabled(!model.canChangeModels)
            }
            if model.downloads.outdatedIDs.count >= 2 {
                Button(t("Update all", "Alle aktualisieren")) {
                    prompt = .updateAll
                }
                .disabled(!model.canChangeModels)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch prompt {
        case .remove(let id):
            Button(t("Remove", "Entfernen"), role: .destructive) {
                Task { await model.removeModel(id) }
            }
        case .update(let id):
            Button(t("Update", "Aktualisieren")) {
                Task { await model.updateModel(id) }
            }
        case .updateAll:
            Button(t("Update all", "Alle aktualisieren")) {
                Task { await model.updateOutdatedModels() }
            }
        case nil:
            EmptyView()
        }
    }

    private var promptTitle: String {
        switch prompt {
        case .remove(let id):
            let name = ModelInfo.info(id)?.name ?? ""
            return t("Remove \(name)?", "\(name) entfernen?")
        case .update(let id):
            let name = ModelInfo.info(id)?.name ?? ""
            return t("Update \(name)?", "\(name) aktualisieren?")
        case .updateAll:
            return t("Update models?", "Modelle aktualisieren?")
        case nil:
            return ""
        }
    }

    private var promptMessage: String {
        switch prompt {
        case .remove(let id):
            guard let info = ModelInfo.info(id) else { return "" }
            return removalMessage(info)
        case .update(let id):
            guard let info = ModelInfo.info(id) else { return "" }
            return t(
                "Replace \(info.name) with the version in this app? \(sized(info)) will be downloaded.",
                "\(info.name) durch die Version in dieser App ersetzen? Dabei werden \(sized(info)) geladen."
            )
        case .updateAll:
            let names = model.downloads.outdatedIDs.compactMap { ModelInfo.info($0)?.name }.formatted(.list(type: .and))
            return t(
                "\(names) will be replaced with the versions in this app.",
                "\(names) werden durch die Versionen in dieser App ersetzt."
            )
        case nil:
            return ""
        }
    }

    private func isDownloading(_ state: ModelState) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    private func sized(_ info: ModelInfo) -> String {
        model.downloads.sizeText(for: info.id) ?? t("the downloaded files", "die geladenen Dateien")
    }

    private func removalMessage(_ info: ModelInfo) -> String {
        let effect: String
        switch info.id {
        case .parakeet:
            effect = t(
                "Dictation in most languages needs this model.",
                "Diktat in den meisten Sprachen braucht dieses Modell."
            )
        case .whisper:
            effect = t(
                "Dictation and meetings need this model.",
                "Diktat und Meetings brauchen dieses Modell."
            )
        case .qwen:
            effect = t(
                "Polishing and rewriting need this model.",
                "Glätten und Umschreiben brauchen dieses Modell."
            )
        }
        return t(
            "\(info.name) will be removed (\(sized(info))). \(effect) You can download it again later.",
            "\(info.name) wird entfernt (\(sized(info))). \(effect) Du kannst es später erneut laden."
        )
    }
}

private enum ModelChangePrompt: Identifiable {
    case remove(ModelID)
    case update(ModelID)
    case updateAll

    var id: String {
        switch self {
        case .remove(let model): "remove-\(model.rawValue)"
        case .update(let model): "update-\(model.rawValue)"
        case .updateAll: "update-all"
        }
    }
}

struct ModelCard: View {
    var info: ModelInfo
    var state: ModelState
    var showsActions = false
    var actionsEnabled = true
    var errorMessage: String?
    var progressDetail: String?
    var sizeText: String?
    var canCancel = false
    var onDownload: () -> Void = {}
    var onUpdate: () -> Void = {}
    var onRemove: () -> Void = {}
    var onCancel: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            HStack(spacing: DS.spacingM) {
                IconTile(symbol: info.symbol, tint: tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name).font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if case .downloading(let progress) = state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(.top, 4)
                        if let progressDetail {
                            Text(progressDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: DS.spacingS)
                trailing
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: DS.spacingM)
        .modifier(OnboardingCardAccessibility(combine: !showsActions && !canCancel))
    }

    private var subtitle: String {
        if let sizeText, !sizeText.isEmpty {
            return "\(info.role) · \(sizeText)"
        }
        return info.role
    }

    private var tint: Color {
        switch info.id {
        case .parakeet: .blue
        case .whisper: .teal
        case .qwen: .purple
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .downloading(_) where canCancel:
            HStack(spacing: DS.spacingS) {
                badge
                Button(t("Cancel", "Abbrechen"), action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .downloading, .waiting:
            badge
        case .missing:
            if showsActions {
                actionButton(
                    errorMessage == nil ? t("Download", "Laden") : t("Try Again", "Erneut versuchen"),
                    prominent: true,
                    action: onDownload
                )
            } else {
                badge
            }
        case .ready:
            HStack(spacing: DS.spacingS) {
                badge
                if showsActions {
                    actionButton(t("Remove", "Entfernen"), prominent: false, action: onRemove)
                }
            }
        case .updateAvailable:
            if showsActions {
                VStack(alignment: .trailing, spacing: DS.spacingXS) {
                    badge
                    HStack(spacing: DS.spacingS) {
                        actionButton(t("Update", "Aktualisieren"), prominent: true, action: onUpdate)
                        actionButton(t("Remove", "Entfernen"), prominent: false, action: onRemove)
                    }
                }
            } else {
                badge
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!actionsEnabled)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!actionsEnabled)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .ready: StatusBadge(title: t("On this Mac", "Auf diesem Mac"), tint: .green)
        case .updateAvailable: StatusBadge(title: t("Update available", "Update verfügbar"), tint: .blue)
        case .downloading(let progress): StatusBadge(title: progress.formatted(.percent.precision(.fractionLength(0))), tint: .blue)
        case .waiting: StatusBadge(title: t("Waiting", "Wartet"), tint: .secondary)
        case .missing: StatusBadge(title: t("Not downloaded", "Nicht geladen"), tint: .orange)
        }
    }
}

/// Onboarding cards are one status summary. Settings cards keep their buttons separate for VoiceOver.
private struct OnboardingCardAccessibility: ViewModifier {
    var combine: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if combine {
            content.accessibilityElement(children: .combine)
        } else {
            content
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: DS.spacingM) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("OnlyWhisper")
                .font(.title2.weight(.semibold))
            Text(t("Version \(version)", "Version \(version)"))
                .foregroundStyle(.secondary)
            Button(t("Check for Updates…", "Nach Updates suchen…")) {
                Updater.shared.checkForUpdates()
            }
            .disabled(!Updater.shared.canCheckForUpdates)
            Text("Whisper MIT · Qwen Apache 2.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, DS.spacingS)
        }
        .padding(32)
        .frame(width: 560)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

private struct SettingsWindowFinder: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = AppWindows.settings
            AppModel.shared.orderSettingsFront()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if nsView.window?.identifier != AppWindows.settings {
                nsView.window?.identifier = AppWindows.settings
            }
        }
    }
}
