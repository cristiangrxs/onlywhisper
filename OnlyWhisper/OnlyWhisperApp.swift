import SwiftUI

@main
struct OnlyWhisperApp: App {
    @State private var model = AppModel.shared
    private let updater = Updater.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)

        Window(t("Files", "Dateien"), id: "files") {
            FilesView().environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 620, height: 480)

        Window(t("History", "Verlauf"), id: "history") {
            HistoryView().environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 820, height: 520)

        Window(t("Rewrite", "Umschreiben"), id: "rewrite") {
            RewriteView().environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.center)

        Window(t("Meeting", "Meeting"), id: "meeting") {
            MeetingView().environment(model)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 400, height: 560)
    }
}
