import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    nonisolated(unsafe) static let rewriteSelection = Self(
        "rewriteSelection",
        default: .init(.e, modifiers: [.command, .shift])
    )
    /// Must not use Option (both dictation keys are Option keys). Cmd+Shift+Space belongs to Siri on macOS 27.
    nonisolated(unsafe) static let commandPalette = Self(
        "commandPalette",
        default: .init(.space, modifiers: [.control, .shift])
    )
}

enum CapturePhase: Equatable {
    case idle
    case recording
    case handsFree
    case working(String)
}

/// What the capsule does with a finished dictation.
enum DictationDelivery: Equatable {
    case nothingHeard
    case inserted
    case holdForCopy

    /// Blank text is never an insertion. A real string stays up for copying when the field did not take it.
    static func decide(text: String, inserted: Bool) -> DictationDelivery {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .nothingHeard }
        return inserted ? .inserted : .holdForCopy
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = SettingsStore()
    let dictionary = DictionaryStore()
    let history = HistoryStore()
    let downloads = ModelDownloadManager()
    let files = FileTranscriptionQueue()

    var phase: CapturePhase = .idle
    var level: Float = 0
    var setupStep = 0
    var needsSetup = true
    var meetingChunks: [TranscriptChunk] = []
    var meetingNotes: MeetingNotes?
    var meetingActive = false
    var meetingStatus = ""
    var statusMessage = ""
    private(set) var hotkeyReady = false
    /// Bumps while a permission is still missing, so Settings updates after the user grants it.
    private(set) var permissionRevision = 0
    private(set) var shortcutConflicts: Set<KeyboardShortcuts.Name> = []
    /// Bumps whenever shortcuts are checked, so Settings refreshes even if the conflict set stays empty.
    private(set) var shortcutRevision = 0
    var overlayHint: String?
    /// Live words for the capsule, set only while the focused field cannot be written live.
    var livePreview = ""
    /// Briefly true after a dictation lands, so the capsule can confirm it before hiding.
    var dictationInserted = false
    /// Polished dictation that never reached a text field. Stays until copy, Escape, or a click outside.
    var pendingCopyText: String?
    /// True while the copy button shows a checkmark, just before the capsule closes.
    var pendingCopyConfirmed = false
    var rewriteText = ""
    var rewriteInstruction = ""
    var showRewrite = false
    var isSmoothing = false
    /// True while Whisper is opening, so the capsule can say so instead of showing an empty transcript.
    var isPreparingSpeech = false
    /// Set before opening Settings so the window lands on that tab. Cleared once applied.
    var settingsTabRequest: String?

    private let recorder = AudioRecorder()
    private let systemAudio = SystemAudioCapture()
    private let hotkeys = HotkeyMonitor()
    private let speech = SpeechRouter()
    private let qwen = QwenPolisher()
    private let diarizer = MeetingDiarizer()
    private var opener: ((String) -> Void)?
    private var settingsOpener: (() -> Void)?
    private var didBootstrap = false
    private(set) var meetingStartedAt: Date?
    private var transcribedUntil: Int = 0
    private var meetingTimer: Task<Void, Never>?
    private var dictationTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var speechTimedOut = false
    private var insertedTask: Task<Void, Never>?
    private var pendingCopyTask: Task<Void, Never>?
    private var dictationEpoch = 0
    private var dictationCursor = 0
    private var dictationSession = DictationSession()
    private var watchesWindowClose = false
    private var watchesActivation = false
    private var watchesShortcuts = false
    private var shortcutSignature = ""
    private var permissionWatch: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?

