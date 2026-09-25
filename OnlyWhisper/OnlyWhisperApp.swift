import SwiftUI

@main
struct OnlyWhisperApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink()
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }

        Window(t("Setup", "Einrichtung"), id: "setup") {
            OnboardingView().environment(model)
        }
        .defaultLaunchBehavior(.suppressed)
        Window(t("Meeting", "Meeting"), id: "meeting") {
            MeetingView().environment(model)
        }
        Window(t("Files", "Dateien"), id: "files") {
            FilesView().environment(model)
        }
        Window(t("History", "Verlauf"), id: "history") {
            HistoryView().environment(model)
        }
        Window(t("Rewrite", "Umschreiben"), id: "rewrite") {
            RewriteView().environment(model)
        }
    }
}
