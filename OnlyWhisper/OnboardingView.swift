import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var granted = false

    var body: some View {
        VStack(spacing: DS.spacingXL) {
            StepDots(current: model.setupStep, total: 5)
            Group {
                if model.setupStep == 0 {
                    BrandIcon(size: 72)
                } else {
                    IconTile(symbol: symbol, tint: tint, size: 64)
                }
            }
                .id(model.setupStep)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            VStack(spacing: DS.spacingS) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            if (1...3).contains(model.setupStep) {
                StatusBadge(
                    title: granted ? t("Allowed", "Erlaubt") : t("Not allowed yet", "Noch nicht erlaubt"),
                    tint: granted ? .green : .orange
                )
            }

            if model.setupStep == 4 {
                VStack(spacing: DS.spacingS) {
                    ForEach(ModelInfo.catalog) { info in
                        let state = model.downloads.state(of: info)
                        ModelCard(
                            info: info,
                            state: state,
                            errorMessage: model.downloads.errorMessage(for: info.id),
                            progressDetail: model.downloads.progressDetail(for: info.id),
                            sizeText: model.downloads.sizeText(for: info.id),
                            canCancel: isDownloading(state),
                            onCancel: { model.downloads.cancel() }
                        )
                    }
                    if model.downloads.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: model.downloads.fraction)
                            Text(model.downloads.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, DS.spacingXS)
                    }
                }
            }

            Button {
                Task { await model.continueSetup() }
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.downloads.isRunning)
        }
        .padding(.horizontal, 36)
        .padding(.top, DS.spacingM)
        .padding(.bottom, 32)
        .frame(width: 460)
        .animation(.snappy, value: model.setupStep)
        .glassWindow()
        .task(id: model.setupStep) {
            if model.setupStep == 4 {
                await model.downloads.loadExactSizes()
            }
            while !Task.isCancelled {
                granted = permissionGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func isDownloading(_ state: ModelState) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    private var permissionGranted: Bool {
        switch model.setupStep {
        case 1: model.microphoneGranted
        case 2: model.accessibilityGranted
        case 3: model.inputGranted
        default: false
        }
    }

    private var symbol: String {
        switch model.setupStep {
        case 0: "lock.shield.fill"
        case 1: "mic.fill"
        case 2: "accessibility"
        case 3: "keyboard.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch model.setupStep {
        case 0: .indigo
        case 1: .red
        case 2: .blue
        case 3: .orange
        default: .green
        }
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
            WhisperModelChoice.usesTurbo
                ? t(
                    "About 4 GB: Whisper Large v3 Turbo and Qwen3 4B. After this, the app stays offline.",
                    "Etwa 4 GB: Whisper Large v3 Turbo und Qwen3 4B. Danach bleibt die App offline."
                )
                : t(
                    "About 3 GB: Whisper Large v3 and Qwen3 4B. After this, the app stays offline.",
                    "Etwa 3 GB: Whisper Large v3 und Qwen3 4B. Danach bleibt die App offline."
                )
        }
    }

    private var buttonTitle: String {
        switch model.setupStep {
        case 0: t("Get Started", "Los geht’s")
        case 1...3 where granted: t("Continue", "Weiter")
        case 1...3: t("Allow", "Erlauben")
        default: model.downloads.lastError == nil ? t("Download", "Laden") : t("Try Again", "Erneut versuchen")
        }
    }
}

private struct StepDots: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Step \(current + 1) of \(total)", "Schritt \(current + 1) von \(total)"))
    }
}
