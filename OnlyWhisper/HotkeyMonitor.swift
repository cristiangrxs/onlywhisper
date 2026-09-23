import CoreGraphics
import Foundation

@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: ((TimeInterval) -> Void)?
    var onEscape: (() -> Void)?
    var keyCode: Int64 = 61

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedAt: Date?
    private var optionIsDown = false

    func start() -> Bool {
        stop()
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
    }

    nonisolated fileprivate func handle(type: CGEventType, event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let down = event.flags.contains(.maskAlternate)
        let isEscape = type == .keyDown && code == 53
        let isFlags = type == .flagsChanged
        Task { @MainActor in
            if isEscape {
                self.onEscape?()
                return
            }
            guard isFlags, code == self.keyCode else { return }
            if down, !self.optionIsDown {
                self.optionIsDown = true
                self.pressedAt = .now
                self.onPress?()
            } else if !down, self.optionIsDown {
                self.optionIsDown = false
                let duration = self.pressedAt.map { Date.now.timeIntervalSince($0) } ?? 1
                self.pressedAt = nil
                self.onRelease?(duration)
            }
        }
    }
}