    private init() {
        recorder.setLevelHandler { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        systemAudio.onSamples = { [weak self] samples in
            self?.recorder.appendSystemSamples(samples)
        }
        hotkeys.onPress = { [weak self] in self?.dictationPressed() }
        hotkeys.onRelease = { [weak self] duration in self?.dictationReleased(after: duration) }
        hotkeys.onEscape = { [weak self] in
            guard let self else { return }
            switch self.phase {
            case .recording, .handsFree:
                self.cancelCapture()
            case .working:
                self.requestFinishCancellation()
            case .idle:
                self.dismissPendingCopy()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .rewriteSelection) { [weak self] in
            Task { @MainActor in self?.beginRewrite() }
        }
        KeyboardShortcuts.onKeyDown(for: .commandPalette) {
            Task { @MainActor in CommandPaletteController.shared.toggle() }
        }
        refreshShortcutConflicts()
        watchShortcutChanges()
    }

    func bind(openWindow: @escaping (String) -> Void, openSettings: @escaping () -> Void) {
        opener = openWindow
        settingsOpener = openSettings
    }

    func showSettings() {
        presentSettings { settingsOpener?() }
    }

    func showModelSettings() {
        settingsTabRequest = "models"
        showSettings()
    }

    var canChangeModels: Bool {
        phase == .idle && !meetingActive && !downloads.isRunning
    }

    /// Gives focus back to the app the user was in, so dictation, rewrite, and paste land there.
    func returnFocus(then work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            if NSApp.isActive {
                NSApp.hide(nil)
            }
            try? await Task.sleep(for: .milliseconds(250))
            work()
        }
    }

    func paste(_ text: String) {
        returnFocus { TextInserter.insert(text) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copies the polished text that could not be inserted, then lets the checkmark register before closing.
    func copyPendingText() {
        guard let text = pendingCopyText, !pendingCopyConfirmed else { return }
        copy(text)
        pendingCopyConfirmed = true
        pendingCopyTask?.cancel()
        pendingCopyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            self.dismissPendingCopy()
        }
    }

    /// Drops the held text. A click outside, Escape, or a finished copy all come through here.
    func dismissPendingCopy() {
        let showing = pendingCopyText != nil
        clearPendingCopy()
        guard showing, phase == .idle, overlayHint == nil, !dictationInserted else { return }
        OverlayPanel.shared.hide()
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        downloads.refreshReadyState()
        ensureHotkeys()
        watchPermissions()
        watchAppActivation()
        if downloads.isReady {
            settings.setupCompleted = true
            needsSetup = false
        } else if settings.setupCompleted {
            needsSetup = false
        } else {
            needsSetup = true
            opener?("setup")
            NSApp.activate()
        }
        applyLaunchAtLogin()
        watchWindowClose()
    }

    /// Settings is a normal window. A menu-bar app stays behind other apps until it becomes a regular, active app.
    func presentSettings(open: () -> Void) {
        becomeRegularApp()
        open()
        orderSettingsFront()
    }

    func orderSettingsFront() {
        orderFront { $0.identifier == AppWindows.settings }
    }

    /// Opens a document window in front, then leaves it at the normal level so other apps can cover it.
    private func orderFront(windowMatching matches: @escaping @MainActor (NSWindow) -> Bool) {
        becomeRegularApp()
        Task { @MainActor in
            for _ in 0..<12 {
                guard let window = NSApp.windows.first(where: matches) else {
                    try? await Task.sleep(for: .milliseconds(40))
                    continue
                }
                bringToFront(window)
                // Activation from a menu-bar extra can land a tick later than the window.
                await Task.yield()
                bringToFront(window)
                return
            }
        }
    }

    private func becomeRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate()
    }

    private func bringToFront(_ window: NSWindow) {
        window.level = .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func watchWindowClose() {
        guard !watchesWindowClose else { return }
        watchesWindowClose = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            let closingNumber = (notification.object as? NSWindow)?.windowNumber
            Task { @MainActor in
                let stillOpen = NSApp.windows.contains { window in
                    window.windowNumber != closingNumber && window.isVisible && window.canBecomeMain && !(window is NSPanel)
                }
                if !stillOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func enqueueFiles(_ urls: [URL]) {
        guard requireUsableModel(speechModel) else { return }
        files.enqueue(urls, speech: speech, language: settings.language)
    }

    func downloadModel(_ id: ModelID) async {
        guard canChangeModels else { return }
        await releaseSpeechModels()
        await downloads.download(id)
        await unloadSpeechModels()
    }

    func downloadMissingModels() async {
        guard canChangeModels else { return }
        await releaseSpeechModels()
        await downloads.downloadMissing()
        await unloadSpeechModels()
    }

    func updateModel(_ id: ModelID) async {
        guard canChangeModels else { return }
        await releaseSpeechModels()
        await downloads.update(id)
        await unloadSpeechModels()
    }

    func updateOutdatedModels() async {
        guard canChangeModels else { return }
        await releaseSpeechModels()
        await downloads.updateOutdated()
        await unloadSpeechModels()
    }

    func removeModel(_ id: ModelID) async {
        guard canChangeModels else { return }
        await releaseSpeechModels()
        downloads.remove(id)
    }

    private var speechModel: ModelID { .whisper }

    /// Opens setup until the first install is finished. After that, a removed model is recovered from Settings.
    @discardableResult
    private func requireUsableModel(_ id: ModelID) -> Bool {
        guard downloads.isUsable(id) else {
            if downloads.isRunning {
                showOverlayHint(t("The model is still downloading.", "Das Modell wird noch geladen."))
                return false
            }
            if settings.setupCompleted {
                let name = ModelInfo.info(id)?.name ?? ""
                showOverlayHint(t("\(name) is not on this Mac.", "\(name) ist nicht auf diesem Mac."))
                showModelSettings()
            } else {
                needsSetup = true
                setupStep = 4
                opener?("setup")
                NSApp.activate()
            }
            return false
        }
        return true
    }

    private func unloadSpeechModels() async {
        await speech.unload()
        await qwen.unload()
    }

    /// Drops a prewarm and any model loaded before the files on disk change.
    private func releaseSpeechModels() async {
        cancelPrewarm()
        await unloadSpeechModels()
    }

    private func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
    }

    private func prewarmPolisherIfNeeded() {
        cancelPrewarm()
        guard settings.polishEnabled, downloads.isUsable(.qwen) else { return }
        prewarmTask = Task { await qwen.prewarm() }
    }

    func startHandsFree() {
        beginRecording(handsFree: true)
    }

    func finishHandsFree() {
        beginFinish()
    }

    func open(_ id: String) {
        opener?(id)
        orderFront { $0.identifier?.rawValue.hasPrefix(id) == true && $0.isVisible }
    }

    var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var inputGranted: Bool { CGPreflightListenEventAccess() }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        ensureHotkeys()
    }

    func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        ensureHotkeys()
    }

    /// Arms the Option-key listener once Input Monitoring is granted, and again after the
    /// system disables the tap. Safe to call whenever the menu bar or Settings opens.
    func ensureHotkeys() {
        hotkeys.keyCode = settings.dictationKey.keyCode
        hotkeyReady = hotkeys.start()
    }

    func refreshShortcutConflicts() {
        shortcutConflicts = ShortcutProbe.conflicts(among: [.commandPalette, .rewriteSelection])
        shortcutRevision += 1
    }

    /// Arms the Option-key listener as soon as Input Monitoring is granted, without requiring a click.
    private func watchPermissions() {
        guard permissionWatch == nil else { return }
        permissionWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let input = self.inputGranted
                let access = self.accessibilityGranted
                if input {
                    self.ensureHotkeys()
                }
                self.permissionRevision += 1
                if input && access {
                    self.permissionWatch = nil
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func watchShortcutChanges() {
        guard !watchesShortcuts else { return }
        watchesShortcuts = true
        shortcutSignature = Self.shortcutSignature()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let signature = Self.shortcutSignature()
                guard signature != AppModel.shared.shortcutSignature else { return }
                AppModel.shared.shortcutSignature = signature
                AppModel.shared.refreshShortcutConflicts()
            }
        }
    }

    private static func shortcutSignature() -> String {
        func part(_ name: KeyboardShortcuts.Name) -> String {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return "-" }
            return "\(shortcut.carbonKeyCode):\(shortcut.carbonModifiers)"
        }
        return part(.commandPalette) + "|" + part(.rewriteSelection)
    }

