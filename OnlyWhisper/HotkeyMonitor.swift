import CoreGraphics
import Foundation
import os

private let hotkeyLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.onlywhisper.mac",
    category: "hotkeys"
)

private struct TapState: Sendable {
    var press = DictationPress()
    var paused = false
    var canSwallow = false
}

private struct TapDecision: Sendable {
    var change: DictationPress.Change?
    var swallow = false
    var escape = false
}

/// Hears the dictation binding in other apps.
///
/// Modifier-only bindings stay visible to the system. A chord's key is swallowed so it is not typed.
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: ((TimeInterval) -> Void)?
    var onEscape: (() -> Void)?

    var binding: DictationKey {
        get { gate.withLock { $0.press.binding } }
        set {
            let shouldRelease = gate.withLock { state -> Bool in
                guard state.press.binding != newValue else { return false }
                let down = state.press.isDown
                state.press.binding = newValue
                if down { state.press.reset() }
                return down
            }
            if shouldRelease { deliverRelease() }
        }
    }

    var isPaused: Bool {
        get { gate.withLock { $0.paused } }
        set {
            let shouldRelease = gate.withLock { state -> Bool in
                state.paused = newValue
                guard newValue, state.press.isDown else { return false }
                state.press.reset()
                return true
            }
            if shouldRelease { deliverRelease() }
        }
    }

    private(set) var isListening = false
    nonisolated private let gate = OSAllocatedUnfairLock(initialState: TapState())
    private var pressedAt: Date?
    nonisolated(unsafe) private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Creates the event tap. Returns false until Input Monitoring is granted.
    /// When `canFilter` is true, a filtering tap is used so chord keys are not typed.
    func start(canFilter: Bool) -> Bool {
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            let swallowing = gate.withLock { $0.canSwallow }
            if swallowing || !canFilter {
                isListening = true
                return true
            }
        }
        reconcileWithSystem()
        stop()
        guard CGPreflightListenEventAccess() else {
            hotkeyLog.error("Event tap not started: Input Monitoring is not granted")
            return false
        }
        if canFilter, install(options: .defaultTap, canSwallow: true) {
            return true
        }
        return install(options: .listenOnly, canSwallow: false)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
        isListening = false
        gate.withLock { $0.canSwallow = false }
    }

    private func install(options: CGEventTapOptions, canSwallow: Bool) -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            let swallow = monitor.handle(type: type, event: event)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            hotkeyLog.error("Event tap was rejected")
            return false
        }
        gate.withLock { $0.canSwallow = canSwallow }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        isListening = true
        hotkeyLog.info("Event tap started")
        reconcileWithSystem()
        return true
    }

    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            hotkeyLog.error("Event tap disabled by the system, re-enabling")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Task { @MainActor in
                self.reconcileWithSystem()
            }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let kind: DictationPress.Event = switch type {
        case .keyDown: .keyDown
        case .keyUp: .keyUp
        default: .flagsChanged
        }
        let decision = gate.withLock { state -> TapDecision in
            if state.paused { return TapDecision() }
            if type == .keyDown, code == 53 {
                return TapDecision(escape: true)
            }
            let step = state.press.handle(event: kind, flags: flags, eventKeyCode: code, isRepeat: isRepeat)
            return TapDecision(change: step.change, swallow: step.swallow && state.canSwallow)
        }
        if decision.escape {
            Task { @MainActor in
                self.onEscape?()
            }
            return false
        }
        if let change = decision.change {
            Task { @MainActor in
                self.apply(change)
            }
        }
        return decision.swallow
    }

    private func reconcileWithSystem() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let change = gate.withLock { state -> DictationPress.Change? in
            guard !state.paused else { return nil }
            return state.press.reconcile(flags: flags)
        }
        apply(change)
    }

    private func apply(_ change: DictationPress.Change?) {
        switch change {
        case .pressed:
            pressedAt = .now
            onPress?()
        case .released:
            deliverRelease()
        case nil:
            break
        }
    }

    private func deliverRelease() {
        let duration = pressedAt.map { Date.now.timeIntervalSince($0) } ?? 1
        pressedAt = nil
        onRelease?(duration)
    }
}
