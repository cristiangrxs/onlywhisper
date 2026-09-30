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
            if self.phase == .recording || self.phase == .handsFree {
                self.cancelCapture()
            } else {
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
            let closing = notification.object as? NSWindow
            Task { @MainActor in
                let stillOpen = NSApp.windows.contains { window in
                    window !== closing && window.isVisible && window.canBecomeMain && !(window is NSPanel)
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
        await downloads.download(id)
    }

    func downloadMissingModels() async {
        guard canChangeModels else { return }
        await downloads.downloadMissing()
    }

    func updateModel(_ id: ModelID) async {
        guard canChangeModels else { return }
        await unloadSpeechModels()
        await downloads.update(id)
    }

    func updateOutdatedModels() async {
        guard canChangeModels else { return }
        await unloadSpeechModels()
        await downloads.updateOutdated()
    }

    func removeModel(_ id: ModelID) async {
        guard canChangeModels else { return }
        await unloadSpeechModels()
        downloads.remove(id)
    }

    private var speechModel: ModelID { .whisper }

    /// Opens setup until the first install is finished. After that, a removed model is recovered from Settings.
    @discardableResult
    private func requireUsableModel(_ id: ModelID) -> Bool {
        guard downloads.isUsable(id) else {
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

    func startHandsFree() {
        beginRecording(handsFree: true)
    }

    func finishHandsFree() {
        Task { await finishDictation() }
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

    func showOverlayHint(_ text: String) {
        clearInsertedConfirmation()
        clearPendingCopy()
        hintTask?.cancel()
        overlayHint = text
        OverlayPanel.shared.show()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
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
            await downloads.downloadRequiredModels()
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
            Task { await finishDictation() }
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
        Task { await finishDictation() }
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
        livePreview = ""
        clearInsertedConfirmation()
        clearPendingCopy()
        hintTask?.cancel()
        overlayHint = nil
        TextInserter.beginInsertion()
        do {
            try recorder.start()
            phase = handsFree ? .handsFree : .recording
            OverlayPanel.shared.show()
            let epoch = dictationEpoch
            dictationTask = Task {
                await speech.resetUtterance()
                await speech.prepare()
                await runDictationLoop(epoch: epoch)
            }
            if settings.polishEnabled, downloads.isUsable(.qwen) {
                Task { await qwen.prewarm() }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelCapture() {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationTask = nil
        _ = recorder.stop()
        TextInserter.revertInsertion()
        dictationSession.reset()
        livePreview = ""
        isSmoothing = false
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

    /// The raw words are already in the field. The writing model runs once over all of them and replaces the draft.
    private func finishDictation() async {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        let epoch = dictationEpoch
        dictationTask?.cancel()
        dictationTask = nil
        phase = .working(t("Smoothing", "Glättet"))
        let samples = recorder.stop()
        level = 0
        await transcribeOpenAudio(samples, epoch: epoch, final: true)
        dictationSession.settleOpen()
        let raw = dictationSession.text
        var finished = ruled(raw)
        if settings.polishEnabled, downloads.isUsable(.qwen), !finished.isEmpty {
            isSmoothing = true
            finished = await polishDictation(finished)
            isSmoothing = false
        }
        await qwen.unload()
        let text = finished.trimmingCharacters(in: .whitespacesAndNewlines)
        let didInsert: Bool
        if text.isEmpty {
            TextInserter.revertInsertion()
            didInsert = false
        } else {
            didInsert = TextInserter.replaceInsertion(with: text, allowPasteFallback: true)
            history.add(source: "dictation", raw: raw, polished: text)
        }
        if !meetingActive {
            await speech.unload()
        }
        dictationSession.reset()
        livePreview = ""
        phase = .idle
        switch DictationDelivery.decide(text: text, inserted: didInsert) {
        case .nothingHeard:
            showOverlayHint(t("Nothing heard", "Nichts verstanden"))
        case .inserted:
            confirmInsertion()
        case .holdForCopy:
            holdForCopy(text)
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
            await transcribeOpenAudio(samples, epoch: epoch, final: false)
            guard epoch == dictationEpoch, !Task.isCancelled else { return }
            let added = recorder.snapshot().count - count
            if !heardSpeech || added < 3_200 {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// Transcribes the open segment again and writes the raw words into the field.
    /// A pause, a long segment, or the end of the dictation freezes it so the next pass starts after it.
    private func transcribeOpenAudio(_ samples: [Float], epoch: Int, final: Bool) async {
        let end = samples.count
        var start = dictationCursor
        var changed = false
        defer {
            if changed, epoch == dictationEpoch, !final {
                publishLive()
            }
        }
        while epoch == dictationEpoch, end - start >= Self.minimumSpeechSamples {
            let cut = final ? end : SpeechPause.settlePoint(in: samples, from: start, to: end)
            let stop = cut ?? end
            let slice = Array(samples[start..<stop])
            let heard: String?
            if SpeechPresence.containsSpeech(slice) {
                heard = await transcribe(samples, from: start, to: stop, epoch: epoch, live: !final)
            } else {
                heard = ""
            }
            guard let heard else { return }
            if dictationSession.updateOpen(heard) {
                changed = true
            }
            guard cut != nil else { return }
            dictationSession.settleOpen()
            dictationCursor = stop
            start = stop
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
    ) async -> String? {
        do {
            let text = try await speech.transcribe(
                samples: Array(samples[start..<end]),
                choice: settings.language,
                live: live,
                dictation: true
            )
            guard epoch == dictationEpoch else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            guard epoch == dictationEpoch else { return nil }
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func publishLive() {
        let text = dictationSession.text
        livePreview = text
        if text.isEmpty {
            TextInserter.revertInsertion()
            TextInserter.beginInsertion()
            return
        }
        _ = TextInserter.replaceInsertion(with: text)
    }

    /// Long dictations go through in pieces so none is cut off. A piece that fails keeps its unpolished text.
    private func polishDictation(_ text: String) async -> String {
        var result = ""
        for piece in DictationSession.polishChunks(text, limit: 1_500) {
            let polished = (try? await qwen.polish(raw: piece, kind: .dictation)) ?? piece
            result = DictationSession.joined(result, polished)
        }
        return result
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
            let revised = try await qwen.polish(raw: rewriteText, kind: .rewrite(instruction))
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
                let reply = try await qwen.polish(raw: transcript, kind: .meeting)
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
            let text = try await speech.transcribe(samples: slice, choice: settings.language)
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
