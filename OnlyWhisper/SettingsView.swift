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
        .onAppear { model.ensureHotkeys() }
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
            Picker(t("Speech", "Gesprochen"), selection: Binding(
                get: { model.settings.language },
                set: { model.settings.language = $0 }
            )) {
                ForEach(SpeechChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            Picker(t("Translate to", "Übersetzen nach"), selection: Binding(
                get: { model.settings.translateTarget },
                set: { model.settings.translateTarget = $0 }
            )) {
                ForEach(SpeechChoice.allCases.filter { $0 != .automatic }) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            LabeledContent("") {
                Text(t(
                    "Automatic detects the language each time. Choosing one is faster and more accurate.",
                    "Automatisch erkennt die Sprache jedes Mal. Eine feste Wahl ist schneller und genauer."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    var body: some View {
        let _ = model.permissionRevision
        SettingsPage {
            LabeledContent(t("Command palette", "Befehlspalette")) {
                VStack(alignment: .leading, spacing: 6) {
                    KeyboardShortcuts.Recorder(for: .commandPalette)
                    shortcutStatus(.commandPalette)
                    Text(t("Opens OnlyWhisper from any app.", "Öffnet OnlyWhisper aus jeder App."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(t("Rewrite selection", "Markierung umschreiben")) {
                VStack(alignment: .leading, spacing: 6) {
                    KeyboardShortcuts.Recorder(for: .rewriteSelection)
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
            Picker(t("Dictation key", "Diktat-Taste"), selection: Binding(
                get: { model.settings.dictationKey },
                set: { model.updateDictationKey($0) }
            )) {
                ForEach(DictationKey.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
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
                            "OnlyWhisper needs this to hear the Option key in other apps.",
                            "OnlyWhisper braucht das, um die Option-Taste in anderen Apps zu hören."
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
                    ShortcutHint(label: t("Hold to dictate", "Halten zum Diktieren"), keys: [holdKey])
                    ShortcutHint(label: t("Tap for hands-free", "Tippen für Freisprechen"), keys: [holdKey])
                    ShortcutHint(label: t("Cancel", "Abbrechen"), keys: ["esc"])
                }
                .font(.callout)
                .frame(maxWidth: 260)
            }
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
        } else {
            StatusBadge(title: t("Ready", "Bereit"), tint: .green)
        }
    }

    private var holdKey: String {
        switch model.settings.dictationKey {
        case .rightOption: t("Right ⌥", "Rechts ⌥")
        case .leftOption: t("Left ⌥", "Links ⌥")
        }
    }
}

private struct ModelSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingM) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Models on this Mac", "Modelle auf diesem Mac"))
                        .font(.headline)
                    Text(t("Everything runs offline once downloaded.", "Nach dem Laden läuft alles offline."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.downloads.isReady ? t("Download Again", "Erneut laden") : t("Download", "Laden")) {
                    Task { await model.downloads.downloadRequiredModels() }
                }
                .disabled(model.downloads.isRunning)
            }
            ForEach(ModelInfo.catalog) { info in
                ModelCard(info: info, state: model.downloads.state(of: info))
            }
            if let error = model.downloads.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

struct ModelCard: View {
    var info: ModelInfo
    var state: ModelState

    var body: some View {
        HStack(spacing: DS.spacingM) {
            IconTile(symbol: info.symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(.system(size: 13, weight: .semibold))
                Text("\(info.role) · \(info.size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .downloading(let progress) = state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: DS.spacingS)
            badge
        }
        .card(padding: DS.spacingM)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch info.id {
        case "parakeet": .blue
        case "whisper": .teal
        default: .purple
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .ready: StatusBadge(title: t("On this Mac", "Auf diesem Mac"), tint: .green)
        case .downloading(let progress): StatusBadge(title: progress.formatted(.percent.precision(.fractionLength(0))), tint: .blue)
        case .waiting: StatusBadge(title: t("Waiting", "Wartet"), tint: .secondary)
        case .missing: StatusBadge(title: t("Not downloaded", "Nicht geladen"), tint: .orange)
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
            Text("Parakeet CC BY 4.0 · Whisper MIT · Qwen Apache 2.0")
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