    func showOverlayHint(_ text: String, milliseconds: Int = 1500) {
        clearInsertedConfirmation()
        clearPendingCopy()
        hintTask?.cancel()
        overlayHint = text
        OverlayPanel.shared.show()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard let self, self.phase == .idle else { return }
            self.overlayHint = nil
            if self.pendingCopyText == nil, !self.dictationInserted {
                OverlayPanel.shared.hide()
            }
        }
    }

    func continueSetup() async {
        switch setupStep {
        case 0:
            setupStep = 1
        case 1:
            await requestMicrophone()
            setupStep = 2
        case 2:
            requestAccessibility()
            setupStep = 3
        case 3:
            requestInputMonitoring()
            setupStep = 4
        default:
            cancelPrewarm()
            await unloadSpeechModels()
            await downloads.downloadRequiredModels()
            await unloadSpeechModels()
            if downloads.isReady {
                settings.setupCompleted = true
                needsSetup = false
                NSApp.keyWindow?.close()
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        applyLaunchAtLogin()
    }

    func updateDictationKey(_ key: DictationKey) {
        settings.dictationKey = key
        hotkeys.keyCode = key.keyCode
        ensureHotkeys()
    }

    private func watchAppActivation() {
        guard !watchesActivation else { return }
        watchesActivation = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppModel.shared.ensureHotkeys()
            }
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func dictationPressed() {
        switch phase {
        case .handsFree:
            beginFinish()
        case .idle:
            beginRecording(handsFree: false)
        default:
            break
        }
    }

    private func dictationReleased(after duration: TimeInterval) {
        guard phase == .recording else { return }
        if duration < 0.35 {
            phase = .handsFree
            return
        }
        beginFinish()
    }

    private func beginFinish() {
        finishTask = Task { await self.finishDictation() }
    }

    private func beginRecording(handsFree: Bool) {
        guard microphoneGranted else {
            needsSetup = true
            setupStep = 1
            opener?("setup")
            NSApp.activate()
            return
        }
        guard requireUsableModel(speechModel) else { return }
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationSession.reset()
        dictationCursor = 0
        isSmoothing = false
        isPreparingSpeech = false
        speechTimedOut = false
        livePreview = ""
        clearInsertedConfirmation()
        clearPendingCopy()
        hintTask?.cancel()
        overlayHint = nil
        TextInserter.beginInsertion()
        do {
            try recorder.start()
            phase = handsFree ? .handsFree : .recording
            isPreparingSpeech = true
            OverlayPanel.shared.show()
            let epoch = dictationEpoch
            let router = speech
            dictationTask = Task {
                await router.resetUtterance()
                do {
                    try await AsyncDeadline.value(ModelDeadline.speechLoad) {
                        try await router.prepare()
                    }
                } catch {
                    guard !Task.isCancelled, epoch == self.dictationEpoch else { return }
                    self.failSpeechPreparation(timedOut: error is AsyncDeadline.TimedOut)
                    return
                }
                guard epoch == self.dictationEpoch, !Task.isCancelled else { return }
                self.isPreparingSpeech = false
                await self.runDictationLoop(epoch: epoch)
            }
            prewarmPolisherIfNeeded()
        } catch {
            isPreparingSpeech = false
            statusMessage = error.localizedDescription
        }
    }

    func cancelCapture() {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationTask = nil
        cancelPrewarm()
        _ = recorder.stop()
        TextInserter.revertInsertion()
        dictationSession.reset()
        livePreview = ""
        isSmoothing = false
        isPreparingSpeech = false
        phase = .idle
        level = 0
        clearPendingCopy()
        OverlayPanel.shared.hide()
        let keepSpeech = meetingActive
        Task {
            if !keepSpeech {
                await speech.unload()
            }
            await qwen.unload()
        }
    }

    private func failSpeechPreparation(timedOut: Bool) {
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationTask = nil
        cancelPrewarm()
        _ = recorder.stop()
        TextInserter.revertInsertion()
        dictationSession.reset()
        livePreview = ""
        isPreparingSpeech = false
        isSmoothing = false
        phase = .idle
        level = 0
        clearPendingCopy()
        Task {
            await speech.unload()
            await qwen.unload()
        }
        let message = timedOut
            ? t("Speech recognition is taking too long.", "Spracherkennung dauert zu lange.")
            : t("Speech recognition could not be loaded.", "Spracherkennung konnte nicht geladen werden.")
        showOverlayHint(message, milliseconds: 3200)
    }

    /// Escape during recognition or polishing. The finish task inserts whatever was already heard.
    private func requestFinishCancellation() {
        guard case .working = phase else { return }
        dictationEpoch += 1
        finishTask?.cancel()
        cancelPrewarm()
        let keepSpeech = meetingActive
        Task {
            if !keepSpeech {
                await speech.unload()
            }
            await qwen.unload()
        }
    }

    /// The raw words are already in the field. Recognition finishes first, then the writing model replaces the draft.
    private func finishDictation() async {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        let epoch = dictationEpoch
        dictationTask?.cancel()
        dictationTask = nil
        cancelPrewarm()
        isPreparingSpeech = false
        speechTimedOut = false
        phase = .working(t("Transcribing…", "Wird erkannt…"))
        let samples = recorder.stop()
        level = 0
        do {
            try await transcribeOpenAudio(samples, epoch: epoch, final: true)
            try Task.checkCancellation()
            guard epoch == dictationEpoch else { throw CancellationError() }
            dictationSession.settleOpen()
            let raw = dictationSession.text
            var finished = ruled(raw)
            var fellBack = false
            if settings.polishEnabled, downloads.isUsable(.qwen), !finished.isEmpty {
                phase = .working(t("Polishing…", "Poliert…"))
                isSmoothing = true
                let outcome = try await polishDictation(finished)
                isSmoothing = false
                try Task.checkCancellation()
                guard epoch == dictationEpoch else { throw CancellationError() }
                finished = outcome.text
                fellBack = outcome.fellBack
            }
            await qwen.unload()
            if !meetingActive {
                await speech.unload()
            }
            try Task.checkCancellation()
            guard epoch == dictationEpoch else { throw CancellationError() }
            await deliver(raw: raw, finished: finished, fellBack: fellBack)
        } catch is CancellationError {
            await deliverCancelledDictation()
        } catch {
            isSmoothing = false
            statusMessage = error.localizedDescription
            await deliverCancelledDictation()
        }
    }

    private func deliver(raw: String, finished: String, fellBack: Bool) async {
        let text = finished.trimmingCharacters(in: .whitespacesAndNewlines)
        let didInsert: Bool
        if text.isEmpty {
            TextInserter.revertInsertion()
            didInsert = false
        } else {
            didInsert = await TextInserter.replaceInsertion(with: text, allowPasteFallback: true)
            history.add(source: "dictation", raw: raw, polished: text)
        }
        dictationSession.reset()
        livePreview = ""
        isSmoothing = false
        isPreparingSpeech = false
        phase = .idle
        if text.isEmpty {
            if speechTimedOut {
                showOverlayHint(
                    t("Speech recognition is taking too long.", "Spracherkennung dauert zu lange."),
                    milliseconds: 3200
                )
            } else {
                showOverlayHint(t("Nothing heard", "Nichts verstanden"))
            }
            return
        }
        if fellBack, didInsert {
            showOverlayHint(
                t(
                    "Polishing was not possible. The original text was inserted.",
                    "Glätten nicht möglich, Rohtext eingefügt."
                ),
                milliseconds: 3200
            )
            return
        }
        switch DictationDelivery.decide(text: text, inserted: didInsert) {
        case .nothingHeard:
            showOverlayHint(t("Nothing heard", "Nichts verstanden"))
        case .inserted:
            confirmInsertion()
        case .holdForCopy:
            holdForCopy(text)
        }
    }

    /// Escape while recognizing or polishing keeps the words heard so far and leaves the capsule.
    private func deliverCancelledDictation() async {
        let raw = dictationSession.text
        let text = ruled(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        isSmoothing = false
        isPreparingSpeech = false
        if text.isEmpty {
            TextInserter.revertInsertion()
            dictationSession.reset()
            livePreview = ""
            phase = .idle
            level = 0
            OverlayPanel.shared.hide()
        } else {
            let didInsert = await TextInserter.replaceInsertion(with: text, allowPasteFallback: true)
            history.add(source: "dictation", raw: raw, polished: text)
            dictationSession.reset()
            livePreview = ""
            phase = .idle
            level = 0
            switch DictationDelivery.decide(text: text, inserted: didInsert) {
            case .nothingHeard:
                OverlayPanel.shared.hide()
            case .inserted:
                confirmInsertion()
            case .holdForCopy:
                holdForCopy(text)
            }
        }
        let keepSpeech = meetingActive
        Task {
            if !keepSpeech {
                await speech.unload()
            }
            await qwen.unload()
        }
    }

    private func runDictationLoop(epoch: Int) async {
        while epoch == dictationEpoch, !Task.isCancelled {
            let samples = recorder.snapshot()
            if samples.count - dictationCursor < Self.minimumSpeechSamples {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }
            let count = samples.count
            let open = Array(samples[dictationCursor..<count])
            let heardSpeech = SpeechPresence.containsSpeech(open)
            do {
                try await transcribeOpenAudio(samples, epoch: epoch, final: false)
            } catch is CancellationError {
                return
            } catch {
                continue
            }
            guard epoch == dictationEpoch, !Task.isCancelled else { return }
            let added = recorder.snapshot().count - count
            if !heardSpeech || added < 3_200 {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// Transcribes the open segment again and writes the raw words into the field.
    /// A pause, a long segment, or the end of the dictation freezes it so the next pass starts after it.
    private func transcribeOpenAudio(_ samples: [Float], epoch: Int, final: Bool) async throws {
        let end = samples.count
        var start = dictationCursor
        var changed = false
        func publishIfNeeded() async {
            if changed, epoch == dictationEpoch, !final {
                await publishLive()
            }
        }
        do {
            while epoch == dictationEpoch, end - start >= Self.minimumSpeechSamples {
                let cut = final ? end : SpeechPause.settlePoint(in: samples, from: start, to: end)
                let stop = cut ?? end
                let slice = Array(samples[start..<stop])
                let heard: String?
                if SpeechPresence.containsSpeech(slice) {
                    heard = try await transcribe(samples, from: start, to: stop, epoch: epoch, live: !final)
                } else {
                    heard = ""
                }
                guard let heard else {
                    await publishIfNeeded()
                    return
                }
                if dictationSession.updateOpen(heard) {
                    changed = true
                }
                guard cut != nil else {
                    await publishIfNeeded()
                    return
                }
                dictationSession.settleOpen()
                dictationCursor = stop
                start = stop
            }
            await publishIfNeeded()
        } catch {
            await publishIfNeeded()
            throw error
        }
    }

    /// Parakeet rejects anything shorter than 0.3 s.
    private static let minimumSpeechSamples = 4_800

    private func transcribe(
        _ samples: [Float],
        from start: Int,
        to end: Int,
        epoch: Int,
        live: Bool
    ) async throws -> String? {
        let slice = Array(samples[start..<end])
        let choice = settings.language
        let router = speech
        let limit = live ? ModelDeadline.liveTranscription : ModelDeadline.finalTranscription
        do {
            let text = try await AsyncDeadline.value(limit) {
                try await router.transcribe(samples: slice, choice: choice, live: live, dictation: true)
            }
            guard epoch == dictationEpoch else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is CancellationError {
            throw CancellationError()
        } catch is AsyncDeadline.TimedOut {
            guard epoch == dictationEpoch else { return nil }
            if !live { speechTimedOut = true }
            return nil
        } catch {
            guard epoch == dictationEpoch else { return nil }
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func publishLive() async {
        let text = dictationSession.text
        if text.isEmpty {
            TextInserter.undoLiveInsertion()
            livePreview = ""
            return
        }
        let written = await TextInserter.replaceInsertion(with: text)
        livePreview = written ? "" : text
    }

    /// Long dictations go through in pieces so none is cut off. A piece that fails keeps its unpolished text.
    private func polishDictation(_ text: String) async throws -> PolishFallback.Step {
        var result = ""
        var fellBack = false
        let polisher = qwen
        for piece in DictationSession.polishChunks(text, limit: 1_500) {
            try Task.checkCancellation()
            let outcome: Result<String, Error>
            do {
                let polished = try await AsyncDeadline.value(ModelDeadline.polish) {
                    try await polisher.polish(raw: piece, kind: .dictation)
                }
                outcome = .success(polished)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                outcome = .failure(error)
            }
            let step = PolishFallback.resolve(original: piece, result: outcome)
            if step.fellBack { fellBack = true }
            result = DictationSession.joined(result, step.text)
        }
        return PolishFallback.Step(text: result, fellBack: fellBack)
    }

    private func confirmInsertion() {
        clearPendingCopy()
        insertedTask?.cancel()
        dictationInserted = true
        insertedTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            self.dictationInserted = false
            if self.phase == .idle, self.overlayHint == nil, self.pendingCopyText == nil {
                OverlayPanel.shared.hide()
            }
        }
    }

    private func clearInsertedConfirmation() {
        insertedTask?.cancel()
        insertedTask = nil
        dictationInserted = false
    }

    private func holdForCopy(_ text: String) {
        clearInsertedConfirmation()
        hintTask?.cancel()
        hintTask = nil
        overlayHint = nil
        pendingCopyTask?.cancel()
        pendingCopyTask = nil
        pendingCopyConfirmed = false
        pendingCopyText = text
        OverlayPanel.shared.show()
        OverlayPanel.shared.beginCopyTracking()
    }

    private func clearPendingCopy() {
        pendingCopyTask?.cancel()
        pendingCopyTask = nil
        pendingCopyConfirmed = false
        pendingCopyText = nil
        OverlayPanel.shared.endCopyTracking()
    }

    private func ruled(_ text: String) -> String {
        dictionary.dictionary.apply(to: RulePolisher.apply(text))
    }

    func beginRewrite() {
        switch RewriteGate.evaluate(accessibilityGranted: accessibilityGranted, selectedText: TextInserter.selectedText()) {
        case .needsAccessibility:
            openAccessibilitySettings()
        case .needsSelection:
            showOverlayHint(RewriteGate.needsSelectionMessage)
        case .ready(let selected):
            rewriteText = selected
            rewriteInstruction = ""
            showRewrite = true
            open("rewrite")
        }
    }

    func applyRewrite(_ action: RewriteAction) async {
        let instruction = action.instruction(target: settings.translateTarget)
        await rewrite(instruction: instruction)
    }

    func applyCustomRewrite() async {
        let instruction = rewriteInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        await rewrite(instruction: instruction)
    }

    func dictateRewriteInstruction() async {
        guard requireUsableModel(speechModel) else { return }
        do {
            try recorder.start()
            phase = .recording
            try await Task.sleep(for: .seconds(4))
            let samples = recorder.stop()
            phase = .idle
            let spoken = try await speech.transcribe(samples: samples, choice: settings.language, dictation: true)
            await speech.unload()
            rewriteInstruction = spoken
        } catch {
            statusMessage = error.localizedDescription
            phase = .idle
        }
    }

    private func rewrite(instruction: String) async {
        guard requireUsableModel(.qwen) else { return }
        phase = .working(t("Rewriting", "Formuliert"))
        defer { phase = .idle }
        do {
            let polisher = qwen
            let source = rewriteText
            let revised = try await AsyncDeadline.value(ModelDeadline.polish) {
                try await polisher.polish(raw: source, kind: .rewrite(instruction))
            }
            await qwen.unload()
            TextInserter.insert(revised)
            history.add(source: "rewrite", raw: rewriteText, polished: revised)
            showRewrite = false
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startMeeting() async {
        guard requireUsableModel(speechModel) else { return }
        meetingNotes = nil
        meetingChunks = []
        transcribedUntil = 0
        meetingStatus = t("Preparing speakers", "Sprecher werden vorbereitet")
        do {
            try await diarizer.prepare()
            try recorder.start()
            if settings.systemAudioInMeetings {
                if !CGPreflightScreenCaptureAccess() {
                    _ = CGRequestScreenCaptureAccess()
                }
                try? await systemAudio.start()
            }
            meetingStartedAt = .now
            meetingActive = true
            meetingStatus = t("Listening", "Hört zu")
            meetingTimer = Task { await pollMeeting() }
        } catch {
            meetingStatus = error.localizedDescription
        }
    }

    func stopMeeting() async {
        meetingTimer?.cancel()
        meetingTimer = nil
        systemAudio.stop()
        let samples = recorder.stop()
        meetingActive = false
        meetingStatus = t("Wrapping up", "Wird zusammengefasst")
        do {
            await appendMeetingChunk(samples: samples, fullCount: samples.count)
            meetingChunks = try await diarizer.assignSpeakers(to: meetingChunks, samples: samples)
            await speech.unload()
            let transcript = meetingChunks.map { chunk in
                let speaker = chunk.speaker.map { "\($0): " } ?? ""
                return speaker + chunk.text
            }.joined(separator: "\n")
            if settings.polishEnabled, downloads.isUsable(.qwen), !transcript.isEmpty {
                let polisher = qwen
                let reply = try await AsyncDeadline.value(ModelDeadline.polish) {
                    try await polisher.polish(raw: transcript, kind: .meeting)
                }
                await qwen.unload()
                meetingNotes = Self.parseNotes(reply)
            }
            history.add(source: "meeting", raw: transcript, polished: meetingNotes?.summary ?? transcript)
            meetingStatus = t("Done", "Fertig")
        } catch {
            meetingStatus = error.localizedDescription
        }
    }

    private func pollMeeting() async {
        while meetingActive, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            guard meetingActive else { return }
            let samples = recorder.snapshot()
            await appendMeetingChunk(samples: samples, fullCount: samples.count)
        }
    }

    private func appendMeetingChunk(samples: [Float], fullCount: Int) async {
        guard fullCount - transcribedUntil > 16_000 else { return }
        let start = transcribedUntil
        let slice = Array(samples[start..<fullCount])
        transcribedUntil = fullCount
        let startTime = Double(start) / 16_000
        let endTime = Double(fullCount) / 16_000
        do {
            let router = speech
            let choice = settings.language
            let text = try await AsyncDeadline.value(ModelDeadline.finalTranscription) {
                try await router.transcribe(samples: slice, choice: choice)
            }
            guard !text.isEmpty else { return }
            meetingChunks.append(TranscriptChunk(start: startTime, end: endTime, text: text, speaker: nil))
        } catch {
            meetingStatus = error.localizedDescription
        }
    }

    private static func parseNotes(_ reply: String) -> MeetingNotes {
        if let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}") {
            let json = Data(reply[start...end].utf8)
            if let notes = try? JSONDecoder().decode(MeetingNotes.self, from: json) {
                return notes
            }
        }
        return MeetingNotes(summary: reply, decisions: [], tasks: [])
    }
}
