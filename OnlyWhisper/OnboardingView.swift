import ObjectiveC
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var inputGranted = false
    @State private var appeared = false
    @State private var closing = false

    var body: some View {
        VStack(spacing: DS.spacingXL) {
            StepDots(current: model.setupStep, total: 3)
                .allowsHitTesting(false)
            ZStack(alignment: .top) {
                stepBody
                    .id(model.setupStep)
                    .transition(stepTransition)
            }
            setupButton
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(width: 460)
        .animation(stepAnimation, value: model.setupStep)
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(DS.spacingM)
        }
        .glassPanel(cornerRadius: DS.panelRadius)
        .overlay {
            RoundedRectangle(cornerRadius: DS.panelRadius, style: .continuous)
                .strokeBorder(DS.hairline)
        }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
        .padding(40)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .background(SetupWindowChrome())
        .containerBackground(.clear, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            withAnimation(openAnimation) { appeared = true }
        }
        .task(id: model.setupStep) {
            if model.setupStep == 2 {
                await model.downloads.loadExactSizes()
            }
            while !Task.isCancelled {
                microphoneGranted = model.microphoneGranted
                accessibilityGranted = model.accessibilityGranted
                inputGranted = model.inputGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var stepBody: some View {
        VStack(spacing: DS.spacingXL) {
            if model.setupStep != 1 {
                hero
            }
            VStack(spacing: DS.spacingS) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)

            if model.setupStep == 1 {
                VStack(spacing: DS.spacingS) {
                    PermissionRow(
                        symbol: "mic.fill",
                        tint: .red,
                        title: t("Microphone", "Mikrofon"),
                        detail: t("Dictation and meetings. Audio is not uploaded.", "Diktat und Meetings. Audio wird nicht hochgeladen."),
                        granted: microphoneGranted
                    ) {
                        Task { await model.openMicrophoneSettings() }
                    }
                    PermissionRow(
                        symbol: "accessibility",
                        tint: .blue,
                        title: t("Accessibility", "Bedienungshilfen"),
                        detail: t("Inserts text into the app you are using.", "Setzt Text in die App, die du gerade nutzt."),
                        granted: accessibilityGranted
                    ) {
                        model.openAccessibilitySettings()
                    }
                    PermissionRow(
                        symbol: "keyboard.fill",
                        tint: .orange,
                        title: t("Input Monitoring", "Eingabeüberwachung"),
                        detail: t("Lets the Option key start dictation from any app.", "Lässt die Option-Taste das Diktat aus jeder App starten."),
                        granted: inputGranted
                    ) {
                        model.openInputMonitoringSettings()
                    }
                }
            }

            if model.setupStep == 2 {
                VStack(spacing: DS.spacingS) {
                    SpeechEnginePicker(selection: model.setupSpeechChoice) { engine in
                        model.chooseSpeechEngine(engine)
                    }
                    if let choice = model.setupSpeechChoice {
                        ForEach(setupModels(for: choice)) { info in
                            let state = model.downloads.state(of: info)
                            ModelCard(
                                info: info,
                                state: state,
                                errorMessage: model.downloads.errorMessage(for: info.id),
                                progressDetail: model.downloads.progressDetail(for: info.id),
                                sizeText: model.downloads.sizeText(for: info.id),
                                canCancel: isDownloading(state),
                                onCancel: {
                                    if model.settings.pendingSpeechModel != nil, model.downloads.isTransferring(info.id) {
                                        model.cancelPendingSpeechDownload()
                                    } else {
                                        model.downloads.cancel()
                                    }
                                }
                            )
                        }
                    }
                    if model.setupSpeechChoice != nil, model.downloads.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: model.downloads.fraction)
                            Text(model.downloads.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, DS.spacingXS)
                    }
                }
                .speechSwitchDialog(for: .setup)
            }
        }
    }

    private var hero: some View {
        ZStack {
            if model.setupStep == 0 {
                Circle()
                    .fill(BrandPalette.gradient)
                    .frame(width: 108, height: 108)
                    .blur(radius: 26)
                    .opacity(0.55)
                BrandIcon(size: 72)
            } else {
                IconTile(symbol: symbol, tint: tint, size: 64)
            }
        }
        .frame(height: 108)
        .allowsHitTesting(false)
    }

    private var setupButton: some View {
        Button {
            if model.setupStep < 2 {
                Task { await model.continueSetup() }
            } else {
                finishSetup()
            }
        } label: {
            Text(buttonTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrandPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(BrandPalette.gradient, in: RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .opacity(model.setupStep == 2 && model.setupSpeechChoice == nil ? 0.45 : 1)
        .disabled(closing || (model.setupStep == 2 && model.setupSpeechChoice == nil))
    }

    private var closeButton: some View {
        Button {
            dismissWindow(id: "setup")
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("Close", "Schließen"))
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 18)),
            removal: .opacity.combined(with: .offset(x: -18))
        )
    }

    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.18)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.28)
    }

    private var cardScale: CGFloat {
        if reduceMotion { return 1 }
        return appeared && !closing ? 1 : 0.96
    }

    private var cardOpacity: Double {
        appeared && !closing ? 1 : 0
    }

    private func finishSetup() {
        guard !closing else { return }
        model.finishSetup()
        withAnimation(closeAnimation) { closing = true }
        Task {
            try? await Task.sleep(for: reduceMotion ? .milliseconds(160) : .milliseconds(280))
            dismissWindow(id: "setup")
        }
    }

    private var stepAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy
    }

    private func setupModels(for engine: SpeechEngine) -> [ModelInfo] {
        let ids: [ModelID] = [engine.modelID, .qwen]
        return ids.compactMap { ModelInfo.info($0) }
    }

    private func isDownloading(_ state: ModelState) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    private var symbol: String {
        model.setupStep == 0 ? "lock.shield.fill" : "arrow.down.circle.fill"
    }

    private var tint: Color {
        model.setupStep == 0 ? .indigo : .green
    }

    private var title: String {
        switch model.setupStep {
        case 0: t("OnlyWhisper stays on this Mac", "OnlyWhisper bleibt auf diesem Mac")
        case 1: t("Allow OnlyWhisper", "OnlyWhisper erlauben")
        default: t("Choose speech recognition", "Spracherkennung wählen")
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
            t(
                "Each permission stays on this Mac. Continue when you are ready.",
                "Jede Berechtigung bleibt auf diesem Mac. Weiter, wenn du so weit bist."
            )
        default:
            t(
                "Pick one model. Qwen3 4B for rewriting downloads with it. You can switch later in Settings.",
                "Wähle ein Modell. Qwen3 4B zum Umschreiben wird mitgeladen. Wechseln kannst du später in den Einstellungen."
            )
        }
    }

    private var buttonTitle: String {
        switch model.setupStep {
        case 0: t("Get Started", "Los geht’s")
        case 1: t("Continue", "Weiter")
        default: t("Finish Setup", "Einrichtung abschließen")
        }
    }
}

