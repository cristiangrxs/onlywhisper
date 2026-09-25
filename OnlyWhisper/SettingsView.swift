import AppKit
import KeyboardShortcuts
import SwiftUI

enum AppWindows {
    static let settings = NSUserInterfaceItemIdentifier("onlywhisper.settings")
}

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(t("Dictate", "Diktieren")) { model.startHandsFree() }
            .disabled(model.phase != .idle)
        Button(t("Meeting", "Meeting")) { model.open("meeting") }
        Button(t("Files", "Dateien")) { model.open("files") }
        Button(t("History", "Verlauf")) { model.open("history") }
        Divider()
        Button(t("Check for Updates…", "Nach Updates suchen…")) { Updater.shared.checkForUpdates() }
            .disabled(!Updater.shared.canCheckForUpdates)
        Button(t("Settings", "Einstellungen")) {
            model.presentSettings { openSettings() }
        }
        Divider()
        Button(t("Quit", "Beenden")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear {
                model.bind { openWindow(id: $0) }
                model.bootstrap()
            }
    }
}

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: model.menuSymbol)
            .accessibilityLabel("OnlyWhisper")
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var section = SettingsSection.general
    @State private var heard = ""
    @State private var written = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SettingsSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Form {
                switch section {
                case .general: general
                case .dictation: dictation
                case .language: language
                case .dictionary: dictionary
                case .shortcuts: shortcuts
                case .models: models
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(SettingsWindowFinder())
    }

    private var general: some View {
        Section(t("General", "Allgemein")) {
            Toggle(t("Launch at login", "Beim Anmelden starten"), isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Toggle(t("Check for updates automatically", "Automatisch nach Updates suchen"), isOn: Binding(
                get: { Updater.shared.automaticallyChecksForUpdates },
                set: { Updater.shared.automaticallyChecksForUpdates = $0 }
            ))
            LabeledContent(t("Version", "Version")) {
                HStack {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .foregroundStyle(.secondary)
                    Button(t("Check for Updates…", "Nach Updates suchen…")) { Updater.shared.checkForUpdates() }
                        .disabled(!Updater.shared.canCheckForUpdates)
                }
            }
            LabeledContent(t("About", "Über")) {
                Text("Parakeet CC BY 4.0 · Whisper MIT · Qwen Apache 2.0")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dictation: some View {
        Section(t("Dictation", "Diktat")) {
            Picker(t("Hold key", "Halte-Taste"), selection: Binding(
                get: { model.settings.dictationKey },
                set: { model.updateDictationKey($0) }
            )) {
                ForEach(DictationKey.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }
            Toggle(t("Polish text", "Text glätten"), isOn: Binding(
                get: { model.settings.polishEnabled },
                set: { model.settings.polishEnabled = $0 }
            ))
            Toggle(t("System audio in meetings", "Systemton in Meetings"), isOn: Binding(
                get: { model.settings.systemAudioInMeetings },
                set: { model.settings.systemAudioInMeetings = $0 }
            ))
        }
    }

    private var language: some View {
        Section(t("Language", "Sprache")) {
            Picker(t("Speech", "Sprache"), selection: Binding(
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
        }
    }

    private var dictionary: some View {
        Section(t("Dictionary", "Wörterbuch")) {
            TextField(t("Heard", "Gehört"), text: $heard)
            TextField(t("Written", "Geschrieben"), text: $written)
            Button(t("Add word", "Wort hinzufügen")) {
                model.dictionary.add(heard: heard, written: written)
                heard = ""
                written = ""
            }
            ForEach(model.dictionary.dictionary.entries) { entry in
                LabeledContent(entry.heard) {
                    HStack {
                        Text(entry.written)
                        Button(t("Remove", "Entfernen")) { model.dictionary.remove(entry) }
                    }
                }
            }
        }
    }

    private var shortcuts: some View {
        Section(t("Shortcuts", "Kurzbefehle")) {
            LabeledContent(t("Rewrite selection", "Markierung umschreiben")) {
                KeyboardShortcuts.Recorder(for: .rewriteSelection)
            }
            Text(t("Hold Option to dictate. Tap it for hands-free. Escape cancels.", "Option halten zum Diktieren. Tippen für Freisprechen. Escape bricht ab."))
                .foregroundStyle(.secondary)
        }
    }

    private var models: some View {
        Section(t("Models", "Modelle")) {
            LabeledContent(t("Status", "Status")) {
                Text(model.downloads.isReady ? t("On this Mac", "Auf diesem Mac") : t("Not downloaded", "Nicht geladen"))
            }
            if let error = model.downloads.lastError {
                Text(error).foregroundStyle(.red)
            }
            Button(t("Download again", "Erneut laden")) {
                Task { await model.downloads.downloadRequiredModels() }
            }
            .disabled(model.downloads.isRunning)
        }
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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case dictation
    case language
    case dictionary
    case shortcuts
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: t("General", "Allgemein")
        case .dictation: t("Dictation", "Diktat")
        case .language: t("Language", "Sprache")
        case .dictionary: t("Dictionary", "Wörterbuch")
        case .shortcuts: t("Shortcuts", "Kurzbefehle")
        case .models: t("Models", "Modelle")
        }
    }
}
