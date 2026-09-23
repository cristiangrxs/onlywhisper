import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.setupStep == 4 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.downloads.status)
                        .font(.callout)
                    ProgressView(value: model.downloads.fraction)
                }
                if let error = model.downloads.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Button(buttonTitle) {
                Task { await model.continueSetup() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.downloads.isRunning)
        }
        .padding(28)
        .frame(width: 420)
    }

    private var title: String {
        switch model.setupStep {
        case 0: t("OnlyWhisper stays on this Mac", "OnlyWhisper bleibt auf diesem Mac")
        case 1: t("Microphone", "Mikrofon")
        case 2: t("Accessibility", "Bedienungshilfen")
        case 3: t("Input Monitoring", "Eingabeüberwachung")
        default: t("Download models", "Modelle laden")
        }
    }

    private var detail: String {
        switch model.setupStep {
        case 0:
            t(
                "Dictate, rewrite, and transcribe without an account. Internet is only needed once, to download the models.",
                "Diktieren, umschreiben und transkribieren, ohne Konto. Internet brauchst du nur einmal, zum Laden der Modelle."
            )
        case 1:
            t("The microphone is used for dictation and meetings. Audio is not uploaded.", "Das Mikrofon ist für Diktat und Meetings. Audio wird nicht hochgeladen.")
        case 2:
            t("Accessibility lets OnlyWhisper insert text into the app you are using.", "Bedienungshilfen lassen OnlyWhisper Text in die App setzen, die du gerade nutzt.")
        case 3:
            t("Input Monitoring lets the Option key start dictation from any app.", "Eingabeüberwachung lässt die Option-Taste das Diktat aus jeder App starten.")
        default:
            t(
                "About 4–5 GB: Parakeet, Whisper Large v3 Turbo, and Qwen3 4B. After this, the app stays offline.",
                "Etwa 4–5 GB: Parakeet, Whisper Large v3 Turbo und Qwen3 4B. Danach bleibt die App offline."
            )
        }
    }

    private var buttonTitle: String {
        model.setupStep == 4 ? t("Download", "Laden") : t("Continue", "Weiter")
    }
}