private struct PermissionRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var granted: Bool
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            HStack(alignment: .top, spacing: DS.spacingM) {
                IconTile(symbol: symbol, tint: tint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .allowsHitTesting(false)
                Spacer(minLength: DS.spacingS)
                StatusBadge(
                    title: granted ? t("Allowed", "Erlaubt") : t("Not allowed yet", "Noch nicht erlaubt"),
                    tint: granted ? .green : .orange
                )
                .allowsHitTesting(false)
            }
            Button(action: action) {
                Text(granted ? t("System Settings", "Systemeinstellungen") : t("Allow", "Erlauben"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.rowRadius, style: .continuous))
        }
        .card(padding: DS.spacingM)
    }
}

private struct StepDots: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AnyShapeStyle(BrandPalette.gradient) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Step \(current + 1) of \(total)", "Schritt \(current + 1) von \(total)"))
    }
}

/// Drops the system title-bar buttons and the rectangular window fill so the glass card is the window.
private struct SetupWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowView {
        WindowView()
    }

    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.configure()
    }

    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        override func layout() {
            super.layout()
            configure()
        }

        func configure() {
            guard let window else { return }
            if window.isOpaque { window.isOpaque = false }
            if window.backgroundColor != .clear { window.backgroundColor = .clear }
            if window.hasShadow { window.hasShadow = false }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
            TitlebarPassthrough.install(on: window)
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                let button = window.standardWindowButton(kind)
                if button?.isHidden == false { button?.isHidden = true }
            }
        }
    }
}

/// The system title bar sits over the top of the card and swallows clicks without moving the window.
/// This instance ignores those hits so the drag gesture underneath receives the whole window.
private enum TitlebarPassthrough {
    private static let className = "OWSetupTitlebarPassthrough"

    static func install(on window: NSWindow) {
        guard let titlebar = container(in: window) else { return }
        if String(describing: type(of: titlebar)).contains(className) { return }
        object_setClass(titlebar, subclass(of: titlebar))
    }

    private static func container(in window: NSWindow) -> NSView? {
        if let button = window.standardWindowButton(.closeButton) {
            var view: NSView? = button
            while let current = view {
                if String(describing: type(of: current)).contains("TitlebarContainer") {
                    return current
                }
                view = current.superview
            }
        }
        return window.contentView?.superview?.subviews.first {
            String(describing: type(of: $0)).contains("Titlebar")
        }
    }

    private static func subclass(of view: NSView) -> AnyClass {
        if let existing = objc_getClass(className) as? AnyClass {
            return existing
        }
        guard let base = object_getClass(view),
              let pair = objc_allocateClassPair(base, className, 0)
        else {
            return type(of: view)
        }
        let selector = #selector(NSView.hitTest(_:))
        let method = class_getInstanceMethod(TitlebarHitProxy.self, selector)!
        class_addMethod(pair, selector, method_getImplementation(method), method_getTypeEncoding(method))
        objc_registerClassPair(pair)
        return pair
    }
}

private final class TitlebarHitProxy: NSView {
    @objc override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
