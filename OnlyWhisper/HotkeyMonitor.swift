import CoreGraphics
import Foundation
import IOKit.hidsystem

/// Press and release edges for one Option key.
///
/// `flagsChanged` does not reliably carry a keycode, and `.maskAlternate` is set for
/// both Option keys. The side comes from the device-dependent bits. Keyboards that
/// omit those bits fall back to the keycode plus `.maskAlternate`.
struct DictationKeyEdge: Sendable {
    enum Change: Equatable, Sendable {
        case pressed
        case released
    }

    var keyCode: Int64
    private(set) var isDown = false

    init(keyCode: Int64 = DictationKey.rightOption.keyCode) {
        self.keyCode = keyCode
    }

    mutating func reset() {
        isDown = false
    }

    mutating func handle(flags: UInt64, eventKeyCode: Int64) -> Change? {
        let down = Self.isDown(targetKeyCode: keyCode, flags: flags, eventKeyCode: eventKeyCode)
        guard down != isDown else { return nil }
        isDown = down
        return down ? .pressed : .released
    }

    /// Corrects a missed key-up. A key that is already held does not count as a new press.
    mutating func reconcile(flags: UInt64) -> Change? {
        let down = Self.isDown(targetKeyCode: keyCode, flags: flags, eventKeyCode: 0)
        guard isDown, !down else { return nil }
        isDown = false
        return .released
    }

    static func isDown(targetKeyCode: Int64, flags: UInt64, eventKeyCode: Int64) -> Bool {
        let right = flags & UInt64(NX_DEVICERALTKEYMASK) != 0
        let left = flags & UInt64(NX_DEVICELALTKEYMASK) != 0
        switch targetKeyCode {
        case DictationKey.rightOption.keyCode where right || left:
            return right
        case DictationKey.leftOption.keyCode where right || left:
            return left
        default:
            break
        }
        let alternate = flags & CGEventFlags.maskAlternate.rawValue != 0
        return alternate && eventKeyCode == targetKeyCode
    }
}

@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: ((TimeInterval) -> Void)?
    var onEscape: (() -> Void)?

    var keyCode: Int64 {
        get { edge.keyCode }
        set {
            guard edge.keyCode != newValue else { return }
            if edge.isDown {
                edge.reset()
                deliverRelease()
            }
            edge.keyCode = newValue
        }
    }

    private(set) var isListening = false
    private var edge = DictationKeyEdge()
    private var pressedAt: Date?
    nonisolated(unsafe) private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Creates a listen-only tap. Returns false until Input Monitoring is granted, so a
    /// failed tap is not left installed for the rest of the process.
    func start() -> Bool {
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            isListening = true
            return true
        }
        reconcileWithSystem()
        stop()
        guard CGPreflightListenEventAccess() else { return false }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        isListening = true
        reconcileWithSystem()
        return true
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
    }

    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Task { @MainActor in
                self.reconcileWithSystem()
            }
            return
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let isEscape = type == .keyDown && code == 53
        let isFlags = type == .flagsChanged
        Task { @MainActor in
            if isEscape {
                self.onEscape?()
                return
            }
            guard isFlags else { return }
            self.apply(self.edge.handle(flags: flags, eventKeyCode: code))
        }
    }

    private func reconcileWithSystem() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        apply(edge.reconcile(flags: flags))
    }

    private func apply(_ change: DictationKeyEdge.Change?) {
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
