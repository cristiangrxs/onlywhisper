import Carbon.HIToolbox
import Foundation
@preconcurrency import KeyboardShortcuts
import os

enum HotkeyRegistration: Equatable {
    case available
    case taken
    case failed(Int32)

    static func interpret(_ status: OSStatus) -> HotkeyRegistration {
        if status == noErr { return .available }
        if status == OSStatus(eventHotKeyExistsErr) { return .taken }
        return .failed(status)
    }

    var isConflict: Bool {
        switch self {
        case .available: false
        case .taken, .failed: true
        }
    }
}

enum RewriteGate: Equatable {
    case needsAccessibility
    case needsSelection
    case ready(String)

    static var needsSelectionMessage: String {
        t("Select text first", "Erst Text markieren")
    }

    static func evaluate(accessibilityGranted: Bool, selectedText: String?) -> RewriteGate {
        guard accessibilityGranted else { return .needsAccessibility }
        guard let selectedText, !selectedText.isEmpty else { return .needsSelection }
        return .ready(selectedText)
    }
}

enum ShortcutProbe {
    private static let signature = OSType(0x4F575052) // OWPR
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.onlywhisper.mac",
        category: "hotkeys"
    )

    /// Drops our own Carbon registrations first, so a free shortcut is not reported as taken by us.
    static func conflicts(among names: [KeyboardShortcuts.Name]) -> Set<KeyboardShortcuts.Name> {
        let wasEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        defer { KeyboardShortcuts.isEnabled = wasEnabled }

        var taken: Set<KeyboardShortcuts.Name> = []
        for name in names {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { continue }
            let result = registration(for: shortcut)
            switch result {
            case .available:
                log.info("Hotkey available: \(name.rawValue, privacy: .public)")
            case .taken:
                taken.insert(name)
                log.error("Hotkey taken by another app: \(name.rawValue, privacy: .public)")
            case .failed(let status):
                taken.insert(name)
                log.error("Hotkey registration failed: \(name.rawValue, privacy: .public) status \(status)")
            }
        }
        return taken
    }

    static func registration(for shortcut: KeyboardShortcuts.Shortcut) -> HotkeyRegistration {
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        if status == noErr, let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        return HotkeyRegistration.interpret(status)
    }
}
