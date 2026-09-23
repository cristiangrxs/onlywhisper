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
}

enum CapturePhase: Equatable {
    case idle
    case recording
    case handsFree
    case working(String)
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
    var rewriteText = ""
    var rewriteInstruction = ""
    var showRewrite = false
    var isSmoothing = false

    private let recorder = AudioRecorder()
    private let systemAudio = SystemAudioCapture()
    private let hotkeys = HotkeyMonitor()
    private let speech = SpeechRouter()
    private let qwen = QwenPolisher()
    private let diarizer = MeetingDiarizer()
    private var opener: ((String) -> Void)?
    private var meetingStartedAt: Date?
    private var transcribedUntil: Int = 0
    private var meetingTimer: Task<Void, Never>?
    private var dictationTask: Task<Void, Never>?
    private var polishTask: Task<Void, Never>?
    private var dictationEpoch = 0
    private var dictationCursor = 0
    private var dictationActivity = Date()
    private var dictationSession = DictationSession()
    private var rawOpen = ""
    private var rawLog = ""
    private var watchesWindowClose = false

    private init() {
        recorder.setLevelHandler { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        systemAudio.onSamples = { [weak self] samples in
            self?.recorder.appendSystemSamples(samples)
        }
        hotkeys.onPress = { [weak self] in self?.dictationPressed() }
        hotkeys.onRelease = { [weak self] duration in self?.dictationReleased(after: duration) }
        hotkeys.onEscape = { [weak self] in self?.cancelCapture() }
        KeyboardShortcuts.onKeyDown(for: .rewriteSelection) { [weak self] in
            Task { @MainActor in self?.beginRewrite() }
        }
    }

    var menuSymbol: String {
        switch phase {
        case .recording, .handsFree: "waveform"
        case .working: "ellipsis"
        default: "mic"
        }
    }

    func bind(openWindow: @escaping (String) -> Void) {
        opener = openWindow
    }

    func bootstrap() {
        downloads.refreshReadyState()
        hotkeys.keyCode = settings.dictationKey.keyCode
        _ = hotkeys.start()
        needsSetup = !downloads.isReady || !microphoneGranted || !accessibilityGranted || !inputGranted
        if needsSetup {
            opener?("setup")
            NSApp.activate()
        }
        applyLaunchAtLogin()
        watchWindowClose()
    }

    /// Settings is a normal window. A menu-bar app stays behind other apps until it becomes a regular, active app.
    func presentSettings(open: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        open()
        orderSettingsFront()
    }

    func orderSettingsFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            for _ in 0..<12 {
                guard let window = NSApp.windows.first(where: { $0.identifier == AppWindows.settings }) else {
                    try? await Task.sleep(for: .milliseconds(40))
                    continue
                }
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                if NSApp.isActive {
                    window.level = .normal
                    window.orderFrontRegardless()
                }
                return
            }
        }
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
        files.enqueue(urls, speech: speech, language: settings.language)
    }

    func startHandsFree() {
        beginRecording(handsFree: true)
    }

    func open(_ id: String) {
        opener?(id)
        NSApp.activate()
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
        _ = hotkeys.start()
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
        guard downloads.isReady, microphoneGranted else {
            needsSetup = true
            opener?("setup")
            return
        }
        dictationEpoch += 1
        dictationTask?.cancel()
        polishTask?.cancel()
        polishTask = nil
        dictationSession = DictationSession()
        rawOpen = ""
        rawLog = ""
        dictationCursor = 0
        dictationActivity = .now
        isSmoothing = false
        TextInserter.beginInsertion()
        do {
            try recorder.start()
            phase = handsFree ? .handsFree : .recording
            OverlayPanel.shared.show()
            let epoch = dictationEpoch
            dictationTask = Task { await runDictationLoop(epoch: epoch) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelCapture() {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationTask = nil
        polishTask?.cancel()
        polishTask = nil
        _ = recorder.stop()
        TextInserter.revertInsertion()
        dictationSession.reset()
        rawOpen = ""
        rawLog = ""
        isSmoothing = false
        phase = .idle
        level = 0
        OverlayPanel.shared.hide()
        let keepSpeech = meetingActive
        Task {
            if !keepSpeech {
                await speech.unload()
            }
            await qwen.unload()
        }
    }

    private func finishDictation() async {
        guard phase == .recording || phase == .handsFree else { return }
        dictationEpoch += 1
        dictationTask?.cancel()
        dictationTask = nil
        polishTask?.cancel()
        polishTask = nil
        phase = .working(t("Smoothing", "Glättet"))
        let samples = recorder.stop()
        await appendNewAudio(samples, from: dictationCursor, epoch: dictationEpoch)
        if settings.polishEnabled, !dictationSession.openText.isEmpty {
            isSmoothing = true
            let polished = (try? await qwen.polish(raw: dictationSession.openText, kind: .dictation))
                ?? dictationSession.openText
            await qwen.unload()
            dictationSession.commitFinal(polished)
            isSmoothing = false
        }
        let finished = dictationSession.visibleText
        if finished.isEmpty {
            TextInserter.revertInsertion()
        } else {
            TextInserter.replaceInsertion(with: finished, allowPasteFallback: true)
            history.add(source: "dictation", raw: rawLog, polished: finished)
        }
        if !meetingActive {
            await speech.unload()
        }
        dictationSession.reset()
        rawOpen = ""
        rawLog = ""
        phase = .idle
        level = 0
        OverlayPanel.shared.hide()
    }

    private func runDictationLoop(epoch: Int) async {
        while epoch == dictationEpoch, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
            guard epoch == dictationEpoch else { return }
            let samples = recorder.snapshot()
            let start = dictationCursor
            if samples.count - start >= 11_200 {
                _ = await appendNewAudio(samples, from: start, epoch: epoch)
            }
            guard epoch == dictationEpoch else { return }
            let paused = Date().timeIntervalSince(dictationActivity) >= 0.9
            startPolishIfNeeded(paused: paused, epoch: epoch)
        }
    }

    @discardableResult
    private func appendNewAudio(_ samples: [Float], from start: Int, epoch: Int) async -> Bool {
        guard samples.count - start > 1_600 else { return false }
        let end = samples.count
        do {
            let piece = try await speech.transcribe(
                samples: Array(samples[start..<end]),
                choice: settings.language
            )
            guard epoch == dictationEpoch else { return false }
            dictationCursor = end
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            rawOpen = joined(rawOpen, trimmed)
            rawLog = joined(rawLog, trimmed)
            dictationSession.updateOpenText(ruled(rawOpen))
            dictationActivity = .now
            TextInserter.replaceInsertion(with: dictationSession.visibleText)
            return true
        } catch {
            guard epoch == dictationEpoch else { return false }
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func startPolishIfNeeded(paused: Bool, epoch: Int) {
        guard settings.polishEnabled, polishTask == nil else { return }
        guard let request = dictationSession.polishRequest(paused: paused) else { return }
        isSmoothing = true
        polishTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.polishTask = nil
                if self.dictationEpoch == epoch {
                    self.isSmoothing = false
                }
            }
            do {
                let polished = try await self.qwen.polish(raw: request.sentence, kind: .dictation)
                await self.qwen.unload()
                guard epoch == self.dictationEpoch else { return }
                guard self.dictationSession.acceptPolish(polished, generation: request.generation) else { return }
                self.rawOpen = self.dictationSession.openText
                self.dictationActivity = .now
                TextInserter.replaceInsertion(with: self.dictationSession.visibleText)
            } catch {
                guard epoch == self.dictationEpoch else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    private func ruled(_ text: String) -> String {
        dictionary.dictionary.apply(to: RulePolisher.apply(text))
    }

    private func joined(_ left: String, _ right: String) -> String {
        let left = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    func beginRewrite() {
        guard let selected = TextInserter.selectedText(), !selected.isEmpty else { return }
        rewriteText = selected
        rewriteInstruction = ""
        showRewrite = true
        open("rewrite")
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
        do {
            try recorder.start()
            phase = .recording
            try await Task.sleep(for: .seconds(4))
            let samples = recorder.stop()
            phase = .idle
            let spoken = try await speech.transcribe(samples: samples, choice: settings.language)
            await speech.unload()
            rewriteInstruction = spoken
        } catch {
            statusMessage = error.localizedDescription
            phase = .idle
        }
    }

    private func rewrite(instruction: String) async {
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
        guard downloads.isReady else {
            opener?("setup")
            return
        }
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
            if settings.polishEnabled, !transcript.isEmpty {
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
